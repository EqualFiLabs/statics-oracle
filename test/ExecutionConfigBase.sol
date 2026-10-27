// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Test } from "forge-std/Test.sol";
import { StaticsExecutionOracle } from "src/StaticsExecutionOracle.sol";
import { IStaticsExecutionOracle as IEO } from "src/interfaces/IStaticsExecutionOracle.sol";

contract ExecutionVerifierCodeMock { }

abstract contract ExecutionConfigBase is Test {
    StaticsExecutionOracle internal oracle;
    address internal verifier;
    bytes32 internal constant MARKET = keccak256("BTC_USD");
    bytes32 internal constant STREAM = bytes32((uint256(3) << 240) | 1234);

    function setUp() public {
        vm.warp(1000);
        verifier = address(new ExecutionVerifierCodeMock());
        oracle = new StaticsExecutionOracle(address(this), verifier, 5);
    }

    function input() internal pure returns (IEO.ExecutionMarketConfigInput memory) {
        return IEO.ExecutionMarketConfigInput(STREAM, 10, 30, 8);
    }
}
