// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {IERC20} from "openzeppelin/interfaces/IERC20.sol";

import {FirmBase} from "../bases/FirmBase.sol";
import {ZodiacModule, IAvatar, SafeEnums} from "../bases/ZodiacModule.sol";
import {IRoles, RolesAuth} from "../common/RolesAuth.sol";

import {TimeShiftLib, EncodedTimeShift} from "./TimeShiftLib.sol";

address constant NATIVE_ASSET = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
uint256 constant NO_PARENT_ID = 0;
uint256 constant INHERITED_AMOUNT = 0;
uint40 constant INHERITED_RESET_TIME = 0;
address constant IMPL_INIT_ADDRESS = address(1);

/**
 * @title Budget
 * @author Firm (engineering@firm.org)
 * @notice Budgeting module for efficient spending from a Safe using allowance chains
 * to delegate spending authority
 */
contract Budget is FirmBase, ZodiacModule, RolesAuth {
    string public constant moduleId = "org.firm.budget";
    uint256 public constant moduleVersion = 1;

    using TimeShiftLib for uint40;

    ////////////////////////////////////////////////////////////////////////////////
    // INITIALIZATION
    ////////////////////////////////////////////////////////////////////////////////

    constructor() {
        // Initialize with impossible values in constructor so impl base cannot be used
        initialize(IAvatar(IMPL_INIT_ADDRESS), IRoles(IMPL_INIT_ADDRESS), IMPL_INIT_ADDRESS);
    }

    function initialize(IAvatar _safe, IRoles _roles, address trustedForwarder_) public {
        __init_firmBase(_safe, trustedForwarder_); // calls SafeAware.__init_setSafe which reverts on reinitialization
        roles = _roles;
    }

    ////////////////////////////////////////////////////////////////////////////////
    // ALLOWANCE MANAGEMENT
    ////////////////////////////////////////////////////////////////////////////////

    struct Allowance {
        uint256 parentId;
        uint256 amount;
        uint256 spent;
        // This is somewhat a weak abstraction because people tend to think in
        // terms of USD (or other currency) to spend; so it would not matter if
        // it is USDC, DAI or USDT, especially for non-technical and non-defi
        // people. On another note budgets in volatile market assets (like
        // Bitcoin) doesn't make much sense anyway. Maybe budgets should be
        // pegged to dollars for the simplicity?
        // In fact I would go as far as supporting only one spending asset for the
        // v1, like USDC. Safe can hold any number of different assets but doing
        // budgeting on only one assets would extremely simplify things and it
        // is hard to imagine an edge case where a dollar would not work.
        // It is also trivial to trade any asset to USDC
        address token;
        // Solidity uses 32 bytes slots for storate layout; It would be more gas
        // efficient to use uint256 for nextResetTime than uint40 unless you
        // pack it with other variables. I suggest to leave gas and storage
        // optimization until the project in the final phase
        uint40 nextResetTime;
        address spender;
        // While using TimeUnits such daily, weekly etc sounds attractive it
        // implies higher gas costs and much harder to audit. In fact Solidity
        // team dropped years suffix for the same reason. I suggest to keep it
        // simple and use only seconds because not even each day has the same
        // number of seconds (see leap seconds).
        // https://docs.soliditylang.org/en/v0.8.17/units-and-global-variables.html?highlight=seconds#time-units
        EncodedTimeShift recurrency;
        bool isDisabled;
    }

    mapping(uint256 => Allowance) public allowances;
    uint256 public allowancesCount;

    event AllowanceCreated(
        uint256 indexed allowanceId,
        uint256 indexed parentAllowanceId,
        address indexed spender,
        address token,
        uint256 amount,
        EncodedTimeShift recurrency,
        uint40 nextResetTime,
        string name
    );
    event AllowanceStateChanged(uint256 indexed allowanceId, bool isEnabled);
    event AllowanceAmountChanged(uint256 allowanceId, uint256 amount);
    event AllowanceSpenderChanged(uint256 allowanceId, address spender);
    event AllowanceNameChanged(uint256 allowanceId, string name);
    event PaymentExecuted(
        uint256 indexed allowanceId,
        address indexed actor,
        address token,
        address indexed to,
        uint256 amount,
        uint40 nextResetTime,
        string description
    );
    event MultiPaymentExecuted(
        uint256 indexed allowanceId,
        address indexed actor,
        address token,
        address[] tos,
        uint256[] amounts,
        uint40 nextResetTime,
        string description
    );
    event AllowanceDebited(
        uint256 indexed allowanceId,
        address indexed actor,
        address token,
        uint256 amount,
        uint40 nextResetTime,
        bytes description
    );

    error UnexistentAllowance(uint256 allowanceId);
    error DisabledAllowance(uint256 allowanceId);
    error UnauthorizedNotAllowanceAdmin(uint256 allowanceId);
    error TokenMismatch(address patentToken, address childToken);
    error ZeroAmountForTopLevelAllowance();
    error ZeroAmountPayment();
    error BadInput();
    error BadExecutionContext();
    error UnauthorizedPaymentExecution(uint256 allowanceId, address actor);
    error Overbudget(uint256 allowanceId, uint256 amount, uint256 remainingBudget);
    error PaymentExecutionFailed(uint256 allowanceId, address token, address to, uint256 amount);
    error NativeValueMismatch();

    /**
     * @notice Creates a new allowance giving permission to spend funds from the Safe to a given address or addresses with a certain role
     * @dev Note 1: that child allowances can be greater than the allowed amount of its parent budget and have different recurrency
     * Note 2: It is possible to create child allowances for allowances that are disabled (either its parent disabled or any of its ancestors up to the top-level)
     * @param parentAllowanceId ID for the parent allowance (value is 0 for top-level allowances without dependencies)
     * @param spender Address or role identifier of the entities authorized to execute payments from this allowance
     * @param token Address of the token (must be the same as the parent's token)
     * @param amount Amount of token that can be spent per period
     * @param recurrency Unit of time for the allowance spent amount to be reset (value is 0 for the allowance to inherit its parent's recurrency)
     * @param name Name of the allowance being created
     * @return allowanceId ID of the allowance created
     */
    function createAllowance(
        uint256 parentAllowanceId,
        address spender,
        address token,
        uint256 amount,
        EncodedTimeShift recurrency,
        string memory name
    ) public returns (uint256 allowanceId) {
        uint40 nextResetTime;

        if (parentAllowanceId == NO_PARENT_ID) {
            // Top-level allowances can only be created by the Safe
            // It would be better to use one role system for everything instead
            // of dual system of safe and roles
            if (_msgSender() != address(safe())) {
                revert UnauthorizedNotAllowanceAdmin(NO_PARENT_ID);
            }

            // We don't allow setting amount 0 on top-level allowances as clients
            // could support setting 0 as the amount for the allowance and that
            // will create an allowance that allows completely wiping the safe (for the token)
            if (amount == INHERITED_AMOUNT) {
                revert ZeroAmountForTopLevelAllowance();
            }

            // For top-level allowances, recurrency needs to be set and cannot be zero
            // applyShift reverts with InvalidTimeShift if recurrency is unspecified
            // Therefore, nextResetTime is always greater than the current time
            nextResetTime = uint40(block.timestamp).applyShift(recurrency);
        } else {
            Allowance storage parentAllowance = _getAllowance(parentAllowanceId);

            // Not checking whether the parentAllowance is enabled is a explicit decision
            // Disabling any allowance in a given allowance chain will result in all its
            // children not being able to execute payments
            // This allows for disabling a certain allowance to reconfigure the whole tree
            // of sub-allowances below it, before enabling it again

            // Sub-allowances can be created by entities authorized to spend from a particular allowance
            if (!_isAuthorized(_msgSender(), parentAllowance.spender)) {
                revert UnauthorizedNotAllowanceAdmin(parentAllowanceId);
            }
            if (token != parentAllowance.token) {
                revert TokenMismatch(parentAllowance.token, token);
            }
            // Recurrency can be zero in sub-allowances and is inherited from the parent
            if (!recurrency.isInherited()) {
                // Will revert with InvalidTimeShift if recurrency is invalid
                nextResetTime = uint40(block.timestamp).applyShift(recurrency);
            }
        }

        _validateAuthorizedAddress(spender);

        unchecked {
            // The index of the first allowance is 1, so NO_PARENT_ID can be 0 (gas op)
            allowanceId = ++allowancesCount;
        }

        Allowance storage allowance = allowances[allowanceId];
        if (parentAllowanceId != NO_PARENT_ID) {
            allowance.parentId = parentAllowanceId;
        }
        if (nextResetTime != INHERITED_RESET_TIME) {
            allowance.recurrency = recurrency;
            allowance.nextResetTime = nextResetTime;
        }
        allowance.spender = spender;
        allowance.token = token;
        allowance.amount = amount;

        emit AllowanceCreated(allowanceId, parentAllowanceId, spender, token, amount, recurrency, nextResetTime, name);
    }

    /**
     * @notice Changes the enabled/disabled state of the allowance
     * @dev Note: Disabling an allowance will implicitly disable payments from all its descendant allowances
     * @param allowanceId ID of the allowance whose state is being changed
     * @param isEnabled Whether to enable or disable the allowance
     */
    function setAllowanceState(uint256 allowanceId, bool isEnabled) external {
        Allowance storage allowance = _getAllowanceAndValidateAdmin(allowanceId);
        allowance.isDisabled = !isEnabled;
        emit AllowanceStateChanged(allowanceId, isEnabled);
    }

    /**
     * @notice Changes the amount that an allowance can spend
     * @dev Note: It is possible to decrease the amount in an allowance to a smaller amount of what's already been spent
     * which will cause the allowance not to be able to execute any more payments until it resets (and the new amount will be enforced)
     * @param allowanceId ID of the allowance whose amount is being changed
     * @param amount New allowance amount to be set
     */
    function setAllowanceAmount(uint256 allowanceId, uint256 amount) external {
        Allowance storage allowance = _getAllowanceAndValidateAdmin(allowanceId);

        if (amount == INHERITED_AMOUNT && allowance.parentId == NO_PARENT_ID) {
            revert ZeroAmountForTopLevelAllowance();
        }

        allowance.amount = amount;
        emit AllowanceAmountChanged(allowanceId, amount);
    }

    /**
     * @notice Changes the spender of an allowance
     * @dev Note: Changing the spender also changes who the admin is for all the sub-allowances
     * @param allowanceId ID of the allowance whose spender is being changed
     * @param spender New spender account for the allowance
     */
    function setAllowanceSpender(uint256 allowanceId, address spender) external {
        _validateAuthorizedAddress(spender);

        Allowance storage allowance = _getAllowanceAndValidateAdmin(allowanceId);
        allowance.spender = spender;
        emit AllowanceSpenderChanged(allowanceId, spender);
    }

    /**
     * @notice Changes the name of an allowance
     * @dev Note: This has no on-chain side-effects and only emits an event for off-chain consumption
     * @param allowanceId ID of the allowance whose name is being changed
     * @param name New name for the allowance
     */
    function setAllowanceName(uint256 allowanceId, string memory name) external {
        _getAllowanceAndValidateAdmin(allowanceId);
        emit AllowanceNameChanged(allowanceId, name);
    }

    /**
     * @notice Executes a payment from an allowance
     * @param allowanceId ID of the allowance from which the payment is made
     * @param to Address that will receive the payment
     * @param amount Amount of the allowance's token being sent
     * @param description Description of the payment
     */
    function executePayment(uint256 allowanceId, address to, uint256 amount, string memory description)
        external
        returns (uint40 nextResetTime)
    {
        Allowance storage allowance = _getAllowance(allowanceId);
        address actor = _msgSender();

        if (!_isAuthorized(actor, allowance.spender)) {
            revert UnauthorizedPaymentExecution(allowanceId, actor);
        }

        if (amount == 0) {
            revert ZeroAmountPayment();
        }

        address token = allowance.token;

        // Make sure the payment is within budget all the way up to its top-level budget
        (nextResetTime,) = _checkAndUpdateAllowanceChain(allowanceId, amount, add);

        if (!_performTransfer(token, to, amount)) {
            revert PaymentExecutionFailed(allowanceId, token, to, amount);
        }

        emit PaymentExecuted(allowanceId, actor, token, to, amount, nextResetTime, description);
    }

    /**
     * @notice Executes multiple payments from an allowance
     * @param allowanceId ID of the allowance from which payments are made
     * @param tos Addresses that will receive the payment
     * @param amounts Amounts of the allowance's token being sent
     * @param description Description of the payments
     */
     // Tranfers are great but many DeFI protocols require calling arbitrary
    // methods with ETC20 approval. It seems to make sense for budget to support
    // such functionality. It would be secure enough with a limit ERC20 amount
    // approved
    function executeMultiPayment(
        uint256 allowanceId,
        address[] calldata tos,
        uint256[] calldata amounts,
        string memory description
    ) external returns (uint40 nextResetTime) {
        Allowance storage allowance = _getAllowance(allowanceId);
        address actor = _msgSender();

        if (!_isAuthorized(actor, allowance.spender)) {
            revert UnauthorizedPaymentExecution(allowanceId, actor);
        }

        uint256 count = tos.length;
        if (count != amounts.length || count == 0) {
            revert BadInput();
        }

        uint256 totalAmount = 0;
        for (uint256 i = 0; i < count;) {
            totalAmount += amounts[i];

            unchecked {
                i++;
            }
        }

        (nextResetTime,) = _checkAndUpdateAllowanceChain(allowanceId, totalAmount, add);

        address token = allowance.token;
        if (!_performMultiTransfer(token, tos, amounts)) {
            revert PaymentExecutionFailed(allowanceId, token, address(0), totalAmount);
        }

        emit MultiPaymentExecuted(allowanceId, actor, token, tos, amounts, nextResetTime, description);
    }

    /**
     * @notice Deposit funds into safe debiting funds into an allowance. Frequently used to return a payment
     * @dev Anyone is allowed to perform this action, independently of whether they could have spent funds in the first place
     * @param allowanceId ID of the allowance to be debited (along with its ancester tree)
     * @param amount Amount being debited
     * @param description Description of the debit
     */
    function debitAllowance(uint256 allowanceId, uint256 amount, bytes calldata description)
        external
        payable
        returns (uint40 nextResetTime)
    {
        Allowance storage allowance = _getAllowance(allowanceId);
        address actor = _msgSender();

        // Since funds are going to the safe which is trusted we don't need to follow checks-effects-interactions
        // A malicious token could re-enter, but it would only have effects in allowances for that bad token
        // And we don't need to worry about 'callbacks' since the safe is always the receiver and shouldn't do it
        if (allowance.token != NATIVE_ASSET) {
            if (msg.value != 0) {
                revert NativeValueMismatch();
            }

            // TODO: do we need to make this 'safe'?
            IERC20(allowance.token).transferFrom(actor, address(safe()), amount);
            // TODO: check that safe balance indeed increased by amount
        } else {
            if (msg.value != amount) {
                revert NativeValueMismatch();
            }

            payable(address(safe())).transfer(amount);
            // TODO: check that safe balance indeed increased by amount
        }

        (nextResetTime,) = _checkAndUpdateAllowanceChain(allowanceId, amount, zeroCappedSub);

        emit AllowanceDebited(allowanceId, actor, allowance.token, amount, nextResetTime, description);
    }

    function _performTransfer(address token, address to, uint256 amount) internal returns (bool) {
        if (token == NATIVE_ASSET) {
            // possible reentry attack
            return exec(to, amount, hex"", SafeEnums.Operation.Call);
        } else {
            (bool callSuccess, bytes memory retData) =
                execAndReturnData(token, 0, abi.encodeCall(IERC20.transfer, (to, amount)), SafeEnums.Operation.Call);

            return callSuccess && (((retData.length == 32 && abi.decode(retData, (bool))) || retData.length == 0));
        }
    }

    function _performMultiTransfer(address token, address[] calldata tos, uint256[] calldata amounts)
        internal
        returns (bool)
    {
        bytes memory data = abi.encodeCall(this.__safeContext_performMultiTransfer, (token, tos, amounts));

        (bool callSuccess, bytes memory retData) =
            execAndReturnData(address(_implementation()), 0, data, SafeEnums.Operation.DelegateCall);
        return callSuccess && retData.length == 32 && abi.decode(retData, (bool));
    }

    function __safeContext_performMultiTransfer(address token, address[] calldata tos, uint256[] calldata amounts)
        external
        returns (bool)
    {
        // This function has to be external, but we need to ensure that it cannot be ran
        // if we are on the proxy or impl context
        // There's pressumably nothing malicious that could be done in this contract,
        // but it's a good extra safety check
        if (!_isForeignContext()) {
            revert BadExecutionContext();
        }

        uint256 length = tos.length;

        if (token == NATIVE_ASSET) {
            for (uint256 i = 0; i < length;) {
                (bool callSuccess,) = tos[i].call{value: amounts[i]}(hex"");
                require(callSuccess);
                unchecked {
                    i++;
                }
            }
        } else {
            for (uint256 i = 0; i < length;) {
                (bool callSuccess, bytes memory retData) =
                    token.call(abi.encodeCall(IERC20.transfer, (tos[i], amounts[i])));
                require(callSuccess && (((retData.length == 32 && abi.decode(retData, (bool))) || retData.length == 0)));
                unchecked {
                    i++;
                }
            }
        }

        return true;
    }

    function _getAllowanceAndValidateAdmin(uint256 allowanceId) internal view returns (Allowance storage allowance) {
        allowance = _getAllowance(allowanceId);
        if (!_isAdminOnAllowance(allowance, _msgSender())) {
            revert UnauthorizedNotAllowanceAdmin(allowance.parentId);
        }
    }

    function _getAllowance(uint256 allowanceId) internal view returns (Allowance storage) {
        if (allowanceId == NO_PARENT_ID || allowanceId > allowancesCount) {
            revert UnexistentAllowance(allowanceId);
        }

        return allowances[allowanceId];
    }

    // This can get expensive fast if other modules will keep calling isAdminOnAllowance
    function isAdminOnAllowance(uint256 allowanceId, address actor) public view returns (bool) {
        return _isAdminOnAllowance(_getAllowance(allowanceId), actor);
    }

    function _isAdminOnAllowance(Allowance storage allowance, address actor) internal view returns (bool) {
        // Changes to the allowance state can be done by the same entity that could
        // create that allowance in the first place
        // In the case of top-level allowances, only the safe can enable/disable them
        // For child allowances, spenders of the parent can change the state of the child
        uint256 parentId = allowance.parentId;
        return parentId == NO_PARENT_ID ? actor == address(safe()) : _isAuthorized(actor, allowances[parentId].spender);
    }

    function _checkAndUpdateAllowanceChain(
        uint256 allowanceId,
        uint256 amount,
        function(uint256, uint256) pure returns (uint256) op
    ) internal returns (uint40 nextResetTime, bool allowanceResets) {
        Allowance storage allowance = allowances[allowanceId]; // allowanceId always points to an existing allowance

        if (allowance.isDisabled) {
            revert DisabledAllowance(allowanceId);
        }

        if (allowance.nextResetTime == INHERITED_RESET_TIME) {
            // Note that since top-level allowances are not allowed to have an inherited reset time,
            // this branch is only ever executed for sub-allowances (which always have a parentId)
            // It is certainly possible to run out of gas in this mehtod due to
            // nexted allowances.
            (nextResetTime, allowanceResets) = _checkAndUpdateAllowanceChain(allowance.parentId, amount, op);
        } else {
            nextResetTime = allowance.nextResetTime;

            if (uint40(block.timestamp) >= nextResetTime) {
                allowanceResets = true;
                nextResetTime = uint40(block.timestamp).applyShift(allowance.recurrency);
            }

            if (allowanceResets) {
                allowance.nextResetTime = nextResetTime;
            }

            if (allowance.parentId != NO_PARENT_ID) {
                // Updating every parent would grow liniarly expensive; It be
                // much nicer if it would be possible to update allowance in a
                // constant gas and storage
                _checkAndUpdateAllowanceChain(allowance.parentId, amount, op);
            }
        }

        if (allowance.amount != INHERITED_AMOUNT) {
            uint256 spentAfterPayment = op(allowanceResets ? 0 : allowance.spent, amount);
            if (spentAfterPayment > allowance.amount) {
                revert Overbudget(allowanceId, amount, allowance.amount - allowance.spent);
            }

            allowance.spent = spentAfterPayment;
        }
    }

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        return a + b;
    }

    function zeroCappedSub(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a - b : 0;
    }
}
