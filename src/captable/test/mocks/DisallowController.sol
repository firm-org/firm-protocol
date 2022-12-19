// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {AccountController} from "../../controllers/AccountController.sol";

contract DisallowController is AccountController {
    string public constant moduleId = "org.firm.captable-mocks.disallow";
    uint256 public constant moduleVersion = 1;

    function addAccount(address owner, uint256 classId, uint256 amount, bytes calldata extraParams) external override {}

    function isTransferAllowed(address, address, uint256, uint256) external pure returns (bool) {
        return false;
    }
}
