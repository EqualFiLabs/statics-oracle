// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";
import { IStaticsExecutionOracle } from "src/interfaces/IStaticsExecutionOracle.sol";

/// @notice Transaction-local Data Streams execution adapter for synthetic markets.
contract StaticsExecutionOracle is Ownable2Step, IStaticsExecutionOracle {
    address public immutable override verifierProxy;
    uint8 public immutable override maxReportBundleSize;
    uint64 public override registryVersion;

    error ZeroAddress();
    error NoContractCode(address account);
    error InvalidBundleBound();
    error ExecutionNotAvailable();
    error OwnershipRenunciationDisabled();

    constructor(
        address initialOwner,
        address verifierProxy_,
        uint8 maxReportBundleSize_
    ) Ownable(initialOwner) {
        if (verifierProxy_ == address(0)) revert ZeroAddress();
        if (verifierProxy_.code.length == 0) revert NoContractCode(verifierProxy_);
        if (maxReportBundleSize_ == 0) revert InvalidBundleBound();
        verifierProxy = verifierProxy_;
        maxReportBundleSize = maxReportBundleSize_;
    }

    function renounceOwnership() public pure override {
        revert OwnershipRenunciationDisabled();
    }

    function verifyExecutionPrice(
        bytes32,
        bytes[] calldata
    ) external virtual override returns (ExecutionPrice memory) {
        revert ExecutionNotAvailable();
    }

    function marketConfig(
        bytes32
    ) external view override returns (ExecutionMarketConfig memory) {
        return ExecutionMarketConfig(bytes32(0), 0, 0, 0, MarketStatus.UNSET);
    }

    function configHash(
        bytes32
    ) external view override returns (bytes32) {
        return bytes32(0);
    }

    function sequencerConfig() external view override returns (SequencerConfig memory) {
        return SequencerConfig(address(0), 0);
    }

    function isAuthorizedConsumer(
        address
    ) external view override returns (bool) {
        return false;
    }
}
