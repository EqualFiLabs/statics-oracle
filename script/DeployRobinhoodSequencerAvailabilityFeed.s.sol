// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script } from "forge-std/Script.sol";

import { RobinhoodSequencerAvailabilityFeed } from "src/RobinhoodSequencerAvailabilityFeed.sol";

contract DeployRobinhoodSequencerAvailabilityFeed is Script {
    function run() external returns (RobinhoodSequencerAvailabilityFeed feed) {
        address l1Reporter = vm.envAddress("SEQUENCER_L1_REPORTER");

        vm.startBroadcast();
        feed = deploy(l1Reporter);
        vm.stopBroadcast();
    }

    function deploy(
        address l1Reporter
    ) public returns (RobinhoodSequencerAvailabilityFeed feed) {
        feed = new RobinhoodSequencerAvailabilityFeed(l1Reporter);
    }
}
