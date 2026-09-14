// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Consumer-facing types and reads for the Statics external-asset oracle.
interface IStaticsOracle {
    enum AssetKind {
        NONE,
        STOCK,
        ETF,
        CRYPTO,
        STABLE
    }

    enum AssetStatus {
        UNSET,
        CANDIDATE,
        ENABLED,
        DISABLED
    }

    enum OracleStatus {
        VALID,
        UNSUPPORTED,
        CANDIDATE,
        DISABLED,
        SEQUENCER_NOT_CONFIGURED,
        SEQUENCER_DOWN,
        SEQUENCER_GRACE_PERIOD,
        STOCK_ORACLE_PAUSED,
        STOCK_PAUSE_CHECK_FAILED,
        FEED_CALL_FAILED,
        INVALID_PRICE,
        INCOMPLETE_ROUND,
        INVALID_TIMESTAMP,
        STALE_PRICE
    }

    struct AssetOracleConfig {
        address feed;
        bytes32 feedDescriptionHash;
        uint32 maxAge;
        uint8 tokenDecimals;
        uint8 feedDecimals;
        AssetKind kind;
        AssetStatus status;
        bool checkOraclePause;
    }

    struct AssetOracleConfigInput {
        address feed;
        bytes32 feedDescriptionHash;
        uint32 maxAge;
        uint8 tokenDecimals;
        uint8 feedDecimals;
        AssetKind kind;
        bool checkOraclePause;
    }

    struct PriceData {
        uint256 price1e18;
        uint256 updatedAt;
        uint80 roundId;
        OracleStatus status;
    }

    function priceUsd(
        address token
    ) external view returns (uint256 price1e18);

    function valueUsd(
        address token,
        uint256 amount
    ) external view returns (uint256 value1e18);

    function basketNav(
        address[] calldata assets,
        uint256[] calldata amounts
    ) external view returns (uint256 nav1e18);

    function peekPrice(
        address token
    ) external view returns (PriceData memory);

    function assetConfig(
        address token
    ) external view returns (AssetOracleConfig memory);

    function registryVersion() external view returns (uint64);
}
