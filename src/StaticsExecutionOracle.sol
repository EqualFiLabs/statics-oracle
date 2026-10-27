// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IAggregatorV3 } from "src/interfaces/IAggregatorV3.sol";
import { IStaticsExecutionOracle } from "src/interfaces/IStaticsExecutionOracle.sol";
import { IVerifierProxy } from "src/interfaces/IVerifierProxy.sol";
import { DataStreamsV3 } from "src/libraries/DataStreamsV3.sol";
import { OracleMath } from "src/libraries/OracleMath.sol";

/// @notice Transaction-local Data Streams execution adapter for synthetic markets.
contract StaticsExecutionOracle is Ownable2Step, IStaticsExecutionOracle {
    address public immutable override verifierProxy;
    uint8 public immutable override maxReportBundleSize;
    uint64 public override registryVersion;
    mapping(bytes32 marketId => ExecutionMarketConfig) private _markets;

    mapping(address consumer => bool enabled) private _authorizedConsumers;
    error UnauthorizedConsumer(address consumer);
    error MarketNotEnabled(bytes32 marketId, MarketStatus status);
    event AuthorizedConsumerUpdated(address indexed consumer, bool enabled, uint64 indexed version);

    SequencerConfig private _sequencerConfig;
    error SequencerFeedCallFailed(address feed);
    error SequencerNotConfigured();
    error SequencerDown();
    error SequencerGracePeriod(uint256 recoveryStartedAt, uint32 gracePeriod);
    event SequencerConfigUpdated(address indexed feed, uint32 gracePeriod, uint64 indexed version);

    error EmptyReportBundle();
    error TooManyReports(uint256 supplied, uint256 maximum);
    error VerifierResponseLengthMismatch(uint256 submitted, uint256 returned);
    error WrongStreamId(bytes32 expected, bytes32 actual);
    error InvalidReportPrice(int192 price);
    error InvalidReportTimestampOrder(uint32 validFromTimestamp, uint32 observationsTimestamp);
    error ReportExpired(uint32 expiresAt, uint256 currentTimestamp);
    error FutureObservation(uint32 observationsTimestamp, uint256 currentTimestamp);
    error ReportWindowTooWide(uint32 width, uint32 maximum);
    error ReferenceTimestampOutOfRange(uint256 timestamp, uint32 delay);
    error ReportWindowUnavailable(uint256 referenceTimestamp);
    error OverlappingReportWindows(uint256 referenceTimestamp, uint256 matches);
    error ZeroAddress();
    error NoContractCode(address account);
    error InvalidBundleBound();

    error OwnershipRenunciationDisabled();
    error InvalidMarketId();
    error InvalidStreamId();
    error InvalidExecutionDelay();
    error InvalidMaxReportWindow();
    error UnsupportedStreamDecimals(uint8 decimals);
    error MarketAlreadyRegistered(bytes32 marketId);
    error UnsupportedMarket(bytes32 marketId);
    error InvalidMarketStatusTransition(bytes32 marketId, MarketStatus from, MarketStatus to);
    error MarketMustBeDisabled(bytes32 marketId, MarketStatus status);
    event MarketRegistered(
        bytes32 indexed marketId,
        bytes32 indexed streamId,
        uint64 indexed version,
        bytes32 configHash
    );
    event MarketUpdated(
        bytes32 indexed marketId,
        bytes32 indexed streamId,
        uint64 indexed version,
        bytes32 configHash
    );
    event MarketStatusChanged(
        bytes32 indexed marketId,
        MarketStatus previousStatus,
        MarketStatus newStatus,
        uint64 indexed version
    );

    constructor(
        address initialOwner,
        address verifierProxy_,
        uint8 maxReportBundleSize_
    ) Ownable(initialOwner) {
        if (verifierProxy_ == address(0)) revert ZeroAddress();
        if (verifierProxy_.code.length == 0) revert NoContractCode(verifierProxy_);
        if (maxReportBundleSize_ == 0) revert InvalidBundleBound();
        verifierProxy = verifierProxy_;
        maxReportBundleSize = maxReportBundleSize_;
    }

    function renounceOwnership() public pure override {
        revert OwnershipRenunciationDisabled();
    }

    function registerMarket(
        bytes32 marketId,
        ExecutionMarketConfigInput calldata input
    ) external onlyOwner {
        if (marketId == bytes32(0)) revert InvalidMarketId();
        if (_markets[marketId].status != MarketStatus.UNSET) {
            revert MarketAlreadyRegistered(marketId);
        }
        _validateConfig(input);
        ExecutionMarketConfig memory config = _toConfig(input);
        _markets[marketId] = config;
        uint64 version = ++registryVersion;
        emit MarketRegistered(
            marketId, config.streamId, version, keccak256(abi.encode(marketId, config))
        );
        emit MarketStatusChanged(marketId, MarketStatus.UNSET, MarketStatus.CANDIDATE, version);
    }

    function enableMarket(
        bytes32 marketId
    ) external onlyOwner {
        ExecutionMarketConfig storage config = _markets[marketId];
        MarketStatus previous = config.status;
        if (previous == MarketStatus.UNSET) revert UnsupportedMarket(marketId);
        if (previous != MarketStatus.CANDIDATE) {
            revert InvalidMarketStatusTransition(marketId, previous, MarketStatus.ENABLED);
        }
        _validateConfig(
            ExecutionMarketConfigInput(
                config.streamId,
                config.executionDelay,
                config.maxReportWindow,
                config.streamDecimals
            )
        );
        config.status = MarketStatus.ENABLED;
        emit MarketStatusChanged(marketId, previous, MarketStatus.ENABLED, ++registryVersion);
    }

    function disableMarket(
        bytes32 marketId
    ) external onlyOwner {
        ExecutionMarketConfig storage config = _markets[marketId];
        MarketStatus previous = config.status;
        if (previous == MarketStatus.UNSET) revert UnsupportedMarket(marketId);
        if (previous != MarketStatus.CANDIDATE && previous != MarketStatus.ENABLED) {
            revert InvalidMarketStatusTransition(marketId, previous, MarketStatus.DISABLED);
        }
        config.status = MarketStatus.DISABLED;
        emit MarketStatusChanged(marketId, previous, MarketStatus.DISABLED, ++registryVersion);
    }

    function updateMarket(
        bytes32 marketId,
        ExecutionMarketConfigInput calldata input
    ) external onlyOwner {
        MarketStatus previous = _markets[marketId].status;
        if (previous == MarketStatus.UNSET) revert UnsupportedMarket(marketId);
        if (previous != MarketStatus.DISABLED) revert MarketMustBeDisabled(marketId, previous);
        _validateConfig(input);
        ExecutionMarketConfig memory config = _toConfig(input);
        _markets[marketId] = config;
        uint64 version = ++registryVersion;
        emit MarketUpdated(
            marketId, config.streamId, version, keccak256(abi.encode(marketId, config))
        );
        emit MarketStatusChanged(marketId, previous, MarketStatus.CANDIDATE, version);
    }

    function _validateConfig(
        ExecutionMarketConfigInput memory input
    ) internal pure {
        if (input.streamId == bytes32(0) || uint16(bytes2(input.streamId)) != 3) {
            revert InvalidStreamId();
        }
        if (input.executionDelay == 0) revert InvalidExecutionDelay();
        if (input.maxReportWindow == 0) revert InvalidMaxReportWindow();
        if (input.streamDecimals > 18) revert UnsupportedStreamDecimals(input.streamDecimals);
    }

    function _toConfig(
        ExecutionMarketConfigInput memory input
    ) internal pure returns (ExecutionMarketConfig memory) {
        return ExecutionMarketConfig(
            input.streamId,
            input.executionDelay,
            input.maxReportWindow,
            input.streamDecimals,
            MarketStatus.CANDIDATE
        );
    }

    function setAuthorizedConsumer(
        address consumer,
        bool enabled
    ) external onlyOwner {
        if (consumer == address(0)) revert ZeroAddress();
        if (enabled && consumer.code.length == 0) revert NoContractCode(consumer);
        _authorizedConsumers[consumer] = enabled;
        emit AuthorizedConsumerUpdated(consumer, enabled, ++registryVersion);
    }

    function verifyExecutionPrice(
        bytes32 marketId,
        bytes[] calldata fullReports
    ) external override returns (ExecutionPrice memory) {
        if (!_authorizedConsumers[msg.sender]) revert UnauthorizedConsumer(msg.sender);
        ExecutionMarketConfig memory config = _markets[marketId];
        MarketStatus status = config.status;
        if (status == MarketStatus.UNSET) revert UnsupportedMarket(marketId);
        if (status != MarketStatus.ENABLED) revert MarketNotEnabled(marketId, status);
        if (fullReports.length == 0) revert EmptyReportBundle();
        if (fullReports.length > maxReportBundleSize) {
            revert TooManyReports(fullReports.length, maxReportBundleSize);
        }
        _requireHealthySequencer();
        uint32 referenceTimestamp = _referenceTimestamp(config.executionDelay);
        bytes[] memory verified = _authenticate(fullReports);
        (DataStreamsV3.Report memory selected, uint256 matches) =
            _select(verified, config, referenceTimestamp);
        if (matches == 0) revert ReportWindowUnavailable(referenceTimestamp);
        if (matches > 1) revert OverlappingReportWindows(referenceTimestamp, matches);
        return ExecutionPrice({
            price1e18: _normalize(selected.price, config.streamDecimals),
            referenceTimestamp: referenceTimestamp,
            validFromTimestamp: selected.validFromTimestamp,
            observationsTimestamp: selected.observationsTimestamp,
            streamId: selected.feedId
        });
    }

    /// @dev Scan every body; never select using unverified payload bytes or array position.
    function _select(
        bytes[] memory verified,
        ExecutionMarketConfig memory config,
        uint32 referenceTimestamp
    ) internal view returns (DataStreamsV3.Report memory selected, uint256 matches) {
        for (uint256 i; i < verified.length; ++i) {
            DataStreamsV3.Report memory candidate = _decodeAndValidate(verified[i], config);
            if (
                candidate.validFromTimestamp <= referenceTimestamp
                    && referenceTimestamp <= candidate.observationsTimestamp
            ) {
                selected = candidate;
                ++matches;
            }
        }
    }

    function _normalize(
        int192 price,
        uint8 decimals
    ) internal pure returns (uint256) {
        // Sign validation precedes this conversion for every report.
        return OracleMath.normalizePrice(uint256(int256(price)), decimals);
    }

    function _referenceTimestamp(
        uint32 delay
    ) internal view returns (uint32) {
        if (block.timestamp < delay || block.timestamp - delay > type(uint32).max) {
            revert ReferenceTimestampOutOfRange(block.timestamp, delay);
        }
        return uint32(block.timestamp - delay);
    }

    function _decodeAndValidate(
        bytes memory body,
        ExecutionMarketConfig memory config
    ) internal view returns (DataStreamsV3.Report memory report) {
        if (config.streamId == bytes32(0)) revert InvalidStreamId();
        report = DataStreamsV3.decode(body);
        if (report.feedId != config.streamId) revert WrongStreamId(config.streamId, report.feedId);
        if (report.price <= 0) revert InvalidReportPrice(report.price);
        if (report.validFromTimestamp > report.observationsTimestamp) {
            revert InvalidReportTimestampOrder(
                report.validFromTimestamp, report.observationsTimestamp
            );
        }
        if (report.expiresAt < block.timestamp) {
            revert ReportExpired(report.expiresAt, block.timestamp);
        }
        if (report.observationsTimestamp > block.timestamp) {
            revert FutureObservation(report.observationsTimestamp, block.timestamp);
        }
        uint32 width = report.observationsTimestamp - report.validFromTimestamp;
        if (width > config.maxReportWindow) {
            revert ReportWindowTooWide(width, config.maxReportWindow);
        }
        return report;
    }

    function _authenticate(
        bytes[] calldata fullReports
    ) internal returns (bytes[] memory verified) {
        verified = IVerifierProxy(verifierProxy).verifyBulk(fullReports, bytes(""));
        if (verified.length != fullReports.length) {
            revert VerifierResponseLengthMismatch(fullReports.length, verified.length);
        }
    }

    function marketConfig(
        bytes32 marketId
    ) external view override returns (ExecutionMarketConfig memory) {
        return _markets[marketId];
    }

    /// @notice Commits to the market identity, all parameters and lifecycle state.
    function configHash(
        bytes32 marketId
    ) external view override returns (bytes32) {
        return keccak256(abi.encode(marketId, _markets[marketId]));
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
        (bool ok,,) = _readSequencer(feed);
        if (!ok) revert SequencerFeedCallFailed(feed);
        _sequencerConfig = SequencerConfig(feed, gracePeriod);
        emit SequencerConfigUpdated(feed, gracePeriod, ++registryVersion);
    }

    /// @dev Bound returndata copying and validate narrow round identifiers before trusting the shape.
    function _requireHealthySequencer() internal view {
        SequencerConfig memory config = _sequencerConfig;
        if (config.feed == address(0)) revert SequencerNotConfigured();
        (bool ok, int256 answer, uint256 startedAt) = _readSequencer(config.feed);
        if (!ok || answer != 0 || startedAt == 0 || startedAt > block.timestamp) {
            revert SequencerDown();
        }
        if (block.timestamp - startedAt <= config.gracePeriod) {
            revert SequencerGracePeriod(startedAt, config.gracePeriod);
        }
    }

    function _readSequencer(
        address feed
    ) internal view returns (bool ok, int256 answer, uint256 startedAt) {
        bytes memory data = abi.encodeCall(IAggregatorV3.latestRoundData, ());
        uint256[5] memory words;
        uint256 size;
        assembly ("memory-safe") {
            ok := staticcall(gas(), feed, add(data, 32), mload(data), words, 160)
            size := returndatasize()
        }
        if (!ok || size != 160 || words[0] > type(uint80).max || words[4] > type(uint80).max) {
            return (false, 0, 0);
        }
        assembly ("memory-safe") { answer := mload(add(words, 32)) }
        return (true, answer, words[2]);
    }

    function isAuthorizedConsumer(
        address consumer
    ) external view override returns (bool) {
        return _authorizedConsumers[consumer];
    }
}
