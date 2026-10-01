// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Test } from "forge-std/Test.sol";

import { RobinhoodSequencerReporterL1 } from "src/RobinhoodSequencerReporterL1.sol";
import { IArbitrumDelayedInbox } from "src/interfaces/IArbitrumDelayedInbox.sol";
import {
    IRobinhoodSequencerAvailabilityFeed
} from "src/interfaces/IRobinhoodSequencerAvailabilityFeed.sol";

contract RobinhoodSequencerReporterL1Test is Test {
    uint256 internal constant KEY_A = 0xA11CE;
    uint256 internal constant KEY_B = 0xB0B;
    uint256 internal constant KEY_C = 0xCA401;
    uint256 internal constant STATUS_GAS = 200_000;
    uint256 internal constant CONFIG_GAS = 400_000;
    uint256 internal constant GAS_PRICE = 1 gwei;
    uint256 internal constant SUBMISSION_FEE = 0.001 ether;

    RobinhoodSequencerReporterL1 internal reporter;
    address[] internal observers;
    uint256[] internal keys;
    address internal inbox;

    function setUp() external {
        vm.chainId(1);
        vm.warp(10 days);
        keys.push(KEY_A);
        keys.push(KEY_B);
        keys.push(KEY_C);
        _sortKeys();
        for (uint256 i; i < keys.length; ++i) {
            observers.push(vm.addr(keys[i]));
        }
        reporter = new RobinhoodSequencerReporterL1(
            address(this), observers, 2, address(0xBEEF), STATUS_GAS, CONFIG_GAS, GAS_PRICE
        );
        inbox = address(reporter.inbox());
        vm.mockCall(
            inbox,
            abi.encodeWithSelector(IArbitrumDelayedInbox.calculateRetryableSubmissionFee.selector),
            abi.encode(SUBMISSION_FEE)
        );
        vm.mockCall(
            inbox,
            abi.encodeWithSelector(
                IArbitrumDelayedInbox.createRetryableTicketNoRefundAliasRewrite.selector
            ),
            abi.encode(uint256(7))
        );
        vm.deal(address(reporter), 10 ether);
    }

    function test_InitialConfigurationAndSupportedNetworks() external view {
        assertEq(address(reporter.inbox()), reporter.MAINNET_DELAYED_INBOX());
        assertEq(reporter.childChainId(), 4_663);
        assertEq(reporter.observerSetVersion(), 1);
        assertEq(reporter.threshold(), 2);
        assertEq(reporter.observers(), observers);
        assertFalse(reporter.healthy());
    }

    function test_InitializeOnceThenTransitionWithQuorum() external {
        reporter.initializeL2Feed(address(0xCAFE));
        assertEq(reporter.l2Feed(), address(0xCAFE));

        RobinhoodSequencerReporterL1.StatusReport memory report = _report(true);
        reporter.submitStatusReport(report, _sign(report, 2));
        assertTrue(reporter.healthy());
        assertEq(reporter.statusSequence(), 1);
        assertEq(reporter.lastObservedAt(), report.observedAt);

        vm.expectRevert(
            abi.encodeWithSelector(
                RobinhoodSequencerReporterL1.TargetAlreadyInitialized.selector, address(0xCAFE)
            )
        );
        reporter.initializeL2Feed(address(0xDEAD));
    }

    function test_TransitionOnlyRejectsSameStateReplayAndBadQuorum() external {
        reporter.initializeL2Feed(address(0xCAFE));
        RobinhoodSequencerReporterL1.StatusReport memory report = _report(true);
        bytes[] memory oneSignature = _sign(report, 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                RobinhoodSequencerReporterL1.InsufficientSignatures.selector, 1, 2
            )
        );
        reporter.submitStatusReport(report, oneSignature);
        reporter.submitStatusReport(report, _sign(report, 2));

        RobinhoodSequencerReporterL1.StatusReport memory same = _report(true);
        bytes[] memory sameSignatures = _sign(same, 2);
        vm.expectRevert(
            abi.encodeWithSelector(RobinhoodSequencerReporterL1.StatusUnchanged.selector, true)
        );
        reporter.submitStatusReport(same, sameSignatures);
    }

    function test_RetryableFailureRollsBackStatusAndInsufficientBalanceFailsClosed() external {
        reporter.initializeL2Feed(address(0xCAFE));
        RobinhoodSequencerReporterL1.StatusReport memory report = _report(true);
        bytes[] memory signatures = _sign(report, 2);
        vm.mockCallRevert(
            inbox,
            abi.encodeWithSelector(
                IArbitrumDelayedInbox.createRetryableTicketNoRefundAliasRewrite.selector
            ),
            abi.encodeWithSignature("Error(string)", "inbox failed")
        );
        vm.expectRevert();
        reporter.submitStatusReport(report, signatures);
        assertFalse(reporter.healthy());
        assertEq(reporter.statusSequence(), 0);

        vm.clearMockedCalls();
        vm.mockCall(
            inbox,
            abi.encodeWithSelector(IArbitrumDelayedInbox.calculateRetryableSubmissionFee.selector),
            abi.encode(SUBMISSION_FEE)
        );
        reporter.withdraw(payable(address(0xBEEF)), address(reporter).balance);
        vm.expectRevert(
            abi.encodeWithSelector(
                RobinhoodSequencerReporterL1.InsufficientReporterBalance.selector,
                0,
                SUBMISSION_FEE + STATUS_GAS * GAS_PRICE
            )
        );
        reporter.submitStatusReport(report, signatures);
    }

    function test_RotationFailsClosedAndQueuesNewConfiguration() external {
        reporter.initializeL2Feed(address(0xCAFE));
        RobinhoodSequencerReporterL1.StatusReport memory report = _report(true);
        reporter.submitStatusReport(report, _sign(report, 2));

        reporter.rotateObserverSet(observers, 2);
        assertFalse(reporter.healthy());
        assertEq(reporter.observerSetVersion(), 2);
        assertEq(reporter.statusSequence(), 2);
    }

    function test_SafeCanRequeueExactMissingHistoricalStatus() external {
        address target = address(0xCAFE);
        reporter.initializeL2Feed(target);
        RobinhoodSequencerReporterL1.StatusReport memory up = _report(true);
        reporter.submitStatusReport(up, _sign(up, 2));
        RobinhoodSequencerReporterL1.StatusReport memory down = _report(false);
        reporter.submitStatusReport(down, _sign(down, 2));

        (uint64 recordedVersion, uint64 recordedAt, bool recordedHealthy, bool exists) =
            reporter.statusHistory(1);
        assertEq(recordedVersion, 1);
        assertEq(recordedAt, up.observedAt);
        assertTrue(recordedHealthy);
        assertTrue(exists);

        bytes memory message = abi.encodeCall(
            IRobinhoodSequencerAvailabilityFeed.applyStatus,
            (uint64(1), uint64(1), true, up.observedAt)
        );
        uint256 fee = SUBMISSION_FEE + STATUS_GAS * GAS_PRICE;
        vm.expectCall(
            inbox,
            fee,
            abi.encodeCall(
                IArbitrumDelayedInbox.createRetryableTicketNoRefundAliasRewrite,
                (
                    target,
                    0,
                    SUBMISSION_FEE,
                    address(0xBEEF),
                    address(0xBEEF),
                    STATUS_GAS,
                    GAS_PRICE,
                    message
                )
            )
        );
        reporter.requeueStatus(1);

        vm.expectRevert(
            abi.encodeWithSelector(RobinhoodSequencerReporterL1.StatusNotRecorded.selector, 3)
        );
        reporter.requeueStatus(3);
    }

    function test_AdminControlsAreOwnerOnlyAndRenunciationDisabled() external {
        address stranger = address(0xBAD);
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger)
        );
        reporter.setRetryableGasConfiguration(1, 1, 1);

        vm.expectRevert(RobinhoodSequencerReporterL1.OwnershipRenunciationDisabled.selector);
        reporter.renounceOwnership();
    }

    function test_RejectsStaleFutureExpiredAndOverlongReports() external {
        reporter.initializeL2Feed(address(0xCAFE));
        RobinhoodSequencerReporterL1.StatusReport memory report = _report(true);

        report.observedAt = uint64(block.timestamp - 5 minutes - 1);
        bytes[] memory signatures = _sign(report, 2);
        vm.expectRevert(
            abi.encodeWithSelector(
                RobinhoodSequencerReporterL1.ObservationTooOld.selector,
                report.observedAt,
                block.timestamp - 5 minutes
            )
        );
        reporter.submitStatusReport(report, signatures);

        report = _report(true);
        report.observedAt = uint64(block.timestamp + 31 seconds);
        signatures = _sign(report, 2);
        vm.expectRevert(
            abi.encodeWithSelector(
                RobinhoodSequencerReporterL1.ObservationInFuture.selector,
                report.observedAt,
                block.timestamp
            )
        );
        reporter.submitStatusReport(report, signatures);

        report = _report(true);
        report.validUntil = uint64(block.timestamp);
        signatures = _sign(report, 2);
        vm.expectRevert(
            abi.encodeWithSelector(
                RobinhoodSequencerReporterL1.ReportExpired.selector,
                report.validUntil,
                block.timestamp
            )
        );
        reporter.submitStatusReport(report, signatures);

        report = _report(true);
        report.validUntil = report.observedAt + 10 minutes + 1;
        signatures = _sign(report, 2);
        vm.expectRevert(
            abi.encodeWithSelector(
                RobinhoodSequencerReporterL1.ReportValidityTooLong.selector,
                report.validUntil,
                uint256(report.observedAt) + 10 minutes
            )
        );
        reporter.submitStatusReport(report, signatures);
    }

    function test_RejectsUnsupportedParentChain() external {
        vm.chainId(4_663);
        vm.expectRevert(
            abi.encodeWithSelector(
                RobinhoodSequencerReporterL1.UnsupportedParentChain.selector, 4_663
            )
        );
        new RobinhoodSequencerReporterL1(
            address(this), observers, 2, address(0xBEEF), STATUS_GAS, CONFIG_GAS, GAS_PRICE
        );
    }

    function _report(
        bool healthy
    ) internal view returns (RobinhoodSequencerReporterL1.StatusReport memory) {
        return RobinhoodSequencerReporterL1.StatusReport({
            observerSetVersion: reporter.observerSetVersion(),
            sequence: reporter.statusSequence() + 1,
            healthy: healthy,
            observedAt: uint64(block.timestamp),
            validUntil: uint64(block.timestamp + 5 minutes)
        });
    }

    function _sign(
        RobinhoodSequencerReporterL1.StatusReport memory report,
        uint256 count
    ) internal view returns (bytes[] memory signatures) {
        bytes32 digest = reporter.statusReportDigest(report);
        signatures = new bytes[](count);
        for (uint256 i; i < count; ++i) {
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(keys[i], digest);
            signatures[i] = abi.encodePacked(r, s, v);
        }
    }

    function _sortKeys() internal {
        for (uint256 i = 1; i < keys.length; ++i) {
            uint256 key = keys[i];
            address signer = vm.addr(key);
            uint256 j = i;
            while (j > 0 && vm.addr(keys[j - 1]) > signer) {
                keys[j] = keys[j - 1];
                --j;
            }
            keys[j] = key;
        }
    }
}
