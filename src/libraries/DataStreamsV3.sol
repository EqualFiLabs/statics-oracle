// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Types for authenticated Crypto Advanced V3 report bodies.
library DataStreamsV3 {
    struct Report {
        bytes32 feedId;
        uint32 validFromTimestamp;
        uint32 observationsTimestamp;
        uint192 nativeFee;
        uint192 linkFee;
        uint32 expiresAt;
        int192 price;
        int192 bid;
        int192 ask;
    }
}
