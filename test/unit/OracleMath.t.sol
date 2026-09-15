// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";

import { OracleMath } from "src/libraries/OracleMath.sol";

contract OracleMathHarness {
    function normalizePrice(
        uint256 answer,
        uint8 feedDecimals
    ) external pure returns (uint256) {
        return OracleMath.normalizePrice(answer, feedDecimals);
    }

    function valueUsd(
        uint256 amount,
        uint256 price1e18,
        uint8 tokenDecimals
    ) external pure returns (uint256) {
        return OracleMath.valueUsd(amount, price1e18, tokenDecimals);
    }
}

contract OracleMathTest is Test {
    OracleMathHarness internal harness;

    function setUp() external {
        harness = new OracleMathHarness();
    }

    function test_NormalizeEightDecimalFeed() external pure {
        assertEq(OracleMath.normalizePrice(123_456_789, 8), 1_234_567_890_000_000_000);
    }

    function test_NormalizeEighteenDecimalFeed() external pure {
        assertEq(OracleMath.normalizePrice(4_000e18, 18), 4_000e18);
    }

    function test_ValueSixDecimalToken() external pure {
        assertEq(OracleMath.valueUsd(2_500_000, 4e18, 6), 10e18);
    }

    function test_ValueEightDecimalToken() external pure {
        assertEq(OracleMath.valueUsd(25_000_000, 100_000e18, 8), 25_000e18);
    }

    function test_ValueEighteenDecimalToken() external pure {
        assertEq(OracleMath.valueUsd(3e17, 4_000e18, 18), 1_200e18);
    }

    function test_ZeroAmountAlwaysValuesToZero() external pure {
        assertEq(OracleMath.valueUsd(0, type(uint256).max, 18), 0);
    }

    function test_LargeAmountUsesFullPrecisionMultiplication() external pure {
        assertEq(OracleMath.valueUsd(type(uint256).max, 1e18, 18), type(uint256).max);
    }

    function test_ValueRoundsDown() external pure {
        assertEq(OracleMath.valueUsd(1, 1e18 + 1, 18), 1);
    }

    function test_RevertWhen_FeedDecimalsExceedSupportedBound() external {
        vm.expectRevert(abi.encodeWithSelector(OracleMath.UnsupportedFeedDecimals.selector, 19));
        harness.normalizePrice(1, 19);
    }

    function test_RevertWhen_TokenDecimalsExceedSupportedBound() external {
        vm.expectRevert(abi.encodeWithSelector(OracleMath.UnsupportedTokenDecimals.selector, 19));
        harness.valueUsd(1, 1e18, 19);
    }
}
