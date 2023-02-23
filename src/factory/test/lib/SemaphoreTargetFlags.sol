// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import {SemaphoreTargetsFlag, SEMAPHORE_TARGETS_FLAG_TYPE, AddressUint8FlagsLib} from "../../FirmFactory.sol";

function semaphoreTargetFlag(SemaphoreTargetsFlag flag) pure returns (address) {
  return AddressUint8FlagsLib.toFlag(uint8(flag), SEMAPHORE_TARGETS_FLAG_TYPE);
}