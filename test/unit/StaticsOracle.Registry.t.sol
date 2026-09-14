// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Test } from "forge-std/Test.sol";

import { StaticsOracle } from "src/StaticsOracle.sol";
import { IStaticsOracle } from "src/interfaces/IStaticsOracle.sol";

contract RegistryTokenMock {
    uint8 public immutable decimals;
    bool public oraclePaused;

    constructor(
        uint8 decimals_
    ) {
        decimals = decimals_;
    }

    function setOraclePaused(
        bool paused
    ) external {
        oraclePaused = paused;
    }
}

contract RegistryFeedMock {
    uint8 public immutable decimals;
    string public description;

    constructor(
        uint8 decimals_,
        string memory description_
    ) {
        decimals = decimals_;
        description = description_;
    }
}

contract StaticsOracleRegistryHarness is StaticsOracle {
    error PricingUnavailable();

    constructor(
        address initialOwner
    ) StaticsOracle(initialOwner) { }

    function priceUsd(
        address
    ) external pure override returns (uint256) {
        revert PricingUnavailable();
    }

    function valueUsd(
        address,
        uint256
    ) external pure override returns (uint256) {
        revert PricingUnavailable();
    }

    function basketNav(
        address[] calldata,
        uint256[] calldata
    ) external pure override returns (uint256) {
        revert PricingUnavailable();
    }

    function peekPrice(
        address
    ) external pure override returns (PriceData memory) {
        revert PricingUnavailable();
    }
}

contract StaticsOracleRegistryTest is Test {
    string internal constant FEED_DESCRIPTION = "TEST / USD";

    StaticsOracleRegistryHarness internal oracle;
    RegistryTokenMock internal token;
    RegistryFeedMock internal feed;
    address internal nonOwner;

    function setUp() external {
        oracle = new StaticsOracleRegistryHarness(address(this));
        token = new RegistryTokenMock(18);
        feed = new RegistryFeedMock(8, FEED_DESCRIPTION);
        nonOwner = makeAddr("nonOwner");
    }

    function test_RegisterUsesExactAddressAndStartsCandidate() external {
        oracle.registerAsset(address(token), _cryptoInput(address(feed)));

        IStaticsOracle.AssetOracleConfig memory config = oracle.assetConfig(address(token));
        assertEq(config.feed, address(feed));
        assertEq(config.feedDescriptionHash, keccak256(bytes(FEED_DESCRIPTION)));
        assertEq(config.maxAge, 1 hours);
        assertEq(config.tokenDecimals, 18);
        assertEq(config.feedDecimals, 8);
        assertEq(uint8(config.kind), uint8(IStaticsOracle.AssetKind.CRYPTO));
        assertEq(uint8(config.status), uint8(IStaticsOracle.AssetStatus.CANDIDATE));
        assertFalse(config.checkOraclePause);
        assertEq(oracle.registryVersion(), 1);
    }

    function test_RevertWhen_NonOwnerRegisters() external {
        IStaticsOracle.AssetOracleConfigInput memory input = _cryptoInput(address(feed));
        vm.prank(nonOwner);
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner)
        );
        oracle.registerAsset(address(token), input);
    }

    function test_EnabledBindingCannotMutateSilently() external {
        oracle.registerAsset(address(token), _cryptoInput(address(feed)));
        oracle.enableAsset(address(token));

        RegistryFeedMock replacement = new RegistryFeedMock(8, "REPLACEMENT / USD");
        IStaticsOracle.AssetOracleConfigInput memory replacementInput =
            _cryptoInput(address(replacement));
        vm.expectRevert(
            abi.encodeWithSelector(
                StaticsOracle.AssetMustBeDisabled.selector,
                address(token),
                IStaticsOracle.AssetStatus.ENABLED
            )
        );
        oracle.updateAsset(address(token), replacementInput);

        IStaticsOracle.AssetOracleConfig memory config = oracle.assetConfig(address(token));
        assertEq(config.feed, address(feed));
        assertEq(oracle.registryVersion(), 2);
    }

    function test_DisableUpdateAndReenableIsExplicitAndVersioned() external {
        oracle.registerAsset(address(token), _cryptoInput(address(feed)));
        oracle.enableAsset(address(token));
        oracle.disableAsset(address(token));

        RegistryFeedMock replacement = new RegistryFeedMock(8, "REPLACEMENT / USD");
        oracle.updateAsset(address(token), _cryptoInput(address(replacement)));

        IStaticsOracle.AssetOracleConfig memory config = oracle.assetConfig(address(token));
        assertEq(config.feed, address(replacement));
        assertEq(uint8(config.status), uint8(IStaticsOracle.AssetStatus.CANDIDATE));
        assertEq(oracle.registryVersion(), 4);
    }

    function test_RevertWhen_StockPauseCheckIsNotConfigured() external {
        IStaticsOracle.AssetOracleConfigInput memory input = _cryptoInput(address(feed));
        input.kind = IStaticsOracle.AssetKind.STOCK;

        vm.expectRevert(
            abi.encodeWithSelector(StaticsOracle.StockPauseCheckRequired.selector, address(token))
        );
        oracle.registerAsset(address(token), input);
    }

    function test_RevertWhen_EnablingPausedStock() external {
        IStaticsOracle.AssetOracleConfigInput memory input = _cryptoInput(address(feed));
        input.kind = IStaticsOracle.AssetKind.STOCK;
        input.checkOraclePause = true;
        oracle.registerAsset(address(token), input);

        token.setOraclePaused(true);
        vm.expectRevert(
            abi.encodeWithSelector(StaticsOracle.StockOraclePaused.selector, address(token))
        );
        oracle.enableAsset(address(token));
    }

    function _cryptoInput(
        address feed_
    ) internal view returns (IStaticsOracle.AssetOracleConfigInput memory) {
        return IStaticsOracle.AssetOracleConfigInput({
            feed: feed_,
            feedDescriptionHash: keccak256(bytes(RegistryFeedMock(feed_).description())),
            maxAge: 1 hours,
            tokenDecimals: 18,
            feedDecimals: 8,
            kind: IStaticsOracle.AssetKind.CRYPTO,
            checkOraclePause: false
        });
    }
}
