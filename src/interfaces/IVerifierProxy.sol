// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Chainlink subscription-mode bulk verifier surface.
interface IVerifierProxy {
    function verifyBulk(
        bytes[] calldata payloads,
        bytes calldata parameterPayload
    ) external payable returns (bytes[] memory verifiedReports);
}
