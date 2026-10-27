// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import { StaticsExecutionOracle } from "src/StaticsExecutionOracle.sol";
import { IStaticsExecutionOracle as IEO } from "src/interfaces/IStaticsExecutionOracle.sol";
import { DataStreamsV3 } from "src/libraries/DataStreamsV3.sol";
import { ExecutionTestBase } from "test/ExecutionTestBase.sol";

contract ExecutionSelectionTest is ExecutionTestBase {
    function testReferenceTimeRejectsUnderflowAndNarrowing() public {
        bytes[] memory reports = bundle(report());
        sequencer.setRoundData(1, 0, 1, 1, 1);
        oracle.setSequencerConfig(address(sequencer), 0);
        vm.warp(9);
        vm.expectRevert(
            abi.encodeWithSelector(
                StaticsExecutionOracle.ReferenceTimestampOutOfRange.selector, 9, 10
            )
        );
        oracle.verifyExecutionPrice(MARKET, reports);
        vm.warp(uint256(type(uint32).max) + 11);
        vm.expectRevert(
            abi.encodeWithSelector(
                StaticsExecutionOracle.ReferenceTimestampOutOfRange.selector,
                uint256(type(uint32).max) + 11,
                10
            )
        );
        oracle.verifyExecutionPrice(MARKET, reports);
    }

    function testUnavailableAndDuplicatedMatchingWindowsFail() public {
        DataStreamsV3.Report memory r = report();
        r.validFromTimestamp = 950;
        r.observationsTimestamp = 960;
        bytes[] memory reports = bundle(r);
        vm.expectRevert(
            abi.encodeWithSelector(StaticsExecutionOracle.ReportWindowUnavailable.selector, 990)
        );
        oracle.verifyExecutionPrice(MARKET, reports);
        reports = new bytes[](2);
        reports[0] = signed(report());
        reports[1] = reports[0];
        vm.expectRevert(
            abi.encodeWithSelector(StaticsExecutionOracle.OverlappingReportWindows.selector, 990, 2)
        );
        oracle.verifyExecutionPrice(MARKET, reports);
    }

    function testReturnsAuthenticatedPriceAndCompleteMetadata() public {
        IEO.ExecutionPrice memory got = oracle.verifyExecutionPrice(MARKET, bundle(report()));
        assertEq(got.price1e18, 1_234_567_890_000_000_000);
        assertEq(got.referenceTimestamp, 990);
        assertEq(got.validFromTimestamp, 985);
        assertEq(got.observationsTimestamp, 995);
        assertEq(got.streamId, STREAM);
    }

    function testUnorderedBundleAndNonmatchingDuplicatesDoNotChangePrice() public {
        DataStreamsV3.Report memory old = report();
        old.validFromTimestamp = 950;
        old.observationsTimestamp = 960;
        old.price = 1;
        bytes[] memory reports = new bytes[](3);
        reports[0] = signed(old);
        reports[1] = signed(report());
        reports[2] = reports[0];
        IEO.ExecutionPrice memory a = oracle.verifyExecutionPrice(MARKET, reports);
        (reports[0], reports[1]) = (reports[1], reports[0]);
        IEO.ExecutionPrice memory b = oracle.verifyExecutionPrice(MARKET, reports);
        assertEq(abi.encode(a), abi.encode(b));
        assertEq(a.price1e18, 1_234_567_890_000_000_000);
    }
}
