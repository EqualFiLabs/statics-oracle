// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Script } from "forge-std/Script.sol";

import { StaticsOracle } from "src/StaticsOracle.sol";
import { IStaticsOracle } from "src/interfaces/IStaticsOracle.sol";

contract ConfigureStaticsOracle is Script {
    uint256 internal constant ROBINHOOD_MAINNET_CHAIN_ID = 4663;
    string internal constant DEFAULT_MANIFEST = "config/robinhood-mainnet.assets.json";

    error WrongChain(uint256 expected, uint256 actual);
    error UnverifiedSequencer();
    error ZeroOracleAddress();
    error UnknownAssetKind(string kind);
    error DeployedStateMismatch(string symbol, string field);
    error RegistryVersionMismatch(uint64 expected, uint64 actual);

    function run() external {
        address oracleAddress = vm.envAddress("STATICS_ORACLE");
        if (oracleAddress == address(0)) revert ZeroOracleAddress();
        string memory manifest = vm.readFile(DEFAULT_MANIFEST);

        vm.startBroadcast();
        configure(StaticsOracle(oracleAddress), manifest);
        vm.stopBroadcast();
        verify(StaticsOracle(oracleAddress), manifest);
    }

    function configure(
        StaticsOracle oracle,
        string memory manifest
    ) public {
        _requireRobinhoodMainnet();
        (address sequencerFeed, uint32 gracePeriod) = _sequencer(manifest);
        oracle.setSequencerConfig(sequencerFeed, gracePeriod);

        uint256 count = vm.parseJsonUint(manifest, ".assetCount");
        for (uint256 i; i < count; ++i) {
            address token = vm.parseJsonAddress(manifest, _key(i, "token"));
            oracle.registerAsset(
                token,
                IStaticsOracle.AssetOracleConfigInput({
                    feed: vm.parseJsonAddress(manifest, _key(i, "feed")),
                    feedDescriptionHash: vm.parseJsonBytes32(
                        manifest, _key(i, "feedDescriptionHash")
                    ),
                    maxAge: uint32(vm.parseJsonUint(manifest, _key(i, "maxAge"))),
                    tokenDecimals: uint8(vm.parseJsonUint(manifest, _key(i, "tokenDecimals"))),
                    feedDecimals: uint8(vm.parseJsonUint(manifest, _key(i, "feedDecimals"))),
                    kind: _kind(vm.parseJsonString(manifest, _key(i, "kind"))),
                    checkOraclePause: vm.parseJsonBool(manifest, _key(i, "checkOraclePause"))
                })
            );
            if (_equal(vm.parseJsonString(manifest, _key(i, "status")), "ENABLED")) {
                oracle.enableAsset(token);
            }
        }
    }

    function verify(
        StaticsOracle oracle,
        string memory manifest
    ) public view {
        _requireRobinhoodMainnet();
        (address sequencerFeed, uint32 gracePeriod) = _sequencer(manifest);
        IStaticsOracle.SequencerConfig memory liveSequencer = oracle.sequencerConfig();
        if (liveSequencer.feed != sequencerFeed) revert DeployedStateMismatch("sequencer", "feed");
        if (liveSequencer.gracePeriod != gracePeriod) {
            revert DeployedStateMismatch("sequencer", "gracePeriod");
        }

        uint256 count = vm.parseJsonUint(manifest, ".assetCount");
        uint64 expectedVersion = 1;
        for (uint256 i; i < count; ++i) {
            string memory symbol = vm.parseJsonString(manifest, _key(i, "symbol"));
            address token = vm.parseJsonAddress(manifest, _key(i, "token"));
            IStaticsOracle.AssetOracleConfig memory live = oracle.assetConfig(token);
            if (live.feed != vm.parseJsonAddress(manifest, _key(i, "feed"))) {
                revert DeployedStateMismatch(symbol, "feed");
            }
            if (live.tokenDecimals != vm.parseJsonUint(manifest, _key(i, "tokenDecimals"))) {
                revert DeployedStateMismatch(symbol, "tokenDecimals");
            }
            if (live.feedDecimals != vm.parseJsonUint(manifest, _key(i, "feedDecimals"))) {
                revert DeployedStateMismatch(symbol, "feedDecimals");
            }
            if (live.maxAge != vm.parseJsonUint(manifest, _key(i, "maxAge"))) {
                revert DeployedStateMismatch(symbol, "maxAge");
            }
            if (live.checkOraclePause != vm.parseJsonBool(manifest, _key(i, "checkOraclePause"))) {
                revert DeployedStateMismatch(symbol, "checkOraclePause");
            }

            bool enabled = _equal(vm.parseJsonString(manifest, _key(i, "status")), "ENABLED");
            IStaticsOracle.AssetStatus expectedStatus =
                enabled ? IStaticsOracle.AssetStatus.ENABLED : IStaticsOracle.AssetStatus.CANDIDATE;
            if (live.status != expectedStatus) revert DeployedStateMismatch(symbol, "status");
            expectedVersion += enabled ? 2 : 1;
        }

        uint64 actualVersion = oracle.registryVersion();
        if (actualVersion != expectedVersion) {
            revert RegistryVersionMismatch(expectedVersion, actualVersion);
        }
    }

    function _sequencer(
        string memory manifest
    ) internal pure returns (address feed, uint32 gracePeriod) {
        if (!vm.parseJsonBool(manifest, ".sequencer.verified")) revert UnverifiedSequencer();
        feed = vm.parseJsonAddress(manifest, ".sequencer.feed");
        gracePeriod = uint32(vm.parseJsonUint(manifest, ".sequencer.gracePeriod"));
    }

    function _requireRobinhoodMainnet() internal view {
        if (block.chainid != ROBINHOOD_MAINNET_CHAIN_ID) {
            revert WrongChain(ROBINHOOD_MAINNET_CHAIN_ID, block.chainid);
        }
    }

    function _key(
        uint256 index,
        string memory field
    ) internal pure returns (string memory) {
        return string.concat(".assets[", vm.toString(index), "].", field);
    }

    function _kind(
        string memory value
    ) internal pure returns (IStaticsOracle.AssetKind) {
        bytes32 hash = keccak256(bytes(value));
        if (hash == keccak256("STOCK")) return IStaticsOracle.AssetKind.STOCK;
        if (hash == keccak256("ETF")) return IStaticsOracle.AssetKind.ETF;
        if (hash == keccak256("CRYPTO")) return IStaticsOracle.AssetKind.CRYPTO;
        if (hash == keccak256("STABLE")) return IStaticsOracle.AssetKind.STABLE;
        revert UnknownAssetKind(value);
    }

    function _equal(
        string memory left,
        string memory right
    ) internal pure returns (bool) {
        return keccak256(bytes(left)) == keccak256(bytes(right));
    }
}
