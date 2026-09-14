// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IAggregatorV3 } from "src/interfaces/IAggregatorV3.sol";
import { IRobinhoodStockToken } from "src/interfaces/IRobinhoodStockToken.sol";
import { IStaticsOracle } from "src/interfaces/IStaticsOracle.sol";
import { OracleMath } from "src/libraries/OracleMath.sol";

/// @notice Authoritative address-keyed registry and evaluator for Statics external-asset oracles.
contract StaticsOracle is Ownable2Step, IStaticsOracle {
    uint8 internal constant MAX_SUPPORTED_DECIMALS = 18;
    uint256 public constant MAX_BASKET_ASSETS = 16;

    mapping(address token => AssetOracleConfig config) private _assetConfigs;
    SequencerConfig private _sequencerConfig;

    uint64 public override registryVersion;

    error ZeroAddress();
    error NoContractCode(address account);
    error AssetAlreadyRegistered(address token);
    error UnsupportedAsset(address token);
    error AssetMustBeDisabled(address token, AssetStatus status);
    error InvalidStatusTransition(address token, AssetStatus from, AssetStatus to);
    error InvalidAssetKind(AssetKind kind);
    error InvalidMaxAge();
    error UnsupportedTokenDecimals(uint8 decimals);
    error UnsupportedFeedDecimals(uint8 decimals);
    error TokenDecimalsCallFailed(address token);
    error FeedDecimalsCallFailed(address feed);
    error FeedDescriptionCallFailed(address feed);
    error TokenDecimalsMismatch(address token, uint8 expected, uint8 actual);
    error FeedDecimalsMismatch(address feed, uint8 expected, uint8 actual);
    error FeedDescriptionMismatch(address feed, bytes32 expected, bytes32 actual);
    error StockPauseCheckRequired(address token);
    error StockPauseCheckFailed(address token);
    error StockOraclePaused(address token);
    error SequencerFeedCallFailed(address feed);
    error AssetEnablementFailed(address token, OracleStatus status);
    error AssetNotEnabled(address token, AssetStatus status);
    error SequencerNotConfigured();
    error SequencerDown();
    error SequencerGracePeriod(uint256 recoveryStartedAt, uint256 gracePeriod);
    error FeedCallFailed(address feed);
    error InvalidPrice(address feed);
    error IncompleteRound(address feed, uint80 roundId);
    error InvalidOracleTimestamp(address feed, uint256 updatedAt);
    error StalePrice(address feed, uint256 updatedAt, uint256 maxAge);
    error UnexpectedOracleStatus(address token, OracleStatus status);
    error LengthMismatch();
    error EmptyBasket();
    error TooManyAssets(uint256 count);
    error DuplicateAsset(address token);

    event AssetRegistered(
        address indexed token, address indexed feed, uint64 indexed version, bytes32 configHash
    );
    event AssetUpdated(
        address indexed token, address indexed feed, uint64 indexed version, bytes32 configHash
    );
    event AssetStatusChanged(
        address indexed token,
        AssetStatus previousStatus,
        AssetStatus newStatus,
        uint64 indexed version
    );
    event SequencerConfigUpdated(address indexed feed, uint32 gracePeriod, uint64 indexed version);

    constructor(
        address initialOwner
    ) Ownable(initialOwner) { }

    function assetConfig(
        address token
    ) external view override returns (AssetOracleConfig memory) {
        return _assetConfigs[token];
    }

    function sequencerConfig() external view override returns (SequencerConfig memory) {
        return _sequencerConfig;
    }

    function setSequencerConfig(
        address feed,
        uint32 gracePeriod
    ) external onlyOwner {
        if (feed == address(0)) revert ZeroAddress();
        if (feed.code.length == 0) revert NoContractCode(feed);

        try IAggregatorV3(feed).latestRoundData() returns (
            uint80, int256, uint256, uint256, uint80
        ) { }
        catch {
            revert SequencerFeedCallFailed(feed);
        }

        _sequencerConfig = SequencerConfig({ feed: feed, gracePeriod: gracePeriod });
        uint64 version = _incrementVersion();
        emit SequencerConfigUpdated(feed, gracePeriod, version);
    }

    function registerAsset(
        address token,
        AssetOracleConfigInput calldata input
    ) external onlyOwner {
        if (_assetConfigs[token].status != AssetStatus.UNSET) {
            revert AssetAlreadyRegistered(token);
        }

        _validateConfiguration(token, input);

        AssetOracleConfig memory config = _toConfig(input, AssetStatus.CANDIDATE);
        _assetConfigs[token] = config;

        uint64 version = _incrementVersion();
        emit AssetRegistered(token, config.feed, version, _configHash(token, config));
        emit AssetStatusChanged(token, AssetStatus.UNSET, AssetStatus.CANDIDATE, version);
    }

    function updateAsset(
        address token,
        AssetOracleConfigInput calldata input
    ) external onlyOwner {
        AssetStatus previousStatus = _assetConfigs[token].status;
        if (previousStatus == AssetStatus.UNSET) {
            revert UnsupportedAsset(token);
        }
        if (previousStatus != AssetStatus.DISABLED) {
            revert AssetMustBeDisabled(token, previousStatus);
        }

        _validateConfiguration(token, input);

        AssetOracleConfig memory config = _toConfig(input, AssetStatus.CANDIDATE);
        _assetConfigs[token] = config;

        uint64 version = _incrementVersion();
        emit AssetUpdated(token, config.feed, version, _configHash(token, config));
        emit AssetStatusChanged(token, previousStatus, AssetStatus.CANDIDATE, version);
    }

    function enableAsset(
        address token
    ) external onlyOwner {
        AssetOracleConfig storage config = _assetConfigs[token];
        AssetStatus previousStatus = config.status;
        if (previousStatus == AssetStatus.UNSET) {
            revert UnsupportedAsset(token);
        }
        if (previousStatus != AssetStatus.CANDIDATE) {
            revert InvalidStatusTransition(token, previousStatus, AssetStatus.ENABLED);
        }

        (OracleStatus sequencerStatus,) = _evaluateSequencer();
        if (sequencerStatus != OracleStatus.VALID) {
            revert AssetEnablementFailed(token, sequencerStatus);
        }

        if (_validateStoredConfiguration(token, config)) {
            revert StockOraclePaused(token);
        }

        PriceData memory currentPrice = _evaluateConfiguredPrice(token, config, true);
        if (currentPrice.status != OracleStatus.VALID) {
            revert AssetEnablementFailed(token, currentPrice.status);
        }

        config.status = AssetStatus.ENABLED;
        uint64 version = _incrementVersion();
        emit AssetStatusChanged(token, previousStatus, AssetStatus.ENABLED, version);
    }

    function disableAsset(
        address token
    ) external onlyOwner {
        AssetOracleConfig storage config = _assetConfigs[token];
        AssetStatus previousStatus = config.status;
        if (previousStatus == AssetStatus.UNSET) {
            revert UnsupportedAsset(token);
        }
        if (previousStatus != AssetStatus.CANDIDATE && previousStatus != AssetStatus.ENABLED) {
            revert InvalidStatusTransition(token, previousStatus, AssetStatus.DISABLED);
        }

        config.status = AssetStatus.DISABLED;
        uint64 version = _incrementVersion();
        emit AssetStatusChanged(token, previousStatus, AssetStatus.DISABLED, version);
    }

    function configHash(
        address token
    ) external view returns (bytes32) {
        AssetOracleConfig memory config = _assetConfigs[token];
        if (config.status == AssetStatus.UNSET) {
            revert UnsupportedAsset(token);
        }
        return _configHash(token, config);
    }

    function peekPrice(
        address token
    ) external view override returns (PriceData memory) {
        return _evaluatePrice(token, false);
    }

    function priceUsd(
        address token
    ) external view override returns (uint256 price1e18) {
        PriceData memory data = _evaluatePrice(token, false);
        return _requireValidPrice(token, data);
    }

    function valueUsd(
        address token,
        uint256 amount
    ) external view override returns (uint256 value1e18) {
        PriceData memory data = _evaluatePrice(token, false);
        uint256 price1e18 = _requireValidPrice(token, data);
        return OracleMath.valueUsd(amount, price1e18, _assetConfigs[token].tokenDecimals);
    }

    function basketNav(
        address[] calldata assets,
        uint256[] calldata amounts
    ) external view override returns (uint256 nav1e18) {
        uint256 count = assets.length;
        if (count != amounts.length) revert LengthMismatch();
        if (count == 0) revert EmptyBasket();
        if (count > MAX_BASKET_ASSETS) revert TooManyAssets(count);

        (OracleStatus sequencerStatus, uint256 recoveryStartedAt) = _evaluateSequencer();
        if (sequencerStatus != OracleStatus.VALID) {
            PriceData memory sequencerData = PriceData({
                price1e18: 0, updatedAt: recoveryStartedAt, roundId: 0, status: sequencerStatus
            });
            _revertForStatus(address(0), sequencerData);
        }

        for (uint256 i; i < count; ++i) {
            address token = assets[i];
            for (uint256 j; j < i; ++j) {
                if (assets[j] == token) revert DuplicateAsset(token);
            }

            PriceData memory data = _evaluatePrice(token, true);
            uint256 price1e18 = _requireValidPrice(token, data);
            nav1e18 += OracleMath.valueUsd(
                amounts[i], price1e18, _assetConfigs[token].tokenDecimals
            );
        }
    }

    function _requireValidPrice(
        address token,
        PriceData memory data
    ) internal view returns (uint256 price1e18) {
        if (data.status != OracleStatus.VALID) _revertForStatus(token, data);
        return data.price1e18;
    }

    function _revertForStatus(
        address token,
        PriceData memory data
    ) internal view {
        AssetOracleConfig storage config = _assetConfigs[token];
        if (data.status == OracleStatus.UNSUPPORTED) revert UnsupportedAsset(token);
        if (data.status == OracleStatus.CANDIDATE || data.status == OracleStatus.DISABLED) {
            revert AssetNotEnabled(token, config.status);
        }
        if (data.status == OracleStatus.SEQUENCER_NOT_CONFIGURED) {
            revert SequencerNotConfigured();
        }
        if (data.status == OracleStatus.SEQUENCER_DOWN) revert SequencerDown();
        if (data.status == OracleStatus.SEQUENCER_GRACE_PERIOD) {
            revert SequencerGracePeriod(data.updatedAt, _sequencerConfig.gracePeriod);
        }
        if (data.status == OracleStatus.STOCK_ORACLE_PAUSED) revert StockOraclePaused(token);
        if (data.status == OracleStatus.STOCK_PAUSE_CHECK_FAILED) {
            revert StockPauseCheckFailed(token);
        }
        if (data.status == OracleStatus.FEED_CALL_FAILED) revert FeedCallFailed(config.feed);
        if (data.status == OracleStatus.INVALID_PRICE) revert InvalidPrice(config.feed);
        if (data.status == OracleStatus.INCOMPLETE_ROUND) {
            revert IncompleteRound(config.feed, data.roundId);
        }
        if (data.status == OracleStatus.INVALID_TIMESTAMP) {
            revert InvalidOracleTimestamp(config.feed, data.updatedAt);
        }
        if (data.status == OracleStatus.STALE_PRICE) {
            revert StalePrice(config.feed, data.updatedAt, config.maxAge);
        }
        revert UnexpectedOracleStatus(token, data.status);
    }

    function _evaluatePrice(
        address token,
        bool sequencerAlreadyChecked
    ) internal view returns (PriceData memory data) {
        AssetOracleConfig storage config = _assetConfigs[token];
        if (config.status == AssetStatus.UNSET) {
            data.status = OracleStatus.UNSUPPORTED;
            return data;
        }
        if (config.status == AssetStatus.CANDIDATE) {
            data.status = OracleStatus.CANDIDATE;
            return data;
        }
        if (config.status == AssetStatus.DISABLED) {
            data.status = OracleStatus.DISABLED;
            return data;
        }

        return _evaluateConfiguredPrice(token, config, sequencerAlreadyChecked);
    }

    function _evaluateConfiguredPrice(
        address token,
        AssetOracleConfig storage config,
        bool sequencerAlreadyChecked
    ) internal view returns (PriceData memory data) {
        if (!sequencerAlreadyChecked) {
            (OracleStatus sequencerStatus, uint256 recoveryStartedAt) = _evaluateSequencer();
            if (sequencerStatus != OracleStatus.VALID) {
                data.status = sequencerStatus;
                data.updatedAt = recoveryStartedAt;
                return data;
            }
        }

        if (config.checkOraclePause) {
            try IRobinhoodStockToken(token).oraclePaused() returns (bool paused) {
                if (paused) {
                    data.status = OracleStatus.STOCK_ORACLE_PAUSED;
                    return data;
                }
            } catch {
                data.status = OracleStatus.STOCK_PAUSE_CHECK_FAILED;
                return data;
            }
        }

        try IAggregatorV3(config.feed).latestRoundData() returns (
            uint80 roundId, int256 answer, uint256, uint256 updatedAt, uint80 answeredInRound
        ) {
            data.roundId = roundId;
            data.updatedAt = updatedAt;

            if (answer <= 0) {
                data.status = OracleStatus.INVALID_PRICE;
                return data;
            }
            if (updatedAt == 0 || answeredInRound < roundId) {
                data.status = OracleStatus.INCOMPLETE_ROUND;
                return data;
            }
            if (updatedAt > block.timestamp) {
                data.status = OracleStatus.INVALID_TIMESTAMP;
                return data;
            }

            // forge-lint: disable-next-line(unsafe-typecast)
            data.price1e18 = OracleMath.normalizePrice(uint256(answer), config.feedDecimals);
            if (block.timestamp - updatedAt > config.maxAge) {
                data.status = OracleStatus.STALE_PRICE;
                return data;
            }

            data.status = OracleStatus.VALID;
            return data;
        } catch {
            data.status = OracleStatus.FEED_CALL_FAILED;
            return data;
        }
    }

    function _evaluateSequencer()
        internal
        view
        returns (OracleStatus status, uint256 recoveryStartedAt)
    {
        SequencerConfig memory config = _sequencerConfig;
        if (config.feed == address(0)) return (OracleStatus.SEQUENCER_NOT_CONFIGURED, 0);

        try IAggregatorV3(config.feed).latestRoundData() returns (
            uint80, int256 answer, uint256 startedAt, uint256, uint80
        ) {
            if (answer != 0 || startedAt == 0 || startedAt > block.timestamp) {
                return (OracleStatus.SEQUENCER_DOWN, startedAt);
            }
            if (block.timestamp - startedAt <= config.gracePeriod) {
                return (OracleStatus.SEQUENCER_GRACE_PERIOD, startedAt);
            }
            return (OracleStatus.VALID, startedAt);
        } catch {
            return (OracleStatus.SEQUENCER_DOWN, 0);
        }
    }

    function _validateConfiguration(
        address token,
        AssetOracleConfigInput memory input
    ) internal view returns (bool oraclePaused) {
        if (token == address(0) || input.feed == address(0)) revert ZeroAddress();
        if (token.code.length == 0) revert NoContractCode(token);
        if (input.feed.code.length == 0) revert NoContractCode(input.feed);
        if (input.kind == AssetKind.NONE) revert InvalidAssetKind(input.kind);
        if (input.maxAge == 0) revert InvalidMaxAge();
        if (input.tokenDecimals > MAX_SUPPORTED_DECIMALS) {
            revert UnsupportedTokenDecimals(input.tokenDecimals);
        }
        if (input.feedDecimals > MAX_SUPPORTED_DECIMALS) {
            revert UnsupportedFeedDecimals(input.feedDecimals);
        }
        if (_requiresPauseCheck(input.kind) && !input.checkOraclePause) {
            revert StockPauseCheckRequired(token);
        }

        uint8 tokenDecimals = _readTokenDecimals(token);
        if (tokenDecimals != input.tokenDecimals) {
            revert TokenDecimalsMismatch(token, input.tokenDecimals, tokenDecimals);
        }

        uint8 feedDecimals = _readFeedDecimals(input.feed);
        if (feedDecimals != input.feedDecimals) {
            revert FeedDecimalsMismatch(input.feed, input.feedDecimals, feedDecimals);
        }

        bytes32 descriptionHash = _readFeedDescriptionHash(input.feed);
        if (descriptionHash != input.feedDescriptionHash) {
            revert FeedDescriptionMismatch(input.feed, input.feedDescriptionHash, descriptionHash);
        }

        if (input.checkOraclePause) oraclePaused = _readOraclePaused(token);
    }

    function _validateStoredConfiguration(
        address token,
        AssetOracleConfig storage config
    ) internal view returns (bool oraclePaused) {
        AssetOracleConfigInput memory input = AssetOracleConfigInput({
            feed: config.feed,
            feedDescriptionHash: config.feedDescriptionHash,
            maxAge: config.maxAge,
            tokenDecimals: config.tokenDecimals,
            feedDecimals: config.feedDecimals,
            kind: config.kind,
            checkOraclePause: config.checkOraclePause
        });
        return _validateConfiguration(token, input);
    }

    function _readTokenDecimals(
        address token
    ) internal view returns (uint8 value) {
        try IERC20Metadata(token).decimals() returns (uint8 decimals_) {
            return decimals_;
        } catch {
            revert TokenDecimalsCallFailed(token);
        }
    }

    function _readFeedDecimals(
        address feed
    ) internal view returns (uint8 value) {
        try IAggregatorV3(feed).decimals() returns (uint8 decimals_) {
            return decimals_;
        } catch {
            revert FeedDecimalsCallFailed(feed);
        }
    }

    function _readFeedDescriptionHash(
        address feed
    ) internal view returns (bytes32 value) {
        try IAggregatorV3(feed).description() returns (string memory description_) {
            return keccak256(bytes(description_));
        } catch {
            revert FeedDescriptionCallFailed(feed);
        }
    }

    function _readOraclePaused(
        address token
    ) internal view returns (bool value) {
        try IRobinhoodStockToken(token).oraclePaused() returns (bool paused) {
            return paused;
        } catch {
            revert StockPauseCheckFailed(token);
        }
    }

    function _toConfig(
        AssetOracleConfigInput calldata input,
        AssetStatus status
    ) internal pure returns (AssetOracleConfig memory) {
        return AssetOracleConfig({
            feed: input.feed,
            feedDescriptionHash: input.feedDescriptionHash,
            maxAge: input.maxAge,
            tokenDecimals: input.tokenDecimals,
            feedDecimals: input.feedDecimals,
            kind: input.kind,
            status: status,
            checkOraclePause: input.checkOraclePause
        });
    }

    function _configHash(
        address token,
        AssetOracleConfig memory config
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(token, config));
    }

    function _requiresPauseCheck(
        AssetKind kind
    ) internal pure returns (bool) {
        return kind == AssetKind.STOCK || kind == AssetKind.ETF;
    }

    function _incrementVersion() internal returns (uint64 version) {
        version = registryVersion + 1;
        registryVersion = version;
    }
}
