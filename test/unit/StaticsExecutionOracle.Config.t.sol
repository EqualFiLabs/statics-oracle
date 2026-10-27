// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Test } from "forge-std/Test.sol";
import { StaticsExecutionOracle } from "src/StaticsExecutionOracle.sol";
import { IStaticsExecutionOracle as IEO } from "src/interfaces/IStaticsExecutionOracle.sol";

contract ExecutionVerifierCodeMock { }

contract ExecutionConfigTest is Test {
    StaticsExecutionOracle internal oracle;
    address internal verifier;
    bytes32 internal constant MARKET = keccak256("BTC_USD");
    bytes32 internal constant STREAM = bytes32((uint256(3) << 240) | 1234);

    function setUp() public {
        vm.warp(1000);
        verifier = address(new ExecutionVerifierCodeMock());
        oracle = new StaticsExecutionOracle(address(this), verifier, 5);
    }

    function input() internal pure returns (IEO.ExecutionMarketConfigInput memory) {
        return IEO.ExecutionMarketConfigInput(STREAM, 10, 30, 8);
    }

    function testConstructorRejectsUnusableDependencies() public {
        vm.expectRevert(StaticsExecutionOracle.ZeroAddress.selector);
        new StaticsExecutionOracle(address(this), address(0), 5);
        vm.expectRevert(
            abi.encodeWithSelector(StaticsExecutionOracle.NoContractCode.selector, address(123))
        );
        new StaticsExecutionOracle(address(this), address(123), 5);
        vm.expectRevert(StaticsExecutionOracle.InvalidBundleBound.selector);
        new StaticsExecutionOracle(address(this), verifier, 0);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new StaticsExecutionOracle(address(0), verifier, 5);
    }

    function testOwnershipRequiresAcceptanceAndCannotBeAbandoned() public {
        vm.expectRevert(StaticsExecutionOracle.OwnershipRenunciationDisabled.selector);
        oracle.renounceOwnership();
        oracle.transferOwnership(address(123));
        assertEq(oracle.owner(), address(this));
        vm.prank(address(123));
        oracle.acceptOwnership();
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this))
        );
        oracle.transferOwnership(address(456));
    }

    function testRegisterRejectsInvalidAndRepeatedBindings() public {
        IEO.ExecutionMarketConfigInput memory cfg = input();
        cfg.streamId = bytes32(uint256(1));
        vm.expectRevert(StaticsExecutionOracle.InvalidStreamId.selector);
        oracle.registerMarket(MARKET, cfg);
        cfg = input();
        cfg.executionDelay = 0;
        vm.expectRevert(StaticsExecutionOracle.InvalidExecutionDelay.selector);
        oracle.registerMarket(MARKET, cfg);
        cfg = input();
        cfg.maxReportWindow = 0;
        vm.expectRevert(StaticsExecutionOracle.InvalidMaxReportWindow.selector);
        oracle.registerMarket(MARKET, cfg);
        cfg = input();
        cfg.streamDecimals = 19;
        vm.expectRevert(
            abi.encodeWithSelector(StaticsExecutionOracle.UnsupportedStreamDecimals.selector, 19)
        );
        oracle.registerMarket(MARKET, cfg);
        cfg = input();
        oracle.registerMarket(MARKET, cfg);
        vm.expectRevert(
            abi.encodeWithSelector(StaticsExecutionOracle.MarketAlreadyRegistered.selector, MARKET)
        );
        oracle.registerMarket(MARKET, cfg);
    }

    function testEnableRequiresReviewedCandidate() public {
        vm.expectRevert(
            abi.encodeWithSelector(StaticsExecutionOracle.UnsupportedMarket.selector, MARKET)
        );
        oracle.enableMarket(MARKET);
        oracle.registerMarket(MARKET, input());
        oracle.enableMarket(MARKET);
        vm.expectRevert(
            abi.encodeWithSelector(
                StaticsExecutionOracle.InvalidMarketStatusTransition.selector,
                MARKET,
                IEO.MarketStatus.ENABLED,
                IEO.MarketStatus.ENABLED
            )
        );
        oracle.enableMarket(MARKET);
    }

    function testDisablingDoesNotAllowDirectReenable() public {
        oracle.registerMarket(MARKET, input());
        oracle.enableMarket(MARKET);
        oracle.disableMarket(MARKET);
        vm.expectRevert(
            abi.encodeWithSelector(
                StaticsExecutionOracle.InvalidMarketStatusTransition.selector,
                MARKET,
                IEO.MarketStatus.DISABLED,
                IEO.MarketStatus.ENABLED
            )
        );
        oracle.enableMarket(MARKET);
        vm.expectRevert(
            abi.encodeWithSelector(
                StaticsExecutionOracle.InvalidMarketStatusTransition.selector,
                MARKET,
                IEO.MarketStatus.DISABLED,
                IEO.MarketStatus.DISABLED
            )
        );
        oracle.disableMarket(MARKET);
    }
}
