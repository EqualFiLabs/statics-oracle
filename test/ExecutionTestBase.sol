// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import { Test } from "forge-std/Test.sol";
import { StaticsExecutionOracle } from "src/StaticsExecutionOracle.sol";
import { IStaticsExecutionOracle as IEO } from "src/interfaces/IStaticsExecutionOracle.sol";
import { DataStreamsV3 } from "src/libraries/DataStreamsV3.sol";
import { ExecutionVerifierMock } from "test/mocks/ExecutionOracleMocks.sol";
import { OracleFeedTestMock } from "test/mocks/OracleTestMocks.sol";

abstract contract ExecutionTestBase is Test {
    StaticsExecutionOracle internal oracle;
    ExecutionVerifierMock internal verifier;
    OracleFeedTestMock internal sequencer;
    bytes32 internal constant MARKET = keccak256("BTC_USD");
    bytes32 internal constant STREAM = bytes32((uint256(3) << 240) | 1234);

    function setUp() public virtual {
        vm.warp(1000);
        verifier = new ExecutionVerifierMock();
        oracle = new StaticsExecutionOracle(address(this), address(verifier), 5);
        oracle.registerMarket(MARKET, IEO.ExecutionMarketConfigInput(STREAM, 10, 30, 8));
        oracle.enableMarket(MARKET);
        oracle.setAuthorizedConsumer(address(this), true);
        sequencer = new OracleFeedTestMock(0, "health");
        sequencer.setRoundData(1, 0, 900, 900, 1);
        oracle.setSequencerConfig(address(sequencer), 10);
    }

    function report() internal pure returns (DataStreamsV3.Report memory) {
        return DataStreamsV3.Report(STREAM, 985, 995, 0, 0, 1100, 123_456_789, 1, 2);
    }

    function signed(
        DataStreamsV3.Report memory r
    ) internal returns (bytes memory payload) {
        payload = abi.encode(keccak256("test-only signed payload"), r);
        verifier.accept(payload, abi.encode(r));
    }

    function bundle(
        DataStreamsV3.Report memory r
    ) internal returns (bytes[] memory reports) {
        reports = new bytes[](1);
        reports[0] = signed(r);
    }
}
