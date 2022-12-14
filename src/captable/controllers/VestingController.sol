// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {IRoles, RolesAuth} from "../../common/RolesAuth.sol";

import {AccountController, Captable} from "./AccountController.sol";
import {EquityToken} from "../EquityToken.sol";

contract VestingController is AccountController, RolesAuth {
    string public constant moduleId = "org.firm.captable.vesting";
    uint256 public constant moduleVersion = 1;

    struct VestingParams {
        uint40 startDate;
        uint40 cliffDate;
        uint40 endDate;
        address revoker;
    }

    struct Account {
        uint256 amount;
        VestingParams params;
    }

    // owner -> classId -> Account
    mapping(address => mapping (uint256 => Account)) public accounts;

    error InvalidVestingParameters();
    error UnauthorizedRevoker();
    error InvalidVestingState();

    function initialize(Captable captable_, IRoles _roles, address trustedForwarder_) public {
        initialize(captable_, trustedForwarder_);
        _setRoles(_roles);
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

        _validateAuthorizedAddress(params.revoker);

        Account storage account = accounts[owner][classId];
        if (account.amount > 0) {
            revert AccountAlreadyExists();
        }

        account.amount = amount;
        account.params = params;
    }

    function revokeVesting(address owner, uint256 classId, uint40 effectiveDate) external {
        Account storage account = accounts[owner][classId];

        if (!_isAuthorized(_msgSender(), account.params.revoker)) {
            revert UnauthorizedRevoker();
        }

        if (account.amount == 0) {
            revert AccountDoesntExist();
        }

        // TODO: add hard limit for how much in the past can the effective date be?
        uint256 unvestedAmount = calculateLockedAmount(account.amount, account.params, effectiveDate);
        if (unvestedAmount == 0) {
            revert InvalidVestingState();
        }

        uint256 ownerBalance = captable().balanceOf(owner, classId);
        uint256 forcedTransferAmount = ownerBalance > unvestedAmount ? unvestedAmount : ownerBalance;

        captable().controllerForcedTransfer(
            owner,
            address(safe()),
            classId,
            forcedTransferAmount,
            "Vesting revoked"
        );
        _cleanup(owner, classId);
    }

    function cleanupFullyVested(address owner, uint256 classId) external {
        Account storage account = accounts[owner][classId];

        if (account.amount == 0) {
            revert AccountDoesntExist();
        }

        uint256 lockedAmount = calculateLockedAmount(account.amount, account.params, block.timestamp);
        if (lockedAmount > 0) {
            revert InvalidVestingState();
        }

        _cleanup(owner, classId);
    }

    function _cleanup(address owner, uint256 classId) internal {
        captable().controllerDettach(owner, classId);
        delete accounts[owner][classId];
    }

    function isTransferAllowed(address from, address, uint256 classId, uint256 amount) external view returns (bool) {
        Account storage account = accounts[from][classId];

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
