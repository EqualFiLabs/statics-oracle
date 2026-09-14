// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { StaticsOracle } from "src/StaticsOracle.sol";
import { IStaticsOracle } from "src/interfaces/IStaticsOracle.sol";
import { RobinhoodForkBase } from "test/fork/RobinhoodForkBase.sol";

contract WhitelistMatrixForkTest is RobinhoodForkBase {
    function setUp() external {
        _setUpRobinhoodFork();
    }

    function test_FullManifestRegistersByExactIdentityAsCandidates() external {
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
        assertEq(candidateTargets, 6);
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
