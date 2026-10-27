// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import { StaticsExecutionOracle } from "src/StaticsExecutionOracle.sol";
import { IAggregatorV3 } from "src/interfaces/IAggregatorV3.sol";
import { ExecutionTestBase } from "test/ExecutionTestBase.sol";

contract ExecutionSequencerTest is ExecutionTestBase {
    function testMalformedResponsesFailClosedWithBoundedCopy() public {
        bytes[] memory reports = bundle(report());
        bytes memory callData = abi.encodeCall(IAggregatorV3.latestRoundData, ());
        bytes[4] memory malformed =
            [bytes(hex"01"), new bytes(159), new bytes(161), new bytes(65536)];
        for (uint256 i; i < malformed.length; ++i) {
            vm.mockCall(address(sequencer), callData, malformed[i]);
            vm.expectRevert(StaticsExecutionOracle.SequencerDown.selector);
            oracle.verifyExecutionPrice(MARKET, reports);
            vm.clearMockedCalls();
        }
        vm.mockCall(
            address(sequencer),
            callData,
            abi.encode(
                uint256(type(uint80).max) + 1, int256(0), uint256(900), uint256(900), uint256(1)
            )
        );
        vm.expectRevert(StaticsExecutionOracle.SequencerDown.selector);
        oracle.verifyExecutionPrice(MARKET, reports);
    }

    function testRecoveryRequiresStrictlyElapsedGrace() public {
        bytes[] memory reports = bundle(report());
        sequencer.setRoundData(1, 0, 990, 990, 1);
        vm.expectRevert(
            abi.encodeWithSelector(StaticsExecutionOracle.SequencerGracePeriod.selector, 990, 10)
        );
        oracle.verifyExecutionPrice(MARKET, reports);
        vm.warp(1001);
        assertGt(oracle.verifyExecutionPrice(MARKET, reports).price1e18, 0);
    }

    function testFutureRecoveryAndFeedFailureNeverReturnFallback() public {
        bytes[] memory reports = bundle(report());
        sequencer.setRoundData(1, 0, 1001, 1001, 1);
        vm.expectRevert(StaticsExecutionOracle.SequencerDown.selector);
        oracle.verifyExecutionPrice(MARKET, reports);
        sequencer.setLatestRoundCallFails(true);
        vm.expectRevert(StaticsExecutionOracle.SequencerDown.selector);
        oracle.verifyExecutionPrice(MARKET, reports);
    }
}
