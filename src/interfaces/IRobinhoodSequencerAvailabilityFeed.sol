// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IRobinhoodSequencerAvailabilityFeed {
    function applyConfiguration(
        uint64 observerSetVersion,
        uint64 statusSequence,
        address[] calldata observers,
        uint8 threshold,
        uint64 observedAt
    ) external;

    function applyStatus(
        uint64 observerSetVersion,
        uint64 statusSequence,
        bool healthy,
        uint64 observedAt
    ) external;
}
