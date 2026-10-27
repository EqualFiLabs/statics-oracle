// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import { IStaticsExecutionOracle as IEO } from "src/interfaces/IStaticsExecutionOracle.sol";
import { DataStreamsV3 } from "src/libraries/DataStreamsV3.sol";
import { OracleMath } from "src/libraries/OracleMath.sol";
import { ExecutionTestBase } from "test/ExecutionTestBase.sol";

contract ExecutionNormalizationTest is ExecutionTestBase {
    function setPrecision(
        uint8 decimals
    ) internal {
        oracle.disableMarket(MARKET);
        oracle.updateMarket(MARKET, IEO.ExecutionMarketConfigInput(STREAM, 10, 30, decimals));
        oracle.enableMarket(MARKET);
    }

    function testEquivalentEightAndEighteenDecimalReportsReturnSameUsd() public {
        uint256 expected = oracle.verifyExecutionPrice(MARKET, bundle(report())).price1e18;
        setPrecision(18);
        DataStreamsV3.Report memory r = report();
        r.price = 1_234_567_890_000_000_000;
        assertEq(oracle.verifyExecutionPrice(MARKET, bundle(r)).price1e18, expected);
    }

    function testLargestV3PriceAtZeroDecimalsFitsWithoutTruncation() public {
        setPrecision(0);
        DataStreamsV3.Report memory r = report();
        r.price = type(int192).max;
        assertEq(
            oracle.verifyExecutionPrice(MARKET, bundle(r)).price1e18,
            uint256(uint192(type(int192).max)) * 1e18
        );
    }

    function normalize(
        uint256 value
    ) external pure returns (uint256) {
        return OracleMath.normalizePrice(value, 0);
    }

    function testSharedNormalizerRejectsOverflowRatherThanWraps() public {
        vm.expectRevert();
        this.normalize(type(uint256).max);
    }
}
