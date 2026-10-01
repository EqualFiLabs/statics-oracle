// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { ECDSA } from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import { EIP712 } from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import { IArbitrumDelayedInbox } from "src/interfaces/IArbitrumDelayedInbox.sol";
import {
    IRobinhoodSequencerAvailabilityFeed
} from "src/interfaces/IRobinhoodSequencerAvailabilityFeed.sol";

/// @notice Ethereum source of truth for Robinhood sequencer availability transitions.
/// @dev Observer signatures are gas-free. A relayer submits one transition transaction and this
///      prefunded contract pays for its retryable ticket to Robinhood Chain.
contract RobinhoodSequencerReporterL1 is Ownable2Step, EIP712, ReentrancyGuard {
    using SafeCast for uint256;

    uint256 public constant ETHEREUM_MAINNET_CHAIN_ID = 1;
    uint256 public constant ETHEREUM_SEPOLIA_CHAIN_ID = 11_155_111;
    uint256 public constant ROBINHOOD_MAINNET_CHAIN_ID = 4_663;
    uint256 public constant ROBINHOOD_TESTNET_CHAIN_ID = 46_630;
    address public constant MAINNET_DELAYED_INBOX = 0x1A07cc4BD17E0118BdB54D70990D2158AbAD7a2D;
    address public constant SEPOLIA_DELAYED_INBOX = 0xF2939afA86F6f933A3CE17fCAB007907B6b0B7a4;

    uint8 public constant MIN_OBSERVERS = 3;
    uint8 public constant MAX_OBSERVERS = 16;
    uint64 public constant MAX_FUTURE_SKEW = 30 seconds;
    uint64 public constant MAX_OBSERVATION_AGE = 5 minutes;
    uint64 public constant MAX_REPORT_VALIDITY = 10 minutes;

    bytes32 public constant STATUS_REPORT_TYPEHASH = keccak256(
        "StatusReport(uint64 observerSetVersion,uint64 sequence,bool healthy,uint64 observedAt,uint64 validUntil)"
    );

    struct StatusReport {
        uint64 observerSetVersion;
        uint64 sequence;
        bool healthy;
        uint64 observedAt;
        uint64 validUntil;
    }

    struct RecordedStatus {
        uint64 observerSetVersion;
        uint64 observedAt;
        bool healthy;
        bool exists;
    }

    IArbitrumDelayedInbox public immutable inbox;
    uint256 public immutable childChainId;
    mapping(address observer => bool authorized) public isObserver;
    mapping(uint64 sequence => RecordedStatus status) public statusHistory;
    address[] private _observers;

    address public l2Feed;
    address public l2RefundAddress;
    uint256 public statusGasLimit;
    uint256 public configurationGasLimit;
    uint256 public gasPriceBid;
    uint64 public observerSetVersion;
    uint64 public statusSequence;
    uint64 public lastObservedAt;
    uint8 public threshold;
    bool public healthy;

    error UnsupportedParentChain(uint256 chainId);
    error ZeroAddress();
    error TargetAlreadyInitialized(address target);
    error TargetNotInitialized();
    error InvalidObserverCount(uint256 count);
    error InvalidThreshold(uint256 supplied, uint256 observerCount);
    error ObserversNotStrictlyIncreasing(address previous, address current);
    error ObserverSetVersionMismatch(uint64 expected, uint64 supplied);
    error StatusSequenceMismatch(uint64 expected, uint64 supplied);
    error StatusUnchanged(bool healthy);
    error StatusNotRecorded(uint64 sequence);
    error ObservationInFuture(uint64 observedAt, uint256 currentTimestamp);
    error ObservationTooOld(uint64 observedAt, uint256 oldestAllowed);
    error ReportExpired(uint64 validUntil, uint256 currentTimestamp);
    error ReportValidityTooLong(uint64 validUntil, uint256 maximumValidUntil);
    error InvalidSignature(uint256 index);
    error UnauthorizedObserver(address signer);
    error SignersNotStrictlyIncreasing(address previous, address current);
    error InsufficientSignatures(uint256 supplied, uint256 required);
    error TooManySignatures(uint256 supplied, uint256 observerCount);
    error InvalidGasConfiguration();
    error InsufficientReporterBalance(uint256 available, uint256 required);
    error WithdrawalFailed();
    error OwnershipRenunciationDisabled();

    event ReporterFunded(address indexed sender, uint256 amount, uint256 balance);
    event ReporterWithdrawal(address indexed recipient, uint256 amount);
    event RetryableGasConfigurationUpdated(
        uint256 statusGasLimit, uint256 configurationGasLimit, uint256 gasPriceBid
    );
    event L2RefundAddressUpdated(address indexed refundAddress);
    event L2FeedInitialized(address indexed feed, uint256 indexed ticketId);
    event ObserverSetUpdated(
        uint64 indexed version, uint8 threshold, bytes32 indexed observerSetHash
    );
    event StatusTransitionAccepted(
        uint64 indexed sequence, bool healthy, uint64 observedAt, address indexed relayer
    );
    event RetryableTicketCreated(
        uint256 indexed ticketId,
        bytes4 indexed selector,
        uint64 observerSetVersion,
        uint64 statusSequence,
        uint256 fee
    );

    constructor(
        address initialOwner,
        address[] memory initialObservers,
        uint8 initialThreshold,
        address initialRefundAddress,
        uint256 initialStatusGasLimit,
        uint256 initialConfigurationGasLimit,
        uint256 initialGasPriceBid
    ) Ownable(initialOwner) EIP712("Robinhood Sequencer Reporter", "1") {
        if (block.chainid == ETHEREUM_MAINNET_CHAIN_ID) {
            inbox = IArbitrumDelayedInbox(MAINNET_DELAYED_INBOX);
            childChainId = ROBINHOOD_MAINNET_CHAIN_ID;
        } else if (block.chainid == ETHEREUM_SEPOLIA_CHAIN_ID) {
            inbox = IArbitrumDelayedInbox(SEPOLIA_DELAYED_INBOX);
            childChainId = ROBINHOOD_TESTNET_CHAIN_ID;
        } else {
            revert UnsupportedParentChain(block.chainid);
        }
        _setRefundAddress(initialRefundAddress);
        _setGasConfiguration(
            initialStatusGasLimit, initialConfigurationGasLimit, initialGasPriceBid
        );
        _replaceObserverSet(initialObservers, initialThreshold);
    }

    receive() external payable {
        emit ReporterFunded(msg.sender, msg.value, address(this).balance);
    }

    function renounceOwnership() public pure override {
        revert OwnershipRenunciationDisabled();
    }

    function observers() external view returns (address[] memory) {
        return _observers;
    }

    function observerCount() external view returns (uint256) {
        return _observers.length;
    }

    function statusReportDigest(
        StatusReport calldata report
    ) external view returns (bytes32) {
        return _statusReportDigest(report);
    }

    function setRetryableGasConfiguration(
        uint256 newStatusGasLimit,
        uint256 newConfigurationGasLimit,
        uint256 newGasPriceBid
    ) external onlyOwner {
        _setGasConfiguration(newStatusGasLimit, newConfigurationGasLimit, newGasPriceBid);
    }

    function setL2RefundAddress(
        address newRefundAddress
    ) external onlyOwner {
        _setRefundAddress(newRefundAddress);
    }

    function initializeL2Feed(
        address target
    ) external onlyOwner nonReentrant returns (uint256 ticketId) {
        if (target == address(0)) revert ZeroAddress();
        if (l2Feed != address(0)) revert TargetAlreadyInitialized(l2Feed);
        l2Feed = target;
        ticketId = _queueConfiguration();
        emit L2FeedInitialized(target, ticketId);
    }

    function submitStatusReport(
        StatusReport calldata report,
        bytes[] calldata signatures
    ) external nonReentrant returns (uint256 ticketId) {
        _requireTarget();
        _validateReport(report);
        _validateSignatures(_statusReportDigest(report), signatures);

        healthy = report.healthy;
        statusSequence = report.sequence;
        lastObservedAt = report.observedAt;
        statusHistory[report.sequence] = RecordedStatus({
            observerSetVersion: report.observerSetVersion,
            observedAt: report.observedAt,
            healthy: report.healthy,
            exists: true
        });
        ticketId = _queueStatus(
            report.observerSetVersion, report.sequence, report.healthy, report.observedAt
        );
        emit StatusTransitionAccepted(
            report.sequence, report.healthy, report.observedAt, msg.sender
        );
    }

    function rotateObserverSet(
        address[] calldata newObservers,
        uint8 newThreshold
    ) external onlyOwner nonReentrant returns (uint256 ticketId) {
        _requireTarget();
        healthy = false;
        statusSequence += 1;
        lastObservedAt = block.timestamp.toUint64();
        _replaceObserverSet(newObservers, newThreshold);
        ticketId = _queueConfiguration();
    }

    function requeueLatestStatus() external onlyOwner nonReentrant returns (uint256 ticketId) {
        _requireTarget();
        RecordedStatus memory status = statusHistory[statusSequence];
        if (status.exists) {
            return _queueStatus(
                status.observerSetVersion, statusSequence, status.healthy, status.observedAt
            );
        }
        ticketId = _queueStatus(observerSetVersion, statusSequence, healthy, lastObservedAt);
    }

    function requeueStatus(
        uint64 sequence
    ) external onlyOwner nonReentrant returns (uint256 ticketId) {
        _requireTarget();
        RecordedStatus memory status = statusHistory[sequence];
        if (!status.exists) revert StatusNotRecorded(sequence);
        ticketId =
            _queueStatus(status.observerSetVersion, sequence, status.healthy, status.observedAt);
    }

    function requeueConfiguration() external onlyOwner nonReentrant returns (uint256 ticketId) {
        _requireTarget();
        ticketId = _queueConfiguration();
    }

    function withdraw(
        address payable recipient,
        uint256 amount
    ) external onlyOwner nonReentrant {
        if (recipient == address(0)) revert ZeroAddress();
        (bool success,) = recipient.call{ value: amount }("");
        if (!success) revert WithdrawalFailed();
        emit ReporterWithdrawal(recipient, amount);
    }

    function quoteStatusRetryable() external view returns (uint256) {
        return _quote(
            _statusCalldata(observerSetVersion, statusSequence, healthy, lastObservedAt),
            statusGasLimit
        );
    }

    function quoteConfigurationRetryable() external view returns (uint256) {
        return _quote(_configurationCalldata(), configurationGasLimit);
    }

    function _validateReport(
        StatusReport calldata report
    ) private view {
        if (report.observerSetVersion != observerSetVersion) {
            revert ObserverSetVersionMismatch(observerSetVersion, report.observerSetVersion);
        }
        uint64 expectedSequence = statusSequence + 1;
        if (report.sequence != expectedSequence) {
            revert StatusSequenceMismatch(expectedSequence, report.sequence);
        }
        if (report.healthy == healthy) revert StatusUnchanged(healthy);
        uint256 now_ = block.timestamp;
        if (report.observedAt > now_ + MAX_FUTURE_SKEW) {
            revert ObservationInFuture(report.observedAt, now_);
        }
        uint256 oldestAllowed = now_ > MAX_OBSERVATION_AGE ? now_ - MAX_OBSERVATION_AGE : 0;
        if (report.observedAt < oldestAllowed) {
            revert ObservationTooOld(report.observedAt, oldestAllowed);
        }
        if (report.validUntil <= now_) revert ReportExpired(report.validUntil, now_);
        uint256 maximumValidUntil = uint256(report.observedAt) + MAX_REPORT_VALIDITY;
        if (report.validUntil > maximumValidUntil) {
            revert ReportValidityTooLong(report.validUntil, maximumValidUntil);
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

    function _statusReportDigest(
        StatusReport calldata report
    ) private view returns (bytes32) {
        return _hashTypedDataV4(
            keccak256(
                abi.encode(
                    STATUS_REPORT_TYPEHASH,
                    report.observerSetVersion,
                    report.sequence,
                    report.healthy,
                    report.observedAt,
                    report.validUntil
                )
            )
        );
    }

    function _replaceObserverSet(
        address[] memory newObservers,
        uint8 newThreshold
    ) private {
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
        for (uint256 i; i < _observers.length; ++i) {
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
        emit ObserverSetUpdated(
            observerSetVersion, newThreshold, keccak256(abi.encode(newObservers, newThreshold))
        );
    }

    function _setGasConfiguration(
        uint256 newStatusGasLimit,
        uint256 newConfigurationGasLimit,
        uint256 newGasPriceBid
    ) private {
        if (newStatusGasLimit == 0 || newConfigurationGasLimit == 0 || newGasPriceBid == 0) {
            revert InvalidGasConfiguration();
        }
        statusGasLimit = newStatusGasLimit;
        configurationGasLimit = newConfigurationGasLimit;
        gasPriceBid = newGasPriceBid;
        emit RetryableGasConfigurationUpdated(
            newStatusGasLimit, newConfigurationGasLimit, newGasPriceBid
        );
    }

    function _setRefundAddress(
        address newRefundAddress
    ) private {
        if (newRefundAddress == address(0)) revert ZeroAddress();
        l2RefundAddress = newRefundAddress;
        emit L2RefundAddressUpdated(newRefundAddress);
    }

    function _queueStatus(
        uint64 reportObserverSetVersion,
        uint64 sequence,
        bool reportHealthy,
        uint64 observedAt
    ) private returns (uint256) {
        return _queue(
            _statusCalldata(reportObserverSetVersion, sequence, reportHealthy, observedAt),
            statusGasLimit,
            IRobinhoodSequencerAvailabilityFeed.applyStatus.selector,
            reportObserverSetVersion,
            sequence
        );
    }

    function _queueConfiguration() private returns (uint256) {
        return _queue(
            _configurationCalldata(),
            configurationGasLimit,
            IRobinhoodSequencerAvailabilityFeed.applyConfiguration.selector,
            observerSetVersion,
            statusSequence
        );
    }

    function _queue(
        bytes memory data,
        uint256 gasLimit,
        bytes4 selector,
        uint64 messageObserverSetVersion,
        uint64 messageStatusSequence
    ) private returns (uint256 ticketId) {
        uint256 submissionFee = inbox.calculateRetryableSubmissionFee(data.length, block.basefee);
        uint256 fee = submissionFee + gasLimit * gasPriceBid;
        uint256 balance = address(this).balance;
        if (balance < fee) revert InsufficientReporterBalance(balance, fee);
        ticketId = _createRetryableTicket(data, gasLimit, submissionFee, fee);
        emit RetryableTicketCreated(
            ticketId, selector, messageObserverSetVersion, messageStatusSequence, fee
        );
    }

    function _createRetryableTicket(
        bytes memory data,
        uint256 gasLimit,
        uint256 submissionFee,
        uint256 fee
    ) private returns (uint256) {
        return inbox.createRetryableTicketNoRefundAliasRewrite{ value: fee }(
            l2Feed, 0, submissionFee, l2RefundAddress, l2RefundAddress, gasLimit, gasPriceBid, data
        );
    }

    function _quote(
        bytes memory data,
        uint256 gasLimit
    ) private view returns (uint256) {
        return
            inbox.calculateRetryableSubmissionFee(data.length, block.basefee) + gasLimit
                * gasPriceBid;
    }

    function _statusCalldata(
        uint64 reportObserverSetVersion,
        uint64 sequence,
        bool reportHealthy,
        uint64 observedAt
    ) private pure returns (bytes memory) {
        return abi.encodeCall(
            IRobinhoodSequencerAvailabilityFeed.applyStatus,
            (reportObserverSetVersion, sequence, reportHealthy, observedAt)
        );
    }

    function _configurationCalldata() private view returns (bytes memory) {
        return abi.encodeCall(
            IRobinhoodSequencerAvailabilityFeed.applyConfiguration,
            (observerSetVersion, statusSequence, _observers, threshold, lastObservedAt)
        );
    }

    function _requireTarget() private view {
        if (l2Feed == address(0)) revert TargetNotInitialized();
    }
}
