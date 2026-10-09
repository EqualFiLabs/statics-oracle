// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";

import { RobinhoodSequencerAvailabilityFeed } from "src/RobinhoodSequencerAvailabilityFeed.sol";
import { StaticsOracle } from "src/StaticsOracle.sol";
import { IStaticsOracle } from "src/interfaces/IStaticsOracle.sol";
import { OracleFeedTestMock, OracleTokenTestMock } from "test/mocks/OracleTestMocks.sol";

contract RobinhoodMainnetSequencerRecoveryForkTest is Test {
    uint256 internal constant FORK_BLOCK = 84_486_562;

    function test_DeployedFeedLeaseExpiryBlocksPrices() external {
        string memory rpc = vm.envOr("ROBINHOOD_MAINNET", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true, "ROBINHOOD_MAINNET is not configured");
            return;
        }

        vm.createSelectFork(rpc, FORK_BLOCK);
        assertEq(block.chainid, 4_663);
        string memory manifest = vm.readFile("config/robinhood-mainnet.assets.json");
        address feedAddress = vm.parseJsonAddress(manifest, ".sequencer.feed");
        assertGt(feedAddress.code.length, 0);
        RobinhoodSequencerAvailabilityFeed feed = RobinhoodSequencerAvailabilityFeed(feedAddress);
        assertTrue(feed.isUp());
        uint256 expiresAt = feed.healthyUntil();
        assertGt(expiresAt, block.timestamp + 60);
        (, int256 healthyAnswer,,,) = feed.latestRoundData();
        assertEq(healthyAnswer, 0);

        StaticsOracle oracle = new StaticsOracle(address(this));
        OracleTokenTestMock token = new OracleTokenTestMock(18);
        OracleFeedTestMock priceFeed = new OracleFeedTestMock(8, "ASSET / USD");
        priceFeed.setRound(100e8, block.timestamp);
        oracle.setSequencerConfig(feedAddress, 0);
        oracle.registerAsset(
            address(token),
            IStaticsOracle.AssetOracleConfigInput({
                feed: address(priceFeed),
                feedDescriptionHash: keccak256("ASSET / USD"),
                maxAge: 1 days,
                tokenDecimals: 18,
                feedDecimals: 8,
                kind: IStaticsOracle.AssetKind.CRYPTO,
                checkOraclePause: false
            })
        );
        vm.warp(block.timestamp + 1);
        oracle.enableAsset(address(token));
        assertEq(oracle.priceUsd(address(token)), 100e18);
        oracle.setSequencerConfig(feedAddress, 1 hours);

        vm.warp(expiresAt);
        assertFalse(feed.isUp());
        (, int256 expiredAnswer, uint256 startedAt,,) = feed.latestRoundData();
        assertEq(expiredAnswer, 1);
        assertEq(startedAt, expiresAt);
        vm.expectRevert(StaticsOracle.SequencerDown.selector);
        oracle.priceUsd(address(token));
    }
}
