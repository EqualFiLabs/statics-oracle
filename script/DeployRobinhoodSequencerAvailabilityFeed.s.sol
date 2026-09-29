// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { Script } from "forge-std/Script.sol";

import { RobinhoodSequencerAvailabilityFeed } from "src/RobinhoodSequencerAvailabilityFeed.sol";

contract DeployRobinhoodSequencerAvailabilityFeed is Script {
    using SafeCast for uint256;

    function run() external returns (RobinhoodSequencerAvailabilityFeed feed) {
        address initialOwner = vm.envAddress("SEQUENCER_SIGNAL_OWNER");
        address[] memory observers = vm.envAddress("SEQUENCER_SIGNAL_OBSERVERS", ",");
        uint8 threshold = vm.envUint("SEQUENCER_SIGNAL_THRESHOLD").toUint8();

        vm.startBroadcast();
        feed = deploy(initialOwner, observers, threshold);
        vm.stopBroadcast();
    }

    function deploy(
        address initialOwner,
        address[] memory observers,
        uint8 threshold
    ) public returns (RobinhoodSequencerAvailabilityFeed feed) {
        feed = new RobinhoodSequencerAvailabilityFeed(initialOwner, observers, threshold);
    }
}
