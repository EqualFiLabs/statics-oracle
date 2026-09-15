// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";

import { StaticsOracle } from "src/StaticsOracle.sol";
import { IStaticsOracle } from "src/interfaces/IStaticsOracle.sol";
import { OracleFeedTestMock, OracleTokenTestMock } from "test/mocks/OracleTestMocks.sol";

contract NavPropertiesTest is Test {
    StaticsOracle internal oracle;
    OracleTokenTestMock internal tokenA;
    OracleTokenTestMock internal tokenB;

    function setUp() external {
        vm.warp(10 days);
        oracle = new StaticsOracle(address(this));
        OracleFeedTestMock sequencer = new OracleFeedTestMock(0, "Sequencer");
        sequencer.setRoundData(1, 0, block.timestamp - 2 hours, block.timestamp, 1);
        oracle.setSequencerConfig(address(sequencer), 1 hours);

        tokenA = new OracleTokenTestMock(18);
        tokenB = new OracleTokenTestMock(6);
        _register(tokenA, 18, 8, "A / USD", 321e8);
        _register(tokenB, 6, 18, "B / USD", 7e18);
    }

    function testFuzz_NavIsExactlyAdditive(
        uint96 amountA,
        uint64 amountB
    ) external view {
        address[] memory assets = new address[](2);
        assets[0] = address(tokenA);
        assets[1] = address(tokenB);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amountA;
        amounts[1] = amountB;

        assertEq(
            oracle.basketNav(assets, amounts),
            oracle.valueUsd(address(tokenA), amountA) + oracle.valueUsd(address(tokenB), amountB)
        );
    }

    function _register(
        OracleTokenTestMock token,
        uint8 tokenDecimals,
        uint8 feedDecimals,
        string memory description,
        int256 answer
    ) internal {
        OracleFeedTestMock feed = new OracleFeedTestMock(feedDecimals, description);
        feed.setRound(answer, block.timestamp);
        oracle.registerAsset(
            address(token),
            IStaticsOracle.AssetOracleConfigInput({
                feed: address(feed),
                feedDescriptionHash: keccak256(bytes(description)),
                maxAge: 1 hours,
                tokenDecimals: tokenDecimals,
                feedDecimals: feedDecimals,
                kind: IStaticsOracle.AssetKind.CRYPTO,
                checkOraclePause: false
            })
        );
        oracle.enableAsset(address(token));
    }
}
