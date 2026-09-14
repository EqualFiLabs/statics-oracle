// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";

import { StaticsOracle } from "src/StaticsOracle.sol";
import { IStaticsOracle } from "src/interfaces/IStaticsOracle.sol";
import { OracleFeedTestMock, OracleTokenTestMock } from "test/mocks/OracleTestMocks.sol";

contract StaticsOraclePriceTest is Test {
    string internal constant DESCRIPTION = "PRICE / USD";

    StaticsOracle internal oracle;
    OracleTokenTestMock internal token;
    OracleFeedTestMock internal feed;
    OracleFeedTestMock internal sequencer;

    function setUp() external {
        vm.warp(10 days);
        oracle = new StaticsOracle(address(this));
        token = new OracleTokenTestMock(18);
        feed = new OracleFeedTestMock(8, DESCRIPTION);
        sequencer = new OracleFeedTestMock(0, "Sequencer");
        feed.setRoundData(10, 123e8, block.timestamp, block.timestamp, 10);
        sequencer.setRoundData(1, 0, block.timestamp - 2 hours, block.timestamp, 1);
        oracle.setSequencerConfig(address(sequencer), 1 hours);
        oracle.registerAsset(address(token), _input(address(feed)));
        oracle.enableAsset(address(token));
    }

    function test_ValidPricePreservesNormalizedRoundMetadata() external view {
        IStaticsOracle.PriceData memory data = oracle.peekPrice(address(token));
        assertEq(data.price1e18, 123e18);
        assertEq(data.roundId, 10);
        assertEq(data.updatedAt, block.timestamp);
        assertEq(uint8(data.status), uint8(IStaticsOracle.OracleStatus.VALID));
        assertEq(oracle.priceUsd(address(token)), 123e18);
    }

    function test_ZeroAndNegativeAnswersAreInvalid() external {
        feed.setRoundData(11, 0, block.timestamp, block.timestamp, 11);
        _assertStatus(IStaticsOracle.OracleStatus.INVALID_PRICE);
        vm.expectRevert(abi.encodeWithSelector(StaticsOracle.InvalidPrice.selector, address(feed)));
        oracle.priceUsd(address(token));

        feed.setRoundData(12, -1, block.timestamp, block.timestamp, 12);
        _assertStatus(IStaticsOracle.OracleStatus.INVALID_PRICE);
        vm.expectRevert(abi.encodeWithSelector(StaticsOracle.InvalidPrice.selector, address(feed)));
        oracle.priceUsd(address(token));
    }

    function test_ZeroTimestampAndIncompleteRoundAreRejected() external {
        feed.setRoundData(11, 123e8, block.timestamp, 0, 11);
        _assertStatus(IStaticsOracle.OracleStatus.INCOMPLETE_ROUND);
        vm.expectRevert(
            abi.encodeWithSelector(StaticsOracle.IncompleteRound.selector, address(feed), 11)
        );
        oracle.priceUsd(address(token));

        feed.setRoundData(12, 123e8, block.timestamp, block.timestamp, 11);
        _assertStatus(IStaticsOracle.OracleStatus.INCOMPLETE_ROUND);
        vm.expectRevert(
            abi.encodeWithSelector(StaticsOracle.IncompleteRound.selector, address(feed), 12)
        );
        oracle.priceUsd(address(token));
    }

    function test_FutureAndStaleTimestampsAreRejected() external {
        feed.setRoundData(11, 123e8, block.timestamp, block.timestamp + 1, 11);
        _assertStatus(IStaticsOracle.OracleStatus.INVALID_TIMESTAMP);
        vm.expectRevert(
            abi.encodeWithSelector(
                StaticsOracle.InvalidOracleTimestamp.selector, address(feed), block.timestamp + 1
            )
        );
        oracle.priceUsd(address(token));

        uint256 staleTimestamp = block.timestamp - 1 hours - 1;
        feed.setRoundData(12, 123e8, staleTimestamp, staleTimestamp, 12);
        IStaticsOracle.PriceData memory data = oracle.peekPrice(address(token));
        assertEq(uint8(data.status), uint8(IStaticsOracle.OracleStatus.STALE_PRICE));
        assertEq(data.price1e18, 123e18);
        vm.expectRevert(
            abi.encodeWithSelector(
                StaticsOracle.StalePrice.selector, address(feed), staleTimestamp, 1 hours
            )
        );
        oracle.priceUsd(address(token));
    }

    function test_FailedFeedCallIsDiagnosticAndStrictlyRejected() external {
        feed.setLatestRoundCallFails(true);
        _assertStatus(IStaticsOracle.OracleStatus.FEED_CALL_FAILED);
        vm.expectRevert(
            abi.encodeWithSelector(StaticsOracle.FeedCallFailed.selector, address(feed))
        );
        oracle.priceUsd(address(token));
    }

    function test_LifecycleAwareDiagnosticAndStrictPricing() external {
        OracleTokenTestMock unknown = new OracleTokenTestMock(18);
        assertEq(
            uint8(oracle.peekPrice(address(unknown)).status),
            uint8(IStaticsOracle.OracleStatus.UNSUPPORTED)
        );
        vm.expectRevert(
            abi.encodeWithSelector(StaticsOracle.UnsupportedAsset.selector, address(unknown))
        );
        oracle.priceUsd(address(unknown));

        OracleTokenTestMock candidate = new OracleTokenTestMock(18);
        oracle.registerAsset(address(candidate), _input(address(feed)));
        assertEq(
            uint8(oracle.peekPrice(address(candidate)).status),
            uint8(IStaticsOracle.OracleStatus.CANDIDATE)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                StaticsOracle.AssetNotEnabled.selector,
                address(candidate),
                IStaticsOracle.AssetStatus.CANDIDATE
            )
        );
        oracle.priceUsd(address(candidate));

        oracle.disableAsset(address(token));
        assertEq(
            uint8(oracle.peekPrice(address(token)).status),
            uint8(IStaticsOracle.OracleStatus.DISABLED)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                StaticsOracle.AssetNotEnabled.selector,
                address(token),
                IStaticsOracle.AssetStatus.DISABLED
            )
        );
        oracle.priceUsd(address(token));
    }

    function _assertStatus(
        IStaticsOracle.OracleStatus expected
    ) internal view {
        assertEq(uint8(oracle.peekPrice(address(token)).status), uint8(expected));
    }

    function _input(
        address feed_
    ) internal pure returns (IStaticsOracle.AssetOracleConfigInput memory) {
        return IStaticsOracle.AssetOracleConfigInput({
            feed: feed_,
            feedDescriptionHash: keccak256(bytes(DESCRIPTION)),
            maxAge: 1 hours,
            tokenDecimals: 18,
            feedDecimals: 8,
            kind: IStaticsOracle.AssetKind.CRYPTO,
            checkOraclePause: false
        });
    }
}
