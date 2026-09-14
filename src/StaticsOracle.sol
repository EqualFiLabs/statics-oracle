// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IAggregatorV3 } from "src/interfaces/IAggregatorV3.sol";
import { IRobinhoodStockToken } from "src/interfaces/IRobinhoodStockToken.sol";
import { IStaticsOracle } from "src/interfaces/IStaticsOracle.sol";

/// @notice Authoritative address-keyed registry for Statics external-asset oracles.
/// @dev Pricing functions are implemented by later stack layers; this layer establishes the
///      controlled configuration and lifecycle boundary they consume.
abstract contract StaticsOracle is Ownable2Step, IStaticsOracle {
    uint8 internal constant MAX_SUPPORTED_DECIMALS = 18;

    mapping(address token => AssetOracleConfig config) private _assetConfigs;

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

    constructor(
        address initialOwner
    ) Ownable(initialOwner) { }

    function assetConfig(
        address token
    ) external view override returns (AssetOracleConfig memory) {
        return _assetConfigs[token];
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

        if (_validateStoredConfiguration(token, config)) {
            revert StockOraclePaused(token);
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
