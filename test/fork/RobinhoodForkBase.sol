// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";

abstract contract RobinhoodForkBase is Test {
    string internal manifestJson;
    uint256 internal assetCount;
    uint256 internal verifiedBlock;

    function _setUpRobinhoodFork() internal {
        string memory rpc = vm.envOr("ROBINHOOD_MAINNET", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true, "ROBINHOOD_MAINNET is not configured");
            return;
        }

        manifestJson = vm.readFile("config/robinhood-mainnet.assets.json");
        assetCount = vm.parseJsonUint(manifestJson, ".assetCount");
        verifiedBlock = vm.parseJsonUint(manifestJson, ".verifiedBlock");
        assertEq(vm.parseJsonUint(manifestJson, ".chainId"), 4663);
        vm.createSelectFork(rpc, verifiedBlock);
        assertEq(block.chainid, 4663);
    }

    function _key(
        uint256 index,
        string memory field
    ) internal pure returns (string memory) {
        return string.concat(".assets[", vm.toString(index), "].", field);
    }

    function _address(
        uint256 index,
        string memory field
    ) internal view returns (address) {
        return vm.parseJsonAddress(manifestJson, _key(index, field));
    }

    function _uint(
        uint256 index,
        string memory field
    ) internal view returns (uint256) {
        return vm.parseJsonUint(manifestJson, _key(index, field));
    }

    function _bool(
        uint256 index,
        string memory field
    ) internal view returns (bool) {
        return vm.parseJsonBool(manifestJson, _key(index, field));
    }

    function _string(
        uint256 index,
        string memory field
    ) internal view returns (string memory) {
        return vm.parseJsonString(manifestJson, _key(index, field));
    }
}
