// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

import { RobinhoodSequencerAvailabilityFeed } from "src/RobinhoodSequencerAvailabilityFeed.sol";
import { IArbSys } from "src/interfaces/IArbSys.sol";
import { RobinhoodForkBase } from "test/fork/RobinhoodForkBase.sol";

contract RobinhoodSequencerAvailabilityFeedForkTest is RobinhoodForkBase {
    uint256[] private _keys;
    address[] private _observers;

    function setUp() external {
        _setUpRobinhoodFork();
        uint256[] memory keys = new uint256[](3);
        keys[0] = 0xA11CE;
        keys[1] = 0xB0B;
        keys[2] = 0xCA401;
        _sortKeysByAddress(keys);
        for (uint256 i; i < keys.length; ++i) {
            _keys.push(keys[i]);
            _observers.push(vm.addr(keys[i]));
        }
    }

    function test_LiveRobinhoodBlockhashCanBackQuorumObservation() external {
        address reporter = address(0x123456);
        RobinhoodSequencerAvailabilityFeed feed = new RobinhoodSequencerAvailabilityFeed(reporter);
        vm.prank(feed.aliasedL1Reporter());
        feed.applyConfiguration(1, 0, _observers, 2, uint64(block.timestamp));
        vm.prank(feed.aliasedL1Reporter());
        feed.applyStatus(1, 1, true, uint64(block.timestamp));
        IArbSys arbSys = IArbSys(address(100));
        uint64 observedBlockNumber = uint64(arbSys.arbBlockNumber() - 1);
        string memory blockJson = vm.rpcJson(
            "eth_getBlockByNumber",
            string.concat("[\"", _rpcQuantity(observedBlockNumber), "\",false]")
        );
        bytes32 observedBlockHash = vm.parseJsonBytes32(blockJson, ".hash");
        // Foundry forks do not execute ArbSys.arbBlockHash; supply the RPC-confirmed block hash.
        vm.mockCall(
            address(arbSys),
            abi.encodeCall(IArbSys.arbBlockHash, (observedBlockNumber)),
            abi.encode(observedBlockHash)
        );
        assertNotEq(observedBlockNumber, block.number - 1);
        assertNotEq(observedBlockHash, bytes32(0));

        RobinhoodSequencerAvailabilityFeed.Heartbeat memory heartbeat =
            RobinhoodSequencerAvailabilityFeed.Heartbeat({
                observerSetVersion: feed.observerSetVersion(),
                statusSequence: feed.statusSequence(),
                observedBlockNumber: observedBlockNumber,
                observedBlockHash: observedBlockHash,
                validUntil: uint64(block.timestamp + feed.MAX_LEASE_DURATION())
            });
        bytes32 digest = feed.heartbeatDigest(heartbeat);
        bytes[] memory signatures = new bytes[](2);
        signatures[0] = _signature(_keys[0], digest);
        signatures[1] = _signature(_keys[1], digest);

        feed.submitHeartbeat(heartbeat, signatures);
        (, int256 answer,,,) = feed.latestRoundData();
        assertEq(answer, 0);
    }

    function _signature(
        uint256 privateKey,
        bytes32 digest
    ) private pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function _rpcQuantity(
        uint256 value
    ) private pure returns (string memory) {
        bytes memory padded = bytes(Strings.toHexString(value));
        if (padded.length <= 3 || padded[2] != "0") return string(padded);
        bytes memory compact = new bytes(padded.length - 1);
        compact[0] = "0";
        compact[1] = "x";
        for (uint256 i = 3; i < padded.length; ++i) {
            compact[i - 1] = padded[i];
        }
        return string(compact);
    }

    function _sortKeysByAddress(
        uint256[] memory keys
    ) private pure {
        for (uint256 i = 1; i < keys.length; ++i) {
            uint256 key = keys[i];
            address signer = vm.addr(key);
            uint256 j = i;
            while (j > 0 && vm.addr(keys[j - 1]) > signer) {
                keys[j] = keys[j - 1];
                --j;
            }
            keys[j] = key;
        }
    }
}
