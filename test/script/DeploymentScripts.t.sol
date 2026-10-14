// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { Test } from "forge-std/Test.sol";

import { ConfigureStaticsOracle } from "script/ConfigureStaticsOracle.s.sol";
import {
    DeployRobinhoodSequencerAvailabilityFeed
} from "script/DeployRobinhoodSequencerAvailabilityFeed.s.sol";
import {
    DeployRobinhoodSequencerReporterL1
} from "script/DeployRobinhoodSequencerReporterL1.s.sol";
import { DeployStaticsOracle } from "script/DeployStaticsOracle.s.sol";
import {
    InitializeRobinhoodSequencerSignal
} from "script/InitializeRobinhoodSequencerSignal.s.sol";
import { RobinhoodSequencerAvailabilityFeed } from "src/RobinhoodSequencerAvailabilityFeed.sol";
import { RobinhoodSequencerReporterL1 } from "src/RobinhoodSequencerReporterL1.sol";
import { StaticsOracle } from "src/StaticsOracle.sol";
import { IArbitrumDelayedInbox } from "src/interfaces/IArbitrumDelayedInbox.sol";
import { IStaticsOracle } from "src/interfaces/IStaticsOracle.sol";
import { OracleFeedTestMock, OracleTokenTestMock } from "test/mocks/OracleTestMocks.sol";

contract DeploymentScriptsTest is Test {
    DeployStaticsOracle internal deployer;
    DeployRobinhoodSequencerAvailabilityFeed internal sequencerDeployer;
    DeployRobinhoodSequencerReporterL1 internal reporterDeployer;
    InitializeRobinhoodSequencerSignal internal sequencerInitializer;
    ConfigureStaticsOracle internal configurator;

    function setUp() external {
        deployer = new DeployStaticsOracle();
        sequencerDeployer = new DeployRobinhoodSequencerAvailabilityFeed();
        reporterDeployer = new DeployRobinhoodSequencerReporterL1();
        sequencerInitializer = new InitializeRobinhoodSequencerSignal();
        configurator = new ConfigureStaticsOracle();
    }

    function test_SequencerInitializationFundsTicketAndReserve() external {
        vm.chainId(11_155_111);
        address[] memory observers = _observers();
        RobinhoodSequencerReporterL1 reporter = reporterDeployer.deploy(
            address(sequencerInitializer), observers, 2, address(this), 200_000, 400_000, 1
        );
        uint256 submissionFee = 100;
        vm.mockCall(
            reporter.SEPOLIA_DELAYED_INBOX(),
            abi.encodeWithSelector(IArbitrumDelayedInbox.calculateRetryableSubmissionFee.selector),
            abi.encode(submissionFee)
        );
        vm.mockCall(
            reporter.SEPOLIA_DELAYED_INBOX(),
            abi.encodeWithSelector(
                IArbitrumDelayedInbox.createRetryableTicketNoRefundAliasRewrite.selector
            ),
            abi.encode(uint256(77))
        );

        uint256 required = sequencerInitializer.requiredPreInitializationBalance(reporter, 4);
        vm.deal(address(sequencerInitializer), required);
        uint256 ticketId = sequencerInitializer.fundAndInitialize(
            reporter, address(0xFEE1), 46_630, required, 4
        );

        assertEq(ticketId, 77);
        assertEq(reporter.l2Feed(), address(0xFEE1));
        assertEq(
            address(reporter).balance,
            4 * reporter.quoteConfigurationRetryable(),
            "four maximum retryable quotes remain after initialization"
        );
    }

    function test_SequencerInitializationRejectsUnderfundingAndWrongChildChain() external {
        vm.chainId(11_155_111);
        RobinhoodSequencerReporterL1 reporter = reporterDeployer.deploy(
            address(sequencerInitializer), _observers(), 2, address(this), 200_000, 400_000, 1
        );
        vm.mockCall(
            reporter.SEPOLIA_DELAYED_INBOX(),
            abi.encodeWithSelector(IArbitrumDelayedInbox.calculateRetryableSubmissionFee.selector),
            abi.encode(uint256(100))
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                InitializeRobinhoodSequencerSignal.UnexpectedChildChain.selector, 4_663, 46_630
            )
        );
        sequencerInitializer.fundAndInitialize(reporter, address(0xFEE1), 4_663, 0, 4);

        uint256 required = sequencerInitializer.requiredPreInitializationBalance(reporter, 4);
        vm.expectRevert(
            abi.encodeWithSelector(
                InitializeRobinhoodSequencerSignal.InsufficientReporterFunding.selector,
                required - 1,
                required
            )
        );
        sequencerInitializer.fundAndInitialize(reporter, address(0xFEE1), 46_630, required - 1, 4);
    }

    function test_SequencerInitializationValidatesReviewedReporterConfiguration() external {
        vm.chainId(11_155_111);
        address[] memory observers = _observers();
        RobinhoodSequencerReporterL1 reporter = reporterDeployer.deploy(
            address(sequencerInitializer), observers, 2, address(this), 200_000, 400_000, 1
        );
        sequencerInitializer.validateReporterConfiguration(
            reporter,
            address(sequencerInitializer),
            observers,
            2,
            address(this),
            200_000,
            400_000,
            1
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                InitializeRobinhoodSequencerSignal.ReporterConfigurationMismatch.selector,
                "gasPriceBid"
            )
        );
        sequencerInitializer.validateReporterConfiguration(
            reporter,
            address(sequencerInitializer),
            observers,
            2,
            address(this),
            200_000,
            400_000,
            2
        );
    }

    function test_SequencerSignalDeploymentSeparatesL1AuthorityAndL2Feed() external {
        address[] memory observers = new address[](3);
        observers[0] = address(0x1000);
        observers[1] = address(0x2000);
        observers[2] = address(0x3000);

        vm.chainId(1);
        vm.expectRevert(
            abi.encodeWithSelector(RobinhoodSequencerAvailabilityFeed.WrongChain.selector, 1)
        );
        sequencerDeployer.deploy(address(this));

        vm.chainId(4_663);
        RobinhoodSequencerAvailabilityFeed feed =
            sequencerDeployer.deploy(address(reporterDeployer));
        assertEq(feed.l1Reporter(), address(reporterDeployer));
        assertEq(feed.observerSetVersion(), 0);

        vm.chainId(1);
        vm.expectRevert(
            abi.encodeWithSelector(RobinhoodSequencerReporterL1.InvalidThreshold.selector, 1, 3)
        );
        reporterDeployer.deploy(
            address(this), observers, 1, address(this), 200_000, 400_000, 1 gwei
        );

        RobinhoodSequencerReporterL1 reporter = reporterDeployer.deploy(
            address(this), observers, 2, address(this), 200_000, 400_000, 1 gwei
        );
        assertEq(reporter.owner(), address(this));
        assertEq(reporter.childChainId(), 4_663);
    }

    function test_DeploymentRequiresRobinhoodAndExplicitOwner() external {
        vm.chainId(1);
        vm.expectRevert(abi.encodeWithSelector(DeployStaticsOracle.WrongChain.selector, 4663, 1));
        deployer.deploy(address(this));

        vm.chainId(4663);
        vm.expectRevert(DeployStaticsOracle.ZeroInitialOwner.selector);
        deployer.deploy(address(0));

        StaticsOracle oracle = deployer.deploy(address(this));
        assertEq(oracle.owner(), address(this));
    }

    function test_CheckedInManifestSelectsVerifiedSequencerAndGrace() external view {
        string memory manifest = vm.readFile("config/robinhood-mainnet.assets.json");
        assertTrue(vm.parseJsonBool(manifest, ".sequencer.verified"));
        assertEq(vm.parseJsonUint(manifest, ".sequencer.gracePeriod"), 1 hours);
        assertEq(
            vm.parseJsonAddress(manifest, ".sequencer.feed"),
            0xeCe3F60De85705472292a44787123a8Fc46CDa54
        );
    }

    function test_UnverifiedSequencerStillRejected() external {
        vm.chainId(4663);
        StaticsOracle oracle = new StaticsOracle(address(configurator));
        vm.expectRevert(ConfigureStaticsOracle.UnverifiedSequencer.selector);
        configurator.configure(oracle, "{\"sequencer\":{\"verified\":false}}");
        assertEq(oracle.registryVersion(), 0);
    }

    function test_ConfigurationAndDeployedStateVerificationPreserveCandidates() external {
        vm.chainId(4663);
        OracleFeedTestMock sequencer = new OracleFeedTestMock(0, "Sequencer");
        OracleFeedTestMock feed = new OracleFeedTestMock(8, "DEPLOY / USD");
        OracleTokenTestMock enabledToken = new OracleTokenTestMock(18);
        OracleTokenTestMock candidateToken = new OracleTokenTestMock(18);
        vm.warp(10 days);
        sequencer.setRoundData(1, 0, block.timestamp - 2 hours, block.timestamp, 1);
        feed.setRound(100e8, block.timestamp);

        string memory manifest =
            _manifest(sequencer, feed, enabledToken, candidateToken, keccak256("DEPLOY / USD"));
        StaticsOracle oracle = new StaticsOracle(address(configurator));
        configurator.configure(oracle, manifest);
        configurator.verify(oracle, manifest);

        assertEq(oracle.registryVersion(), 4);
        assertEq(
            uint8(oracle.assetConfig(address(enabledToken)).status),
            uint8(IStaticsOracle.AssetStatus.ENABLED)
        );
        assertEq(
            uint8(oracle.assetConfig(address(candidateToken)).status),
            uint8(IStaticsOracle.AssetStatus.CANDIDATE)
        );

        vm.prank(address(configurator));
        oracle.disableAsset(address(enabledToken));
        vm.expectRevert(
            abi.encodeWithSelector(
                ConfigureStaticsOracle.DeployedStateMismatch.selector, "ENABLED", "status"
            )
        );
        configurator.verify(oracle, manifest);
    }

    function test_ManifestGracePeriodUsesCheckedUint32Conversion() external {
        vm.chainId(4663);
        OracleFeedTestMock sequencer = new OracleFeedTestMock(0, "Sequencer");

        StaticsOracle upperBoundOracle = new StaticsOracle(address(configurator));
        configurator.configure(upperBoundOracle, _sequencerManifest(sequencer, type(uint32).max));
        assertEq(upperBoundOracle.sequencerConfig().gracePeriod, type(uint32).max);

        uint256 overflowingGracePeriod = uint256(type(uint32).max) + 1;
        StaticsOracle overflowOracle = new StaticsOracle(address(configurator));
        vm.expectRevert(
            abi.encodeWithSelector(
                SafeCast.SafeCastOverflowedUintDowncast.selector, 32, overflowingGracePeriod
            )
        );
        configurator.configure(
            overflowOracle, _sequencerManifest(sequencer, overflowingGracePeriod)
        );
        assertEq(overflowOracle.registryVersion(), 0);
    }

    function test_VerificationDetectsKindAndDescriptionHashDrift() external {
        vm.chainId(4663);
        vm.warp(10 days);
        OracleFeedTestMock sequencer = new OracleFeedTestMock(0, "Sequencer");
        OracleFeedTestMock feed = new OracleFeedTestMock(8, "DEPLOY / USD");
        OracleTokenTestMock enabledToken = new OracleTokenTestMock(18);
        OracleTokenTestMock candidateToken = new OracleTokenTestMock(18);
        sequencer.setRoundData(1, 0, block.timestamp - 2 hours, block.timestamp, 1);
        feed.setRound(100e8, block.timestamp);

        bytes32 descriptionHash = keccak256("DEPLOY / USD");
        string memory manifest =
            _manifest(sequencer, feed, enabledToken, candidateToken, descriptionHash);
        StaticsOracle oracle = new StaticsOracle(address(configurator));
        configurator.configure(oracle, manifest);

        vm.startPrank(address(configurator));
        oracle.disableAsset(address(enabledToken));
        oracle.updateAsset(
            address(enabledToken),
            _input(address(feed), descriptionHash, IStaticsOracle.AssetKind.STABLE)
        );
        vm.stopPrank();
        vm.expectRevert(
            abi.encodeWithSelector(
                ConfigureStaticsOracle.DeployedStateMismatch.selector, "ENABLED", "kind"
            )
        );
        configurator.verify(oracle, manifest);

        bytes32 replacementHash = keccak256("REPLACEMENT / USD");
        vm.mockCall(
            address(feed), abi.encodeWithSignature("description()"), abi.encode("REPLACEMENT / USD")
        );
        vm.startPrank(address(configurator));
        oracle.disableAsset(address(enabledToken));
        oracle.updateAsset(
            address(enabledToken),
            _input(address(feed), replacementHash, IStaticsOracle.AssetKind.CRYPTO)
        );
        vm.stopPrank();
        vm.clearMockedCalls();

        vm.expectRevert(
            abi.encodeWithSelector(
                ConfigureStaticsOracle.DeployedStateMismatch.selector,
                "ENABLED",
                "feedDescriptionHash"
            )
        );
        configurator.verify(oracle, manifest);
    }

    function _input(
        address feed,
        bytes32 descriptionHash,
        IStaticsOracle.AssetKind kind
    ) internal pure returns (IStaticsOracle.AssetOracleConfigInput memory) {
        return IStaticsOracle.AssetOracleConfigInput({
            feed: feed,
            feedDescriptionHash: descriptionHash,
            maxAge: 1 hours,
            tokenDecimals: 18,
            feedDecimals: 8,
            kind: kind,
            checkOraclePause: false
        });
    }

    function _observers() internal pure returns (address[] memory observers) {
        observers = new address[](3);
        observers[0] = address(0x1000);
        observers[1] = address(0x2000);
        observers[2] = address(0x3000);
    }

    function _sequencerManifest(
        OracleFeedTestMock sequencer,
        uint256 gracePeriod
    ) internal pure returns (string memory) {
        return string.concat(
            "{\"sequencer\":{\"verified\":true,\"feed\":\"",
            vm.toString(address(sequencer)),
            "\",\"gracePeriod\":",
            vm.toString(gracePeriod),
            "},\"assetCount\":0,\"assets\":[]}"
        );
    }

    function _manifest(
        OracleFeedTestMock sequencer,
        OracleFeedTestMock feed,
        OracleTokenTestMock enabledToken,
        OracleTokenTestMock candidateToken,
        bytes32 descriptionHash
    ) internal pure returns (string memory) {
        string memory common = string.concat(
            "\",\"feed\":\"",
            vm.toString(address(feed)),
            "\",\"feedDescriptionHash\":\"",
            vm.toString(descriptionHash),
            "\",\"maxAge\":3600,\"tokenDecimals\":18,\"feedDecimals\":8,",
            "\"kind\":\"CRYPTO\",\"checkOraclePause\":false,\"status\":\""
        );
        return string.concat(
            "{\"sequencer\":{\"verified\":true,\"feed\":\"",
            vm.toString(address(sequencer)),
            "\",\"gracePeriod\":3600},\"assetCount\":2,\"assets\":[",
            "{\"symbol\":\"ENABLED\",\"token\":\"",
            vm.toString(address(enabledToken)),
            common,
            "ENABLED\"},{\"symbol\":\"CANDIDATE\",\"token\":\"",
            vm.toString(address(candidateToken)),
            common,
            "CANDIDATE\"}]}"
        );
    }
}
