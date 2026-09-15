// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";

import { StaticsOracle } from "src/StaticsOracle.sol";
import { IStaticsOracle } from "src/interfaces/IStaticsOracle.sol";
import { OracleFeedTestMock, OracleTokenTestMock } from "test/mocks/OracleTestMocks.sol";

contract RegistryVersionFuzzTest is Test {
    function testFuzz_EachValidMutationIncrementsExactlyOnce(
        uint8 requestedSteps
    ) external {
        uint256 steps = bound(requestedSteps, 0, 48);
        vm.warp(10 days);
        StaticsOracle oracle = new StaticsOracle(address(this));
        OracleTokenTestMock token = new OracleTokenTestMock(18);
        OracleFeedTestMock feed = new OracleFeedTestMock(8, "VERSION / USD");
        OracleFeedTestMock sequencer = new OracleFeedTestMock(0, "Sequencer");
        feed.setRound(1e8, block.timestamp);
        sequencer.setRoundData(1, 0, block.timestamp - 2 hours, block.timestamp, 1);
        oracle.setSequencerConfig(address(sequencer), 1 hours);
        IStaticsOracle.AssetOracleConfigInput memory input = IStaticsOracle.AssetOracleConfigInput({
            feed: address(feed),
            feedDescriptionHash: keccak256("VERSION / USD"),
            maxAge: 1 hours,
            tokenDecimals: 18,
            feedDecimals: 8,
            kind: IStaticsOracle.AssetKind.CRYPTO,
            checkOraclePause: false
        });
        oracle.registerAsset(address(token), input);

        uint64 expectedVersion = 2;
        for (uint256 i; i < steps; ++i) {
            IStaticsOracle.AssetStatus status = oracle.assetConfig(address(token)).status;
            if (status == IStaticsOracle.AssetStatus.CANDIDATE) {
                oracle.enableAsset(address(token));
            } else if (status == IStaticsOracle.AssetStatus.ENABLED) {
                oracle.disableAsset(address(token));
            } else {
                oracle.updateAsset(address(token), input);
            }
            ++expectedVersion;
            assertEq(oracle.registryVersion(), expectedVersion);

            oracle.assetConfig(address(token));
            if (oracle.assetConfig(address(token)).status == IStaticsOracle.AssetStatus.ENABLED) {
                oracle.peekPrice(address(token));
            }
            assertEq(oracle.registryVersion(), expectedVersion);
        }
    }
}
