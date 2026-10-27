// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import { StaticsExecutionOracle } from "src/StaticsExecutionOracle.sol";
import { DataStreamsV3 } from "src/libraries/DataStreamsV3.sol";
import { ExecutionTestBase } from "test/ExecutionTestBase.sol";

contract ExecutionValidationTest is ExecutionTestBase {
    function testZeroAndNegativeConsensusPriceFail() public {
        DataStreamsV3.Report memory r = report();
        r.price = 0;
        bytes[] memory reports = bundle(r);
        vm.expectRevert(
            abi.encodeWithSelector(StaticsExecutionOracle.InvalidReportPrice.selector, 0)
        );
        oracle.verifyExecutionPrice(MARKET, reports);
        r.price = -1;
        reports = bundle(r);
        vm.expectRevert(
            abi.encodeWithSelector(StaticsExecutionOracle.InvalidReportPrice.selector, int192(-1))
        );
        oracle.verifyExecutionPrice(MARKET, reports);
    }

    function testReversedSignedWindowFails() public {
        DataStreamsV3.Report memory r = report();
        r.validFromTimestamp = 996;
        bytes[] memory reports = bundle(r);
        vm.expectRevert(
            abi.encodeWithSelector(
                StaticsExecutionOracle.InvalidReportTimestampOrder.selector, 996, 995
            )
        );
        oracle.verifyExecutionPrice(MARKET, reports);
    }

    function testExpiredReportFailsIncludingNonmatchingCandidate() public {
        DataStreamsV3.Report memory r = report();
        r.validFromTimestamp = 950;
        r.observationsTimestamp = 960;
        r.expiresAt = 999;
        bytes[] memory reports = new bytes[](2);
        reports[0] = signed(report());
        reports[1] = signed(r);
        vm.expectRevert(
            abi.encodeWithSelector(StaticsExecutionOracle.ReportExpired.selector, 999, 1000)
        );
        oracle.verifyExecutionPrice(MARKET, reports);
    }

    function testFutureObservationsHaveNoImplicitTolerance() public {
        DataStreamsV3.Report memory r = report();
        r.observationsTimestamp = 1001;
        bytes[] memory reports = bundle(r);
        vm.expectRevert(
            abi.encodeWithSelector(StaticsExecutionOracle.FutureObservation.selector, 1001, 1000)
        );
        oracle.verifyExecutionPrice(MARKET, reports);
    }
}
