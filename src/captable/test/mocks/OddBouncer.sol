// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {IBouncer} from "../../bouncers/IBouncer.sol";

contract OddBouncer is IBouncer {
    function isTransferAllowed(address, address, uint256, uint256 amount) external pure override returns (bool) {
        // Odd bouncer only allows transfers of odd amounts
        return amount % 2 == 1;
    }
}
