// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { IAggregatorV3 } from "src/interfaces/IAggregatorV3.sol";

/// @notice Threshold-attested availability signal for the Robinhood Chain sequencer.
/// @dev This is a self-managed observed-availability feed, not a Chainlink-managed feed and
///      not proof that every user can submit a transaction. Independent observers attest to
///      a recent canonical block after checking Robinhood's direct sequencer feed and an
///      independent RPC. If quorum observations stop, the healthy lease expires automatically.
contract RobinhoodSequencerAvailabilityFeed is IAggregatorV3, EIP712, Ownable2Step {
    using SafeCast for uint256;

    uint256 public constant ROBINHOOD_MAINNET_CHAIN_ID = 4663;
    uint8 public constant MIN_OBSERVERS = 3;
    uint8 public constant MAX_OBSERVERS = 16;
    uint32 public constant MAX_LEASE_DURATION = 95 seconds;
    uint16 public constant MAX_BLOCK_LAG = 240;

    bytes32 public constant OBSERVATION_TYPEHASH = keccak256(
        "Observation(uint64 observerSetVersion,uint64 observedBlockNumber,bytes32 observedBlockHash,uint64 validUntil)"
    );

    struct Observation {
        uint64 observerSetVersion;
        uint64 observedBlockNumber;
        bytes32 observedBlockHash;
        uint64 validUntil;
    }

    mapping(address observer => bool authorized) public isObserver;
    address[] private _observers;

    uint64 public observerSetVersion;
    uint64 public lastObservedBlockNumber;
    bytes32 public lastObservedBlockHash;
    uint64 public healthyUntil;
    uint64 public recoveredAt;
    uint64 public lastUpdatedAt;
    uint64 public immutable deployedAt;
    uint8 public threshold;

    uint80 private _roundId;
    bool private _hasObservation;

    error WrongChain(uint256 expected, uint256 actual);
    error InvalidObserverCount(uint256 count);
    error InvalidThreshold(uint256 threshold, uint256 observerCount);
    error ObserversNotStrictlyIncreasing(address previous, address current);
    error ObserverSetVersionMismatch(uint64 expected, uint64 actual);
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
    error OwnershipRenunciationDisabled();

    event ObserverSetUpdated(
        uint64 indexed version, uint8 threshold, bytes32 indexed observerSetHash
    );
    event HealthyLeaseInvalidated(uint64 previousHealthyUntil, uint64 invalidatedAt);
    event HealthyLeaseRenewed(
        uint80 indexed roundId,
        uint64 indexed observedBlockNumber,
        bytes32 observedBlockHash,
        uint64 validUntil,
        uint64 recoveredAt,
        bool recovered
    );

    constructor(
        address initialOwner,
        address[] memory initialObservers,
        uint8 initialThreshold
    ) Ownable(initialOwner) EIP712("Robinhood Sequencer Signal", "1") {
        if (block.chainid != ROBINHOOD_MAINNET_CHAIN_ID) {
            revert WrongChain(ROBINHOOD_MAINNET_CHAIN_ID, block.chainid);
        }

        deployedAt = block.timestamp.toUint64();
        _roundId = 1;
        _replaceObserverSet(initialObservers, initialThreshold);
    }

    /// @notice Preserve observer-key rotation and recovery administration.
    function renounceOwnership() public pure override {
        revert OwnershipRenunciationDisabled();
    }

    /// @notice Replace the observer set and immediately invalidate any existing healthy lease.
    /// @dev Observer addresses must be supplied in strictly increasing address order.
    function setObserverSet(
        address[] calldata newObservers,
        uint8 newThreshold
    ) external onlyOwner {
        _replaceObserverSet(newObservers, newThreshold);
    }

    /// @notice Submit a quorum-signed observation. Any account may relay it.
    /// @dev Signatures must be ordered by recovered signer address with no duplicates.
    function submitObservation(
        Observation calldata observation,
        bytes[] calldata signatures
    ) external {
        _validateObservation(observation);

        uint256 signatureCount = signatures.length;
        uint256 required = threshold;
        uint256 observerCount_ = _observers.length;
        if (signatureCount < required) {
            revert InsufficientSignatures(signatureCount, required);
        }
        if (signatureCount > observerCount_) {
            revert TooManySignatures(signatureCount, observerCount_);
        }

        bytes32 digest = _observationDigest(observation);
        address previousSigner = address(0);
        for (uint256 i; i < signatureCount; ++i) {
            (address signer, ECDSA.RecoverError recoverError,) =
                ECDSA.tryRecoverCalldata(digest, signatures[i]);
            if (recoverError != ECDSA.RecoverError.NoError) revert InvalidSignature(i);
            if (!isObserver[signer]) revert UnauthorizedObserver(signer);
            if (signer <= previousSigner) {
                revert SignersNotStrictlyIncreasing(previousSigner, signer);
            }
            previousSigner = signer;
        }

        bool recovered = !isUp();
        uint64 now_ = block.timestamp.toUint64();
        if (recovered) recoveredAt = now_;

        if (_hasObservation && recovered) {
            _roundId += 2;
        } else {
            _roundId += 1;
        }

        _hasObservation = true;
        lastObservedBlockNumber = observation.observedBlockNumber;
        lastObservedBlockHash = observation.observedBlockHash;
        healthyUntil = observation.validUntil;
        lastUpdatedAt = now_;

        emit HealthyLeaseRenewed(
            _roundId,
            observation.observedBlockNumber,
            observation.observedBlockHash,
            observation.validUntil,
            recoveredAt,
            recovered
        );
    }

    function observers() external view returns (address[] memory) {
        return _observers;
    }

    function observerCount() external view returns (uint256) {
        return _observers.length;
    }

    function isUp() public view returns (bool) {
        return _hasObservation && block.timestamp < healthyUntil;
    }

    function observationDigest(
        Observation calldata observation
    ) external view returns (bytes32) {
        return _observationDigest(observation);
    }

    function decimals() external pure override returns (uint8) {
        return 0;
    }

    function description() external pure override returns (string memory) {
        return "Robinhood Sequencer Availability";
    }

    function version() external pure returns (uint256) {
        return 1;
    }

    /// @notice Return Chainlink uptime-feed-compatible status fields.
    /// @dev answer 0 means the observed healthy lease is active. answer 1 means no valid
    ///      lease exists. A lease expiry synthesizes a down round without requiring a write.
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
        if (isUp()) {
            return (_roundId, 0, recoveredAt, lastUpdatedAt, _roundId);
        }

        if (!_hasObservation) {
            return (_roundId, 1, deployedAt, deployedAt, _roundId);
        }

        uint80 expiredRoundId = _roundId + 1;
        return (expiredRoundId, 1, healthyUntil, healthyUntil, expiredRoundId);
    }

    function _validateObservation(
        Observation calldata observation
    ) private view {
        uint64 expectedVersion = observerSetVersion;
        if (observation.observerSetVersion != expectedVersion) {
            revert ObserverSetVersionMismatch(expectedVersion, observation.observerSetVersion);
        }
        if (observation.observedBlockNumber <= lastObservedBlockNumber) {
            revert ObservedBlockNotNewer(lastObservedBlockNumber, observation.observedBlockNumber);
        }

        uint256 observedBlockNumber = observation.observedBlockNumber;
        if (observedBlockNumber >= block.number) {
            revert ObservedBlockNotFinalized(observation.observedBlockNumber, block.number);
        }
        if (block.number - observedBlockNumber > MAX_BLOCK_LAG) {
            revert ObservedBlockTooOld(observation.observedBlockNumber, block.number);
        }

        bytes32 canonicalBlockHash = blockhash(observedBlockNumber);
        if (
            observation.observedBlockHash == bytes32(0)
                || canonicalBlockHash != observation.observedBlockHash
        ) {
            revert ObservedBlockHashMismatch(canonicalBlockHash, observation.observedBlockHash);
        }

        uint256 currentTimestamp = block.timestamp;
        if (observation.validUntil <= currentTimestamp) {
            revert LeaseExpired(observation.validUntil, currentTimestamp);
        }
        uint256 maximumValidUntil = currentTimestamp + MAX_LEASE_DURATION;
        if (observation.validUntil > maximumValidUntil) {
            revert LeaseTooLong(observation.validUntil, maximumValidUntil);
        }
        if (observation.validUntil <= healthyUntil) {
            revert LeaseNotExtended(healthyUntil, observation.validUntil);
        }
    }

    function _observationDigest(
        Observation calldata observation
    ) private view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    OBSERVATION_TYPEHASH,
                    observation.observerSetVersion,
                    observation.observedBlockNumber,
                    observation.observedBlockHash,
                    observation.validUntil
                )
            )
        );
    }

    function _replaceObserverSet(
        address[] memory newObservers,
        uint8 newThreshold
    ) private {
        uint256 count = newObservers.length;
        if (count < MIN_OBSERVERS || count > MAX_OBSERVERS) {
            revert InvalidObserverCount(count);
        }
        if (newThreshold <= count / 2 || newThreshold > count) {
            revert InvalidThreshold(newThreshold, count);
        }

        address previous = address(0);
        for (uint256 i; i < count; ++i) {
            address observer = newObservers[i];
            if (observer <= previous) {
                revert ObserversNotStrictlyIncreasing(previous, observer);
            }
            previous = observer;
        }

        uint256 oldCount = _observers.length;
        for (uint256 i; i < oldCount; ++i) {
            isObserver[_observers[i]] = false;
        }
        delete _observers;

        for (uint256 i; i < count; ++i) {
            address observer = newObservers[i];
            isObserver[observer] = true;
            _observers.push(observer);
        }

        threshold = newThreshold;
        observerSetVersion += 1;

        uint64 previousHealthyUntil = healthyUntil;
        uint64 now_ = block.timestamp.toUint64();
        if (previousHealthyUntil > now_) {
            healthyUntil = now_;
            emit HealthyLeaseInvalidated(previousHealthyUntil, now_);
        }

        emit ObserverSetUpdated(
            observerSetVersion, newThreshold, keccak256(abi.encode(newObservers, newThreshold))
        );
    }
}
