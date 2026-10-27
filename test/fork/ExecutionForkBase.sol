// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import { Test } from "forge-std/Test.sol";

abstract contract ExecutionForkBase is Test {
    string internal bindings;

    function setUp() public virtual {
        bindings = vm.readFile("config/execution-chain-bindings.json");
    }

    function key(
        uint256 network,
        string memory field
    ) internal pure returns (string memory) {
        return string.concat(".networks[", vm.toString(network), "].", field);
    }

    function forkNetwork(
        uint256 network
    ) internal {
        string memory rpc =
            vm.envOr(network == 0 ? "ROBINHOOD_MAINNET" : "ROBINHOOD_TESTNET", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true, "Configured Robinhood RPC is required");
            return;
        }
        vm.createSelectFork(rpc, vm.parseJsonUint(bindings, key(network, "block")));
        assertEq(block.chainid, vm.parseJsonUint(bindings, key(network, "chainId")));
        assertEq(block.timestamp, vm.parseJsonUint(bindings, key(network, "timestamp")));
    }

    function proxy(
        uint256 network
    ) internal view returns (address) {
        return vm.parseJsonAddress(bindings, key(network, "verifierProxy"));
    }

    function assertProxy(
        uint256 network
    ) internal view {
        assertEq(
            proxy(network).codehash, vm.parseJsonBytes32(bindings, key(network, "verifierCodeHash"))
        );
    }
}
