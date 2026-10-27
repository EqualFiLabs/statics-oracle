// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Atomic synthetic execution pricing; no position or economic accounting.
interface IStaticsExecutionOracle {
    enum MarketStatus {
        UNSET,
        CANDIDATE,
        ENABLED,
        DISABLED
    }

    struct ExecutionMarketConfigInput {
        bytes32 streamId;
        uint32 executionDelay;
        uint32 maxReportWindow;
        uint8 streamDecimals;
    }

    struct ExecutionMarketConfig {
        bytes32 streamId;
        uint32 executionDelay;
        uint32 maxReportWindow;
        uint8 streamDecimals;
        MarketStatus status;
    }

    struct SequencerConfig {
        address feed;
        uint32 gracePeriod;
    }

    struct ExecutionPrice {
        uint256 price1e18;
        uint32 referenceTimestamp;
        uint32 validFromTimestamp;
        uint32 observationsTimestamp;
        bytes32 streamId;
    }
    /// @dev All signed reports are authenticated. Endpoint provenance has no authority.
    function verifyExecutionPrice(
        bytes32 marketId,
        bytes[] calldata fullReports
    ) external returns (ExecutionPrice memory);
    function marketConfig(
        bytes32 marketId
    ) external view returns (ExecutionMarketConfig memory);
    function configHash(
        bytes32 marketId
    ) external view returns (bytes32);
    function sequencerConfig() external view returns (SequencerConfig memory);
    function isAuthorizedConsumer(
        address consumer
    ) external view returns (bool);
    function verifierProxy() external view returns (address);
    function maxReportBundleSize() external view returns (uint8);
    function registryVersion() external view returns (uint64);
}
