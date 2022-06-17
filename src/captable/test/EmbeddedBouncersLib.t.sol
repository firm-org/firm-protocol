// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import {FirmTest} from "../../common/test/lib/FirmTest.sol";
import {EmbeddedBouncersLib, IBouncer} from "../Captable.sol";

contract EmbeddedBouncersLibTest is FirmTest {
    using EmbeddedBouncersLib for IBouncer;

    function testRandomAddressIsNotEmbedded() public {
        assertBouncerType(
            address(this),
            EmbeddedBouncersLib.BouncerType.NotEmbedded
        );
    }

    function testEmbeddedTypes() public {
        assertBouncerType(
            0x0000000000000000000000000000000000000000,
            EmbeddedBouncersLib.BouncerType.AllowAll
        );
        assertBouncerType(
            0x0100000000000000000000000000000000000000,
            EmbeddedBouncersLib.BouncerType.DenyAll
        );
        assertBouncerType(
            0x0200000000000000000000000000000000000000,
            EmbeddedBouncersLib.BouncerType.AllowClassHolders
        );
        assertBouncerType(
            0x0300000000000000000000000000000000000000,
            EmbeddedBouncersLib.BouncerType.AllowAllHolders
        );
        assertBouncerType(
            0x0400000000000000000000000000000000000000,
            EmbeddedBouncersLib.BouncerType.NotEmbedded
        );
        assertBouncerType(
            0x0500000000000000000000000000000000000000,
            EmbeddedBouncersLib.BouncerType.NotEmbedded
        );
    }

    function testEdgeCases() public {
        assertBouncerType(
            0x0100000000000000000000000000000000000001,
            EmbeddedBouncersLib.BouncerType.NotEmbedded
        );
        assertBouncerType(
            0x0110000000000000000000000000000000000000,
            EmbeddedBouncersLib.BouncerType.NotEmbedded
        );
        assertBouncerType(
            0x0000000000000000000000000000000000000001,
            EmbeddedBouncersLib.BouncerType.NotEmbedded
        );
        assertBouncerType(
            0xfF00000000000000000000000000000000000000,
            EmbeddedBouncersLib.BouncerType.NotEmbedded
        );
    }

    function assertBouncerType(
        address bouncerAddr,
        EmbeddedBouncersLib.BouncerType bouncerType
    ) internal {
        assertEq(
            uint8(IBouncer(bouncerAddr).bouncerType()),
            uint8(bouncerType)
        );
    }
}
