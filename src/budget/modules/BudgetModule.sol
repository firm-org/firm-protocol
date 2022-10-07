// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {Budget} from "../Budget.sol";
import {FirmBase, IAvatar} from "../../bases/FirmBase.sol";

address constant IMPL_INIT_ADDRESS = address(1);

abstract contract BudgetModule is FirmBase {
    Budget public budget; // TODO: Unstructured storage

    constructor() {
        // Initialize with impossible values in constructor so impl base cannot be used
        initialize(Budget(IMPL_INIT_ADDRESS), IMPL_INIT_ADDRESS);
    }

    function initialize(Budget budget_, address trustedForwarder_) public {
        IAvatar safe = address(budget_) != IMPL_INIT_ADDRESS ? budget_.safe() : IAvatar(IMPL_INIT_ADDRESS);
        __init_firmBase(safe, trustedForwarder_);
        budget = budget_;
    }

    error UnauthorizedNotAllowanceAdmin(uint256 allowanceId, address actor);

    modifier onlyAllowanceAdmin(uint256 allowanceId) {
        address actor = _msgSender();
        if (!budget.isAdminOnAllowance(allowanceId, actor)) {
            revert UnauthorizedNotAllowanceAdmin(allowanceId, actor);
        }

        _;
    }
}
