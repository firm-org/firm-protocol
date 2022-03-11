// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "zodiac/core/Module.sol";
import "openzeppelin/interfaces/IERC20.sol";

import "./TimeShiftLib.sol";

address constant ETH = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
contract Budget is Module {
    using TimeShiftLib for uint64;

    ////////////////////////////////////////////////////////////////////////////////
    // SETUP
    ////////////////////////////////////////////////////////////////////////////////

    struct InitParams {
        address owner;
        address avatar;
        address target;
    }

    event BudgetSetup(
        address indexed owner,
        address indexed avatar,
        address indexed target
    );

    constructor(InitParams memory _initParams) {
        setUp(abi.encode(_initParams));
    }

    function setUp(bytes memory _encodedParams) public override initializer {
        InitParams memory _params = abi.decode(_encodedParams, (InitParams));

        __Ownable_init();
        transferOwnership(_params.owner);

        avatar = _params.avatar;
        target = _params.target;

        emit BudgetSetup(_params.owner, _params.avatar, _params.target);
    }

    ////////////////////////////////////////////////////////////////////////////////
    // ALLOWANCE MANAGEMENT
    ////////////////////////////////////////////////////////////////////////////////

    struct Allowance {
        address token;
        uint256 amount;
        address spender; // TODO: consider defining spenders as a role instead
        TimeShiftLib.TimeShift recurrency;

        uint256 spent;
        uint64 nextResetTime;
        bool isDisabled;
    }

    mapping (uint256 => Allowance) public getAllowance;
    uint256 public allowancesCount = 0;

    event AllowanceCreated(
        uint256 indexed allowanceId,
        address indexed spender,
        address indexed token,
        uint256 amount,
        TimeShiftLib.TimeShift recurrency,
        uint64 nextResetTime
    );
    event PaymentExecuted(
        uint256 indexed allowanceId,
        address indexed token,
        address indexed to,
        uint256 amount
    );

    error ExecutionDisallowed(uint256 allowanceId);
    error Overbudget(uint256 allowanceId, address token, address to, uint256 amount, uint256 remainingBudget);
    error ExecutionFailed(uint256 allowanceId, address token, address to, uint256 amount);

    function createAllowance(
        address _spender,
        address _token,
        uint256 _amount,
        TimeShiftLib.TimeShift calldata _recurrency
    ) onlyOwner public returns (uint256 allowanceId) {
        unchecked {
            allowanceId = allowancesCount++;
        }

        Allowance storage allowance = getAllowance[allowanceId];
        allowance.spender = _spender;
        allowance.token = _token;
        allowance.amount = _amount;
        allowance.recurrency = _recurrency;

        uint64 nextResetTime = uint64(block.timestamp).applyShift(_recurrency);
        allowance.nextResetTime = nextResetTime;

        emit AllowanceCreated(allowanceId, _spender, _token, _amount, _recurrency, nextResetTime);
    }

    function executePayment(uint256 _allowanceId, address _to, uint256 _amount) external {
        Allowance storage allowance = getAllowance[_allowanceId];
        
        // Implicitly checks that the allowance exists as if spender hasn't been set, it will revert
        if (allowance.spender != msg.sender || allowance.isDisabled)
            revert ExecutionDisallowed(_allowanceId);

        uint64 time = uint64(block.timestamp);
        address token = allowance.token;

        bool allowanceResets = time >= allowance.nextResetTime;
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

        if (allowanceResets) {
            allowance.nextResetTime = time.applyShift(allowance.recurrency);
            // TODO: Consider emitting an event here
        }
        allowance.spent = spentAfterPayment;

        bool success;
        if (token == ETH) {
            success = exec(_to, _amount, hex"", Enum.Operation.Call);
        } else {
            (bool callSuccess, bytes memory retData) = execAndReturnData(
                token,
                0,
                abi.encodeWithSelector(IERC20.transfer.selector, _to, _amount),
                Enum.Operation.Call
            );

            success = callSuccess
                && ((retData.length == 32 && abi.decode(retData, (bool)) || retData.length == 0));
        }
        if (!success) revert ExecutionFailed(_allowanceId, token, _to, _amount);

        emit PaymentExecuted(_allowanceId, allowance.token, _to, _amount);
    }
}
