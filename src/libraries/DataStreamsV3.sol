// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice Types for authenticated Crypto Advanced V3 report bodies.
library DataStreamsV3 {
    error InvalidReportLength(uint256 length);
    error UnsupportedReportSchema(bytes2 schema);

    /// @dev Crypto Advanced V3 is nine static ABI words, including canonical narrow values.
    function decode(
        bytes memory body
    ) internal pure returns (Report memory report) {
        if (body.length != 9 * 32) revert InvalidReportLength(body.length);
        report = abi.decode(body, (Report));
        if (bytes2(report.feedId) != bytes2(uint16(3))) {
            revert UnsupportedReportSchema(bytes2(report.feedId));
        }
    }

    struct Report {
        bytes32 feedId;
        uint32 validFromTimestamp;
        uint32 observationsTimestamp;
        uint192 nativeFee;
        uint192 linkFee;
        uint32 expiresAt;
        // Sole execution price. Fees, bid and ask are decoded for schema compatibility only.
        int192 price;
        int192 bid;
        int192 ask;
    }
}
