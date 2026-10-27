// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import { StaticsExecutionOracle } from "src/StaticsExecutionOracle.sol";
import { IStaticsExecutionOracle as IEO } from "src/interfaces/IStaticsExecutionOracle.sol";
import { DataStreamsV3 } from "src/libraries/DataStreamsV3.sol";
import { ExecutionTestBase } from "test/ExecutionTestBase.sol";
import { ExecutionVerifierMock } from "test/mocks/ExecutionOracleMocks.sol";

contract ExecutionPropertiesTest is ExecutionTestBase {
    function precision(
        uint8 decimals,
        uint32 delay,
        uint32 width
    ) internal {
        oracle.disableMarket(MARKET);
        oracle.updateMarket(MARKET, IEO.ExecutionMarketConfigInput(STREAM, delay, width, decimals));
        oracle.enableMarket(MARKET);
    }
}
