// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {FirmBase, ISafe, IMPL_INIT_NOOP_ADDR, IMPL_INIT_NOOP_SAFE} from "../../bases/FirmBase.sol";

import {FirmBudget} from "../FirmBudget.sol";

abstract contract BudgetModule is FirmBase {
    // BUDGET_SLOT = keccak256("firm.budgetmodule.budget") - 1
    bytes32 internal constant BUDGET_SLOT = 0xc7637e5414363c2355f9e835e00d15501df0666fb3c6c5fe259b9a40aeedbc49;

    constructor() {
        // Initialize with impossible values in constructor so impl base cannot be used
        initialize(FirmBudget(IMPL_INIT_NOOP_ADDR), IMPL_INIT_NOOP_ADDR);
    }

    function initialize(FirmBudget budget_, address trustedForwarder_) public {
        ISafe safe = address(budget_) != IMPL_INIT_NOOP_ADDR ? budget_.safe() : IMPL_INIT_NOOP_SAFE;

        // Will revert if reinitialized
        __init_firmBase(safe, trustedForwarder_);
        assembly {
            sstore(BUDGET_SLOT, budget_)
        }
    }

    function budget() public view returns (FirmBudget _budget) {
        assembly {
            _budget := sload(BUDGET_SLOT)
        }
    }

    error UnauthorizedNotAllowanceAdmin(uint256 allowanceId, address actor);

    modifier onlyAllowanceAdmin(uint256 allowanceId) {
        address actor = _msgSender();
        if (!budget().isAdminOnAllowance(allowanceId, actor)) {
            revert UnauthorizedNotAllowanceAdmin(allowanceId, actor);
        }

        _;
    }
}
