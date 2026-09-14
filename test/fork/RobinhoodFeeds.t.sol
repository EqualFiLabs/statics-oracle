// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { IAggregatorV3 } from "src/interfaces/IAggregatorV3.sol";
import { IRobinhoodStockToken } from "src/interfaces/IRobinhoodStockToken.sol";
import { RobinhoodForkBase } from "test/fork/RobinhoodForkBase.sol";

contract RobinhoodFeedsForkTest is RobinhoodForkBase {
    function setUp() external {
        _setUpRobinhoodFork();
    }

    function test_EnabledTargetsMatchPinnedLiveContracts() external view {
        uint256 enabledCount;
        for (uint256 i; i < assetCount; ++i) {
            if (keccak256(bytes(_string(i, "status"))) != keccak256("ENABLED")) continue;
            ++enabledCount;

            address token = _address(i, "token");
            address feed = _address(i, "feed");
            assertGt(token.code.length, 0);
            assertGt(feed.code.length, 0);
            assertEq(IERC20Metadata(token).decimals(), _uint(i, "tokenDecimals"));
            assertEq(IAggregatorV3(feed).decimals(), _uint(i, "feedDecimals"));
            assertEq(IAggregatorV3(feed).description(), _string(i, "feedDescription"));

            (uint80 roundId, int256 answer,, uint256 updatedAt, uint80 answeredInRound) =
                IAggregatorV3(feed).latestRoundData();
            assertGt(answer, 0);
            assertGt(updatedAt, 0);
            assertGe(answeredInRound, roundId);
            assertLe(updatedAt, block.timestamp);
            assertLe(block.timestamp - updatedAt, _uint(i, "maxAge"));

            if (_bool(i, "checkOraclePause")) {
                assertFalse(IRobinhoodStockToken(token).oraclePaused());
            }
        }
        assertEq(enabledCount, 17);
    }
}
