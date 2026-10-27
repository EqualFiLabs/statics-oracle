// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { Script } from "forge-std/Script.sol";
import { StaticsExecutionOracle } from "src/StaticsExecutionOracle.sol";

contract DeployStaticsExecutionOracle is Script {
    using SafeCast for uint256;
    error WrongChain();
    error InvalidVerifierBinding();
    error UnratifiedParameters();

    function run() external returns (StaticsExecutionOracle oracle) {
        string memory manifest = vm.readFile(
            vm.envOr("EXECUTION_STREAM_MANIFEST", string("config/robinhood-mainnet.streams.json"))
        );
        if (
            vm.parseJsonUint(manifest, ".schemaVersion") != 1
                || !vm.parseJsonBool(manifest, ".productionParametersRatified")
        ) revert UnratifiedParameters();
        uint256 chainId = vm.parseJsonUint(manifest, ".chainId");
        address owner = vm.envAddress("INITIAL_OWNER");
        address verifier = vm.parseJsonAddress(manifest, ".verifierProxy");
        bytes32 hash = vm.parseJsonBytes32(manifest, ".verifierCodeHash");
        uint8 bound = vm.parseJsonUint(manifest, ".maxReportBundleSize").toUint8();
        _validate(chainId, verifier, hash);
        vm.startBroadcast();
        oracle = deploy(chainId, owner, verifier, hash, bound);
        vm.stopBroadcast();
    }

    function deploy(
        uint256 chainId,
        address initialOwner,
        address verifier,
        bytes32 expectedCodeHash,
        uint8 bound
    ) public returns (StaticsExecutionOracle) {
        _validate(chainId, verifier, expectedCodeHash);
        return new StaticsExecutionOracle(initialOwner, verifier, bound);
    }

    function _validate(
        uint256 chainId,
        address verifier,
        bytes32 expectedCodeHash
    ) internal view {
        if ((chainId != 4663 && chainId != 46630) || block.chainid != chainId) revert WrongChain();
        if (
            verifier.code.length == 0 || expectedCodeHash == bytes32(0)
                || verifier.codehash != expectedCodeHash
        ) revert InvalidVerifierBinding();
    }
}
