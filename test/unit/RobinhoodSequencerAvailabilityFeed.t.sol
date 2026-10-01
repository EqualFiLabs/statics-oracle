// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";

import { RobinhoodSequencerAvailabilityFeed } from "src/RobinhoodSequencerAvailabilityFeed.sol";
import { StaticsOracle } from "src/StaticsOracle.sol";
import { IStaticsOracle } from "src/interfaces/IStaticsOracle.sol";
import { OracleFeedTestMock, OracleTokenTestMock } from "test/mocks/OracleTestMocks.sol";

contract RobinhoodSequencerAvailabilityFeedTest is Test {
    uint256 internal constant KEY_A = 0xA11CE;
    uint256 internal constant KEY_B = 0xB0B;
    uint256 internal constant KEY_C = 0xCA401;
    address internal constant REPORTER = address(0x123456);

    RobinhoodSequencerAvailabilityFeed internal feed;
    address[] internal observers;
    uint256[] internal keys;
    address internal aliasReporter;

    function setUp() external {
        vm.chainId(4_663);
        vm.warp(10 days);
        vm.roll(1_000);
        keys.push(KEY_A);
        keys.push(KEY_B);
        keys.push(KEY_C);
        _sortKeys();
        for (uint256 i; i < keys.length; ++i) {
            observers.push(vm.addr(keys[i]));
        }
        feed = new RobinhoodSequencerAvailabilityFeed(REPORTER);
        aliasReporter = feed.aliasedL1Reporter();
    }

    function test_InitialStateIsFailClosedAndChainlinkCompatible() external view {
        assertFalse(feed.isUp());
        assertEq(uint8(feed.availabilityReason()), 0);
        assertEq(feed.decimals(), 0);
        assertEq(feed.version(), 2);
        assertEq(feed.l1Reporter(), REPORTER);
        _assertRound(1, 1, feed.deployedAt(), feed.deployedAt());
    }

    function test_AliasedReporterConfiguresAndStatusPlusHeartbeatRecovers() external {
        _configure(1, 0);
        assertEq(feed.observers(), observers);
        assertEq(feed.threshold(), 2);
        assertEq(uint8(feed.availabilityReason()), 2);

        _status(1, true);
        assertEq(uint8(feed.availabilityReason()), 3);

        RobinhoodSequencerAvailabilityFeed.Heartbeat memory heartbeat = _heartbeat(999, 15 minutes);
        feed.submitHeartbeat(heartbeat, _sign(heartbeat, 2));

        assertTrue(feed.isUp());
        assertEq(uint8(feed.availabilityReason()), 1);
        assertEq(feed.healthyUntil(), heartbeat.validUntil);
        assertEq(feed.recoveredAt(), block.timestamp);
        _assertRound(2, 0, block.timestamp, block.timestamp);
    }

    function test_LeaseExpiresWithoutWriteAndRecoveryGetsFullGrace() external {
        _configure(1, 0);
        _status(1, true);
        RobinhoodSequencerAvailabilityFeed.Heartbeat memory first = _heartbeat(999, 15 minutes);
        feed.submitHeartbeat(first, _sign(first, 2));

        vm.warp(first.validUntil);
        assertFalse(feed.isUp());
        assertEq(uint8(feed.availabilityReason()), 3);
        _assertRound(3, 1, first.validUntil, first.validUntil);

        vm.roll(1_001);
        RobinhoodSequencerAvailabilityFeed.Heartbeat memory recovery = _heartbeat(1_000, 15 minutes);
        feed.submitHeartbeat(recovery, _sign(recovery, 2));
        assertTrue(feed.isUp());
        _assertRound(4, 0, block.timestamp, block.timestamp);
    }

    function test_L1ImpairmentOverridesActiveLeaseAndStaleMessagesAreNoOps() external {
        _configure(1, 0);
        _status(1, true);
        RobinhoodSequencerAvailabilityFeed.Heartbeat memory heartbeat = _heartbeat(999, 15 minutes);
        feed.submitHeartbeat(heartbeat, _sign(heartbeat, 2));

        vm.warp(block.timestamp + 1 minutes);
        _status(2, false);
        assertFalse(feed.isUp());
        assertEq(uint8(feed.availabilityReason()), 2);
        _assertRound(3, 1, block.timestamp, block.timestamp);

        vm.prank(aliasReporter);
        feed.applyStatus(1, 1, true, uint64(block.timestamp));
        assertFalse(feed.isUp());
        assertEq(feed.statusSequence(), 2);
    }

    function test_ConfigurationRotationInvalidatesLeaseAndOldHeartbeats() external {
        _configure(1, 0);
        _status(1, true);
        RobinhoodSequencerAvailabilityFeed.Heartbeat memory heartbeat = _heartbeat(999, 15 minutes);
        feed.submitHeartbeat(heartbeat, _sign(heartbeat, 2));

        _configure(2, 2);
        assertFalse(feed.isUp());
        assertEq(feed.observerSetVersion(), 2);
        assertEq(feed.healthyUntil(), block.timestamp);

        vm.roll(1_001);
        RobinhoodSequencerAvailabilityFeed.Heartbeat memory stale = _heartbeat(1_000, 15 minutes);
        stale.observerSetVersion = 1;
        bytes[] memory staleSignatures = _sign(stale, 2);
        vm.expectRevert(
            abi.encodeWithSelector(
                RobinhoodSequencerAvailabilityFeed.ObserverSetVersionMismatch.selector, 2, 1
            )
        );
        feed.submitHeartbeat(stale, staleSignatures);
    }

    function test_OnlyAliasCanApplyOrderedCrossChainMessages() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                RobinhoodSequencerAvailabilityFeed.NotAliasedL1Reporter.selector,
                address(this),
                aliasReporter
            )
        );
        feed.applyConfiguration(1, 0, observers, 2, uint64(block.timestamp));

        vm.prank(aliasReporter);
        vm.expectRevert(
            abi.encodeWithSelector(
                RobinhoodSequencerAvailabilityFeed.ConfigurationVersionGap.selector, 1, 2
            )
        );
        feed.applyConfiguration(2, 0, observers, 2, uint64(block.timestamp));

        _configure(1, 0);
        vm.prank(aliasReporter);
        vm.expectRevert(
            abi.encodeWithSelector(
                RobinhoodSequencerAvailabilityFeed.StatusConfigurationNotApplied.selector, 1, 2
            )
        );
        feed.applyStatus(2, 1, true, uint64(block.timestamp));
    }

    function test_AuthenticatedLatestStatusCanAdvanceAcrossMissingRetryable() external {
        _configure(1, 0);

        vm.prank(aliasReporter);
        feed.applyStatus(1, 3, true, uint64(block.timestamp));
        assertEq(feed.statusSequence(), 3);
        assertTrue(feed.l1Healthy());
        assertEq(uint8(feed.availabilityReason()), 3);

        vm.prank(aliasReporter);
        feed.applyStatus(1, 2, false, uint64(block.timestamp));
        assertEq(feed.statusSequence(), 3);
        assertTrue(feed.l1Healthy());
    }

    function test_HeartbeatRequiresQuorumCanonicalBlockAndBoundedLease() external {
        _configure(1, 0);
        _status(1, true);
        RobinhoodSequencerAvailabilityFeed.Heartbeat memory heartbeat = _heartbeat(999, 15 minutes);
        bytes[] memory oneSignature = _sign(heartbeat, 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                RobinhoodSequencerAvailabilityFeed.InsufficientSignatures.selector, 1, 2
            )
        );
        feed.submitHeartbeat(heartbeat, oneSignature);

        heartbeat.validUntil += 1;
        bytes[] memory signatures = _sign(heartbeat, 2);
        vm.expectRevert(
            abi.encodeWithSelector(
                RobinhoodSequencerAvailabilityFeed.LeaseTooLong.selector,
                heartbeat.validUntil,
                block.timestamp + 15 minutes
            )
        );
        feed.submitHeartbeat(heartbeat, signatures);
    }

    function test_EffectiveRecoveryIntegratesWithStaticsOracleGracePeriod() external {
        _configure(1, 0);
        _status(1, true);
        RobinhoodSequencerAvailabilityFeed.Heartbeat memory heartbeat = _heartbeat(999, 15 minutes);
        feed.submitHeartbeat(heartbeat, _sign(heartbeat, 2));

        StaticsOracle oracle = new StaticsOracle(address(this));
        OracleTokenTestMock token = new OracleTokenTestMock(18);
        OracleFeedTestMock priceFeed = new OracleFeedTestMock(8, "ASSET / USD");
        priceFeed.setRound(100e8, block.timestamp);
        oracle.setSequencerConfig(address(feed), 30 seconds);
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
        vm.warp(block.timestamp + 31 seconds);
        oracle.enableAsset(address(token));
        assertEq(oracle.priceUsd(address(token)), 100e18);

        _status(2, false);
        assertEq(
            uint8(oracle.peekPrice(address(token)).status),
            uint8(IStaticsOracle.OracleStatus.SEQUENCER_DOWN)
        );
        vm.warp(block.timestamp + 1);
        _status(3, true);
        assertEq(
            uint8(oracle.peekPrice(address(token)).status),
            uint8(IStaticsOracle.OracleStatus.SEQUENCER_GRACE_PERIOD)
        );
    }

    function test_DeploymentSupportsOnlyRobinhoodMainnetAndTestnet() external {
        vm.chainId(46_630);
        RobinhoodSequencerAvailabilityFeed testnetFeed =
            new RobinhoodSequencerAvailabilityFeed(REPORTER);
        assertEq(testnetFeed.l1Reporter(), REPORTER);

        vm.chainId(1);
        vm.expectRevert(
            abi.encodeWithSelector(RobinhoodSequencerAvailabilityFeed.WrongChain.selector, 1)
        );
        new RobinhoodSequencerAvailabilityFeed(REPORTER);
    }

    function testFuzz_AnswerZeroIffL1HealthyAndLeaseActive(
        uint32 elapsed
    ) external {
        _configure(1, 0);
        _status(1, true);
        RobinhoodSequencerAvailabilityFeed.Heartbeat memory heartbeat = _heartbeat(999, 15 minutes);
        feed.submitHeartbeat(heartbeat, _sign(heartbeat, 2));
        elapsed = uint32(bound(elapsed, 0, 20 minutes));
        vm.warp(block.timestamp + elapsed);
        (, int256 answer,,,) = feed.latestRoundData();
        assertEq(answer == 0, feed.l1Healthy() && block.timestamp < feed.healthyUntil());
    }

    function _configure(
        uint64 version,
        uint64 sequence
    ) internal {
        vm.prank(aliasReporter);
        feed.applyConfiguration(version, sequence, observers, 2, uint64(block.timestamp));
    }

    function _status(
        uint64 sequence,
        bool healthy
    ) internal {
        uint64 version = feed.observerSetVersion();
        vm.prank(aliasReporter);
        feed.applyStatus(version, sequence, healthy, uint64(block.timestamp));
    }

    function _heartbeat(
        uint64 blockNumber,
        uint64 duration
    ) internal returns (RobinhoodSequencerAvailabilityFeed.Heartbeat memory heartbeat) {
        bytes32 hash = keccak256(abi.encode(blockNumber));
        vm.setBlockhash(blockNumber, hash);
        heartbeat = RobinhoodSequencerAvailabilityFeed.Heartbeat({
            observerSetVersion: feed.observerSetVersion(),
            observedBlockNumber: blockNumber,
            observedBlockHash: hash,
            validUntil: uint64(block.timestamp + duration)
        });
    }

    function _sign(
        RobinhoodSequencerAvailabilityFeed.Heartbeat memory heartbeat,
        uint256 count
    ) internal view returns (bytes[] memory signatures) {
        bytes32 digest = feed.heartbeatDigest(heartbeat);
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

    function _assertRound(
        uint80 expectedRoundId,
        int256 expectedAnswer,
        uint256 expectedStartedAt,
        uint256 expectedUpdatedAt
    ) internal view {
        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();
        assertEq(roundId, expectedRoundId);
        assertEq(answer, expectedAnswer);
        assertEq(startedAt, expectedStartedAt);
        assertEq(updatedAt, expectedUpdatedAt);
        assertEq(answeredInRound, roundId);
    }
}
