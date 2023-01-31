// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import {IBouncer, EmbeddedBouncerType, EMBEDDED_BOUNCER_FLAG_TYPE, AddressUint8FlagsLib} from "../BouncerChecker.sol";

function bouncerFlag(EmbeddedBouncerType bouncer) pure returns (IBouncer) {
  return IBouncer(AddressUint8FlagsLib.toFlag(uint8(bouncer), EMBEDDED_BOUNCER_FLAG_TYPE));
}