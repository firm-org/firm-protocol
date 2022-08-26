// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {IERC20} from "openzeppelin/interfaces/IERC20.sol";

import {UpgradeableModule} from "../bases/UpgradeableModule.sol";
import {ZodiacModule, IAvatar, SafeEnums} from "../bases/ZodiacModule.sol";
import {IRoles, RolesAuth} from "../common/RolesAuth.sol";

import {TimeShiftLib, EncodedTimeShift} from "./TimeShiftLib.sol";

address constant ETH = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
uint256 constant NO_PARENT_ID = 0;

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
    event PaymentExecuted(
        uint256 indexed allowanceId,
        address indexed actor,
        address token,
        address indexed to,
        uint256 amount,
        uint64 nextResetTime,
        string description
    );
    event AllowanceStateChanged(uint256 indexed allowanceId, bool isEnabled);

    error UnexistentAllowance(uint256 allowanceId);
    error DisabledAllowance(uint256 allowanceId);
    error UnauthorizedNotAllowanceAdmin(uint256 allowanceId);
    error TokenMismatch(address patentToken, address childToken);
    error UnauthorizedExecution(uint256 allowanceId, address actor);
    error Overbudget(uint256 allowanceId, address token, address to, uint256 amount, uint256 remainingBudget);
    error ExecutionFailed(uint256 allowanceId, address token, address to, uint256 amount);

    function createAllowance(
        uint256 _parentAllowanceId,
        address _spender,
        address _token,
        uint256 _amount,
        EncodedTimeShift _recurrency,
        string memory _name
    )
        public
        returns (uint256 allowanceId)
    {
        uint64 nextResetTime;

        if (_parentAllowanceId == NO_PARENT_ID) {
            // Top-level allowances can only be created by the avatar
            if (msg.sender != address(safe())) {
                revert UnauthorizedNotAllowanceAdmin(NO_PARENT_ID);
            }

            // For top-level allowances, _recurrency needs to be set and cannot be zero
            // applyShift reverts with InvalidTimeShift if _recurrency is unspecified
            // Therefore, nextResetTime is implicitly ensured to always be greater than the current time
            nextResetTime = uint64(block.timestamp).applyShift(_recurrency);
        } else {
            Allowance storage parentAllowance = _getAllowance(_parentAllowanceId);
            // Not checking whether the parentAllowance is enabled is a explicit decision
            // Disabling any allowance in a given allowance chain will result in the child-most
            // allowance being disabled and payments not executable.
            // This allows for disabling a certain allowance to reconfigure the whole tree
            // of suballowances below it, before enabling it again

            // Sub-allowances can be created by entities authorized to spend from a particular allowance
            if (!_isAuthorized(msg.sender, parentAllowance.spender)) {
                revert UnauthorizedNotAllowanceAdmin(_parentAllowanceId);
            }
            if (_token != parentAllowance.token) {
                revert TokenMismatch(parentAllowance.token, _token);
            }
            // Recurrency can be zero in sub-allowances and is inherited from the parent
            if (!_recurrency.isInherited()) {
                // Will revert with InvalidTimeShift if _recurrency is invalid
                nextResetTime = uint64(block.timestamp).applyShift(_recurrency);
            }
        }

        unchecked {
            allowanceId = ++allowancesCount;
        }

        Allowance storage allowance = allowances[allowanceId];
        if (_parentAllowanceId != 0) {
            allowance.parentId = _parentAllowanceId;
        }
        if (nextResetTime != 0) {
            allowance.recurrency = _recurrency;
            allowance.nextResetTime = nextResetTime;
        }
        allowance.spender = _spender;
        allowance.token = _token;
        allowance.amount = _amount;

        emit AllowanceCreated(
            allowanceId, _parentAllowanceId, _spender, _token, _amount, _recurrency, nextResetTime, _name
            );
    }

    function setAllowanceState(uint256 _allowanceId, bool _isEnabled) external {
        Allowance storage allowance = _getAllowance(_allowanceId);

        if (!_isAdminOnAllowance(allowance, msg.sender)) {
            revert UnauthorizedNotAllowanceAdmin(allowance.parentId);
        }
        allowance.isDisabled = !_isEnabled;

        emit AllowanceStateChanged(_allowanceId, _isEnabled);
    }

    function _isAdminOnAllowance(Allowance storage allowance, address actor) internal view returns (bool) {
        // Changes to the allowance state can be done by the same entity that could
        // create that allowance in the first place
        // In the case of top-level allowances, only the safe can enable/disable them
        // For child allowances, spenders of the parent can change the state of the child
        uint256 parentId = allowance.parentId;
        return
            parentId == NO_PARENT_ID
            ? actor == address(safe())
            : _isAuthorized(actor, allowances[parentId].spender);
    }

    function executePayment(uint256 _allowanceId, address _to, uint256 _amount, string memory _description) external {
        Allowance storage allowance = _getAllowance(_allowanceId);

        if (!_isAuthorized(msg.sender, allowance.spender)) {
            revert UnauthorizedExecution(_allowanceId, msg.sender);
        }

        address token = allowance.token;

        (uint64 nextResetTime,) = _checkAndUpdateAllowanceChain(_allowanceId, token, _to, _amount);

        bool success;
        if (token == ETH) {
            success = exec(_to, _amount, hex"", SafeEnums.Operation.Call);
        } else {
            (bool callSuccess, bytes memory retData) =
                execAndReturnData(token, 0, abi.encodeCall(IERC20.transfer, (_to, _amount)), SafeEnums.Operation.Call);

            success = callSuccess && (((retData.length == 32 && abi.decode(retData, (bool))) || retData.length == 0));
        }
        if (!success) {
            revert ExecutionFailed(_allowanceId, token, _to, _amount);
        }

        emit PaymentExecuted(_allowanceId, msg.sender, allowance.token, _to, _amount, nextResetTime, _description);
    }

    function _getAllowance(uint256 allowanceId) internal view returns (Allowance storage) {
        if (allowanceId > allowancesCount) {
            revert UnexistentAllowance(allowanceId);
        }

        return allowances[allowanceId];
    }

    function _checkAndUpdateAllowanceChain(uint256 _allowanceId, address _token, address _to, uint256 _amount)
        internal
        returns (uint64 nextResetTime, bool allowanceResets)
    {
        Allowance storage allowance = allowances[_allowanceId]; // _allowanceId always points to an existing allowance

        if (allowance.isDisabled) {
            revert DisabledAllowance(_allowanceId);
        }

        if (allowance.nextResetTime == 0) {
            // Sub-budget's recurrency is inherited from parent
            (nextResetTime, allowanceResets) = _checkAndUpdateAllowanceChain(allowance.parentId, _token, _to, _amount);
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
                _checkAndUpdateAllowanceChain(allowance.parentId, _token, _to, _amount);
            }
        }

        uint256 spentAfterPayment = (allowanceResets ? 0 : allowance.spent) + _amount;
        if (spentAfterPayment > allowance.amount) {
            revert Overbudget(_allowanceId, _token, _to, _amount, allowance.amount - allowance.spent);
        }

        allowance.spent = spentAfterPayment;
    }
}
