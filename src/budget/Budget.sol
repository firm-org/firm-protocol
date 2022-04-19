// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import "openzeppelin/interfaces/IERC20.sol";

import "../common/FirmModule.sol";
import "../common/RolesAuth.sol";

import "./TimeShiftLib.sol";

address constant ETH = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
uint256 constant NO_PARENT_ID = 0;

contract Budget is FirmModule, RolesAuth {
    using TimeShiftLib for uint64;

    ////////////////////////////////////////////////////////////////////////////////
    // SETUP
    ////////////////////////////////////////////////////////////////////////////////

    event BudgetSetup(
        IAvatar avatar,
        IAvatar target,
        IRoles roles
    );

    struct InitParams {
        IAvatar avatar;
        IAvatar target;
        IRoles roles;
    }

    constructor(InitParams memory _initParams) {
        setUp(_initParams);
    }

    function setUp(InitParams memory _params) public {
        initialize(_params.avatar, _params.target); // reverts on reinitialization
        roles = _params.roles;

        emit BudgetSetup(_params.avatar, _params.target, _params.roles);
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

    mapping (uint256 => Allowance) public getAllowance;
    uint256 public allowancesCount = 0;

    event AllowanceCreated(
        uint256 indexed allowanceId,
        uint256 indexed parentAllowanceId,
        address indexed spender,
        address token,
        uint256 amount,
        EncodedTimeShift recurrency,
        uint64 nextResetTime
    );
    event PaymentExecuted(
        uint256 indexed allowanceId,
        address indexed actor,
        address token,
        address indexed to,
        uint256 amount,
        uint64 nextResetTime
    );

    error UnauthorizedForAllowance(uint256 allowanceId, address actor);
    error TokenMismatch(address token);
    error ExecutionDisallowed(uint256 allowanceId, address actor);
    error Overbudget(uint256 allowanceId, address token, address to, uint256 amount, uint256 remainingBudget);
    error ExecutionFailed(uint256 allowanceId, address token, address to, uint256 amount);

    function createAllowance(
        uint256 _parentAllowanceId,
        address _spender,
        address _token,
        uint256 _amount,
        EncodedTimeShift _recurrency
    ) public returns (uint256 allowanceId) {
        uint64 nextResetTime;

        if (_parentAllowanceId == NO_PARENT_ID) {
            // For top-level allowances, _recurrency needs to be set and cannot be zero
            // applyShift reverts with InvalidTimeShift if _recurrency is unspecified
            // Therefore, nextResetTime is implicitly ensured to always be greater than the current time
            nextResetTime = uint64(block.timestamp).applyShift(_recurrency);

            // Top-level allowances can only be created by the avatar
            if (msg.sender != address(moduleState().avatar))
                revert UnauthorizedNotAvatar();
        } else {
            // Sub-allowances can be created by entities authorized to spend from a particular allowance
            // Implicit check that the allowanceId exists as there's 
            if (!_isAuthorized(msg.sender, getAllowance[_parentAllowanceId].spender))
                revert UnauthorizedForAllowance(_parentAllowanceId, msg.sender);
            if (_token != getAllowance[_parentAllowanceId].token)
                revert TokenMismatch(_token);

            // Recurrency can be zero in sub-allowances and is inherited from the parent
            if (!_recurrency.isInherited()) {
                // Will revert with InvalidTimeShift if _recurrency is invalid
                nextResetTime = uint64(block.timestamp).applyShift(_recurrency);
            }
        }

        unchecked {
            allowanceId = ++allowancesCount;
        }

        Allowance storage allowance = getAllowance[allowanceId];
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
            allowanceId,
            _parentAllowanceId,
            _spender,
            _token,
            _amount,
            _recurrency,
            nextResetTime
        );
    }

    function executePayment(uint256 _allowanceId, address _to, uint256 _amount) external {
        Allowance storage allowance = getAllowance[_allowanceId];
        
        // Implicitly checks that the allowance exists as if spender hasn't been set, it will revert
        if (!_isAuthorized(msg.sender, allowance.spender) || allowance.isDisabled)
            revert ExecutionDisallowed(_allowanceId, msg.sender);

        address token = allowance.token;

        (uint64 nextResetTime,) = _checkAndUpdateAllowanceChain(_allowanceId, token, _to, _amount);
        
        bool success;
        if (token == ETH) {
            success = exec(_to, _amount, hex"", Enum.Operation.Call);
        } else {
            (bool callSuccess, bytes memory retData) = execAndReturnData(
                token,
                0,
                abi.encodeCall(IERC20.transfer, (_to, _amount)),
                Enum.Operation.Call
            );

            success = callSuccess
                && ((retData.length == 32 && abi.decode(retData, (bool)) || retData.length == 0));
        }
        if (!success)
            revert ExecutionFailed(_allowanceId, token, _to, _amount);

        emit PaymentExecuted(_allowanceId, msg.sender, allowance.token, _to, _amount, nextResetTime);
    }

    function _checkAndUpdateAllowanceChain(
        uint256 _allowanceId,
        address _token,
        address _to,
        uint256 _amount
    )
        internal
        returns (uint64 nextResetTime, bool allowanceResets)
    {
        Allowance storage allowance = getAllowance[_allowanceId];
    
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
            revert Overbudget(
                _allowanceId,
                _token,
                _to,
                _amount,
                allowance.amount - allowance.spent
            );
        }

        allowance.spent = spentAfterPayment;
    }
}
