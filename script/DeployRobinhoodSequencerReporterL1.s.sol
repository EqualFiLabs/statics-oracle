// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { Script } from "forge-std/Script.sol";

import { RobinhoodSequencerReporterL1 } from "src/RobinhoodSequencerReporterL1.sol";

contract DeployRobinhoodSequencerReporterL1 is Script {
    using SafeCast for uint256;

    function run() external returns (RobinhoodSequencerReporterL1 reporter) {
        address owner = vm.envAddress("SEQUENCER_SIGNAL_OWNER");
        address[] memory observers = vm.envAddress("SEQUENCER_SIGNAL_OBSERVERS", ",");
        uint8 threshold = vm.envUint("SEQUENCER_SIGNAL_THRESHOLD").toUint8();
        address refundAddress = vm.envAddress("SEQUENCER_L2_REFUND_ADDRESS");
        uint256 statusGasLimit = vm.envUint("SEQUENCER_STATUS_GAS_LIMIT");
        uint256 configurationGasLimit = vm.envUint("SEQUENCER_CONFIGURATION_GAS_LIMIT");
        uint256 gasPriceBid = vm.envUint("SEQUENCER_L2_GAS_PRICE_BID");

        vm.startBroadcast();
        reporter = deploy(
            owner,
            observers,
            threshold,
            refundAddress,
            statusGasLimit,
            configurationGasLimit,
            gasPriceBid
        );
        vm.stopBroadcast();
    }

    function deploy(
        address owner,
        address[] memory observers,
        uint8 threshold,
        address refundAddress,
        uint256 statusGasLimit,
        uint256 configurationGasLimit,
        uint256 gasPriceBid
    ) public returns (RobinhoodSequencerReporterL1 reporter) {
        reporter = new RobinhoodSequencerReporterL1(
            owner,
            observers,
            threshold,
            refundAddress,
            statusGasLimit,
            configurationGasLimit,
            gasPriceBid
        );
    }
}
