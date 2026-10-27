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

    function testCanonicalVerifierIdentityOnMainnetAndTestnet() public {
        for (uint256 network; network < 2; ++network) {
            forkNetwork(network);
            assertProxy(network);
            assertEq(IVersionedVerifier(proxy(network)).typeAndVersion(), "VerifierProxy 2.0.0");
        }
    }

    function testCanonicalVerifierRejectsForgedPayload() public {
        forkNetwork(0);
        bytes[] memory reports = new bytes[](1);
        reports[0] = hex"deadbeef";
        vm.expectRevert();
        IVerifierProxy(proxy(0)).verifyBulk(reports, bytes(""));
    }

    function testRealSignedReportsAndSubscriptionVerification() public {
        string memory path = vm.envOr("EXECUTION_REPORT_FIXTURE", string(""));
        if (bytes(path).length == 0) {
            vm.skip(true, "Licensed pinned signed-report fixture is required");
            return;
        }
        string memory rpc = vm.envOr("ROBINHOOD_MAINNET", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true, "Configured Robinhood RPC is required");
            return;
        }
        string memory fixture = vm.readFile(path);
        vm.createSelectFork(rpc, vm.parseJsonUint(fixture, ".blockNumber"));
        assertEq(block.chainid, 4663);
        assertEq(block.timestamp, vm.parseJsonUint(fixture, ".blockTimestamp"));
        assertProxy(0);
        bytes[] memory reports = vm.parseJsonBytesArray(fixture, ".fullReports");
        bytes[] memory expected = vm.parseJsonBytesArray(fixture, ".verifiedBodies");
        assertGt(reports.length, 0);
        assertEq(reports.length, expected.length);
        bytes[] memory actual = IVerifierProxy(proxy(0)).verifyBulk(reports, bytes(""));
        assertEq(actual.length, expected.length);
        for (uint256 i; i < actual.length; ++i) {
            assertEq(actual[i], expected[i]);
        }
        StaticsExecutionOracle oracle =
            new StaticsExecutionOracle(address(this), proxy(0), uint8(reports.length));
        bytes32 market = vm.parseJsonBytes32(fixture, ".marketId");
        uint256 delay = vm.parseJsonUint(fixture, ".executionDelay");
        uint256 width = vm.parseJsonUint(fixture, ".maxReportWindow");
        uint256 decimals = vm.parseJsonUint(fixture, ".streamDecimals");
        assertLe(reports.length, 255);
        assertLe(delay, type(uint32).max);
        assertLe(width, type(uint32).max);
        assertLe(decimals, 18);
        oracle.registerMarket(
            market,
            IEO.ExecutionMarketConfigInput(
                vm.parseJsonBytes32(fixture, ".streamId"),
                uint32(delay),
                uint32(width),
                uint8(decimals)
            )
        );
        oracle.enableMarket(market);
        oracle.setAuthorizedConsumer(address(this), true);
        address feed = vm.parseJsonAddress(bindings, key(0, "sequencerFeed"));
        oracle.setSequencerConfig(feed, 3600);
        IEO.ExecutionPrice memory got = oracle.verifyExecutionPrice(market, reports);
        DataStreamsV3.Report memory selected =
            DataStreamsV3.decode(vm.parseJsonBytes(fixture, ".selectedBody"));
        assertEq(got.price1e18, uint256(int256(selected.price)) * 10 ** (18 - decimals));
        assertEq(got.streamId, selected.feedId);
        assertEq(got.validFromTimestamp, selected.validFromTimestamp);
        assertEq(got.observationsTimestamp, selected.observationsTimestamp);
        assertEq(got.referenceTimestamp, block.timestamp - delay);
    }

    function testDeployedSequencerHealthRecoveryAndLeaseExpiry() public {
        forkNetwork(0);
        address feed = vm.parseJsonAddress(bindings, key(0, "sequencerFeed"));
        assertEq(feed.codehash, vm.parseJsonBytes32(bindings, key(0, "sequencerCodeHash")));
        (, int256 answer, uint256 startedAt,,) = IAggregatorV3(feed).latestRoundData();
        assertEq(answer, 0);
        ExecutionSequencerGateHarness oracle = new ExecutionSequencerGateHarness(proxy(0));
        oracle.setSequencerConfig(feed, 3600);
        oracle.checkHealth();
        vm.warp(startedAt + 3600);
        vm.expectRevert(
            abi.encodeWithSelector(
                StaticsExecutionOracle.SequencerGracePeriod.selector, startedAt, 3600
            )
        );
        oracle.checkHealth();
        vm.warp(RobinhoodSequencerAvailabilityFeed(feed).healthyUntil() + 1);
        vm.expectRevert(StaticsExecutionOracle.SequencerDown.selector);
        oracle.checkHealth();
    }
}
