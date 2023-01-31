// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import {ROLES_FLAG_TYPE, AddressUint8FlagsLib} from "../../RolesAuth.sol";

function roleFlag(uint8 role) pure returns (address) {
    return AddressUint8FlagsLib.toFlag(role, ROLES_FLAG_TYPE);
}