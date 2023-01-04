// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import {FirmBase, ISafe, IMPL_INIT_NOOP_ADDR, IMPL_INIT_NOOP_SAFE} from "../../bases/FirmBase.sol";

import {FirmCaptable} from "../FirmCaptable.sol";
import {IBouncer} from "../bouncers/IBouncer.sol";

abstract contract IAccountController is IBouncer {
    function addAccount(address owner, uint256 classId, uint256 amount, bytes calldata extraParams) external virtual;
}

abstract contract AccountController is FirmBase, IAccountController {
    // CAPTABLE_SLOT = keccak256("firm.accountcontroller.captable") - 1
    bytes32 internal constant CAPTABLE_SLOT = 0xff0072f9b8f3624c7501bc21bf62fd5a141de3e4b1703f9e7f919a1ff011f4e6;

    constructor() {
        initialize(FirmCaptable(IMPL_INIT_NOOP_ADDR), IMPL_INIT_NOOP_ADDR);
    }

    function initialize(FirmCaptable captable_, address trustedForwarder_) public {
        ISafe safe = address(captable_) != IMPL_INIT_NOOP_ADDR ? captable_.safe() : IMPL_INIT_NOOP_SAFE;

        // Will revert if reinitialized
        __init_firmBase(safe, trustedForwarder_);
        assembly {
            sstore(CAPTABLE_SLOT, captable_)
        }
    }

    function captable() public view returns (FirmCaptable _captable) {
        assembly {
            _captable := sload(CAPTABLE_SLOT)
        }
    }

    error UnauthorizedNotCaptable();
    error AccountAlreadyExists();
    error AccountDoesntExist();

    modifier onlyCaptable() {
        // We use msg.sender directly here because FirmCaptable will never do meta-txs into this contract
        if (msg.sender != address(captable())) {
            revert UnauthorizedNotCaptable();
        }

        _;
    }
}
