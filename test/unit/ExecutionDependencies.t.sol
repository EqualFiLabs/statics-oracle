// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import { Test } from "forge-std/Test.sol";
import { OracleMath } from "src/libraries/OracleMath.sol";

contract ExecutionDependenciesTest is Test {
    function testNormalizationPreservesUsdAcrossSupportedPrecisions() public pure {
        assertEq(OracleMath.normalizePrice(123_456_789, 8), 1_234_567_890_000_000_000);
        assertEq(
            OracleMath.normalizePrice(1_234_567_890_000_000_000, 18),
            OracleMath.normalizePrice(123_456_789, 8)
        );
    }

    function normalize(
        uint8 decimals
    ) external pure returns (uint256) {
        return OracleMath.normalizePrice(1, decimals);
    }

    function testUnsupportedPrecisionFailsRatherThanTruncates() public {
        vm.expectRevert(abi.encodeWithSelector(OracleMath.UnsupportedFeedDecimals.selector, 19));
        this.normalize(19);
    }
}
