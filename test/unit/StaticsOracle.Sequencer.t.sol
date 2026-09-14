// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";

import { StaticsOracle } from "src/StaticsOracle.sol";
import { IStaticsOracle } from "src/interfaces/IStaticsOracle.sol";
import { OracleFeedTestMock, OracleTokenTestMock } from "test/mocks/OracleTestMocks.sol";

contract StaticsOracleSequencerTest is Test {
    string internal constant DESCRIPTION = "SEQUENCED / USD";

    StaticsOracle internal oracle;
    OracleTokenTestMock internal token;
    OracleFeedTestMock internal feed;
    OracleFeedTestMock internal sequencer;

    function setUp() external {
        vm.warp(10 days);
        oracle = new StaticsOracle(address(this));
        token = new OracleTokenTestMock(18);
        feed = new OracleFeedTestMock(8, DESCRIPTION);
        sequencer = new OracleFeedTestMock(0, "Sequencer");
        feed.setRound(100e8, block.timestamp);
        sequencer.setRoundData(1, 0, block.timestamp - 2 hours, block.timestamp, 1);
        oracle.setSequencerConfig(address(sequencer), 1 hours);
        oracle.registerAsset(address(token), _input());
        oracle.enableAsset(address(token));
    }

    function test_MissingConfigurationFailsEnablementAndStrictBasketPricing() external {
        StaticsOracle missing = new StaticsOracle(address(this));
        OracleTokenTestMock candidate = new OracleTokenTestMock(18);
        missing.registerAsset(address(candidate), _input());

        vm.expectRevert(
            abi.encodeWithSelector(
                StaticsOracle.AssetEnablementFailed.selector,
                address(candidate),
                IStaticsOracle.OracleStatus.SEQUENCER_NOT_CONFIGURED
            )
        );
        missing.enableAsset(address(candidate));

        address[] memory assets = new address[](1);
        assets[0] = address(candidate);
        uint256[] memory amounts = new uint256[](1);
        vm.expectRevert(StaticsOracle.SequencerNotConfigured.selector);
        missing.basketNav(assets, amounts);
    }

    function test_HealthySequencerAllowsStrictPrice() external view {
        assertEq(
            uint8(oracle.peekPrice(address(token)).status), uint8(IStaticsOracle.OracleStatus.VALID)
        );
        assertEq(oracle.priceUsd(address(token)), 100e18);
    }

    function test_DownSequencerGatesDiagnosticAndStrictPrice() external {
        sequencer.setRoundData(2, 1, block.timestamp, block.timestamp, 2);
        assertEq(
            uint8(oracle.peekPrice(address(token)).status),
            uint8(IStaticsOracle.OracleStatus.SEQUENCER_DOWN)
        );
        vm.expectRevert(StaticsOracle.SequencerDown.selector);
        oracle.priceUsd(address(token));
    }

    function test_RecoveryGraceIncludesBoundaryAndExpiresAfterward() external {
        uint256 recoveredAt = block.timestamp;
        sequencer.setRoundData(2, 0, recoveredAt, recoveredAt, 2);

        vm.warp(recoveredAt + 1 hours);
        assertEq(
            uint8(oracle.peekPrice(address(token)).status),
            uint8(IStaticsOracle.OracleStatus.SEQUENCER_GRACE_PERIOD)
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                StaticsOracle.SequencerGracePeriod.selector, recoveredAt, 1 hours
            )
        );
        oracle.priceUsd(address(token));

        vm.warp(recoveredAt + 1 hours + 1);
        feed.setRound(100e8, block.timestamp);
        assertEq(oracle.priceUsd(address(token)), 100e18);
    }

    function test_MalformedSequencerResponsesFailClosedAsUnavailable() external {
        sequencer.setLatestRoundCallFails(true);
        _assertDown();

        sequencer.setLatestRoundCallFails(false);
        sequencer.setRoundData(2, 0, 0, block.timestamp, 2);
        _assertDown();

        sequencer.setRoundData(3, 0, block.timestamp + 1, block.timestamp, 3);
        _assertDown();
    }

    function test_InvalidSequencerConfigurationDoesNotMutateState() external {
        uint64 versionBefore = oracle.registryVersion();
        address noCode = makeAddr("noCodeSequencer");
        vm.expectRevert(abi.encodeWithSelector(StaticsOracle.NoContractCode.selector, noCode));
        oracle.setSequencerConfig(noCode, 1 hours);
        assertEq(oracle.registryVersion(), versionBefore);

        OracleFeedTestMock broken = new OracleFeedTestMock(0, "Broken");
        broken.setLatestRoundCallFails(true);
        vm.expectRevert(
            abi.encodeWithSelector(StaticsOracle.SequencerFeedCallFailed.selector, address(broken))
        );
        oracle.setSequencerConfig(address(broken), 1 hours);
        assertEq(oracle.registryVersion(), versionBefore);
        assertEq(oracle.sequencerConfig().feed, address(sequencer));
    }

    function _assertDown() internal {
        assertEq(
            uint8(oracle.peekPrice(address(token)).status),
            uint8(IStaticsOracle.OracleStatus.SEQUENCER_DOWN)
        );
        vm.expectRevert(StaticsOracle.SequencerDown.selector);
        oracle.priceUsd(address(token));
    }

    function _input() internal view returns (IStaticsOracle.AssetOracleConfigInput memory) {
        return IStaticsOracle.AssetOracleConfigInput({
            feed: address(feed),
            feedDescriptionHash: keccak256(bytes(DESCRIPTION)),
            maxAge: 1 hours,
            tokenDecimals: 18,
            feedDecimals: 8,
            kind: IStaticsOracle.AssetKind.CRYPTO,
            checkOraclePause: false
        });
    }
}
