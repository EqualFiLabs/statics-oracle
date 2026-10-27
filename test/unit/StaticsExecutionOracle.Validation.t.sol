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

    function testGapExpandedWindowBeyondReviewedBoundFails() public {
        DataStreamsV3.Report memory r = report();
        r.validFromTimestamp = 964;
        bytes[] memory reports = bundle(r);
        vm.expectRevert(
            abi.encodeWithSelector(StaticsExecutionOracle.ReportWindowTooWide.selector, 31, 30)
        );
        oracle.verifyExecutionPrice(MARKET, reports);
    }

    function testExactExpiryWindowAndFutureBoundariesAccept() public {
        DataStreamsV3.Report memory r = report();
        r.expiresAt = 1000;
        r.validFromTimestamp = 970;
        r.observationsTimestamp = 1000;
        assertEq(
            oracle.verifyExecutionPrice(MARKET, bundle(r)).price1e18, 1_234_567_890_000_000_000
        );
    }

    function testChangingFeeBidAndAskDoesNotChangeExecution() public {
        DataStreamsV3.Report memory r = report();
        bytes[] memory first = bundle(r);
        uint256 expected = oracle.verifyExecutionPrice(MARKET, first).price1e18;
        r.bid = type(int192).min;
        r.ask = type(int192).max;
        r.nativeFee = type(uint192).max;
        r.linkFee = type(uint192).max;
        assertEq(oracle.verifyExecutionPrice(MARKET, bundle(r)).price1e18, expected);
    }

    function testNoncanonicalNarrowAbiWordFailsAfterAuthentication() public {
        bytes memory body = abi.encode(report());
        assembly ("memory-safe") { mstore(add(body, 64), shl(32, 1)) }
        bytes[] memory reports = new bytes[](1);
        reports[0] = hex"deadbeef";
        verifier.accept(reports[0], body);
        vm.expectRevert();
        oracle.verifyExecutionPrice(MARKET, reports);
    }

    function testEveryNonmatchingBodyStillRequiresPositivePrice() public {
        DataStreamsV3.Report memory r = report();
        r.validFromTimestamp = 950;
        r.observationsTimestamp = 960;
        r.price = -1;
        bytes[] memory reports = new bytes[](2);
        reports[0] = signed(report());
        reports[1] = signed(r);
        vm.expectRevert(
            abi.encodeWithSelector(StaticsExecutionOracle.InvalidReportPrice.selector, int192(-1))
        );
        oracle.verifyExecutionPrice(MARKET, reports);
    }
}
