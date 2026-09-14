// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";

import { StaticsOracle } from "src/StaticsOracle.sol";
import { IStaticsOracle } from "src/interfaces/IStaticsOracle.sol";
import { OracleFeedTestMock, OracleTokenTestMock } from "test/mocks/OracleTestMocks.sol";

contract StaticsOracleStockTest is Test {
    string internal constant DESCRIPTION = "RHSTOCK / USD";

    StaticsOracle internal oracle;
    OracleTokenTestMock internal stock;
    OracleFeedTestMock internal feed;

    function setUp() external {
        vm.warp(10 days);
        oracle = new StaticsOracle(address(this));
        stock = new OracleTokenTestMock(18);
        feed = new OracleFeedTestMock(8, DESCRIPTION);
        OracleFeedTestMock sequencer = new OracleFeedTestMock(0, "Sequencer");
        feed.setRound(100e8, block.timestamp);
        sequencer.setRoundData(1, 0, block.timestamp - 2 hours, block.timestamp, 1);
        oracle.setSequencerConfig(address(sequencer), 1 hours);
        oracle.registerAsset(address(stock), _stockInput());
        oracle.enableAsset(address(stock));
    }

    function test_NormalStockPriceUsesAdjustedChainlinkAnswer() external view {
        assertEq(oracle.priceUsd(address(stock)), 100e18);
        assertEq(oracle.valueUsd(address(stock), 2e18), 200e18);
    }

    function test_PausedStockIsDiagnosticAndStrictlyRejected() external {
        stock.setOraclePaused(true);
        assertEq(
            uint8(oracle.peekPrice(address(stock)).status),
            uint8(IStaticsOracle.OracleStatus.STOCK_ORACLE_PAUSED)
        );
        vm.expectRevert(
            abi.encodeWithSelector(StaticsOracle.StockOraclePaused.selector, address(stock))
        );
        oracle.priceUsd(address(stock));
    }

    function test_FailedPauseCallIsDiagnosticAndStrictlyRejected() external {
        stock.setPauseCallFails(true);
        assertEq(
            uint8(oracle.peekPrice(address(stock)).status),
            uint8(IStaticsOracle.OracleStatus.STOCK_PAUSE_CHECK_FAILED)
        );
        vm.expectRevert(
            abi.encodeWithSelector(StaticsOracle.StockPauseCheckFailed.selector, address(stock))
        );
        oracle.priceUsd(address(stock));
    }

    function test_UiMultiplierChangeCannotDoubleApplyToUnchangedFeedAnswer() external {
        uint256 priceBefore = oracle.priceUsd(address(stock));
        stock.setUiMultiplier(2e18);

        assertEq(stock.uiMultiplier(), 2e18);
        assertEq(oracle.priceUsd(address(stock)), priceBefore);
        assertEq(oracle.valueUsd(address(stock), 1e18), 100e18);
    }

    function test_DividendMultiplierAdjustmentUsesFeedExactlyOnce() external {
        stock.setUiMultiplier(1.1e18);
        feed.setRoundData(2, 110e8, block.timestamp, block.timestamp, 2);

        assertEq(oracle.priceUsd(address(stock)), 110e18);
        assertEq(oracle.valueUsd(address(stock), 1e18), 110e18);
        assertTrue(oracle.valueUsd(address(stock), 1e18) != 121e18);
    }

    function test_SplitScenarioPreservesEconomicValueFromAdjustedFeed() external {
        uint256 valueBefore = oracle.valueUsd(address(stock), 1e18);

        // A representative 2:1 split halves the reference share price while the raw
        // token's multiplier doubles. Chainlink publishes the already-adjusted $100 value.
        stock.setUiMultiplier(2e18);
        feed.setRoundData(2, 100e8, block.timestamp, block.timestamp, 2);

        assertEq(oracle.valueUsd(address(stock), 1e18), valueBefore);
        assertEq(oracle.valueUsd(address(stock), 1e18), 100e18);
    }

    function _stockInput() internal view returns (IStaticsOracle.AssetOracleConfigInput memory) {
        return IStaticsOracle.AssetOracleConfigInput({
            feed: address(feed),
            feedDescriptionHash: keccak256(bytes(DESCRIPTION)),
            maxAge: 1 hours,
            tokenDecimals: 18,
            feedDecimals: 8,
            kind: IStaticsOracle.AssetKind.STOCK,
            checkOraclePause: true
        });
    }
}
