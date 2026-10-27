// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import { ExecutionConfigTest } from "./StaticsExecutionOracle.Config.t.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { StaticsExecutionOracle } from "src/StaticsExecutionOracle.sol";
import { IStaticsExecutionOracle as IEO } from "src/interfaces/IStaticsExecutionOracle.sol";
import { OracleFeedTestMock } from "test/mocks/OracleTestMocks.sol";

contract ExecutionAdminTest is ExecutionConfigTest {
    function testOnlyOwnerCanAuthorizeContracts() public {
        vm.prank(address(123));
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(123))
        );
        oracle.setAuthorizedConsumer(address(this), true);
        vm.expectRevert(
            abi.encodeWithSelector(StaticsExecutionOracle.NoContractCode.selector, address(123))
        );
        oracle.setAuthorizedConsumer(address(123), true);
        oracle.setAuthorizedConsumer(address(this), true);
        oracle.setAuthorizedConsumer(address(this), false);
        assertFalse(oracle.isAuthorizedConsumer(address(this)));
    }

    function testUnauthorizedRequestStopsBeforeMarketAndVerifier() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                StaticsExecutionOracle.UnauthorizedConsumer.selector, address(this)
            )
        );
        oracle.verifyExecutionPrice(MARKET, new bytes[](0));
        oracle.setAuthorizedConsumer(address(this), true);
        vm.expectRevert(
            abi.encodeWithSelector(StaticsExecutionOracle.UnsupportedMarket.selector, MARKET)
        );
        oracle.verifyExecutionPrice(MARKET, new bytes[](0));
    }

    function testSequencerConfigurationRejectsMalformedFeed() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                StaticsExecutionOracle.SequencerFeedCallFailed.selector, verifier
            )
        );
        oracle.setSequencerConfig(verifier, 10);
        OracleFeedTestMock feed = new OracleFeedTestMock(0, "health");
        feed.setRoundData(1, 0, 900, 900, 1);
        oracle.setSequencerConfig(address(feed), 10);
        uint64 version = oracle.registryVersion();
        feed.setLatestRoundCallFails(true);
        vm.expectRevert(
            abi.encodeWithSelector(
                StaticsExecutionOracle.SequencerFeedCallFailed.selector, address(feed)
            )
        );
        oracle.setSequencerConfig(address(feed), 20);
        assertEq(oracle.registryVersion(), version);
    }

    function testSequencerRejectsOutageAndExactGraceBoundary() public {
        oracle.registerMarket(MARKET, input());
        oracle.enableMarket(MARKET);
        oracle.setAuthorizedConsumer(address(this), true);
        vm.expectRevert(StaticsExecutionOracle.SequencerNotConfigured.selector);
        oracle.verifyExecutionPrice(MARKET, new bytes[](1));
        OracleFeedTestMock feed = new OracleFeedTestMock(0, "health");
        feed.setRoundData(1, 0, 990, 990, 1);
        oracle.setSequencerConfig(address(feed), 10);
        vm.expectRevert(
            abi.encodeWithSelector(StaticsExecutionOracle.SequencerGracePeriod.selector, 990, 10)
        );
        oracle.verifyExecutionPrice(MARKET, new bytes[](1));
        feed.setRoundData(1, 1, 900, 900, 1);
        vm.expectRevert(StaticsExecutionOracle.SequencerDown.selector);
        oracle.verifyExecutionPrice(MARKET, new bytes[](1));
        feed.setRoundData(1, 0, 0, 900, 1);
        vm.expectRevert(StaticsExecutionOracle.SequencerDown.selector);
        oracle.verifyExecutionPrice(MARKET, new bytes[](1));
    }
}
