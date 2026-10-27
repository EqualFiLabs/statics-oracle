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
}
