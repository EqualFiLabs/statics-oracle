// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import { Test } from "forge-std/Test.sol";
import { ConfigureExecutionMarkets } from "script/ConfigureExecutionMarkets.s.sol";
import { DeployStaticsExecutionOracle } from "script/DeployStaticsExecutionOracle.s.sol";
import { StaticsExecutionOracle } from "src/StaticsExecutionOracle.sol";
import { IStaticsExecutionOracle as IEO } from "src/interfaces/IStaticsExecutionOracle.sol";
import { ExecutionVerifierMock } from "test/mocks/ExecutionOracleMocks.sol";
import { OracleFeedTestMock } from "test/mocks/OracleTestMocks.sol";

contract ExecutionDeploymentScriptsTest is Test {
    DeployStaticsExecutionOracle internal deployer;
    ExecutionVerifierMock internal verifier;

    function setUp() public {
        vm.chainId(46630);
        deployer = new DeployStaticsExecutionOracle();
        verifier = new ExecutionVerifierMock();
    }

    function testDeploymentRejectsWrongChainAndRuntime() public {
        vm.expectRevert(DeployStaticsExecutionOracle.WrongChain.selector);
        deployer.deploy(4663, address(this), address(verifier), address(verifier).codehash, 5);
        vm.expectRevert(DeployStaticsExecutionOracle.InvalidVerifierBinding.selector);
        deployer.deploy(46630, address(this), address(verifier), bytes32(uint256(1)), 5);
        StaticsExecutionOracle oracle =
            deployer.deploy(46630, address(this), address(verifier), address(verifier).codehash, 5);
        assertEq(oracle.owner(), address(this));
        assertEq(oracle.verifierProxy(), address(verifier));
    }

    function testCandidateManifestCannotTriggerBroadcast() public {
        vm.expectRevert(DeployStaticsExecutionOracle.UnratifiedParameters.selector);
        deployer.run();
    }

    function testConfigurationPreflightsAllMarketsBeforeMutationAndRequiresFreshOracle() public {
        ConfigureExecutionMarkets configurator = new ConfigureExecutionMarkets();
        StaticsExecutionOracle oracle = deployer.deploy(
            46630, address(configurator), address(verifier), address(verifier).codehash, 5
        );
        OracleFeedTestMock feed = new OracleFeedTestMock(0, "health");
        feed.setRoundData(1, 0, 1, 1, 1);
        ConfigureExecutionMarkets.Configuration memory cfg;
        cfg.chainId = 46630;
        cfg.expectedOwner = address(configurator);
        cfg.verifierProxy = address(verifier);
        cfg.verifierCodeHash = address(verifier).codehash;
        cfg.bundleBound = 5;
        cfg.sequencerFeed = address(feed);
        cfg.sequencerCodeHash = address(feed).codehash;
        cfg.gracePeriod = 10;
        cfg.consumers = new address[](1);
        cfg.consumers[0] = address(this);
        cfg.markets = new ConfigureExecutionMarkets.Market[](2);
        cfg.markets[0] = ConfigureExecutionMarkets.Market(
            keccak256("BTC_USD"),
            IEO.ExecutionMarketConfigInput(bytes32(uint256(3) << 240), 10, 30, 18),
            IEO.MarketStatus.ENABLED
        );
        cfg.markets[1] = cfg.markets[0];
        vm.expectRevert(ConfigureExecutionMarkets.InvalidConfiguration.selector);
        configurator.configure(oracle, cfg);
        assertEq(oracle.registryVersion(), 0);
        cfg.markets[1] = ConfigureExecutionMarkets.Market(
            keccak256("ETH_USD"),
            IEO.ExecutionMarketConfigInput(bytes32(uint256(3) << 240), 10, 30, 18),
            IEO.MarketStatus.CANDIDATE
        );
        configurator.configure(oracle, cfg);
        assertEq(oracle.registryVersion(), 5);
        assertEq(
            uint8(oracle.marketConfig(keccak256("BTC_USD")).status), uint8(IEO.MarketStatus.ENABLED)
        );
        vm.expectRevert(ConfigureExecutionMarkets.BindingMismatch.selector);
        configurator.configure(oracle, cfg);
    }

    function testManifestArrayParsingAndCandidateRefusal() public {
        ConfigureExecutionMarkets configurator = new ConfigureExecutionMarkets();
        string memory candidate = vm.readFile("config/robinhood-mainnet.streams.json");
        vm.expectRevert(ConfigureExecutionMarkets.InvalidConfiguration.selector);
        configurator.load(candidate, address(this), address(this));
        string memory manifest = string.concat(
            '{"schemaVersion":1,"chainId":46630,"productionParametersRatified":true,"verifierProxy":"',
            vm.toString(address(verifier)),
            '","verifierCodeHash":"',
            vm.toString(address(verifier).codehash),
            '","maxReportBundleSize":5,"sequencer":{"feed":"',
            vm.toString(address(verifier)),
            '","codeHash":"',
            vm.toString(address(verifier).codehash),
            '","gracePeriod":10},"markets":[{"label":"BTC_USD","marketId":"',
            vm.toString(keccak256("BTC_USD")),
            '","streamId":"',
            vm.toString(bytes32(uint256(3) << 240)),
            '","reportSchema":3,"streamDecimals":18,"status":"CANDIDATE","executionDelay":10,"maxReportWindow":30,"verification":{"authenticatedOnRobinhood":true,"directoryStatus":"testing"}}]}'
        );
        ConfigureExecutionMarkets.Configuration memory parsed =
            configurator.load(manifest, address(this), address(this));
        assertEq(parsed.markets.length, 1);
        assertEq(parsed.markets[0].id, keccak256("BTC_USD"));
        assertEq(uint8(parsed.markets[0].status), uint8(IEO.MarketStatus.CANDIDATE));
    }
}
