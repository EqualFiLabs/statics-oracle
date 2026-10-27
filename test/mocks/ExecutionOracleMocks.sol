// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import { IVerifierProxy } from "src/interfaces/IVerifierProxy.sol";

/// @dev Test-only authentication allowlist. Arbitrary input is never echoed as verified data.
contract ExecutionVerifierMock is IVerifierProxy {
    mapping(bytes32 => bytes) private _bodies;
    bool public fail;
    bool public wrongCount;
    error Unauthenticated();

    function accept(
        bytes calldata payload,
        bytes calldata body
    ) external {
        _bodies[keccak256(payload)] = body;
    }

    function setFail(
        bool value
    ) external {
        fail = value;
    }

    function setWrongCount(
        bool value
    ) external {
        wrongCount = value;
    }

    function verifyBulk(
        bytes[] calldata payloads,
        bytes calldata parameters
    ) external payable returns (bytes[] memory bodies) {
        require(parameters.length == 0 && msg.value == 0, "subscription parameters");
        if (fail) revert Unauthenticated();
        bodies = new bytes[](wrongCount ? payloads.length + 1 : payloads.length);
        for (uint256 i; i < payloads.length; ++i) {
            bytes memory body = _bodies[keccak256(payloads[i])];
            if (body.length == 0) revert Unauthenticated();
            bodies[i] = body;
        }
    }
}
