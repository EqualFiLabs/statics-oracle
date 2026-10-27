// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import { Test } from "forge-std/Test.sol";
import { DataStreamsV3 } from "src/libraries/DataStreamsV3.sol";

contract ReportV3ModelTest is Test {
    function testFeeBidAndAskFieldsDoNotSubstituteForConsensusPrice() public pure {
        DataStreamsV3.Report memory r = DataStreamsV3.Report(
            bytes32(uint256(3) << 240),
            1,
            2,
            type(uint192).max,
            type(uint192).max,
            3,
            123,
            type(int192).min,
            type(int192).max
        );
        DataStreamsV3.Report memory decoded = DataStreamsV3.decode(abi.encode(r));
        assertEq(int256(decoded.price), 123);
        assertEq(int256(decoded.bid), type(int192).min);
        assertEq(int256(decoded.ask), type(int192).max);
    }
}
