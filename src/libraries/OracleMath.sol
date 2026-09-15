// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

/// @notice Decimal normalization and full-precision USD valuation for Statics Oracle.
library OracleMath {
    uint8 internal constant MAX_SUPPORTED_DECIMALS = 18;

    error UnsupportedFeedDecimals(uint8 decimals);
    error UnsupportedTokenDecimals(uint8 decimals);

    /// @notice Normalizes a positive feed answer to 18-decimal USD precision.
    /// @dev Price-sign validation belongs to the oracle evaluator before this function is called.
    function normalizePrice(
        uint256 answer,
        uint8 feedDecimals
    ) internal pure returns (uint256 price1e18) {
        if (feedDecimals > MAX_SUPPORTED_DECIMALS) {
            revert UnsupportedFeedDecimals(feedDecimals);
        }

        uint256 scale = 10 ** uint256(MAX_SUPPORTED_DECIMALS - feedDecimals);
        return Math.mulDiv(answer, scale, 1);
    }

    /// @notice Values a raw token amount using an 18-decimal USD price.
    /// @dev Rounds down, matching Solidity and OpenZeppelin Math.mulDiv defaults.
    function valueUsd(
        uint256 amount,
        uint256 price1e18,
        uint8 tokenDecimals
    ) internal pure returns (uint256 value1e18) {
        if (tokenDecimals > MAX_SUPPORTED_DECIMALS) {
            revert UnsupportedTokenDecimals(tokenDecimals);
        }

        uint256 tokenUnit = 10 ** uint256(tokenDecimals);
        return Math.mulDiv(amount, price1e18, tokenUnit);
    }
}
