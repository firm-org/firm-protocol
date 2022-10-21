// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {Budget} from "../Budget.sol";
import {FirmBase, IAvatar} from "../../bases/FirmBase.sol";

address constant IMPL_INIT_ADDRESS = address(1);

abstract contract BudgetModule is FirmBase {
    // BUDGET_SLOT = keccak256("firm.budgetmodule.budget") - 1
    bytes32 internal constant BUDGET_SLOT = 0xc7637e5414363c2355f9e835e00d15501df0666fb3c6c5fe259b9a40aeedbc49;

    constructor() {
        // Initialize with impossible values in constructor so impl base cannot be used
        initialize(Budget(IMPL_INIT_ADDRESS), IMPL_INIT_ADDRESS);
    }

    function initialize(Budget budget_, address trustedForwarder_) public {
        IAvatar safe = address(budget_) != IMPL_INIT_ADDRESS ? budget_.safe() : IAvatar(IMPL_INIT_ADDRESS);
        __init_firmBase(safe, trustedForwarder_);
        assembly {
            sstore(BUDGET_SLOT, budget_)
        }
    }

    function budget() public view returns (Budget _budget) {
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
