// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { Test } from "forge-std/Test.sol";

import { IAggregatorV3 } from "src/interfaces/IAggregatorV3.sol";
import { IRobinhoodStockToken } from "src/interfaces/IRobinhoodStockToken.sol";
import { IStaticsOracle } from "src/interfaces/IStaticsOracle.sol";

contract InterfaceSurfaceTest is Test {
    function test_ConsumerSelectorsMatchDocumentedAbi() external pure {
        assertEq(IStaticsOracle.priceUsd.selector, bytes4(keccak256("priceUsd(address)")));
        assertEq(IStaticsOracle.valueUsd.selector, bytes4(keccak256("valueUsd(address,uint256)")));
        assertEq(
            IStaticsOracle.basketNav.selector, bytes4(keccak256("basketNav(address[],uint256[])"))
        );
        assertEq(IStaticsOracle.peekPrice.selector, bytes4(keccak256("peekPrice(address)")));
        assertEq(IStaticsOracle.assetConfig.selector, bytes4(keccak256("assetConfig(address)")));
        assertEq(IStaticsOracle.registryVersion.selector, bytes4(keccak256("registryVersion()")));
    }

    function test_ExternalOracleSelectorsMatchExpectedInterfaces() external pure {
        assertEq(IAggregatorV3.decimals.selector, bytes4(keccak256("decimals()")));
        assertEq(IAggregatorV3.description.selector, bytes4(keccak256("description()")));
        assertEq(IAggregatorV3.latestRoundData.selector, bytes4(keccak256("latestRoundData()")));
        assertEq(IRobinhoodStockToken.oraclePaused.selector, bytes4(keccak256("oraclePaused()")));
        assertEq(IRobinhoodStockToken.decimals.selector, bytes4(keccak256("decimals()")));
    }
}
