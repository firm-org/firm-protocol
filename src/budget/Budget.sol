

// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import "openzeppelin/interfaces/IERC20.sol";

import "../common/FirmModule.sol";
import "../common/RolesAuth.sol";

import "./TimeShiftLib.sol";

address constant ETH = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

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
        address indexed spender,
        address indexed token,
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

    error ExecutionDisallowed(uint256 allowanceId, address actor);
    error Overbudget(uint256 allowanceId, address token, address to, uint256 amount, uint256 remainingBudget);
    error ExecutionFailed(uint256 allowanceId, address token, address to, uint256 amount);

    function createAllowance(
        address _spender,
        address _token,
        uint256 _amount,
        EncodedTimeShift _recurrency
    ) onlyAvatar public returns (uint256 allowanceId) {
        // Will revert with InvalidTimeShift if _recurrency is invalid
        uint64 nextResetTime = uint64(block.timestamp).applyShift(_recurrency);

        unchecked {
            allowanceId = allowancesCount++;
        }

        Allowance storage allowance = getAllowance[allowanceId];
        allowance.spender = _spender;
        allowance.token = _token;
        allowance.amount = _amount;
        allowance.recurrency = _recurrency;
        allowance.nextResetTime = nextResetTime;

        emit AllowanceCreated(allowanceId, _spender, _token, _amount, _recurrency, nextResetTime);
    }

    function executePayment(uint256 _allowanceId, address _to, uint256 _amount) external {
        Allowance storage allowance = getAllowance[_allowanceId];
        
        // Implicitly checks that the allowance exists as if spender hasn't been set, it will revert
        if (!_isAuthorized(msg.sender, allowance.spender) || allowance.isDisabled)
            revert ExecutionDisallowed(_allowanceId, msg.sender);

        address token = allowance.token;
        uint64 nextResetTime = allowance.nextResetTime;

        bool allowanceResets = uint64(block.timestamp) >= nextResetTime;
        uint256 spentAfterPayment = (allowanceResets ? 0 : allowance.spent) + _amount;
        if (spentAfterPayment > allowance.amount) {
            revert Overbudget(
                _allowanceId,
                token,
                _to,
                _amount,
                allowance.amount - allowance.spent
            );
        }

        allowance.spent = spentAfterPayment;
        if (allowanceResets) {
            nextResetTime = uint64(block.timestamp).applyShift(allowance.recurrency);
            allowance.nextResetTime = nextResetTime;
        }

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
        if (!success) revert ExecutionFailed(_allowanceId, token, _to, _amount);

        emit PaymentExecuted(_allowanceId, msg.sender, allowance.token, _to, _amount, nextResetTime);
    }
}
