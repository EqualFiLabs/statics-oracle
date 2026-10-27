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
}
