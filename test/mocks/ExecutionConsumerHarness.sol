// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import { IStaticsExecutionOracle } from "src/interfaces/IStaticsExecutionOracle.sol";

/// @dev Consumer-only integration harness; no BucketPerps trading implementation.
contract ExecutionConsumerHarness {
    IStaticsExecutionOracle public immutable oracle;
    uint256 public completedActions;
    event Executed(
        bytes32 indexed marketId,
        uint256 price1e18,
        uint32 referenceTimestamp,
        uint32 observationsTimestamp
    );

    constructor(
        IStaticsExecutionOracle oracle_
    ) {
        oracle = oracle_;
    }

    function execute(
        bytes32 marketId,
        bytes[] calldata reports
    ) external returns (IStaticsExecutionOracle.ExecutionPrice memory execution) {
        ++completedActions; // Must roll back with the entire consumer call on oracle failure.
        execution = oracle.verifyExecutionPrice(marketId, reports);
        emit Executed(
            marketId,
            execution.price1e18,
            execution.referenceTimestamp,
            execution.observationsTimestamp
        );
    }
}
