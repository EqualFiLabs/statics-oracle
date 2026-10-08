// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";

import { RobinhoodSequencerReporterL1 } from "src/RobinhoodSequencerReporterL1.sol";
import { IArbitrumDelayedInbox } from "src/interfaces/IArbitrumDelayedInbox.sol";

contract RobinhoodSequencerReporterL1ForkTest is Test {
    function test_MainnetInboxCodeAndRetryableQuote() external {
        _assertInbox("ETH_MAINNET", 1, 0x1A07cc4BD17E0118BdB54D70990D2158AbAD7a2D);
    }

    function test_SepoliaInboxCodeAndRetryableQuote() external {
        _assertInbox("ETH_SEPOLIA", 11_155_111, 0xF2939afA86F6f933A3CE17fCAB007907B6b0B7a4);
    }

    function test_MainnetReporterCanCreateConfigurationRetryable() external {
        string memory rpc = vm.envOr("ETH_MAINNET", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true, "ETH_MAINNET is not configured");
            return;
        }
        vm.createSelectFork(rpc);
        address[] memory observers = new address[](3);
        observers[0] = address(0x1000);
        observers[1] = address(0x2000);
        observers[2] = address(0x3000);
        RobinhoodSequencerReporterL1 reporter = new RobinhoodSequencerReporterL1(
            address(this), observers, 2, address(this), 300_000, 500_000, 1 gwei
        );
        vm.deal(address(reporter), 1 ether);
        reporter.initializeL2Feed(address(0xCAFE));
        assertEq(reporter.l2Feed(), address(0xCAFE));
        assertLt(address(reporter).balance, 1 ether);
    }

    function _assertInbox(
        string memory environment,
        uint256 expectedChainId,
        address inbox
    ) private {
        string memory rpc = vm.envOr(environment, string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true, string.concat(environment, " is not configured"));
            return;
        }
        vm.createSelectFork(rpc);
        assertEq(block.chainid, expectedChainId);
        assertGt(inbox.code.length, 0);
        assertGt(IArbitrumDelayedInbox(inbox).calculateRetryableSubmissionFee(68, 1 gwei), 0);
    }
}
