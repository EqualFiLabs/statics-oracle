// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import { StaticsExecutionOracle } from "src/StaticsExecutionOracle.sol";
import { IVerifierProxy } from "src/interfaces/IVerifierProxy.sol";
import { DataStreamsV3 } from "src/libraries/DataStreamsV3.sol";
import { ExecutionTestBase } from "test/ExecutionTestBase.sol";
import { ExecutionVerifierMock } from "test/mocks/ExecutionOracleMocks.sol";

contract ExecutionAuthenticationTest is ExecutionTestBase {
    function testBundleBoundsPrecedeVerifier() public {
        vm.expectRevert(StaticsExecutionOracle.EmptyReportBundle.selector);
        oracle.verifyExecutionPrice(MARKET, new bytes[](0));
        vm.expectRevert(
            abi.encodeWithSelector(StaticsExecutionOracle.TooManyReports.selector, 6, 5)
        );
        oracle.verifyExecutionPrice(MARKET, new bytes[](6));
    }

    function testCompleteBundleUsesSubscriptionVerifierAndBubblesFailure() public {
        bytes[] memory reports = new bytes[](2);
        reports[0] = hex"aabb";
        reports[1] = hex"ccdd";
        vm.expectCall(
            address(verifier), 0, abi.encodeCall(IVerifierProxy.verifyBulk, (reports, bytes("")))
        );
        vm.expectRevert(ExecutionVerifierMock.Unauthenticated.selector);
        oracle.verifyExecutionPrice(MARKET, reports);
    }

    function testVerifierMustReturnOneBodyPerPayload() public {
        bytes[] memory reports = bundle(report());
        verifier.setWrongCount(true);
        vm.expectRevert(
            abi.encodeWithSelector(
                StaticsExecutionOracle.VerifierResponseLengthMismatch.selector, 1, 2
            )
        );
        oracle.verifyExecutionPrice(MARKET, reports);
    }
}
