// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.16;

import {IBouncer} from "./IBouncer.sol";

library EmbeddedBouncersLib {
    enum BouncerType {
        DenyAll,
        AllowAll,
        AllowClassHolders,
        AllowAllHolders,
        NotEmbedded
    }

    function bouncerType(IBouncer bouncer) internal pure returns (BouncerType) {
        // An embedded bouncer is an address whose first byte is the embededded bouncer type
        // followed by all 0s
        // 0x0100..00 would signal embedded bouncer type 1 which is BlockAll
        uint256 x = uint256(uint160(bytes20(address(bouncer))));

        if (x & type(uint152).max != 0) return BouncerType.NotEmbedded;

        uint256 typeId = x >> 152;
        if (typeId >= uint256(uint8(BouncerType.NotEmbedded)))
            return BouncerType.NotEmbedded;

        return BouncerType(uint8(typeId));
    }

    // NOTE: `addrFlag` is unused in production code, here for testing purposes
    function addrFlag(BouncerType bType) internal pure returns (IBouncer) {
        return IBouncer(address(bytes20(bytes32(uint256(uint8(bType)) << 248))));
    }
}