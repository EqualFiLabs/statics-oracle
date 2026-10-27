// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import { Test } from "forge-std/Test.sol";
import { DeployStaticsExecutionOracle } from "script/DeployStaticsExecutionOracle.s.sol";
import { StaticsExecutionOracle } from "src/StaticsExecutionOracle.sol";
import { ExecutionVerifierMock } from "test/mocks/ExecutionOracleMocks.sol";

contract ExecutionDeploymentScriptsTest is Test {
    DeployStaticsExecutionOracle internal deployer;
    ExecutionVerifierMock internal verifier;

    function setUp() public {
        vm.chainId(46630);
        deployer = new DeployStaticsExecutionOracle();
        verifier = new ExecutionVerifierMock();
    }

    function testDeploymentRejectsWrongChainAndRuntime() public {
        vm.expectRevert(DeployStaticsExecutionOracle.WrongChain.selector);
        deployer.deploy(4663, address(this), address(verifier), address(verifier).codehash, 5);
        vm.expectRevert(DeployStaticsExecutionOracle.InvalidVerifierBinding.selector);
        deployer.deploy(46630, address(this), address(verifier), bytes32(uint256(1)), 5);
        StaticsExecutionOracle oracle =
            deployer.deploy(46630, address(this), address(verifier), address(verifier).codehash, 5);
        assertEq(oracle.owner(), address(this));
        assertEq(oracle.verifierProxy(), address(verifier));
    }

    function testCandidateManifestCannotTriggerBroadcast() public {
        vm.expectRevert(DeployStaticsExecutionOracle.UnratifiedParameters.selector);
        deployer.run();
    }
}
