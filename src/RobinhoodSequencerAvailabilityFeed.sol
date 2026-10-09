// SPDX-License-Identifier: MIT
// ============================================================================
//                                 EqualFi Labs
//                          https://equalfi.org
//                       https://staticsprotocol.com
//                           mhooft@equalfilabs.com
// ============================================================================
pragma solidity ^0.8.24;

import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { IAggregatorV3 } from "src/interfaces/IAggregatorV3.sol";
import { IArbSys } from "src/interfaces/IArbSys.sol";
import { AddressAliasHelper } from "src/libraries/AddressAliasHelper.sol";

/// @notice Fail-closed Robinhood sequencer signal anchored to Ethereum status transitions.
/// @dev A healthy answer requires both an L1-reported healthy state and a current L2 heartbeat.
contract RobinhoodSequencerAvailabilityFeed is IAggregatorV3, EIP712 {
    using SafeCast for uint256;

    enum AvailabilityReason {
        UNINITIALIZED,
        HEALTHY,
        L1_REPORTED_IMPAIRED,
        LEASE_EXPIRED
    }

    uint256 public constant ROBINHOOD_MAINNET_CHAIN_ID = 4_663;
    uint256 public constant ROBINHOOD_TESTNET_CHAIN_ID = 46_630;
    uint8 public constant MIN_OBSERVERS = 3;
    uint8 public constant MAX_OBSERVERS = 16;
    uint32 public constant MAX_LEASE_DURATION = 15 minutes;
    uint16 public constant MAX_BLOCK_LAG = 240;

    bytes32 public constant HEARTBEAT_TYPEHASH = keccak256(
        "Heartbeat(uint64 observerSetVersion,uint64 statusSequence,uint64 observedBlockNumber,bytes32 observedBlockHash,uint64 validUntil)"
    );

    struct Heartbeat {
        uint64 observerSetVersion;
        uint64 statusSequence;
        uint64 observedBlockNumber;
        bytes32 observedBlockHash;
        uint64 validUntil;
    }

    address public immutable l1Reporter;
    address public immutable aliasedL1Reporter;
    uint64 public immutable deployedAt;
    mapping(address observer => bool authorized) public isObserver;
    address[] private _observers;

    uint64 public observerSetVersion;
    uint64 public statusSequence;
    uint64 public l1ObservedAt;
    uint64 public l1ReceivedAt;
    uint64 public lastObservedBlockNumber;
    bytes32 public lastObservedBlockHash;
    uint64 public lastHeartbeatStatusSequence;
    uint64 public healthyUntil;
    uint64 public recoveredAt;
    uint64 public lastUpdatedAt;
    uint64 public stateStartedAt;
    uint8 public threshold;
    bool public l1Healthy;

    uint80 private _roundId;
    bool private _recordedHealthy;

    error WrongChain(uint256 actual);
    error ZeroReporter();
    error NotAliasedL1Reporter(address caller, address expected);
    error ConfigurationStatusSequenceRegression(uint64 current, uint64 supplied);
    error StatusConfigurationNotApplied(uint64 expected, uint64 supplied);
    error InvalidObserverCount(uint256 count);
    error InvalidThreshold(uint256 supplied, uint256 observerCount);
    error ObserversNotStrictlyIncreasing(address previous, address current);
    error ObserverSetVersionMismatch(uint64 expected, uint64 supplied);
    error HeartbeatStatusSequenceMismatch(uint64 expected, uint64 supplied);
    error ObservedBlockNotNewer(uint64 previous, uint64 supplied);
    error ObservedBlockNotFinalized(uint64 observedBlockNumber, uint256 currentBlockNumber);
    error ObservedBlockTooOld(uint64 observedBlockNumber, uint256 currentBlockNumber);
    error ObservedBlockHashMismatch(bytes32 expected, bytes32 actual);
    error LeaseExpired(uint64 validUntil, uint256 currentTimestamp);
    error LeaseTooLong(uint64 validUntil, uint256 maximumValidUntil);
    error LeaseNotExtended(uint64 currentValidUntil, uint64 suppliedValidUntil);
    error InvalidSignature(uint256 index);
    error UnauthorizedObserver(address signer);
    error SignersNotStrictlyIncreasing(address previous, address current);
    error InsufficientSignatures(uint256 supplied, uint256 required);
    error TooManySignatures(uint256 supplied, uint256 observerCount);

    event ConfigurationApplied(
        uint64 indexed observerSetVersion,
        uint64 indexed statusSequence,
        uint8 threshold,
        bytes32 observerSetHash
    );
    event L1StatusApplied(
        uint64 indexed observerSetVersion,
        uint64 indexed statusSequence,
        bool healthy,
        uint64 observedAt,
        uint64 receivedAt
    );
    event HealthyLeaseRenewed(
        uint64 indexed statusSequence,
        uint64 indexed observedBlockNumber,
        bytes32 observedBlockHash,
        uint64 validUntil,
        bool effectiveHealthy
    );
    event HealthyLeaseInvalidated(
        uint64 previousHealthyUntil, uint64 invalidatedAt, uint64 indexed statusSequence
    );

    modifier onlyAliasedL1Reporter() {
        if (msg.sender != aliasedL1Reporter) {
            revert NotAliasedL1Reporter(msg.sender, aliasedL1Reporter);
        }
        _;
    }

    constructor(
        address reporter
    ) EIP712("Robinhood Sequencer Heartbeat", "1") {
        if (
            block.chainid != ROBINHOOD_MAINNET_CHAIN_ID
                && block.chainid != ROBINHOOD_TESTNET_CHAIN_ID
        ) revert WrongChain(block.chainid);
        if (reporter == address(0)) revert ZeroReporter();
        l1Reporter = reporter;
        aliasedL1Reporter = AddressAliasHelper.applyL1ToL2Alias(reporter);
        deployedAt = block.timestamp.toUint64();
        stateStartedAt = deployedAt;
        lastUpdatedAt = deployedAt;
        _roundId = 1;
    }

    function applyConfiguration(
        uint64 newObserverSetVersion,
        uint64 newStatusSequence,
        address[] calldata newObservers,
        uint8 newThreshold,
        uint64 observedAt
    ) external onlyAliasedL1Reporter {
        if (newObserverSetVersion <= observerSetVersion) return;
        if (newStatusSequence < statusSequence) {
            revert ConfigurationStatusSequenceRegression(statusSequence, newStatusSequence);
        }
        _materializeExpiry();
        _validateObserverSet(newObservers, newThreshold);
        for (uint256 i; i < _observers.length; ++i) {
            isObserver[_observers[i]] = false;
        }
        delete _observers;
        for (uint256 i; i < newObservers.length; ++i) {
            address observer = newObservers[i];
            isObserver[observer] = true;
            _observers.push(observer);
        }
        observerSetVersion = newObserverSetVersion;
        statusSequence = newStatusSequence;
        threshold = newThreshold;
        l1Healthy = false;
        l1ObservedAt = observedAt;
        l1ReceivedAt = block.timestamp.toUint64();
        healthyUntil = l1ReceivedAt;
        _recordAfterMutation();
        emit ConfigurationApplied(
            newObserverSetVersion,
            newStatusSequence,
            newThreshold,
            keccak256(abi.encode(newObservers, newThreshold))
        );
    }

    function applyStatus(
        uint64 reportObserverSetVersion,
        uint64 newStatusSequence,
        bool newHealthy,
        uint64 observedAt
    ) external onlyAliasedL1Reporter {
        if (reportObserverSetVersion < observerSetVersion) return;
        if (reportObserverSetVersion > observerSetVersion) {
            revert StatusConfigurationNotApplied(observerSetVersion, reportObserverSetVersion);
        }
        bool restoresAnchoredHealthyStatus =
            newStatusSequence == statusSequence && !l1Healthy && newHealthy;
        if (newStatusSequence < statusSequence) return;
        if (newStatusSequence == statusSequence && !restoresAnchoredHealthyStatus) return;
        _materializeExpiry();
        bool skippedTransition = newStatusSequence > statusSequence + 1;
        statusSequence = newStatusSequence;
        l1Healthy = newHealthy;
        l1ObservedAt = observedAt;
        l1ReceivedAt = block.timestamp.toUint64();
        if (skippedTransition && newHealthy) {
            uint64 previousHealthyUntil = healthyUntil;
            healthyUntil = l1ReceivedAt;
            emit HealthyLeaseInvalidated(previousHealthyUntil, l1ReceivedAt, newStatusSequence);
        }
        _recordAfterMutation();
        emit L1StatusApplied(
            reportObserverSetVersion, newStatusSequence, newHealthy, observedAt, l1ReceivedAt
        );
    }

    function submitHeartbeat(
        Heartbeat calldata heartbeat,
        bytes[] calldata signatures
    ) external {
        _validateHeartbeat(heartbeat);
        _validateSignatures(_heartbeatDigest(heartbeat), signatures);
        _materializeExpiry();
        lastObservedBlockNumber = heartbeat.observedBlockNumber;
        lastObservedBlockHash = heartbeat.observedBlockHash;
        lastHeartbeatStatusSequence = heartbeat.statusSequence;
        healthyUntil = heartbeat.validUntil;
        _recordAfterMutation();
        emit HealthyLeaseRenewed(
            heartbeat.statusSequence,
            heartbeat.observedBlockNumber,
            heartbeat.observedBlockHash,
            heartbeat.validUntil,
            isUp()
        );
    }

    function observers() external view returns (address[] memory) {
        return _observers;
    }

    function observerCount() external view returns (uint256) {
        return _observers.length;
    }

    function isUp() public view returns (bool) {
        return observerSetVersion != 0 && l1Healthy && lastHeartbeatStatusSequence == statusSequence
            && block.timestamp < healthyUntil;
    }

    function availabilityReason() public view returns (AvailabilityReason) {
        if (observerSetVersion == 0) return AvailabilityReason.UNINITIALIZED;
        if (!l1Healthy) return AvailabilityReason.L1_REPORTED_IMPAIRED;
        if (lastHeartbeatStatusSequence != statusSequence || block.timestamp >= healthyUntil) {
            return AvailabilityReason.LEASE_EXPIRED;
        }
        return AvailabilityReason.HEALTHY;
    }

    function heartbeatDigest(
        Heartbeat calldata heartbeat
    ) external view returns (bytes32) {
        return _heartbeatDigest(heartbeat);
    }

    function decimals() external pure override returns (uint8) {
        return 0;
    }

    function description() external pure override returns (string memory) {
        return "Robinhood Sequencer Availability";
    }

    function version() external pure returns (uint256) {
        return 2;
    }

    function latestRoundData()
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        if (_recordedHealthy && !isUp()) {
            uint80 expiredRoundId = _roundId + 1;
            return (expiredRoundId, 1, healthyUntil, healthyUntil, expiredRoundId);
        }
        return (
            _roundId,
            _recordedHealthy ? int256(0) : int256(1),
            stateStartedAt,
            lastUpdatedAt,
            _roundId
        );
    }

    function _validateHeartbeat(
        Heartbeat calldata heartbeat
    ) private view {
        if (heartbeat.observerSetVersion != observerSetVersion) {
            revert ObserverSetVersionMismatch(observerSetVersion, heartbeat.observerSetVersion);
        }
        if (heartbeat.statusSequence != statusSequence) {
            revert HeartbeatStatusSequenceMismatch(statusSequence, heartbeat.statusSequence);
        }
        if (heartbeat.observedBlockNumber <= lastObservedBlockNumber) {
            revert ObservedBlockNotNewer(lastObservedBlockNumber, heartbeat.observedBlockNumber);
        }
        uint256 observedBlockNumber = heartbeat.observedBlockNumber;
        // Arbitrum block.number follows the parent chain; heartbeat blocks are L2 blocks.
        IArbSys arbSys = IArbSys(address(100));
        uint256 currentBlockNumber = arbSys.arbBlockNumber();
        if (observedBlockNumber >= currentBlockNumber) {
            revert ObservedBlockNotFinalized(heartbeat.observedBlockNumber, currentBlockNumber);
        }
        if (currentBlockNumber - observedBlockNumber > MAX_BLOCK_LAG) {
            revert ObservedBlockTooOld(heartbeat.observedBlockNumber, currentBlockNumber);
        }
        bytes32 canonicalHash = arbSys.arbBlockHash(observedBlockNumber);
        if (
            heartbeat.observedBlockHash == bytes32(0)
                || canonicalHash != heartbeat.observedBlockHash
        ) revert ObservedBlockHashMismatch(canonicalHash, heartbeat.observedBlockHash);
        uint256 now_ = block.timestamp;
        if (heartbeat.validUntil <= now_) revert LeaseExpired(heartbeat.validUntil, now_);
        uint256 maximumValidUntil = now_ + MAX_LEASE_DURATION;
        if (heartbeat.validUntil > maximumValidUntil) {
            revert LeaseTooLong(heartbeat.validUntil, maximumValidUntil);
        }
        if (heartbeat.validUntil <= healthyUntil) {
            revert LeaseNotExtended(healthyUntil, heartbeat.validUntil);
        }
    }

    function _validateSignatures(
        bytes32 digest,
        bytes[] calldata signatures
    ) private view {
        uint256 count = signatures.length;
        if (count < threshold) revert InsufficientSignatures(count, threshold);
        if (count > _observers.length) revert TooManySignatures(count, _observers.length);
        address previous;
        for (uint256 i; i < count; ++i) {
            (address signer, ECDSA.RecoverError recoverError,) =
                ECDSA.tryRecoverCalldata(digest, signatures[i]);
            if (recoverError != ECDSA.RecoverError.NoError) revert InvalidSignature(i);
            if (!isObserver[signer]) revert UnauthorizedObserver(signer);
            if (signer <= previous) revert SignersNotStrictlyIncreasing(previous, signer);
            previous = signer;
        }
    }

    function _validateObserverSet(
        address[] calldata newObservers,
        uint8 newThreshold
    ) private pure {
        uint256 count = newObservers.length;
        if (count < MIN_OBSERVERS || count > MAX_OBSERVERS) revert InvalidObserverCount(count);
        if (newThreshold <= count / 2 || newThreshold > count) {
            revert InvalidThreshold(newThreshold, count);
        }
        address previous;
        for (uint256 i; i < count; ++i) {
            address observer = newObservers[i];
            if (observer <= previous) {
                revert ObserversNotStrictlyIncreasing(previous, observer);
            }
            previous = observer;
        }
    }

    function _heartbeatDigest(
        Heartbeat calldata heartbeat
    ) private view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    HEARTBEAT_TYPEHASH,
                    heartbeat.observerSetVersion,
                    heartbeat.statusSequence,
                    heartbeat.observedBlockNumber,
                    heartbeat.observedBlockHash,
                    heartbeat.validUntil
                )
            )
        );
    }

    function _materializeExpiry() private {
        if (_recordedHealthy && !isUp()) {
            _roundId += 1;
            _recordedHealthy = false;
            stateStartedAt = healthyUntil;
            lastUpdatedAt = healthyUntil;
        }
    }

    function _recordAfterMutation() private {
        bool effectiveHealthy = isUp();
        uint64 now_ = block.timestamp.toUint64();
        if (effectiveHealthy != _recordedHealthy) {
            _roundId += 1;
            _recordedHealthy = effectiveHealthy;
            stateStartedAt = now_;
            if (effectiveHealthy) recoveredAt = now_;
        }
        lastUpdatedAt = now_;
    }
}
