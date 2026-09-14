// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Minimal safety and metadata surface exposed by Robinhood Stock Tokens.
interface IRobinhoodStockToken {
    function oraclePaused() external view returns (bool);

    function decimals() external view returns (uint8);
}
