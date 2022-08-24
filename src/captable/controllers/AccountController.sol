// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import {Captable} from "../Captable.sol";
import {IBouncer} from "../bouncers/IBouncer.sol";

abstract contract IAccountController is IBouncer {
    function addAccount(address owner, uint256 classId, uint256 amount, bytes calldata extraParams) external virtual;
}

abstract contract AccountController is IAccountController {
    // CAPTABLE_SLOT = keccak256("firm.accountcontroller.captable") - 1
    bytes32 internal constant CAPTABLE_SLOT = 0xff0072f9b8f3624c7501bc21bf62fd5a141de3e4b1703f9e7f919a1ff011f4e6;

    error CaptableAddressZero();
    error AlreadyInitialized();
    error UnauthorizedNotCaptable();
    error UnauthorizedNotSafe();
    error AccountAlreadyExists();
    error AccountDoesntExist();

    function captable() public view returns (Captable _captable) {
        assembly {
            _captable := sload(CAPTABLE_SLOT)
        }
    }

    function __init_setCaptable(Captable captable_) internal {
        if (address(captable_) == address(0)) {
            revert CaptableAddressZero();
        }

        if (address(captable()) != address(0)) {
            revert AlreadyInitialized();
        }

        assembly {
            sstore(CAPTABLE_SLOT, captable_)
        }
    }

    modifier onlyCaptable() {
        if (msg.sender != address(captable())) {
            revert UnauthorizedNotCaptable();
        }

        _;
    }
}
