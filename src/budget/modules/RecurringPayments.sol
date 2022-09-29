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

contract RecurringPayments is BudgetModule {
    string public constant moduleId = "org.firm.budget.recurring";
    uint256 public constant moduleVersion = 1;

    struct RecurringPayment {
        bool enabled;
        address to;
        uint256 amount;
    }

    struct AllowancePayments {
        mapping (uint256 => RecurringPayment) paymentData;
        mapping (uint256 => uint64[4]) nextExecutionTime; // tightly stored as an optimization
        uint256 paymentsCount;
    }

    mapping (uint256 => AllowancePayments) payments;

    // Protected so only spenders from the parent allowance to the one recurring payments can spend can add payments
    function addPayment(uint256 allowanceId, address to, uint256 amount) external onlyAllowanceAdmin(allowanceId) returns (uint256 paymentId) {
        AllowancePayments storage allowancePayments = payments[allowanceId];

        unchecked {
            paymentId = ++allowancePayments.paymentsCount;
        }
        allowancePayments.paymentData[paymentId].to = to;
        allowancePayments.paymentData[paymentId].amount = amount;
    }

    // Unprotected
    function executePayment(uint256 allowanceId, uint256 paymentId) external {
        RecurringPayment storage payment = payments[allowanceId].paymentData[paymentId];

        uint256 id1 = paymentId / 4;
        uint256 id2 = paymentId % 4;
        require(payment.enabled);
        require(uint64(block.timestamp) >= payments[allowanceId].nextExecutionTime[id1][id2]);

        // reentrancy lock
        payments[allowanceId].nextExecutionTime[id1][id2] = type(uint64).max;

        uint64 nextResetTime = budget.executePayment(allowanceId, payment.to, payment.amount, "");

        payments[allowanceId].nextExecutionTime[id1][id2] = nextResetTime;
    }

    function executeManyPayments(uint256 allowanceId, uint256[] calldata paymentIds) external {
        uint256[] memory amounts = new uint256[](paymentIds.length);
        address[] memory tos = new address[](paymentIds.length);

        for (uint256 i = 0; i < paymentIds.length; i++) {
            uint256 paymentId = paymentIds[i];
            RecurringPayment storage payment = payments[allowanceId].paymentData[paymentId];

            uint256 id1 = paymentId / 4;
            uint256 id2 = paymentId % 4;

            require(payment.enabled);
            require(uint64(block.timestamp) >= payments[allowanceId].nextExecutionTime[id1][id2]);

            tos[i] = payment.to;
            amounts[i] = payment.amount;

            // set reentrancy lock for paymentId
            payments[allowanceId].nextExecutionTime[id1][id2] = type(uint64).max;
        }

        uint64 nextResetTime = budget.executeMultiPayment(allowanceId, tos, amounts, "");

        for (uint256 i = 0; i < paymentIds.length; i++) {
            uint256 paymentId = paymentIds[i];
            uint256 id1 = paymentId / 4;
            uint256 id2 = paymentId % 4;

            payments[allowanceId].nextExecutionTime[id1][id2] = nextResetTime;
        }
    }
}
