// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {IERC20} from "openzeppelin/interfaces/IERC20.sol";

import {UpgradeableModule} from "../bases/UpgradeableModule.sol";
import {ZodiacModule, IAvatar, SafeEnums} from "../bases/ZodiacModule.sol";
import {IRoles, RolesAuth} from "../common/RolesAuth.sol";

import {TimeShiftLib, EncodedTimeShift} from "./TimeShiftLib.sol";

address constant ETH = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
uint256 constant NO_PARENT_ID = 0;
uint64 constant INHERITED_RESET_TIME = 0;

contract Budget is UpgradeableModule, ZodiacModule, RolesAuth {
    string public constant moduleId = "org.firm.budget";
    uint256 public constant moduleVersion = 0;

    using TimeShiftLib for uint64;

    ////////////////////////////////////////////////////////////////////////////////
    // INITIALIZATION
    ////////////////////////////////////////////////////////////////////////////////

    constructor(IAvatar _safe, IRoles _roles) {
        initialize(_safe, _roles);
    }

    function initialize(IAvatar _safe, IRoles _roles) public {
        __init_setSafe(_safe); // SafeAware.__init_setSafe reverts on reinitialization
        roles = _roles;
    }

    ////////////////////////////////////////////////////////////////////////////////
    // ALLOWANCE MANAGEMENT
    ////////////////////////////////////////////////////////////////////////////////

    struct Allowance {
        uint256 parentId;
        uint256 amount;
        uint256 spent;
        address token;
        uint64 nextResetTime;
        address spender;
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
        uint64 nextResetTime,
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
        uint64 nextResetTime,
        string description
    );

    error UnexistentAllowance(uint256 allowanceId);
    error DisabledAllowance(uint256 allowanceId);
    error UnauthorizedNotAllowanceAdmin(uint256 allowanceId);
    error TokenMismatch(address patentToken, address childToken);
    error UnauthorizedPaymentExecution(uint256 allowanceId, address actor);
    error Overbudget(uint256 allowanceId, address token, address to, uint256 amount, uint256 remainingBudget);
    error PaymentExecutionFailed(uint256 allowanceId, address token, address to, uint256 amount);

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
    )
        public
        returns (uint256 allowanceId)
    {
        uint64 nextResetTime;

        if (parentAllowanceId == NO_PARENT_ID) {
            // Top-level allowances can only be created by the Safe
            if (msg.sender != address(safe())) {
                revert UnauthorizedNotAllowanceAdmin(NO_PARENT_ID);
            }

            // For top-level allowances, recurrency needs to be set and cannot be zero
            // applyShift reverts with InvalidTimeShift if recurrency is unspecified
            // Therefore, nextResetTime is always greater than the current time
            nextResetTime = uint64(block.timestamp).applyShift(recurrency);
        } else {
            Allowance storage parentAllowance = _getAllowance(parentAllowanceId);

            // Not checking whether the parentAllowance is enabled is a explicit decision
            // Disabling any allowance in a given allowance chain will result in all its
            // childs not being able to execute payments
            // This allows for disabling a certain allowance to reconfigure the whole tree
            // of suballowances below it, before enabling it again

            // Sub-allowances can be created by entities authorized to spend from a particular allowance
            if (!_isAuthorized(msg.sender, parentAllowance.spender)) {
                revert UnauthorizedNotAllowanceAdmin(parentAllowanceId);
            }
            if (token != parentAllowance.token) {
                revert TokenMismatch(parentAllowance.token, token);
            }
            // Recurrency can be zero in sub-allowances and is inherited from the parent
            if (!recurrency.isInherited()) {
                // Will revert with InvalidTimeShift if _recurrency is invalid
                nextResetTime = uint64(block.timestamp).applyShift(recurrency);
            }
        }

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
     * @dev Note: Disabling an allowance will implictly disable payments from all its descendant allowances
     * @param allowanceId ID of the allowance whose state is being changed
     * @param isEnabled Whether to enable or disable the allowance
     */
    function setAllowanceState(uint256 allowanceId, bool isEnabled) external {
        Allowance storage allowance = _getAllowance(allowanceId);

        if (!_isAdminOnAllowance(allowance, msg.sender)) {
            revert UnauthorizedNotAllowanceAdmin(allowance.parentId);
        }
        allowance.isDisabled = !isEnabled;

        emit AllowanceStateChanged(allowanceId, isEnabled);
    }

    /**
     * @notice Changes the amount that an allowance can spend
     * @dev Note: It is possible to decrease the amount in an allowance to a smaller amount of what's already been spent
     * which will cause the allowance not to be able to execute any more payments until it resets (and the new amount will be enforced)
     * @param allowanceId ID of the allowance whose amount is being changed
     * @param amount Whether to enable or disable the allowance
     */
    function setAllowanceAmount(uint256 allowanceId, uint256 amount) external {
        Allowance storage allowance = _getAllowance(allowanceId);

        if (!_isAdminOnAllowance(allowance, msg.sender)) {
            revert UnauthorizedNotAllowanceAdmin(allowance.parentId);
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
        Allowance storage allowance = _getAllowance(allowanceId);

        if (!_isAdminOnAllowance(allowance, msg.sender)) {
            revert UnauthorizedNotAllowanceAdmin(allowance.parentId);
        }
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
        Allowance storage allowance = _getAllowance(allowanceId);

        if (!_isAdminOnAllowance(allowance, msg.sender)) {
            revert UnauthorizedNotAllowanceAdmin(allowance.parentId);
        }

        emit AllowanceNameChanged(allowanceId, name);
    }

    /**
     * @notice Executes a payment from an allowance
     * @param allowanceId ID of the allowance from which the payment is made
     * @param to Address that will receive the payment
     * @param amount Amount of the allowance's token being sent
     * @param description Description of the payment
     */
    function executePayment(uint256 allowanceId, address to, uint256 amount, string memory description) external {
        Allowance storage allowance = _getAllowance(allowanceId);

        if (!_isAuthorized(msg.sender, allowance.spender)) {
            revert UnauthorizedPaymentExecution(allowanceId, msg.sender);
        }

        address token = allowance.token;
        // Make sure the payment is within budget all the way up to its top-level budget
        (uint64 nextResetTime,) = _checkAndUpdateAllowanceChain(allowanceId, token, to, amount);

        bool success;
        if (token == ETH) {
            success = exec(to, amount, hex"", SafeEnums.Operation.Call);
        } else {
            (bool callSuccess, bytes memory retData) =
                execAndReturnData(token, 0, abi.encodeCall(IERC20.transfer, (to, amount)), SafeEnums.Operation.Call);

            success = callSuccess && (((retData.length == 32 && abi.decode(retData, (bool))) || retData.length == 0));
        }
        if (!success) {
            revert PaymentExecutionFailed(allowanceId, token, to, amount);
        }

        emit PaymentExecuted(allowanceId, msg.sender, allowance.token, to, amount, nextResetTime, description);
    }

    function _getAllowance(uint256 allowanceId) internal view returns (Allowance storage) {
        if (allowanceId > allowancesCount) {
            revert UnexistentAllowance(allowanceId);
        }

        return allowances[allowanceId];
    }

    function _isAdminOnAllowance(Allowance storage allowance, address actor) internal view returns (bool) {
        // Changes to the allowance state can be done by the same entity that could
        // create that allowance in the first place
        // In the case of top-level allowances, only the safe can enable/disable them
        // For child allowances, spenders of the parent can change the state of the child
        uint256 parentId = allowance.parentId;
        return parentId == NO_PARENT_ID ? actor == address(safe()) : _isAuthorized(actor, allowances[parentId].spender);
    }

    function _checkAndUpdateAllowanceChain(uint256 allowanceId, address token, address to, uint256 amount)
        internal
        returns (uint64 nextResetTime, bool allowanceResets)
    {
        Allowance storage allowance = allowances[allowanceId]; // allowanceId always points to an existing allowance

        if (allowance.isDisabled) {
            revert DisabledAllowance(allowanceId);
        }

        if (allowance.nextResetTime == 0) {
            // Sub-budget's recurrency is inherited from parent
            (nextResetTime, allowanceResets) = _checkAndUpdateAllowanceChain(allowance.parentId, token, to, amount);
        } else {
            nextResetTime = allowance.nextResetTime;

            if (uint64(block.timestamp) >= nextResetTime) {
                allowanceResets = true;
                nextResetTime = uint64(block.timestamp).applyShift(allowance.recurrency);
            }

            if (allowanceResets) {
                // TODO: Consider emitting an event here since the 'spent' field in other suballowances that depend
                // on this one won't be updated on-chain until they are touched
                allowance.nextResetTime = nextResetTime;
            }

            if (allowance.parentId != NO_PARENT_ID) {
                _checkAndUpdateAllowanceChain(allowance.parentId, token, to, amount);
            }
        }

        uint256 spentAfterPayment = (allowanceResets ? 0 : allowance.spent) + amount;
        if (spentAfterPayment > allowance.amount) {
            revert Overbudget(allowanceId, token, to, amount, allowance.amount - allowance.spent);
        }

        allowance.spent = spentAfterPayment;
    }
}
