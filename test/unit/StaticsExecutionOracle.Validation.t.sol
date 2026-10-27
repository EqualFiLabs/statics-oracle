// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import { StaticsExecutionOracle } from "src/StaticsExecutionOracle.sol";
import { DataStreamsV3 } from "src/libraries/DataStreamsV3.sol";
import { ExecutionTestBase } from "test/ExecutionTestBase.sol";

contract ExecutionValidationTest is ExecutionTestBase {
    function testZeroAndNegativeConsensusPriceFail() public {
        DataStreamsV3.Report memory r = report();
        r.price = 0;
        bytes[] memory reports = bundle(r);
        vm.expectRevert(
            abi.encodeWithSelector(StaticsExecutionOracle.InvalidReportPrice.selector, 0)
        );
        oracle.verifyExecutionPrice(MARKET, reports);
        r.price = -1;
        reports = bundle(r);
        vm.expectRevert(
            abi.encodeWithSelector(StaticsExecutionOracle.InvalidReportPrice.selector, int192(-1))
        );
        oracle.verifyExecutionPrice(MARKET, reports);
    }
}
