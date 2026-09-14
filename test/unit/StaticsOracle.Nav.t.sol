// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";

import { StaticsOracle } from "src/StaticsOracle.sol";
import { IStaticsOracle } from "src/interfaces/IStaticsOracle.sol";
import { OracleFeedTestMock, OracleTokenTestMock } from "test/mocks/OracleTestMocks.sol";

contract StaticsOracleNavTest is Test {
    StaticsOracle internal oracle;
    OracleFeedTestMock internal sequencer;
    OracleTokenTestMock internal nvda;
    OracleTokenTestMock internal weth;
    OracleTokenTestMock internal spy;
    OracleTokenTestMock internal usd6;
    OracleFeedTestMock internal nvdaFeed;
    OracleFeedTestMock internal wethFeed;
    OracleFeedTestMock internal spyFeed;
    OracleFeedTestMock internal usdFeed;

    function setUp() external {
        vm.warp(10 days);
        oracle = new StaticsOracle(address(this));
        sequencer = new OracleFeedTestMock(0, "Sequencer");
        sequencer.setRoundData(1, 0, block.timestamp - 2 hours, block.timestamp, 1);
        oracle.setSequencerConfig(address(sequencer), 1 hours);

        nvda = new OracleTokenTestMock(18);
        weth = new OracleTokenTestMock(18);
        spy = new OracleTokenTestMock(18);
        usd6 = new OracleTokenTestMock(6);
        nvdaFeed = _feed(8, "RHNVDA / USD", 220e8);
        wethFeed = _feed(18, "ETH / USD", 4000e18);
        spyFeed = _feed(8, "RHSPY / USD", 700e8);
        usdFeed = _feed(8, "USD / USD", 1e8);
        _registerEnable(nvda, nvdaFeed, 18, 8, IStaticsOracle.AssetKind.STOCK, true);
        _registerEnable(weth, wethFeed, 18, 18, IStaticsOracle.AssetKind.CRYPTO, false);
        _registerEnable(spy, spyFeed, 18, 8, IStaticsOracle.AssetKind.ETF, true);
        _registerEnable(usd6, usdFeed, 6, 8, IStaticsOracle.AssetKind.STABLE, false);
    }

    function test_SingleTwoAssetMixedDecimalsAndZeroAmount() external view {
        assertEq(oracle.basketNav(_assets(address(nvda)), _amounts(0.1e18)), 22e18);

        address[] memory assets = new address[](2);
        assets[0] = address(weth);
        assets[1] = address(usd6);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 0.3e18;
        amounts[1] = 10e6;
        assertEq(oracle.basketNav(assets, amounts), 1210e18);

        assertEq(oracle.basketNav(_assets(address(usd6)), _amounts(0)), 0);
    }

    function test_RepresentativeStaticsBasketNavIs1278Usd() external view {
        address[] memory assets = new address[](3);
        assets[0] = address(nvda);
        assets[1] = address(weth);
        assets[2] = address(spy);
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 0.1e18;
        amounts[1] = 0.3e18;
        amounts[2] = 0.08e18;
        assertEq(oracle.basketNav(assets, amounts), 1278e18);
    }

    function test_RejectsLengthEmptyDuplicateAndOverLimit() external {
        vm.expectRevert(StaticsOracle.EmptyBasket.selector);
        oracle.basketNav(new address[](0), new uint256[](0));

        vm.expectRevert(StaticsOracle.LengthMismatch.selector);
        oracle.basketNav(_assets(address(nvda)), new uint256[](0));

        address[] memory duplicates = new address[](2);
        duplicates[0] = address(nvda);
        duplicates[1] = address(nvda);
        vm.expectRevert(
            abi.encodeWithSelector(StaticsOracle.DuplicateAsset.selector, address(nvda))
        );
        oracle.basketNav(duplicates, new uint256[](2));

        vm.expectRevert(abi.encodeWithSelector(StaticsOracle.TooManyAssets.selector, 17));
        oracle.basketNav(new address[](17), new uint256[](17));
    }

    function test_SupportsExactlySixteenUniqueAssets() external {
        address[] memory assets = new address[](16);
        uint256[] memory amounts = new uint256[](16);
        for (uint256 i; i < 16; ++i) {
            OracleTokenTestMock component = new OracleTokenTestMock(18);
            _registerEnable(component, nvdaFeed, 18, 8, IStaticsOracle.AssetKind.CRYPTO, false);
            assets[i] = address(component);
            amounts[i] = 1e18;
        }
        assertEq(oracle.basketNav(assets, amounts), 16 * 220e18);
    }

    function test_StalePausedDisabledUnsupportedAndSequencerInvalidComponentsRevert() external {
        uint256 staleAt = block.timestamp - 1 hours - 1;
        wethFeed.setRoundData(2, 4000e18, staleAt, staleAt, 2);
        vm.expectRevert(
            abi.encodeWithSelector(
                StaticsOracle.StalePrice.selector, address(wethFeed), staleAt, 1 hours
            )
        );
        oracle.basketNav(_assets(address(weth)), _amounts(1e18));
        wethFeed.setRound(4000e18, block.timestamp);

        nvda.setOraclePaused(true);
        vm.expectRevert(
            abi.encodeWithSelector(StaticsOracle.StockOraclePaused.selector, address(nvda))
        );
        oracle.basketNav(_assets(address(nvda)), _amounts(1e18));
        nvda.setOraclePaused(false);

        oracle.disableAsset(address(spy));
        vm.expectRevert(
            abi.encodeWithSelector(
                StaticsOracle.AssetNotEnabled.selector,
                address(spy),
                IStaticsOracle.AssetStatus.DISABLED
            )
        );
        oracle.basketNav(_assets(address(spy)), _amounts(1e18));

        OracleTokenTestMock unknown = new OracleTokenTestMock(18);
        vm.expectRevert(
            abi.encodeWithSelector(StaticsOracle.UnsupportedAsset.selector, address(unknown))
        );
        oracle.basketNav(_assets(address(unknown)), _amounts(1e18));

        sequencer.setRoundData(2, 1, block.timestamp, block.timestamp, 2);
        vm.expectRevert(StaticsOracle.SequencerDown.selector);
        oracle.basketNav(_assets(address(weth)), _amounts(1e18));
    }

    function _feed(
        uint8 decimals,
        string memory description,
        int256 answer
    ) internal returns (OracleFeedTestMock result) {
        result = new OracleFeedTestMock(decimals, description);
        result.setRound(answer, block.timestamp);
    }

    function _registerEnable(
        OracleTokenTestMock token,
        OracleFeedTestMock feed,
        uint8 tokenDecimals,
        uint8 feedDecimals,
        IStaticsOracle.AssetKind kind,
        bool checkPause
    ) internal {
        oracle.registerAsset(
            address(token),
            IStaticsOracle.AssetOracleConfigInput({
                feed: address(feed),
                feedDescriptionHash: keccak256(bytes(feed.description())),
                maxAge: 1 hours,
                tokenDecimals: tokenDecimals,
                feedDecimals: feedDecimals,
                kind: kind,
                checkOraclePause: checkPause
            })
        );
        oracle.enableAsset(address(token));
    }

    function _assets(
        address token
    ) internal pure returns (address[] memory result) {
        result = new address[](1);
        result[0] = token;
    }

    function _amounts(
        uint256 amount
    ) internal pure returns (uint256[] memory result) {
        result = new uint256[](1);
        result[0] = amount;
    }
}
