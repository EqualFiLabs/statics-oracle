// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library AddressAliasHelper {
    uint160 internal constant OFFSET = uint160(0x1111000000000000000000000000000000001111);

    function applyL1ToL2Alias(
        address l1Address
    ) internal pure returns (address) {
        unchecked {
            return address(uint160(l1Address) + OFFSET);
        }
    }
}
