// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Test } from "forge-std/Test.sol";

import { StaticsOracle } from "src/StaticsOracle.sol";
import { IStaticsOracle } from "src/interfaces/IStaticsOracle.sol";

contract EvaluationTokenMock {
    uint8 public immutable decimals;
    bool public paused;
    bool public pauseCallFails;

    constructor(
        uint8 decimals_
    ) {
        decimals = decimals_;
    }

    function setPaused(
        bool value
    ) external {
        paused = value;
    }

    function setPauseCallFails(
        bool value
    ) external {
        pauseCallFails = value;
    }

    function oraclePaused() external view returns (bool) {
        if (pauseCallFails) revert("pause call failed");
        return paused;
    }
}

contract EvaluationFeedMock {
    uint8 public immutable decimals;
    string public description;
    uint80 public roundId;
    int256 public answer;
    uint256 public startedAt;
    uint256 public updatedAt;
    uint80 public answeredInRound;
    bool public callFails;

    constructor(
        uint8 decimals_,
        string memory description_
    ) {
        decimals = decimals_;
        description = description_;
    }

    function setRoundData(
        uint80 roundId_,
        int256 answer_,
        uint256 startedAt_,
        uint256 updatedAt_,
        uint80 answeredInRound_
    ) external {
        roundId = roundId_;
        answer = answer_;
        startedAt = startedAt_;
        updatedAt = updatedAt_;
        answeredInRound = answeredInRound_;
    }

    function setCallFails(
        bool value
    ) external {
        callFails = value;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        if (callFails) revert("feed call failed");
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}

contract StaticsOracleEvaluationHarness is StaticsOracle {
    constructor(
        address initialOwner
    ) StaticsOracle(initialOwner) { }
}

contract StaticsOracleEvaluationTest is Test {
    string internal constant FEED_DESCRIPTION = "TEST / USD";

    StaticsOracleEvaluationHarness internal oracle;
    EvaluationTokenMock internal token;
    EvaluationFeedMock internal feed;
    EvaluationFeedMock internal sequencer;

    function setUp() external {
        vm.warp(10 days);
        oracle = new StaticsOracleEvaluationHarness(address(this));
        token = new EvaluationTokenMock(18);
        feed = new EvaluationFeedMock(8, FEED_DESCRIPTION);
        sequencer = new EvaluationFeedMock(0, "Sequencer Uptime Feed");

        feed.setRoundData(12, 123_456_789, block.timestamp, block.timestamp, 12);
        sequencer.setRoundData(7, 0, block.timestamp - 2 hours, block.timestamp, 7);
        oracle.setSequencerConfig(address(sequencer), 1 hours);
        oracle.registerAsset(address(token), _input(IStaticsOracle.AssetKind.CRYPTO, false));
        oracle.enableAsset(address(token));
    }

    function test_PeekPriceReturnsNormalizedHealthyRound() external view {
        IStaticsOracle.PriceData memory data = oracle.peekPrice(address(token));

        assertEq(data.price1e18, 1_234_567_890_000_000_000);
        assertEq(data.updatedAt, block.timestamp);
        assertEq(data.roundId, 12);
        assertEq(uint8(data.status), uint8(IStaticsOracle.OracleStatus.VALID));
    }

    function test_SequencerConfigurationIsVersionedAndOwnerControlled() external {
        IStaticsOracle.SequencerConfig memory config = oracle.sequencerConfig();
        assertEq(config.feed, address(sequencer));
        assertEq(config.gracePeriod, 1 hours);
        assertEq(oracle.registryVersion(), 3);

        address nonOwner = makeAddr("nonOwner");
        vm.prank(nonOwner);
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner)
        );
        oracle.setSequencerConfig(address(sequencer), 2 hours);
    }

    function test_RevertWhen_SequencerFeedCannotBeCalled() external {
        EvaluationFeedMock broken = new EvaluationFeedMock(0, "Broken");
        broken.setCallFails(true);

        vm.expectRevert(
            abi.encodeWithSelector(StaticsOracle.SequencerFeedCallFailed.selector, address(broken))
        );
        oracle.setSequencerConfig(address(broken), 1 hours);
    }

    function test_PeekPriceFailsClosedWhenSequencerIsDownOrMalformed() external {
        sequencer.setRoundData(8, 1, block.timestamp, block.timestamp, 8);
        _assertStatus(IStaticsOracle.OracleStatus.SEQUENCER_DOWN);

        sequencer.setRoundData(8, 0, block.timestamp + 1, block.timestamp, 8);
        _assertStatus(IStaticsOracle.OracleStatus.SEQUENCER_DOWN);

        sequencer.setCallFails(true);
        _assertStatus(IStaticsOracle.OracleStatus.SEQUENCER_DOWN);
    }

    function test_PeekPriceRejectsSequencerRecoveryGrace() external {
        sequencer.setRoundData(8, 0, block.timestamp, block.timestamp, 8);
        _assertStatus(IStaticsOracle.OracleStatus.SEQUENCER_GRACE_PERIOD);

        vm.warp(block.timestamp + 1 hours + 1);
        feed.setRoundData(12, 123_456_789, block.timestamp, block.timestamp, 12);
        _assertStatus(IStaticsOracle.OracleStatus.VALID);
    }

    function test_PeekPriceReportsStockPauseAndPauseCallFailure() external {
        EvaluationTokenMock stock = new EvaluationTokenMock(18);
        oracle.registerAsset(address(stock), _stockInput(address(stock)));
        oracle.enableAsset(address(stock));

        stock.setPaused(true);
        _assertStatusFor(address(stock), IStaticsOracle.OracleStatus.STOCK_ORACLE_PAUSED);

        stock.setPaused(false);
        stock.setPauseCallFails(true);
        _assertStatusFor(address(stock), IStaticsOracle.OracleStatus.STOCK_PAUSE_CHECK_FAILED);
    }

    function test_PeekPriceReportsFeedFailureAndInvalidAnswer() external {
        feed.setCallFails(true);
        _assertStatus(IStaticsOracle.OracleStatus.FEED_CALL_FAILED);

        feed.setCallFails(false);
        feed.setRoundData(13, 0, block.timestamp, block.timestamp, 13);
        _assertStatus(IStaticsOracle.OracleStatus.INVALID_PRICE);

        feed.setRoundData(13, -1, block.timestamp, block.timestamp, 13);
        _assertStatus(IStaticsOracle.OracleStatus.INVALID_PRICE);
    }

    function test_PeekPriceReportsIncompleteFutureAndStaleRounds() external {
        feed.setRoundData(13, 100e8, block.timestamp, 0, 13);
        _assertStatus(IStaticsOracle.OracleStatus.INCOMPLETE_ROUND);

        feed.setRoundData(13, 100e8, block.timestamp, block.timestamp, 12);
        _assertStatus(IStaticsOracle.OracleStatus.INCOMPLETE_ROUND);

        feed.setRoundData(13, 100e8, block.timestamp, block.timestamp + 1, 13);
        _assertStatus(IStaticsOracle.OracleStatus.INVALID_TIMESTAMP);

        feed.setRoundData(13, 100e8, block.timestamp, block.timestamp - 1 hours - 1, 13);
        IStaticsOracle.PriceData memory data = oracle.peekPrice(address(token));
        assertEq(uint8(data.status), uint8(IStaticsOracle.OracleStatus.STALE_PRICE));
        assertEq(data.price1e18, 100e18);
        assertEq(data.updatedAt, block.timestamp - 1 hours - 1);
        assertEq(data.roundId, 13);
    }

    function test_EnableAssetRequiresCurrentlyValidPrice() external {
        EvaluationTokenMock candidate = new EvaluationTokenMock(18);
        oracle.registerAsset(address(candidate), _stockInput(address(candidate)));
        candidate.setPaused(true);

        vm.expectRevert(
            abi.encodeWithSelector(StaticsOracle.StockOraclePaused.selector, address(candidate))
        );
        oracle.enableAsset(address(candidate));
    }

    function test_EnableAssetFailsClosedWithoutSequencerConfiguration() external {
        StaticsOracleEvaluationHarness unconfigured =
            new StaticsOracleEvaluationHarness(address(this));
        EvaluationTokenMock candidate = new EvaluationTokenMock(18);
        unconfigured.registerAsset(
            address(candidate), _input(IStaticsOracle.AssetKind.CRYPTO, false)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                StaticsOracle.AssetEnablementFailed.selector,
                address(candidate),
                IStaticsOracle.OracleStatus.SEQUENCER_NOT_CONFIGURED
            )
        );
        unconfigured.enableAsset(address(candidate));
    }

    function _assertStatus(
        IStaticsOracle.OracleStatus expected
    ) internal view {
        _assertStatusFor(address(token), expected);
    }

    function _assertStatusFor(
        address token_,
        IStaticsOracle.OracleStatus expected
    ) internal view {
        IStaticsOracle.PriceData memory data = oracle.peekPrice(token_);
        assertEq(uint8(data.status), uint8(expected));
    }

    function _input(
        IStaticsOracle.AssetKind kind,
        bool checkPause
    ) internal view returns (IStaticsOracle.AssetOracleConfigInput memory) {
        return IStaticsOracle.AssetOracleConfigInput({
            feed: address(feed),
            feedDescriptionHash: keccak256(bytes(FEED_DESCRIPTION)),
            maxAge: 1 hours,
            tokenDecimals: 18,
            feedDecimals: 8,
            kind: kind,
            checkOraclePause: checkPause
        });
    }

    function _stockInput(
        address
    ) internal view returns (IStaticsOracle.AssetOracleConfigInput memory) {
        return _input(IStaticsOracle.AssetKind.STOCK, true);
    }
}
