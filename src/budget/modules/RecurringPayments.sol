// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {BudgetModule} from "./BudgetModule.sol";

contract RecurringPayments is BudgetModule {
    string public constant moduleId = "org.firm.budget.recurring";
    uint256 public constant moduleVersion = 1;

    struct RecurringPayment {
        bool disabled;
        address to;
        uint256 amount;
    }

    struct AllowancePayments {
        mapping(uint256 => RecurringPayment) paymentData;
        // tighly packed fixed array as on execution, the next execution time
        // is updated, resulting in less slots being touched
        // index 0 acts as the length for how many payments there are
        uint40[2 ** 40] nextExecutionTime;
    }

    uint256 internal constant PAYMENTS_LENGTH_INDEX = 0;

    mapping(uint256 => AllowancePayments) payments;

    // Protected so only spenders from the parent allowance to the one recurring payments can spend can add payments
    function addPayment(uint256 allowanceId, address to, uint256 amount)
        external
        onlyAllowanceAdmin(allowanceId)
        returns (uint40 paymentId)
    {
        AllowancePayments storage allowancePayments = payments[allowanceId];

        unchecked {
            paymentId = ++allowancePayments.nextExecutionTime[PAYMENTS_LENGTH_INDEX];
        }
        allowancePayments.paymentData[paymentId] = RecurringPayment({disabled: false, to: to, amount: amount});
    }
    
    error UnexistentPayment(uint256 allowanceId, uint256 paymentId);

    // Unprotected
    function executePayment(uint256 allowanceId, uint256 paymentId) external {
        RecurringPayment storage payment = payments[allowanceId].paymentData[paymentId];
        uint40[2 ** 40] storage nextExecutionTime = payments[allowanceId].nextExecutionTime;

        bool badPaymentId = paymentId == PAYMENTS_LENGTH_INDEX || paymentId > nextExecutionTime[PAYMENTS_LENGTH_INDEX];
        if (badPaymentId) {
            revert UnexistentPayment(allowanceId, paymentId);
        }

        require(!payment.disabled);
        require(uint40(block.timestamp) >= nextExecutionTime[paymentId]);

        // reentrancy lock
        nextExecutionTime[paymentId] = type(uint40).max;

        uint40 nextResetTime = budget.executePayment(allowanceId, payment.to, payment.amount, "");

        nextExecutionTime[paymentId] = nextResetTime;
    }

    // Unprotected
    function executeManyPayments(uint256 allowanceId, uint40[] calldata paymentIds) external {
        uint40[2 ** 40] storage nextExecutionTime = payments[allowanceId].nextExecutionTime;
        
        uint256[] memory amounts = new uint256[](paymentIds.length);
        address[] memory tos = new address[](paymentIds.length);

        uint40 paymentsLength = nextExecutionTime[PAYMENTS_LENGTH_INDEX];
        for (uint256 i = 0; i < paymentIds.length; i++) {
            uint256 paymentId = paymentIds[i];
            RecurringPayment storage payment = payments[allowanceId].paymentData[paymentId];

            bool badPaymentId = paymentId == PAYMENTS_LENGTH_INDEX || paymentId > paymentsLength;
            if (badPaymentId) {
                revert UnexistentPayment(allowanceId, paymentId);
            }   

            require(!payment.disabled);
            require(uint40(block.timestamp) >= nextExecutionTime[paymentId]);

            tos[i] = payment.to;
            amounts[i] = payment.amount;

            // set reentrancy lock for paymentId
            nextExecutionTime[paymentId] = type(uint40).max;
        }

        uint40 nextResetTime = budget.executeMultiPayment(allowanceId, tos, amounts, "");

        for (uint256 i = 0; i < paymentIds.length; i++) {
            nextExecutionTime[paymentIds[i]] = nextResetTime;
        }
    }
}
