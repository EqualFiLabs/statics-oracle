// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Test } from "forge-std/Test.sol";
import { Vm } from "forge-std/Vm.sol";
import { StaticsExecutionOracle } from "src/StaticsExecutionOracle.sol";
import { IStaticsExecutionOracle as IEO } from "src/interfaces/IStaticsExecutionOracle.sol";

contract ExecutionVerifierCodeMock { }

import { ExecutionConfigBase } from "test/ExecutionConfigBase.sol";

contract ExecutionConfigTest is ExecutionConfigBase {
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

    function testStreamReplacementRequiresDisableAndReview() public {
        oracle.registerMarket(MARKET, input());
        oracle.enableMarket(MARKET);
        IEO.ExecutionMarketConfigInput memory next = input();
        next.streamId = bytes32((uint256(3) << 240) | 5678);
        vm.expectRevert(
            abi.encodeWithSelector(
                StaticsExecutionOracle.MarketMustBeDisabled.selector,
                MARKET,
                IEO.MarketStatus.ENABLED
            )
        );
        oracle.updateMarket(MARKET, next);
        oracle.disableMarket(MARKET);
        oracle.updateMarket(MARKET, next);
        assertEq(uint8(oracle.marketConfig(MARKET).status), uint8(IEO.MarketStatus.CANDIDATE));
        oracle.enableMarket(MARKET);
    }

    function testRejectedMutationsPreserveVersionAndHashTracksLifecycle() public {
        oracle.registerMarket(MARKET, input());
        bytes32 candidate = oracle.configHash(MARKET);
        oracle.enableMarket(MARKET);
        assertNotEq(candidate, oracle.configHash(MARKET));
        uint64 version = oracle.registryVersion();
        vm.expectRevert();
        oracle.updateMarket(MARKET, input());
        assertEq(oracle.registryVersion(), version);
        oracle.disableMarket(MARKET);
        oracle.updateMarket(MARKET, input());
        assertEq(candidate, oracle.configHash(MARKET));
        assertEq(oracle.registryVersion(), version + 2);
    }

    function testAllMarketMutationsRequireOwnerAndFailedCallsDoNotAdvanceVersion() public {
        IEO.ExecutionMarketConfigInput memory cfg = input();
        oracle.registerMarket(MARKET, cfg);
        uint64 version = oracle.registryVersion();
        vm.startPrank(address(123));
        vm.expectRevert();
        oracle.enableMarket(MARKET);
        vm.expectRevert();
        oracle.disableMarket(MARKET);
        vm.expectRevert();
        oracle.updateMarket(MARKET, cfg);
        vm.expectRevert();
        oracle.registerMarket(keccak256("ETH_USD"), cfg);
        vm.stopPrank();
        assertEq(oracle.registryVersion(), version);
    }

    function testRegistrationEmitsLifecycleAndBindingWithOneVersion() public {
        vm.recordLogs();
        oracle.registerMarket(MARKET, input());
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 2);
        assertEq(logs[0].topics[0], keccak256("MarketRegistered(bytes32,bytes32,uint64,bytes32)"));
        assertEq(logs[0].topics[1], MARKET);
        assertEq(logs[0].topics[2], STREAM);
        assertEq(logs[0].topics[3], bytes32(uint256(1)));
        assertEq(logs[0].data, abi.encode(oracle.configHash(MARKET)));
        assertEq(logs[1].topics[0], keccak256("MarketStatusChanged(bytes32,uint8,uint8,uint64)"));
        assertEq(logs[1].topics[2], bytes32(uint256(1)));
        assertEq(oracle.registryVersion(), 1);
    }
}
