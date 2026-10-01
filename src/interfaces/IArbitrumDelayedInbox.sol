// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IArbitrumDelayedInbox {
    function calculateRetryableSubmissionFee(
        uint256 dataLength,
        uint256 baseFee
    ) external view returns (uint256);

    function createRetryableTicketNoRefundAliasRewrite(
        address to,
        uint256 l2CallValue,
        uint256 maxSubmissionCost,
        address excessFeeRefundAddress,
        address callValueRefundAddress,
        uint256 gasLimit,
        uint256 maxFeePerGas,
        bytes calldata data
    ) external payable returns (uint256 ticketId);
}
