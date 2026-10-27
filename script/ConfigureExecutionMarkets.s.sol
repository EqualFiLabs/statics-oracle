// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { Script } from "forge-std/Script.sol";
import { StaticsExecutionOracle } from "src/StaticsExecutionOracle.sol";
import { IStaticsExecutionOracle as IEO } from "src/interfaces/IStaticsExecutionOracle.sol";

contract ConfigureExecutionMarkets is Script {
    using SafeCast for uint256;
    error InvalidConfiguration();
    error BindingMismatch();

    struct Market {
        bytes32 id;
        IEO.ExecutionMarketConfigInput input;
        IEO.MarketStatus status;
    }

    struct Configuration {
        uint256 chainId;
        address expectedOwner;
        address verifierProxy;
        bytes32 verifierCodeHash;
        uint8 bundleBound;
        address sequencerFeed;
        bytes32 sequencerCodeHash;
        uint32 gracePeriod;
        address[] consumers;
        Market[] markets;
    }

    function run() external {
        string memory manifest = vm.readFile(
            vm.envOr("EXECUTION_STREAM_MANIFEST", string("config/robinhood-mainnet.streams.json"))
        );
        Configuration memory config =
            load(manifest, vm.envAddress("INITIAL_OWNER"), vm.envAddress("EXECUTION_CONSUMER"));
        StaticsExecutionOracle oracle = StaticsExecutionOracle(vm.envAddress("EXECUTION_ORACLE"));
        preflight(oracle, config);
        vm.startBroadcast();
        configure(oracle, config);
        vm.stopBroadcast();
    }

    function load(
        string memory manifest,
        address expectedOwner,
        address consumer
    ) public view returns (Configuration memory cfg) {
        if (
            vm.parseJsonUint(manifest, ".schemaVersion") != 1
                || !vm.parseJsonBool(manifest, ".productionParametersRatified")
        ) revert InvalidConfiguration();
        cfg.chainId = vm.parseJsonUint(manifest, ".chainId");
        cfg.expectedOwner = expectedOwner;
        cfg.verifierProxy = vm.parseJsonAddress(manifest, ".verifierProxy");
        cfg.verifierCodeHash = vm.parseJsonBytes32(manifest, ".verifierCodeHash");
        cfg.bundleBound = vm.parseJsonUint(manifest, ".maxReportBundleSize").toUint8();
        cfg.sequencerFeed = vm.parseJsonAddress(manifest, ".sequencer.feed");
        cfg.sequencerCodeHash = vm.parseJsonBytes32(manifest, ".sequencer.codeHash");
        cfg.gracePeriod = vm.parseJsonUint(manifest, ".sequencer.gracePeriod").toUint32();
        cfg.consumers = new address[](1);
        cfg.consumers[0] = consumer;
        uint256 count;
        while (vm.keyExistsJson(manifest, string.concat(".markets[", vm.toString(count), "]"))) {
            ++count;
            if (count > 256) revert InvalidConfiguration();
        }
        cfg.markets = new Market[](count);
        for (uint256 i; i < count; ++i) {
            string memory base = string.concat(".markets[", vm.toString(i), "].");
            if (
                vm.parseJsonUint(manifest, string.concat(base, "reportSchema")) != 3
                    || !vm.parseJsonBool(
                        manifest, string.concat(base, "verification.authenticatedOnRobinhood")
                    )
            ) revert InvalidConfiguration();
            if (
                cfg.chainId == 4663
                    && keccak256(
                            bytes(
                                vm.parseJsonString(
                                    manifest, string.concat(base, "verification.directoryStatus")
                                )
                            )
                        ) != keccak256("live")
            ) revert InvalidConfiguration();
            bytes32 status =
                keccak256(bytes(vm.parseJsonString(manifest, string.concat(base, "status"))));
            IEO.MarketStatus target;
            if (status == keccak256("CANDIDATE")) target = IEO.MarketStatus.CANDIDATE;
            else if (status == keccak256("ENABLED")) target = IEO.MarketStatus.ENABLED;
            else if (status == keccak256("DISABLED")) target = IEO.MarketStatus.DISABLED;
            else revert InvalidConfiguration();
            cfg.markets[i] = Market(
                vm.parseJsonBytes32(manifest, string.concat(base, "marketId")),
                IEO.ExecutionMarketConfigInput(
                    vm.parseJsonBytes32(manifest, string.concat(base, "streamId")),
                    vm.parseJsonUint(manifest, string.concat(base, "executionDelay")).toUint32(),
                    vm.parseJsonUint(manifest, string.concat(base, "maxReportWindow")).toUint32(),
                    vm.parseJsonUint(manifest, string.concat(base, "streamDecimals")).toUint8()
                ),
                target
            );
        }
    }

    function preflight(
        StaticsExecutionOracle oracle,
        Configuration memory cfg
    ) public view {
        if (
            (cfg.chainId != 4663 && cfg.chainId != 46630) || cfg.chainId != block.chainid
                || address(oracle).code.length == 0
        ) revert BindingMismatch();
        if (
            cfg.expectedOwner == address(0) || oracle.owner() != cfg.expectedOwner
                || oracle.registryVersion() != 0
        ) revert BindingMismatch();
        if (
            oracle.verifierProxy() != cfg.verifierProxy || cfg.verifierProxy.code.length == 0
                || cfg.verifierProxy.codehash != cfg.verifierCodeHash
                || oracle.maxReportBundleSize() != cfg.bundleBound
        ) revert BindingMismatch();
        if (
            cfg.sequencerFeed.code.length == 0
                || cfg.sequencerFeed.codehash != cfg.sequencerCodeHash || cfg.consumers.length == 0
                || cfg.markets.length == 0
        ) revert InvalidConfiguration();
        for (uint256 i; i < cfg.consumers.length; ++i) {
            if (cfg.consumers[i].code.length == 0) revert InvalidConfiguration();
        }
        for (uint256 i; i < cfg.markets.length; ++i) {
            Market memory m = cfg.markets[i];
            if (
                m.id == bytes32(0) || uint16(bytes2(m.input.streamId)) != 3
                    || m.input.executionDelay == 0 || m.input.maxReportWindow == 0
                    || m.input.streamDecimals > 18 || m.status == IEO.MarketStatus.UNSET
            ) revert InvalidConfiguration();
            for (uint256 j; j < i; ++j) {
                if (cfg.markets[j].id == m.id) revert InvalidConfiguration();
            }
        }
    }

    /// @notice Initial configuration only. Existing registries require an explicit migration.
    function configure(
        StaticsExecutionOracle oracle,
        Configuration memory cfg
    ) public {
        preflight(oracle, cfg);
        oracle.setSequencerConfig(cfg.sequencerFeed, cfg.gracePeriod);
        for (uint256 i; i < cfg.consumers.length; ++i) {
            oracle.setAuthorizedConsumer(cfg.consumers[i], true);
        }
        for (uint256 i; i < cfg.markets.length; ++i) {
            Market memory m = cfg.markets[i];
            oracle.registerMarket(m.id, m.input);
            if (m.status == IEO.MarketStatus.ENABLED) oracle.enableMarket(m.id);
            else if (m.status == IEO.MarketStatus.DISABLED) oracle.disableMarket(m.id);
        }
    }
}
