// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { Test } from "forge-std/Test.sol";

import { OracleMath } from "src/libraries/OracleMath.sol";

contract OracleMathFuzzHarness {
    function normalize(
        uint256 answer,
        uint8 decimals
    ) external pure returns (uint256) {
        return OracleMath.normalizePrice(answer, decimals);
    }

    function value(
        uint256 amount,
        uint256 price,
        uint8 decimals
    ) external pure returns (uint256) {
        return OracleMath.valueUsd(amount, price, decimals);
    }
}

contract OracleMathFuzzTest is Test {
    OracleMathFuzzHarness internal harness = new OracleMathFuzzHarness();

    function testFuzz_NormalizationMatchesEconomicScale(
        uint96 wholeDollarPrice,
        uint8 feedDecimalsSeed
    ) external view {
        uint8 feedDecimals = uint8(bound(feedDecimalsSeed, 0, 18));
        uint256 answer = uint256(wholeDollarPrice) * 10 ** uint256(feedDecimals);
        assertEq(harness.normalize(answer, feedDecimals), uint256(wholeDollarPrice) * 1e18);
    }

    function testFuzz_ValueMatchesFullPrecisionReference(
        uint128 amount,
        uint128 price,
        uint8 tokenDecimalsSeed
    ) external view {
        uint8 tokenDecimals = uint8(bound(tokenDecimalsSeed, 0, 18));
        assertEq(
            harness.value(amount, price, tokenDecimals),
            Math.mulDiv(amount, price, 10 ** uint256(tokenDecimals))
        );
    }

    function testFuzz_TokenRepresentationScalePreservesValue(
        uint64 wholeTokens,
        uint96 price,
        uint8 tokenDecimalsSeed
    ) external view {
        uint8 tokenDecimals = uint8(bound(tokenDecimalsSeed, 0, 18));
        uint256 amount = uint256(wholeTokens) * 10 ** uint256(tokenDecimals);
        assertEq(harness.value(amount, price, tokenDecimals), uint256(wholeTokens) * price);
    }
}
