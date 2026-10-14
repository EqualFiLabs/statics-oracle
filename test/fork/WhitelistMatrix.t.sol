// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { StaticsOracle } from "src/StaticsOracle.sol";
import { IStaticsOracle } from "src/interfaces/IStaticsOracle.sol";
import { RobinhoodForkBase } from "test/fork/RobinhoodForkBase.sol";

contract WhitelistMatrixForkTest is RobinhoodForkBase {
    function setUp() external {
        _setUpRobinhoodFork();
    }

    function test_FullManifestRegistersExactIdentityBeforeEnablement() external {
        StaticsOracle oracle = new StaticsOracle(address(this));
        uint256 candidateTargets;

        for (uint256 i; i < assetCount; ++i) {
            address token = _address(i, "token");
            address feed = _address(i, "feed");
            IStaticsOracle.AssetKind kind = _kind(_string(i, "kind"));
            oracle.registerAsset(
                token,
                IStaticsOracle.AssetOracleConfigInput({
                    feed: feed,
                    feedDescriptionHash: vm.parseJsonBytes32(
                        manifestJson, _key(i, "feedDescriptionHash")
                    ),
                    maxAge: uint32(_uint(i, "maxAge")),
                    tokenDecimals: uint8(_uint(i, "tokenDecimals")),
                    feedDecimals: uint8(_uint(i, "feedDecimals")),
                    kind: kind,
                    checkOraclePause: _bool(i, "checkOraclePause")
                })
            );

            IStaticsOracle.AssetOracleConfig memory config = oracle.assetConfig(token);
            assertEq(config.feed, feed);
            assertEq(uint8(config.status), uint8(IStaticsOracle.AssetStatus.CANDIDATE));
            assertEq(
                config.feedDescriptionHash,
                vm.parseJsonBytes32(manifestJson, _key(i, "feedDescriptionHash"))
            );
            if (keccak256(bytes(_string(i, "status"))) == keccak256("CANDIDATE")) {
                ++candidateTargets;
            }
        }

        assertEq(oracle.registryVersion(), assetCount);
        assertEq(candidateTargets, 0);
    }

    function test_BridgedTokensMatchRecordedOriginAndCanonicalGateway() external view {
        address gateway = 0x1E324B9316138CA9a73F960213621AD1aaf01B89;
        uint256 bridgedCount;
        for (uint256 i; i < assetCount; ++i) {
            if (!_isBridged(_string(i, "symbol"))) continue;
            ++bridgedCount;
            address token = _address(i, "token");
            address origin = vm.parseJsonAddress(manifestJson, _key(i, "l1Origin"));
            (bool originOk, bytes memory originData) =
                token.staticcall(abi.encodeWithSignature("l1Address()"));
            assertTrue(originOk);
            assertEq(abi.decode(originData, (address)), origin);
            (bool gatewayOk, bytes memory gatewayData) = gateway.staticcall(
                abi.encodeWithSignature("calculateL2TokenAddress(address)", origin)
            );
            assertTrue(gatewayOk);
            assertEq(abi.decode(gatewayData, (address)), token);
        }
        assertEq(bridgedCount, 7);
    }

    function _isBridged(
        string memory symbol
    ) internal pure returns (bool) {
        bytes32 hash = keccak256(bytes(symbol));
        return hash == keccak256("EURC") || hash == keccak256("USDC") || hash == keccak256("USDS")
            || hash == keccak256("USDT") || hash == keccak256("WBTC") || hash == keccak256("cbBTC")
            || hash == keccak256("wstETH");
    }

    function _kind(
        string memory value
    ) internal pure returns (IStaticsOracle.AssetKind) {
        bytes32 hash = keccak256(bytes(value));
        if (hash == keccak256("STOCK")) return IStaticsOracle.AssetKind.STOCK;
        if (hash == keccak256("ETF")) return IStaticsOracle.AssetKind.ETF;
        if (hash == keccak256("CRYPTO")) return IStaticsOracle.AssetKind.CRYPTO;
        if (hash == keccak256("STABLE")) return IStaticsOracle.AssetKind.STABLE;
        revert("unknown asset kind");
    }
}
