// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import { StaticsExecutionOracle } from "src/StaticsExecutionOracle.sol";
import { IStaticsExecutionOracle as IEO } from "src/interfaces/IStaticsExecutionOracle.sol";
import { ExecutionTestBase } from "test/ExecutionTestBase.sol";
import { ExecutionConsumerHarness } from "test/mocks/ExecutionConsumerHarness.sol";

contract ExecutionConsumersTest is ExecutionTestBase {
    function testPermissionlessUsersCanSupplyIndependentReportsThroughConsumer() public {
        ExecutionConsumerHarness consumer = new ExecutionConsumerHarness(oracle);
        oracle.setAuthorizedConsumer(address(consumer), true);
        bytes[] memory reports = bundle(report());
        vm.prank(address(111));
        IEO.ExecutionPrice memory first = consumer.execute(MARKET, reports);
        vm.prank(address(222));
        IEO.ExecutionPrice memory second = consumer.execute(MARKET, reports);
        assertEq(abi.encode(first), abi.encode(second));
        assertEq(consumer.completedActions(), 2);
        oracle.setAuthorizedConsumer(address(consumer), false);
        vm.expectRevert(
            abi.encodeWithSelector(
                StaticsExecutionOracle.UnauthorizedConsumer.selector, address(consumer)
            )
        );
        consumer.execute(MARKET, reports);
        assertEq(consumer.completedActions(), 2);
    }

    function testOracleFailureRollsBackConsumerWrites() public {
        ExecutionConsumerHarness consumer = new ExecutionConsumerHarness(oracle);
        oracle.setAuthorizedConsumer(address(consumer), true);
        bytes[] memory reports = bundle(report());
        verifier.setFail(true);
        vm.expectRevert();
        consumer.execute(MARKET, reports);
        assertEq(consumer.completedActions(), 0);
    }

    function testDisabledMarketBlocksPreviouslyUsableReports() public {
        bytes[] memory reports = bundle(report());
        oracle.disableMarket(MARKET);
        vm.expectRevert(
            abi.encodeWithSelector(
                StaticsExecutionOracle.MarketNotEnabled.selector, MARKET, IEO.MarketStatus.DISABLED
            )
        );
        oracle.verifyExecutionPrice(MARKET, reports);
    }
}
