// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script } from "forge-std/Script.sol";

import { StaticsOracle } from "src/StaticsOracle.sol";

contract DeployStaticsOracle is Script {
    uint256 internal constant ROBINHOOD_MAINNET_CHAIN_ID = 4663;

    error WrongChain(uint256 expected, uint256 actual);
    error ZeroInitialOwner();

    function run() external returns (StaticsOracle oracle) {
        address initialOwner = vm.envAddress("INITIAL_OWNER");
        vm.startBroadcast();
        oracle = deploy(initialOwner);
        vm.stopBroadcast();
    }

    function deploy(
        address initialOwner
    ) public returns (StaticsOracle oracle) {
        if (block.chainid != ROBINHOOD_MAINNET_CHAIN_ID) {
            revert WrongChain(ROBINHOOD_MAINNET_CHAIN_ID, block.chainid);
        }
        if (initialOwner == address(0)) revert ZeroInitialOwner();
        oracle = new StaticsOracle(initialOwner);
    }
}
