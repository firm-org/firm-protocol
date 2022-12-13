// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {AccountController, Captable} from "./AccountController.sol";
import {EquityToken} from "../EquityToken.sol";

// NOTE: it should also be possible for VestingController to be a global contract
// that all orgs can just use. Multiple Captables could use the same VestingController
// if the account state is always scoped to captable -> accounts
// NOTE 2: As we did with budget modules, it might be better to have a VestingController
// per organization so that this is a component that can be upgraded by the org.
// The base account controller should take a lot of inspiration from the BudgetModule
contract VestingController is AccountController {
    struct VestingParams {
        uint64 startDate;
        uint64 cliffDate;
        uint64 endDate;
    }
    // address admin; // make a configuration param who/what role can cancel the vesting

    struct Account {
        uint256 classId;
        uint256 amount;
        VestingParams params;
    }

    mapping(address => Account) public accounts;

    error InvalidVestingParameters();

    constructor(Captable captable_) {
        initialize(captable_);
    }

    function initialize(Captable captable_) public {
        __init_setCaptable(captable_);
    }

    function addAccount(address owner, uint256 classId, uint256 amount, bytes calldata extraParams)
        external
        override
        onlyCaptable
    {
        VestingParams memory params = abi.decode(extraParams, (VestingParams));

        if (params.startDate > params.cliffDate || params.cliffDate > params.endDate) {
            revert InvalidVestingParameters();
        }

        Account storage account = accounts[owner];
        if (account.amount > 0) {
            revert AccountAlreadyExists();
        }

        account.classId = classId;
        account.amount = amount;
        account.params = params;
    }

    function revokeVesting(address owner, uint64 effectiveDate) external {
        address safe = address(captable().safe());
        if (msg.sender != safe) {
            revert UnauthorizedNotSafe();
        }

        Account storage account = accounts[owner];

        if (account.amount == 0) {
            revert AccountDoesntExist();
        }

        // TODO: add hard limit for how much in the past can the effective date be
        uint256 unvestedAmount = calculateLockedAmount(account.amount, account.params, effectiveDate);
        uint256 ownerBalance = captable().balanceOf(owner, account.classId);
        uint256 forfeitAmount = ownerBalance > unvestedAmount ? unvestedAmount : ownerBalance;
        captable().controllerForfeit(owner, safe, account.classId, forfeitAmount);

        delete accounts[owner];
    }

    function isTransferAllowed(address from, address, uint256 classId, uint256 amount) external view returns (bool) {
        Account storage account = accounts[from];

        if (account.amount == 0) {
            revert AccountDoesntExist();
        }

        uint256 lockedAmount = calculateLockedAmount(account.amount, account.params, block.timestamp);

        if (lockedAmount > 0) {
            uint256 afterBalance = captable().balanceOf(from, classId) - amount;

            return afterBalance >= lockedAmount;
        }

        return true;
    }

    function calculateLockedAmount(uint256 amount, VestingParams memory params, uint256 time)
        internal
        pure
        returns (uint256)
    {
        if (time >= params.endDate) {
            return 0;
        }

        if (time < params.cliffDate) {
            return amount;
        }

        return amount * (params.endDate - time) / (params.endDate - params.startDate);
    }
}
