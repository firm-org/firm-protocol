// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import {IBouncer} from "../../interfaces/IBouncer.sol";

contract OddBouncer is IBouncer {
    function isTransferAllowed(address, address, uint256, uint256 amount) external pure override returns (bool) {
        // Odd bouncer only allows transfers of odd amounts
        return amount % 2 == 1;
    }
}
