// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import { ExecutionForkBase } from "./ExecutionForkBase.sol";
import { RobinhoodSequencerAvailabilityFeed } from "src/RobinhoodSequencerAvailabilityFeed.sol";
import { StaticsExecutionOracle } from "src/StaticsExecutionOracle.sol";
import { IAggregatorV3 } from "src/interfaces/IAggregatorV3.sol";
import { IStaticsExecutionOracle as IEO } from "src/interfaces/IStaticsExecutionOracle.sol";
import { IVerifierProxy } from "src/interfaces/IVerifierProxy.sol";
import { DataStreamsV3 } from "src/libraries/DataStreamsV3.sol";

interface IVersionedVerifier {
    function typeAndVersion() external view returns (string memory);
}

contract ExecutionSequencerGateHarness is StaticsExecutionOracle {
    constructor(
        address verifier
    ) StaticsExecutionOracle(msg.sender, verifier, 5) { }

    function checkHealth() external view {
        _requireHealthySequencer();
    }
}

contract RobinhoodExecutionOracleForkTest is ExecutionForkBase {
    function testPinnedMainnetArchiveAndDeployment() public {
        forkNetwork(0);
        assertProxy(0);
    }
}
