// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {Budget} from "../Budget.sol";
import {FirmBase, IAvatar} from "../../bases/FirmBase.sol";

abstract contract BudgetModule is FirmBase {
    Budget public budget; // TODO: Unstructured storage

    function initialize(Budget budget_, address trustedForwarder_) public {
        __init_firmBase(budget_.safe(), trustedForwarder_);
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
