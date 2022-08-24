// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {AccountController} from "../../controllers/AccountController.sol";

contract DisallowController is AccountController {
    function addAccount(address owner, uint256 classId, uint256 amount, bytes calldata extraParams) external override {}

    function isTransferAllowed(address, address, uint256, uint256) external view returns (bool) {
        return false;
    }
}
