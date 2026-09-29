// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Test } from "forge-std/Test.sol";

import { RobinhoodSequencerAvailabilityFeed } from "src/RobinhoodSequencerAvailabilityFeed.sol";
import { StaticsOracle } from "src/StaticsOracle.sol";
import { IStaticsOracle } from "src/interfaces/IStaticsOracle.sol";
import { OracleFeedTestMock, OracleTokenTestMock } from "test/mocks/OracleTestMocks.sol";

contract RobinhoodSequencerAvailabilityFeedTest is Test {
    uint256 internal constant OBSERVER_A_KEY = 0xA11CE;
    uint256 internal constant OBSERVER_B_KEY = 0xB0B;
    uint256 internal constant OBSERVER_C_KEY = 0xCA401;

    RobinhoodSequencerAvailabilityFeed internal feed;
    address[] internal observerAddresses;
    uint256[] internal observerKeys;

    function setUp() external {
        vm.chainId(4663);
        vm.warp(10 days);
        vm.roll(1_000);

        uint256[] memory keys = new uint256[](3);
        keys[0] = OBSERVER_A_KEY;
        keys[1] = OBSERVER_B_KEY;
        keys[2] = OBSERVER_C_KEY;
        _sortKeysByAddress(keys);
        for (uint256 i; i < keys.length; ++i) {
            observerKeys.push(keys[i]);
            observerAddresses.push(vm.addr(keys[i]));
        }

        feed = new RobinhoodSequencerAvailabilityFeed(address(this), observerAddresses, 2);
    }

    function test_InitialStateIsDownAndChainlinkCompatible() external view {
        assertFalse(feed.isUp());
        assertEq(feed.decimals(), 0);
        assertEq(feed.description(), "Robinhood Sequencer Availability");
        assertEq(feed.version(), 1);
        assertEq(feed.observerSetVersion(), 1);
        assertEq(feed.threshold(), 2);
        assertEq(feed.observerCount(), 3);
        assertEq(feed.observers(), observerAddresses);

        (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();
        assertEq(roundId, 1);
        assertEq(answer, 1);
        assertEq(startedAt, feed.deployedAt());
        assertEq(updatedAt, feed.deployedAt());
        assertEq(answeredInRound, roundId);
    }

    function test_QuorumObservationCreatesAndRenewsHealthyLease() external {
        bytes32 firstHash = keccak256("block-999");
        vm.setBlockhash(999, firstHash);
        RobinhoodSequencerAvailabilityFeed.Observation memory first =
            _observation(999, firstHash, block.timestamp + 95 seconds);

        feed.submitObservation(first, _sign(first, 2));

        assertTrue(feed.isUp());
        assertEq(feed.lastObservedBlockNumber(), 999);
        assertEq(feed.lastObservedBlockHash(), firstHash);
        assertEq(feed.healthyUntil(), first.validUntil);
        assertEq(feed.recoveredAt(), block.timestamp);
        assertEq(feed.lastUpdatedAt(), block.timestamp);
        _assertRound(2, 0, block.timestamp, block.timestamp);

        uint256 recoveredAt = block.timestamp;
        vm.warp(block.timestamp + 30 seconds);
        vm.roll(1_001);
        bytes32 secondHash = keccak256("block-1000");
        vm.setBlockhash(1_000, secondHash);
        RobinhoodSequencerAvailabilityFeed.Observation memory second =
            _observation(1_000, secondHash, block.timestamp + 95 seconds);

        feed.submitObservation(second, _sign(second, 3));

        assertEq(feed.recoveredAt(), recoveredAt);
        assertEq(feed.lastUpdatedAt(), block.timestamp);
        _assertRound(3, 0, recoveredAt, block.timestamp);
    }

    function test_LeaseExpiresWithoutTransactionAndRecoveryStartsNewRound() external {
        bytes32 firstHash = keccak256("block-999");
        vm.setBlockhash(999, firstHash);
        RobinhoodSequencerAvailabilityFeed.Observation memory first =
            _observation(999, firstHash, block.timestamp + 95 seconds);
        feed.submitObservation(first, _sign(first, 2));

        uint256 expiredAt = first.validUntil;
        vm.warp(expiredAt);
        assertFalse(feed.isUp());
        _assertRound(3, 1, expiredAt, expiredAt);

        vm.roll(1_001);
        bytes32 recoveryHash = keccak256("block-1000");
        vm.setBlockhash(1_000, recoveryHash);
        RobinhoodSequencerAvailabilityFeed.Observation memory recovery =
            _observation(1_000, recoveryHash, block.timestamp + 95 seconds);
        feed.submitObservation(recovery, _sign(recovery, 2));

        assertTrue(feed.isUp());
        assertEq(feed.recoveredAt(), expiredAt);
        _assertRound(4, 0, expiredAt, expiredAt);
    }

    function test_LeaseExpiryAndRecoveryGateStaticsOracle() external {
        bytes32 firstHash = keccak256("block-999");
        vm.setBlockhash(999, firstHash);
        RobinhoodSequencerAvailabilityFeed.Observation memory first =
            _observation(999, firstHash, block.timestamp + 95 seconds);
        feed.submitObservation(first, _sign(first, 2));

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

        vm.warp(first.validUntil);
        assertEq(
            uint8(oracle.peekPrice(address(token)).status),
            uint8(IStaticsOracle.OracleStatus.SEQUENCER_DOWN)
        );
        vm.expectRevert(StaticsOracle.SequencerDown.selector);
        oracle.priceUsd(address(token));

        vm.roll(1_001);
        bytes32 recoveryHash = keccak256("block-1000");
        vm.setBlockhash(1_000, recoveryHash);
        RobinhoodSequencerAvailabilityFeed.Observation memory recovery =
            _observation(1_000, recoveryHash, block.timestamp + 95 seconds);
        feed.submitObservation(recovery, _sign(recovery, 2));

        assertEq(
            uint8(oracle.peekPrice(address(token)).status),
            uint8(IStaticsOracle.OracleStatus.SEQUENCER_GRACE_PERIOD)
        );
        vm.warp(block.timestamp + 31 seconds);
        assertEq(oracle.priceUsd(address(token)), 100e18);
    }

    function test_ObserverRotationInvalidatesLeaseAndOldSignatures() external {
        bytes32 firstHash = keccak256("block-999");
        vm.setBlockhash(999, firstHash);
        RobinhoodSequencerAvailabilityFeed.Observation memory first =
            _observation(999, firstHash, block.timestamp + 95 seconds);
        feed.submitObservation(first, _sign(first, 2));

        uint64 previousHealthyUntil = feed.healthyUntil();
        feed.setObserverSet(observerAddresses, 2);

        assertFalse(feed.isUp());
        assertEq(feed.observerSetVersion(), 2);
        assertEq(feed.healthyUntil(), block.timestamp);
        assertLt(feed.healthyUntil(), previousHealthyUntil);

        vm.roll(1_001);
        bytes32 secondHash = keccak256("block-1000");
        vm.setBlockhash(1_000, secondHash);
        RobinhoodSequencerAvailabilityFeed.Observation memory staleVersion =
            _observation(1_000, secondHash, block.timestamp + 95 seconds);
        staleVersion.observerSetVersion = 1;
        bytes[] memory staleSignatures = _sign(staleVersion, 2);

        vm.expectRevert(
            abi.encodeWithSelector(
                RobinhoodSequencerAvailabilityFeed.ObserverSetVersionMismatch.selector, 2, 1
            )
        );
        feed.submitObservation(staleVersion, staleSignatures);
    }

    function test_RevertWhen_ObservationDoesNotHaveStrictMajorityQuorum() external {
        bytes32 observedHash = keccak256("block-999");
        vm.setBlockhash(999, observedHash);
        RobinhoodSequencerAvailabilityFeed.Observation memory observation =
            _observation(999, observedHash, block.timestamp + 95 seconds);
        bytes[] memory insufficientSignatures = _sign(observation, 1);

        vm.expectRevert(
            abi.encodeWithSelector(
                RobinhoodSequencerAvailabilityFeed.InsufficientSignatures.selector, 1, 2
            )
        );
        feed.submitObservation(observation, insufficientSignatures);

        bytes[] memory duplicateSignatures = new bytes[](2);
        duplicateSignatures[0] = _signature(observerKeys[0], feed.observationDigest(observation));
        duplicateSignatures[1] = duplicateSignatures[0];
        vm.expectRevert(
            abi.encodeWithSelector(
                RobinhoodSequencerAvailabilityFeed.SignersNotStrictlyIncreasing.selector,
                observerAddresses[0],
                observerAddresses[0]
            )
        );
        feed.submitObservation(observation, duplicateSignatures);
    }

    function test_RevertWhen_SignerIsNotAnObserver() external {
        bytes32 observedHash = keccak256("block-999");
        vm.setBlockhash(999, observedHash);
        RobinhoodSequencerAvailabilityFeed.Observation memory observation =
            _observation(999, observedHash, block.timestamp + 95 seconds);
        bytes32 digest = feed.observationDigest(observation);

        uint256[] memory keys = new uint256[](2);
        keys[0] = observerKeys[0];
        keys[1] = 0xBAD;
        _sortKeysByAddress(keys);
        bytes[] memory signatures = new bytes[](2);
        for (uint256 i; i < keys.length; ++i) {
            signatures[i] = _signature(keys[i], digest);
        }

        address attacker = vm.addr(0xBAD);
        vm.expectRevert(
            abi.encodeWithSelector(
                RobinhoodSequencerAvailabilityFeed.UnauthorizedObserver.selector, attacker
            )
        );
        feed.submitObservation(observation, signatures);
    }

    function test_RevertWhen_SignatureIsMalformedOrCountExceedsObserverSet() external {
        bytes32 observedHash = keccak256("block-999");
        vm.setBlockhash(999, observedHash);
        RobinhoodSequencerAvailabilityFeed.Observation memory observation =
            _observation(999, observedHash, block.timestamp + 95 seconds);

        bytes[] memory malformed = new bytes[](2);
        malformed[0] = hex"1234";
        malformed[1] = _signature(observerKeys[1], feed.observationDigest(observation));
        vm.expectRevert(
            abi.encodeWithSelector(RobinhoodSequencerAvailabilityFeed.InvalidSignature.selector, 0)
        );
        feed.submitObservation(observation, malformed);

        bytes[] memory excessive = new bytes[](4);
        vm.expectRevert(
            abi.encodeWithSelector(
                RobinhoodSequencerAvailabilityFeed.TooManySignatures.selector, 4, 3
            )
        );
        feed.submitObservation(observation, excessive);
    }

    function test_RevertWhen_ObservedBlockIsReplayed() external {
        bytes32 observedHash = keccak256("block-999");
        vm.setBlockhash(999, observedHash);
        RobinhoodSequencerAvailabilityFeed.Observation memory observation =
            _observation(999, observedHash, block.timestamp + 95 seconds);
        bytes[] memory signatures = _sign(observation, 2);
        feed.submitObservation(observation, signatures);

        vm.expectRevert(
            abi.encodeWithSelector(
                RobinhoodSequencerAvailabilityFeed.ObservedBlockNotNewer.selector, 999, 999
            )
        );
        feed.submitObservation(observation, signatures);
    }

    function test_RevertWhen_BlockEvidenceIsInvalid() external {
        bytes32 canonicalHash = keccak256("block-999");
        vm.setBlockhash(999, canonicalHash);

        RobinhoodSequencerAvailabilityFeed.Observation memory currentBlock =
            _observation(1_000, canonicalHash, block.timestamp + 95 seconds);
        bytes[] memory currentBlockSignatures = _sign(currentBlock, 2);
        vm.expectRevert(
            abi.encodeWithSelector(
                RobinhoodSequencerAvailabilityFeed.ObservedBlockNotFinalized.selector, 1_000, 1_000
            )
        );
        feed.submitObservation(currentBlock, currentBlockSignatures);

        RobinhoodSequencerAvailabilityFeed.Observation memory wrongHash =
            _observation(999, keccak256("wrong"), block.timestamp + 95 seconds);
        bytes[] memory wrongHashSignatures = _sign(wrongHash, 2);
        vm.expectRevert(
            abi.encodeWithSelector(
                RobinhoodSequencerAvailabilityFeed.ObservedBlockHashMismatch.selector,
                canonicalHash,
                wrongHash.observedBlockHash
            )
        );
        feed.submitObservation(wrongHash, wrongHashSignatures);

        RobinhoodSequencerAvailabilityFeed.Observation memory tooOld =
            _observation(759, keccak256("old"), block.timestamp + 95 seconds);
        bytes[] memory tooOldSignatures = _sign(tooOld, 2);
        vm.expectRevert(
            abi.encodeWithSelector(
                RobinhoodSequencerAvailabilityFeed.ObservedBlockTooOld.selector, 759, 1_000
            )
        );
        feed.submitObservation(tooOld, tooOldSignatures);
    }

    function test_RevertWhen_LeaseIsInvalidOrDoesNotExtend() external {
        bytes32 firstHash = keccak256("block-999");
        vm.setBlockhash(999, firstHash);

        RobinhoodSequencerAvailabilityFeed.Observation memory expired =
            _observation(999, firstHash, block.timestamp);
        bytes[] memory expiredSignatures = _sign(expired, 2);
        vm.expectRevert(
            abi.encodeWithSelector(
                RobinhoodSequencerAvailabilityFeed.LeaseExpired.selector,
                block.timestamp,
                block.timestamp
            )
        );
        feed.submitObservation(expired, expiredSignatures);

        RobinhoodSequencerAvailabilityFeed.Observation memory tooLong =
            _observation(999, firstHash, block.timestamp + 96 seconds);
        bytes[] memory tooLongSignatures = _sign(tooLong, 2);
        vm.expectRevert(
            abi.encodeWithSelector(
                RobinhoodSequencerAvailabilityFeed.LeaseTooLong.selector,
                block.timestamp + 96 seconds,
                block.timestamp + 95 seconds
            )
        );
        feed.submitObservation(tooLong, tooLongSignatures);

        RobinhoodSequencerAvailabilityFeed.Observation memory first =
            _observation(999, firstHash, block.timestamp + 95 seconds);
        feed.submitObservation(first, _sign(first, 2));

        vm.roll(1_001);
        bytes32 secondHash = keccak256("block-1000");
        vm.setBlockhash(1_000, secondHash);
        RobinhoodSequencerAvailabilityFeed.Observation memory shorter =
            _observation(1_000, secondHash, first.validUntil);
        bytes[] memory shorterSignatures = _sign(shorter, 2);
        vm.expectRevert(
            abi.encodeWithSelector(
                RobinhoodSequencerAvailabilityFeed.LeaseNotExtended.selector,
                first.validUntil,
                first.validUntil
            )
        );
        feed.submitObservation(shorter, shorterSignatures);
    }

    function test_RevertWhen_ObserverConfigurationIsUnsafe() external {
        address[] memory tooFew = new address[](2);
        tooFew[0] = observerAddresses[0];
        tooFew[1] = observerAddresses[1];
        vm.expectRevert(
            abi.encodeWithSelector(
                RobinhoodSequencerAvailabilityFeed.InvalidObserverCount.selector, 2
            )
        );
        feed.setObserverSet(tooFew, 2);

        vm.expectRevert(
            abi.encodeWithSelector(
                RobinhoodSequencerAvailabilityFeed.InvalidThreshold.selector, 1, 3
            )
        );
        feed.setObserverSet(observerAddresses, 1);

        address[] memory fourObservers = new address[](4);
        fourObservers[0] = address(0x1000);
        fourObservers[1] = address(0x2000);
        fourObservers[2] = address(0x3000);
        fourObservers[3] = address(0x4000);
        vm.expectRevert(
            abi.encodeWithSelector(
                RobinhoodSequencerAvailabilityFeed.InvalidThreshold.selector, 2, 4
            )
        );
        feed.setObserverSet(fourObservers, 2);

        address[] memory unsorted = new address[](3);
        unsorted[0] = observerAddresses[1];
        unsorted[1] = observerAddresses[0];
        unsorted[2] = observerAddresses[2];
        vm.expectRevert(
            abi.encodeWithSelector(
                RobinhoodSequencerAvailabilityFeed.ObserversNotStrictlyIncreasing.selector,
                observerAddresses[1],
                observerAddresses[0]
            )
        );
        feed.setObserverSet(unsorted, 2);
    }

    function test_RevertWhen_NonOwnerRotatesObserversOrOwnerRenounces() external {
        address nonOwner = makeAddr("nonOwner");
        vm.prank(nonOwner);
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, nonOwner)
        );
        feed.setObserverSet(observerAddresses, 2);

        vm.expectRevert(RobinhoodSequencerAvailabilityFeed.OwnershipRenunciationDisabled.selector);
        feed.renounceOwnership();
    }

    function test_DeploymentRejectsWrongChain() external {
        vm.chainId(1);
        vm.expectRevert(
            abi.encodeWithSelector(RobinhoodSequencerAvailabilityFeed.WrongChain.selector, 4663, 1)
        );
        new RobinhoodSequencerAvailabilityFeed(address(this), observerAddresses, 2);
    }

    function testFuzz_LeaseIsUpOnlyBeforeExpiry(
        uint32 leaseDuration
    ) external {
        leaseDuration = uint32(bound(leaseDuration, 1, feed.MAX_LEASE_DURATION()));
        bytes32 observedHash = keccak256("block-999");
        vm.setBlockhash(999, observedHash);
        RobinhoodSequencerAvailabilityFeed.Observation memory observation =
            _observation(999, observedHash, block.timestamp + leaseDuration);
        feed.submitObservation(observation, _sign(observation, 2));

        vm.warp(observation.validUntil - 1);
        assertTrue(feed.isUp());
        (, int256 upAnswer,,,) = feed.latestRoundData();
        assertEq(upAnswer, 0);

        vm.warp(observation.validUntil);
        assertFalse(feed.isUp());
        (, int256 downAnswer, uint256 startedAt,,) = feed.latestRoundData();
        assertEq(downAnswer, 1);
        assertEq(startedAt, observation.validUntil);
    }

    function _observation(
        uint64 observedBlockNumber,
        bytes32 observedBlockHash,
        uint256 validUntil
    ) internal view returns (RobinhoodSequencerAvailabilityFeed.Observation memory) {
        return RobinhoodSequencerAvailabilityFeed.Observation({
            observerSetVersion: feed.observerSetVersion(),
            observedBlockNumber: observedBlockNumber,
            observedBlockHash: observedBlockHash,
            validUntil: uint64(validUntil)
        });
    }

    function _sign(
        RobinhoodSequencerAvailabilityFeed.Observation memory observation,
        uint256 count
    ) internal view returns (bytes[] memory signatures) {
        bytes32 digest = feed.observationDigest(observation);
        signatures = new bytes[](count);
        for (uint256 i; i < count; ++i) {
            signatures[i] = _signature(observerKeys[i], digest);
        }
    }

    function _signature(
        uint256 privateKey,
        bytes32 digest
    ) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    function _sortKeysByAddress(
        uint256[] memory keys
    ) internal pure {
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
