// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";

import { StaticsOracle } from "src/StaticsOracle.sol";
import { IStaticsOracle } from "src/interfaces/IStaticsOracle.sol";
import { OracleFeedTestMock, OracleTokenTestMock } from "test/mocks/OracleTestMocks.sol";

contract StaticsOracleConfigTest is Test {
    string internal constant DESCRIPTION = "CONFIG / USD";

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
    }

    function test_ValidRegistrationStoresCandidateAndRejectsDuplicate() external {
        oracle.registerAsset(address(token), _input());
        IStaticsOracle.AssetOracleConfig memory config = oracle.assetConfig(address(token));
        assertEq(config.feed, address(feed));
        assertEq(uint8(config.status), uint8(IStaticsOracle.AssetStatus.CANDIDATE));
        assertEq(oracle.registryVersion(), 2);

        vm.expectRevert(
            abi.encodeWithSelector(StaticsOracle.AssetAlreadyRegistered.selector, address(token))
        );
        oracle.registerAsset(address(token), _input());
        assertEq(oracle.registryVersion(), 2);
    }

    function test_RejectsZeroAndNoCodeAddresses() external {
        vm.expectRevert(StaticsOracle.ZeroAddress.selector);
        oracle.registerAsset(address(0), _input());

        IStaticsOracle.AssetOracleConfigInput memory input = _input();
        input.feed = address(0);
        vm.expectRevert(StaticsOracle.ZeroAddress.selector);
        oracle.registerAsset(address(token), input);

        address noCodeToken = makeAddr("noCodeToken");
        vm.expectRevert(abi.encodeWithSelector(StaticsOracle.NoContractCode.selector, noCodeToken));
        oracle.registerAsset(noCodeToken, _input());

        address noCodeFeed = makeAddr("noCodeFeed");
        input = _input();
        input.feed = noCodeFeed;
        vm.expectRevert(abi.encodeWithSelector(StaticsOracle.NoContractCode.selector, noCodeFeed));
        oracle.registerAsset(address(token), input);
    }

    function test_RejectsInvalidBoundsKindAndMaxAge() external {
        IStaticsOracle.AssetOracleConfigInput memory input = _input();
        input.maxAge = 0;
        vm.expectRevert(StaticsOracle.InvalidMaxAge.selector);
        oracle.registerAsset(address(token), input);

        input = _input();
        input.kind = IStaticsOracle.AssetKind.NONE;
        vm.expectRevert(
            abi.encodeWithSelector(
                StaticsOracle.InvalidAssetKind.selector, IStaticsOracle.AssetKind.NONE
            )
        );
        oracle.registerAsset(address(token), input);

        input = _input();
        input.tokenDecimals = 19;
        vm.expectRevert(abi.encodeWithSelector(StaticsOracle.UnsupportedTokenDecimals.selector, 19));
        oracle.registerAsset(address(token), input);

        input = _input();
        input.feedDecimals = 19;
        vm.expectRevert(abi.encodeWithSelector(StaticsOracle.UnsupportedFeedDecimals.selector, 19));
        oracle.registerAsset(address(token), input);
    }

    function test_RejectsMetadataMismatchAndCallFailures() external {
        IStaticsOracle.AssetOracleConfigInput memory input = _input();
        input.tokenDecimals = 6;
        vm.expectRevert(
            abi.encodeWithSelector(
                StaticsOracle.TokenDecimalsMismatch.selector, address(token), 6, 18
            )
        );
        oracle.registerAsset(address(token), input);

        input = _input();
        input.feedDecimals = 18;
        vm.expectRevert(
            abi.encodeWithSelector(
                StaticsOracle.FeedDecimalsMismatch.selector, address(feed), 18, 8
            )
        );
        oracle.registerAsset(address(token), input);

        input = _input();
        bytes32 wrongHash = keccak256("WRONG");
        input.feedDescriptionHash = wrongHash;
        vm.expectRevert(
            abi.encodeWithSelector(
                StaticsOracle.FeedDescriptionMismatch.selector,
                address(feed),
                wrongHash,
                keccak256(bytes(DESCRIPTION))
            )
        );
        oracle.registerAsset(address(token), input);

        token.setDecimalsCallFails(true);
        vm.expectRevert(
            abi.encodeWithSelector(StaticsOracle.TokenDecimalsCallFailed.selector, address(token))
        );
        oracle.registerAsset(address(token), _input());
        token.setDecimalsCallFails(false);

        feed.setDecimalsCallFails(true);
        vm.expectRevert(
            abi.encodeWithSelector(StaticsOracle.FeedDecimalsCallFailed.selector, address(feed))
        );
        oracle.registerAsset(address(token), _input());
        feed.setDecimalsCallFails(false);

        feed.setDescriptionCallFails(true);
        vm.expectRevert(
            abi.encodeWithSelector(StaticsOracle.FeedDescriptionCallFailed.selector, address(feed))
        );
        oracle.registerAsset(address(token), _input());
    }

    function test_RejectsInvalidStockPauseConfigurationAndCallFailure() external {
        IStaticsOracle.AssetOracleConfigInput memory input = _input();
        input.kind = IStaticsOracle.AssetKind.STOCK;
        vm.expectRevert(
            abi.encodeWithSelector(StaticsOracle.StockPauseCheckRequired.selector, address(token))
        );
        oracle.registerAsset(address(token), input);

        input.checkOraclePause = true;
        token.setPauseCallFails(true);
        vm.expectRevert(
            abi.encodeWithSelector(StaticsOracle.StockPauseCheckFailed.selector, address(token))
        );
        oracle.registerAsset(address(token), input);
    }

    function test_LifecycleAndVersioningAreExplicitAndExact() external {
        assertEq(oracle.registryVersion(), 1);
        oracle.registerAsset(address(token), _input());
        assertEq(oracle.registryVersion(), 2);

        vm.expectRevert(
            abi.encodeWithSelector(
                StaticsOracle.AssetMustBeDisabled.selector,
                address(token),
                IStaticsOracle.AssetStatus.CANDIDATE
            )
        );
        oracle.updateAsset(address(token), _input());
        assertEq(oracle.registryVersion(), 2);

        oracle.enableAsset(address(token));
        assertEq(oracle.registryVersion(), 3);
        vm.expectRevert(
            abi.encodeWithSelector(
                StaticsOracle.InvalidStatusTransition.selector,
                address(token),
                IStaticsOracle.AssetStatus.ENABLED,
                IStaticsOracle.AssetStatus.ENABLED
            )
        );
        oracle.enableAsset(address(token));
        assertEq(oracle.registryVersion(), 3);

        vm.expectRevert(
            abi.encodeWithSelector(
                StaticsOracle.AssetMustBeDisabled.selector,
                address(token),
                IStaticsOracle.AssetStatus.ENABLED
            )
        );
        oracle.updateAsset(address(token), _input());
        assertEq(oracle.registryVersion(), 3);

        oracle.disableAsset(address(token));
        assertEq(oracle.registryVersion(), 4);
        oracle.updateAsset(address(token), _input());
        assertEq(oracle.registryVersion(), 5);
        assertEq(
            uint8(oracle.assetConfig(address(token)).status),
            uint8(IStaticsOracle.AssetStatus.CANDIDATE)
        );
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
