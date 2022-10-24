// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {BudgetModule} from "./BudgetModule.sol";

uint256 constant PAYMENTS_LENGTH_INDEX = 0;

contract RecurringPayments is BudgetModule {
    string public constant moduleId = "org.firm.budget.recurring";
    uint256 public constant moduleVersion = 1;

    struct RecurringPayment {
        bool disabled;
        address to;
        uint256 amount;
    }

    struct AllowancePayments {
        mapping(uint40 => RecurringPayment) paymentData;
        // tighly packed fixed array as on execution, the next execution time
        // is updated, resulting in less slots being touched
        // index 0 acts as the length for how many payments there are
        uint40[2 ** 40] nextExecutionTime;
    }

    mapping(uint256 => AllowancePayments) payments;

    event RecurringPaymentCreated(
        uint256 indexed allowanceId, uint40 indexed paymentId, address indexed to, uint256 amount
    );
    event RecurringPaymentExecuted(
        uint256 indexed allowanceId, uint40 indexed paymentId, uint64 nextExecutionTime, address actor
    );
    event RecurringPaymentsExecuted(
        uint256 indexed allowanceId, uint40[] paymentIds, uint64 nextExecutionTime, address actor
    );

    error ZeroAmount();
    error UnexistentPayment(uint256 allowanceId, uint256 paymentId);
    error PaymentDisabled(uint256 allowanceId, uint256 paymentId);
    error AlreadyExecutedForPeriod(uint256 allowanceId, uint256 paymentId, uint40 nextExecutionTime);

    // Protected so only spenders from the parent allowance to the one recurring payments can spend can add payments
    function addPayment(uint256 allowanceId, address to, uint256 amount)
        external
        onlyAllowanceAdmin(allowanceId)
        returns (uint40 paymentId)
    {
        AllowancePayments storage allowancePayments = payments[allowanceId];

        if (amount == 0) {
            revert ZeroAmount();
        }

        unchecked {
            paymentId = ++allowancePayments.nextExecutionTime[PAYMENTS_LENGTH_INDEX];
        }
        allowancePayments.paymentData[paymentId] = RecurringPayment({disabled: false, to: to, amount: amount});

        emit RecurringPaymentCreated(allowanceId, paymentId, to, amount);
    }

    // Unprotected
    function executePayment(uint256 allowanceId, uint40 paymentId) external returns (uint40 nextExecutionTime) {
        RecurringPayment storage payment = payments[allowanceId].paymentData[paymentId];
        uint40[2 ** 40] storage nextExecutionTimes = payments[allowanceId].nextExecutionTime;

        bool badPaymentId = paymentId == PAYMENTS_LENGTH_INDEX || paymentId > nextExecutionTimes[PAYMENTS_LENGTH_INDEX];
        if (badPaymentId) {
            revert UnexistentPayment(allowanceId, paymentId);
        }

        if (payment.disabled) {
            revert PaymentDisabled(allowanceId, paymentId);
        }

        if (uint40(block.timestamp) < nextExecutionTimes[paymentId]) {
            revert AlreadyExecutedForPeriod(allowanceId, paymentId, nextExecutionTimes[paymentId]);
        }

        nextExecutionTimes[paymentId] = type(uint40).max; // reentrancy lock
        nextExecutionTime = budget().executePayment(allowanceId, payment.to, payment.amount, "");
        nextExecutionTimes[paymentId] = nextExecutionTime;

        emit RecurringPaymentExecuted(allowanceId, paymentId, nextExecutionTime, _msgSender());
    }

    // Unprotected
    function executePayments(uint256 allowanceId, uint40[] calldata paymentIds)
        external
        returns (uint40 nextExecutionTime)
    {
        uint40[2 ** 40] storage nextExecutionTimes = payments[allowanceId].nextExecutionTime;

        uint256[] memory amounts = new uint256[](paymentIds.length);
        address[] memory tos = new address[](paymentIds.length);

        uint40 paymentsLength = nextExecutionTimes[PAYMENTS_LENGTH_INDEX];
        for (uint256 i = 0; i < paymentIds.length; i++) {
            uint40 paymentId = paymentIds[i];
            RecurringPayment storage payment = payments[allowanceId].paymentData[paymentId];

            bool badPaymentId = paymentId == PAYMENTS_LENGTH_INDEX || paymentId > paymentsLength;
            if (badPaymentId) {
                revert UnexistentPayment(allowanceId, paymentId);
            }

            if (payment.disabled) {
                revert PaymentDisabled(allowanceId, paymentId);
            }

            if (uint40(block.timestamp) < nextExecutionTimes[paymentId]) {
                revert AlreadyExecutedForPeriod(allowanceId, paymentId, nextExecutionTimes[paymentId]);
            }

            tos[i] = payment.to;
            amounts[i] = payment.amount;

            // set reentrancy lock for paymentId
            nextExecutionTimes[paymentId] = type(uint40).max;
        }

        nextExecutionTime = budget().executeMultiPayment(allowanceId, tos, amounts, "");

        for (uint256 i = 0; i < paymentIds.length; i++) {
            nextExecutionTimes[paymentIds[i]] = nextExecutionTime;
        }

        emit RecurringPaymentsExecuted(allowanceId, paymentIds, nextExecutionTime, _msgSender());
    }
}
