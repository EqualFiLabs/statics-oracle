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

    function testFuzzConsensusPriceIsSoleAuthority(
        uint192 raw,
        uint8 decimals,
        int192 bid,
        int192 ask
    ) public {
        uint256 price = bound(uint256(raw), 1, uint256(uint192(type(int192).max)));
        decimals = uint8(bound(decimals, 0, 18));
        precision(decimals, 10, 30);
        DataStreamsV3.Report memory r = report();
        r.price = int192(int256(price));
        r.bid = bid;
        r.ask = ask;
        assertEq(
            oracle.verifyExecutionPrice(MARKET, bundle(r)).price1e18, price * 10 ** (18 - decimals)
        );
    }
}
