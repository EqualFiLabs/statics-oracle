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

    function testFuzzReferenceTimeAndInclusiveWindow(
        uint32 delay,
        uint32 width,
        uint32 seed
    ) public {
        delay = uint32(bound(delay, 1, type(uint32).max));
        width = uint32(bound(width, 1, type(uint32).max));
        uint32 refTime = uint32(bound(seed, 2, type(uint32).max - 1));
        uint256 nowTime = uint256(delay) + refTime;
        // Signed expiry is uint32; successful V3 execution requires a representable current time.
        if (nowTime > type(uint32).max) nowTime = type(uint32).max;
        if (nowTime <= delay) return;
        refTime = uint32(nowTime - delay);
        precision(8, delay, width);
        vm.warp(nowTime);
        sequencer.setRoundData(1, 0, 1, 1, 1);
        oracle.setSequencerConfig(address(sequencer), 0);
        uint32 left = uint32(bound(seed, 0, width));
        if (left > refTime) left = refTime;
        DataStreamsV3.Report memory r = report();
        r.validFromTimestamp = refTime - left;
        r.observationsTimestamp = refTime;
        r.expiresAt = type(uint32).max;
        IEO.ExecutionPrice memory got = oracle.verifyExecutionPrice(MARKET, bundle(r));
        assertEq(got.referenceTimestamp, nowTime - delay);
        assertLe(got.validFromTimestamp, got.referenceTimestamp);
        assertLe(got.referenceTimestamp, got.observationsTimestamp);
    }
}
