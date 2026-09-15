// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";

import { StaticsOracle } from "src/StaticsOracle.sol";
import { IStaticsOracle } from "src/interfaces/IStaticsOracle.sol";
import { OracleFeedTestMock, OracleTokenTestMock } from "test/mocks/OracleTestMocks.sol";

contract LookalikeWrapperMock {
    function symbol() external pure returns (string memory) {
        return "WBTC";
    }

    function name() external pure returns (string memory) {
        return "Wrapped Bitcoin";
    }

    function decimals() external pure returns (uint8) {
        return 8;
    }
}

contract AddressIsolationFuzzTest is Test {
    StaticsOracle internal oracle;
    OracleTokenTestMock internal approved;
    OracleFeedTestMock internal feed;
    OracleFeedTestMock internal sequencer;
    LookalikeWrapperMock internal template;

    function setUp() external {
        vm.warp(10 days);
        oracle = new StaticsOracle(address(this));
        approved = new OracleTokenTestMock(8);
        feed = new OracleFeedTestMock(8, "WBTC / USD");
        template = new LookalikeWrapperMock();
        sequencer = new OracleFeedTestMock(0, "Sequencer");
        feed.setRound(100_000e8, block.timestamp);
        sequencer.setRoundData(1, 0, block.timestamp - 2 hours, block.timestamp, 1);
        oracle.setSequencerConfig(address(sequencer), 1 hours);
        oracle.registerAsset(
            address(approved),
            IStaticsOracle.AssetOracleConfigInput({
                feed: address(feed),
                feedDescriptionHash: keccak256("WBTC / USD"),
                maxAge: 1 hours,
                tokenDecimals: 8,
                feedDecimals: 8,
                kind: IStaticsOracle.AssetKind.CRYPTO,
                checkOraclePause: false
            })
        );
        oracle.enableAsset(address(approved));
    }

    function testFuzz_LookalikeAndEquivalentWrappersCannotInheritFeed(
        address lookalike
    ) external {
        vm.assume(uint160(lookalike) > 0xffff);
        vm.assume(lookalike != address(this));
        vm.assume(lookalike != address(vm));
        vm.assume(lookalike != address(approved));
        vm.assume(lookalike != address(oracle));
        vm.assume(lookalike != address(feed));
        vm.assume(lookalike != address(sequencer));
        vm.assume(lookalike != address(template));
        vm.etch(lookalike, address(template).code);

        assertEq(LookalikeWrapperMock(lookalike).symbol(), "WBTC");
        assertEq(
            uint8(oracle.peekPrice(lookalike).status),
            uint8(IStaticsOracle.OracleStatus.UNSUPPORTED)
        );
        vm.expectRevert(abi.encodeWithSelector(StaticsOracle.UnsupportedAsset.selector, lookalike));
        oracle.priceUsd(lookalike);
        assertEq(oracle.priceUsd(address(approved)), 100_000e18);
    }
}
