// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IStaticsExecutionOracle } from "src/interfaces/IStaticsExecutionOracle.sol";

/// @notice Transaction-local Data Streams execution adapter for synthetic markets.
contract StaticsExecutionOracle is Ownable2Step, IStaticsExecutionOracle {
    address public immutable override verifierProxy;
    uint8 public immutable override maxReportBundleSize;
    uint64 public override registryVersion;
    mapping(bytes32 marketId => ExecutionMarketConfig) private _markets;

    error ZeroAddress();
    error NoContractCode(address account);
    error InvalidBundleBound();
    error ExecutionNotAvailable();
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

    function verifyExecutionPrice(
        bytes32,
        bytes[] calldata
    ) external virtual override returns (ExecutionPrice memory) {
        revert ExecutionNotAvailable();
    }

    function marketConfig(
        bytes32 marketId
    ) external view override returns (ExecutionMarketConfig memory) {
        return _markets[marketId];
    }

    function configHash(
        bytes32
    ) external view override returns (bytes32) {
        return bytes32(0);
    }

    function sequencerConfig() external view override returns (SequencerConfig memory) {
        return SequencerConfig(address(0), 0);
    }

    function isAuthorizedConsumer(
        address
    ) external view override returns (bool) {
        return false;
    }
}
