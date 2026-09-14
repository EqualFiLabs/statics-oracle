// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";

import { StaticsOracle } from "src/StaticsOracle.sol";
import { IAggregatorV3 } from "src/interfaces/IAggregatorV3.sol";
import { IStaticsOracle } from "src/interfaces/IStaticsOracle.sol";

contract PricingTokenMock {
    uint8 public immutable decimals;
    bool public oraclePaused;

    constructor(
        uint8 decimals_
    ) {
        decimals = decimals_;
    }
}

contract PricingFeedMock {
    uint8 public immutable decimals;
    string public description;
    uint80 public roundId;
    int256 public answer;
    uint256 public startedAt;
    uint256 public updatedAt;
    uint80 public answeredInRound;

    constructor(
        uint8 decimals_,
        string memory description_,
        int256 answer_
    ) {
        decimals = decimals_;
        description = description_;
        setRoundData(1, answer_, block.timestamp, block.timestamp, 1);
    }

    function setRoundData(
        uint80 roundId_,
        int256 answer_,
        uint256 startedAt_,
        uint256 updatedAt_,
        uint80 answeredInRound_
    ) public {
        roundId = roundId_;
        answer = answer_;
        startedAt = startedAt_;
        updatedAt = updatedAt_;
        answeredInRound = answeredInRound_;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}

contract StaticsOraclePricingTest is Test {
    StaticsOracle internal oracle;
    PricingTokenMock internal token18;
    PricingTokenMock internal token6;
    PricingFeedMock internal feed8;
    PricingFeedMock internal feed18;
    PricingFeedMock internal sequencer;

    function setUp() external {
        vm.warp(10 days);
        oracle = new StaticsOracle(address(this));
        token18 = new PricingTokenMock(18);
        token6 = new PricingTokenMock(6);
        feed8 = new PricingFeedMock(8, "ASSET-A / USD", 2500e8);
        feed18 = new PricingFeedMock(18, "ASSET-B / USD", 1e18);
        sequencer = new PricingFeedMock(0, "Sequencer Uptime Feed", 0);
        sequencer.setRoundData(1, 0, block.timestamp - 2 hours, block.timestamp, 1);

        oracle.setSequencerConfig(address(sequencer), 1 hours);
        _registerAndEnable(address(token18), address(feed8), 18, 8, "ASSET-A / USD");
        _registerAndEnable(address(token6), address(feed18), 6, 18, "ASSET-B / USD");
    }

    function test_PriceAndValueUseExactTokenDecimals() external view {
        assertEq(oracle.priceUsd(address(token18)), 2500e18);
        assertEq(oracle.valueUsd(address(token18), 0.2e18), 500e18);
        assertEq(oracle.priceUsd(address(token6)), 1e18);
        assertEq(oracle.valueUsd(address(token6), 5_000_000), 5e18);
    }

    function test_StrictPricingMapsDiagnosticFailuresToCustomErrors() external {
        PricingTokenMock unsupported = new PricingTokenMock(18);
        vm.expectRevert(
            abi.encodeWithSelector(StaticsOracle.UnsupportedAsset.selector, address(unsupported))
        );
        oracle.priceUsd(address(unsupported));

        feed8.setRoundData(2, 2500e8, block.timestamp, block.timestamp - 1 hours - 1, 2);
        vm.expectRevert(
            abi.encodeWithSelector(
                StaticsOracle.StalePrice.selector,
                address(feed8),
                block.timestamp - 1 hours - 1,
                1 hours
            )
        );
        oracle.priceUsd(address(token18));
    }

    function test_SameEconomicAssetCannotInheritRegisteredFeed() external {
        PricingTokenMock lookalike = new PricingTokenMock(18);
        vm.expectRevert(
            abi.encodeWithSelector(StaticsOracle.UnsupportedAsset.selector, address(lookalike))
        );
        oracle.priceUsd(address(lookalike));

        oracle.registerAsset(address(lookalike), _input(address(feed8), 18, 8, "ASSET-A / USD"));
        vm.expectRevert(
            abi.encodeWithSelector(
                StaticsOracle.AssetNotEnabled.selector,
                address(lookalike),
                IStaticsOracle.AssetStatus.CANDIDATE
            )
        );
        oracle.priceUsd(address(lookalike));
    }

    function test_BasketNavIsAdditiveAndChecksSequencerOnce() external {
        address[] memory assets = new address[](2);
        assets[0] = address(token18);
        assets[1] = address(token6);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1e18;
        amounts[1] = 10e6;

        vm.expectCall(
            address(sequencer), abi.encodeWithSelector(IAggregatorV3.latestRoundData.selector), 1
        );
        assertEq(oracle.basketNav(assets, amounts), 2510e18);
    }

    function test_BasketNavRejectsInvalidShapesAndDuplicates() external {
        address[] memory noAssets = new address[](0);
        uint256[] memory noAmounts = new uint256[](0);
        vm.expectRevert(StaticsOracle.EmptyBasket.selector);
        oracle.basketNav(noAssets, noAmounts);

        address[] memory assets = new address[](2);
        assets[0] = address(token18);
        assets[1] = address(token18);
        uint256[] memory oneAmount = new uint256[](1);
        vm.expectRevert(StaticsOracle.LengthMismatch.selector);
        oracle.basketNav(assets, oneAmount);

        uint256[] memory twoAmounts = new uint256[](2);
        vm.expectRevert(
            abi.encodeWithSelector(StaticsOracle.DuplicateAsset.selector, address(token18))
        );
        oracle.basketNav(assets, twoAmounts);

        address[] memory tooMany = new address[](17);
        uint256[] memory tooManyAmounts = new uint256[](17);
        vm.expectRevert(abi.encodeWithSelector(StaticsOracle.TooManyAssets.selector, 17));
        oracle.basketNav(tooMany, tooManyAmounts);
    }

    function test_BasketNavRevertsWhenAnyComponentIsInvalid() external {
        feed18.setRoundData(2, 1e18, block.timestamp, block.timestamp - 1 hours - 1, 2);

        address[] memory assets = new address[](2);
        assets[0] = address(token18);
        assets[1] = address(token6);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1e18;
        amounts[1] = 1e6;

        vm.expectRevert(
            abi.encodeWithSelector(
                StaticsOracle.StalePrice.selector,
                address(feed18),
                block.timestamp - 1 hours - 1,
                1 hours
            )
        );
        oracle.basketNav(assets, amounts);
    }

    function test_StrictPricingRejectsSequencerDownAndGracePeriod() external {
        sequencer.setRoundData(2, 1, block.timestamp, block.timestamp, 2);
        vm.expectRevert(StaticsOracle.SequencerDown.selector);
        oracle.priceUsd(address(token18));

        sequencer.setRoundData(3, 0, block.timestamp, block.timestamp, 3);
        vm.expectRevert(
            abi.encodeWithSelector(
                StaticsOracle.SequencerGracePeriod.selector, block.timestamp, 1 hours
            )
        );
        oracle.priceUsd(address(token18));
    }

    function test_ReadsDoNotMutateRegistryVersion() external view {
        uint64 versionBefore = oracle.registryVersion();
        oracle.priceUsd(address(token18));
        oracle.valueUsd(address(token18), 1e18);

        address[] memory assets = new address[](1);
        assets[0] = address(token18);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1e18;
        oracle.basketNav(assets, amounts);

        assertEq(oracle.registryVersion(), versionBefore);
    }

    function _registerAndEnable(
        address token,
        address feed,
        uint8 tokenDecimals,
        uint8 feedDecimals,
        string memory description
    ) internal {
        oracle.registerAsset(token, _input(feed, tokenDecimals, feedDecimals, description));
        oracle.enableAsset(token);
    }

    function _input(
        address feed,
        uint8 tokenDecimals,
        uint8 feedDecimals,
        string memory description
    ) internal pure returns (IStaticsOracle.AssetOracleConfigInput memory) {
        return IStaticsOracle.AssetOracleConfigInput({
            feed: feed,
            feedDescriptionHash: keccak256(bytes(description)),
            maxAge: 1 hours,
            tokenDecimals: tokenDecimals,
            feedDecimals: feedDecimals,
            kind: IStaticsOracle.AssetKind.CRYPTO,
            checkOraclePause: false
        });
    }
}
