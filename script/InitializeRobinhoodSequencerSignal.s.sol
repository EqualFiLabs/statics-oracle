// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { Script } from "forge-std/Script.sol";

import { RobinhoodSequencerReporterL1 } from "src/RobinhoodSequencerReporterL1.sol";

/// @notice Funds the L1 reporter and queues its one-time L2 configuration.
/// @dev Run only after the read-only deployment preflight validates both deployed contracts.
contract InitializeRobinhoodSequencerSignal is Script {
    using SafeCast for uint256;

    uint256 public constant DEFAULT_RESERVE_MESSAGES = 4;

    error ZeroAddress();
    error InvalidReserveMessages(uint256 supplied);
    error UnexpectedChildChain(uint256 expected, uint256 actual);
    error ReporterAlreadyInitialized(address configuredFeed);
    error InsufficientReporterFunding(uint256 available, uint256 required);
    error ReporterFundingFailed();
    error ReporterConfigurationMismatch(string field);

    function run() external returns (uint256 ticketId) {
        RobinhoodSequencerReporterL1 reporter =
            RobinhoodSequencerReporterL1(payable(vm.envAddress("SEQUENCER_L1_REPORTER")));
        address feed = vm.envAddress("SEQUENCER_SIGNAL_FEED");
        uint256 expectedChildChainId = vm.envUint("ROBINHOOD_CHAIN_ID");
        uint256 fundingWei = vm.envOr("SEQUENCER_REPORTER_FUNDING_WEI", uint256(0));
        uint256 reserveMessages =
            vm.envOr("SEQUENCER_RETRYABLE_RESERVE_MESSAGES", DEFAULT_RESERVE_MESSAGES);
        validateReporterConfiguration(
            reporter,
            vm.envAddress("SEQUENCER_SIGNAL_OWNER"),
            vm.envAddress("SEQUENCER_SIGNAL_OBSERVERS", ","),
            vm.envUint("SEQUENCER_SIGNAL_THRESHOLD").toUint8(),
            vm.envAddress("SEQUENCER_L2_REFUND_ADDRESS"),
            vm.envUint("SEQUENCER_STATUS_GAS_LIMIT"),
            vm.envUint("SEQUENCER_CONFIGURATION_GAS_LIMIT"),
            vm.envUint("SEQUENCER_L2_GAS_PRICE_BID")
        );

        vm.startBroadcast();
        ticketId =
            fundAndInitialize(reporter, feed, expectedChildChainId, fundingWei, reserveMessages);
        vm.stopBroadcast();
    }

    function validateReporterConfiguration(
        RobinhoodSequencerReporterL1 reporter,
        address expectedOwner,
        address[] memory expectedObservers,
        uint8 expectedThreshold,
        address expectedRefundAddress,
        uint256 expectedStatusGasLimit,
        uint256 expectedConfigurationGasLimit,
        uint256 expectedGasPriceBid
    ) public view {
        if (reporter.owner() != expectedOwner) revert ReporterConfigurationMismatch("owner");
        if (reporter.threshold() != expectedThreshold) {
            revert ReporterConfigurationMismatch("threshold");
        }
        address[] memory actualObservers = reporter.observers();
        if (actualObservers.length != expectedObservers.length) {
            revert ReporterConfigurationMismatch("observers");
        }
        for (uint256 i; i < actualObservers.length; ++i) {
            if (actualObservers[i] != expectedObservers[i]) {
                revert ReporterConfigurationMismatch("observers");
            }
        }
        if (reporter.l2RefundAddress() != expectedRefundAddress) {
            revert ReporterConfigurationMismatch("refundAddress");
        }
        if (reporter.statusGasLimit() != expectedStatusGasLimit) {
            revert ReporterConfigurationMismatch("statusGasLimit");
        }
        if (reporter.configurationGasLimit() != expectedConfigurationGasLimit) {
            revert ReporterConfigurationMismatch("configurationGasLimit");
        }
        if (reporter.gasPriceBid() != expectedGasPriceBid) {
            revert ReporterConfigurationMismatch("gasPriceBid");
        }
    }

    function requiredPreInitializationBalance(
        RobinhoodSequencerReporterL1 reporter,
        uint256 reserveMessages
    ) public view returns (uint256 required) {
        if (reserveMessages == 0) revert InvalidReserveMessages(reserveMessages);
        uint256 statusQuote = reporter.quoteStatusRetryable();
        uint256 configurationQuote = reporter.quoteConfigurationRetryable();
        uint256 maximumQuote = statusQuote > configurationQuote ? statusQuote : configurationQuote;
        required = configurationQuote + maximumQuote * reserveMessages;
    }

    function fundAndInitialize(
        RobinhoodSequencerReporterL1 reporter,
        address feed,
        uint256 expectedChildChainId,
        uint256 fundingWei,
        uint256 reserveMessages
    ) public returns (uint256 ticketId) {
        if (address(reporter) == address(0) || feed == address(0)) revert ZeroAddress();
        uint256 actualChildChainId = reporter.childChainId();
        if (actualChildChainId != expectedChildChainId) {
            revert UnexpectedChildChain(expectedChildChainId, actualChildChainId);
        }
        address configuredFeed = reporter.l2Feed();
        if (configuredFeed != address(0)) revert ReporterAlreadyInitialized(configuredFeed);

        uint256 required = requiredPreInitializationBalance(reporter, reserveMessages);
        uint256 available = address(reporter).balance + fundingWei;
        if (available < required) revert InsufficientReporterFunding(available, required);

        if (fundingWei != 0) {
            (bool funded,) = payable(address(reporter)).call{ value: fundingWei }("");
            if (!funded) revert ReporterFundingFailed();
        }
        ticketId = reporter.initializeL2Feed(feed);
    }
}
