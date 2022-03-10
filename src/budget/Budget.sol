// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "zodiac/core/Module.sol";

import "./TimeShiftLib.sol";

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
    // ALLOWANCES
    ////////////////////////////////////////////////////////////////////////////////

    struct Allowance {
        address token; // TODO: handle ETH
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

    function createAllowance(address _spender, address _token, uint256 _amount, TimeShiftLib.TimeShift calldata _recurrency) onlyOwner public returns (uint256 allowanceId) {
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

    error ExecutionDisallowed(uint256 allowanceId);
    error Overbudget(uint256 allowanceId);
    event PaymentExecuted(uint256 indexed allowanceId, address indexed token, address indexed to, uint256 amount);

    function executePayment(uint256 _allowanceId, address _to, uint256 _amount) external {
        Allowance storage allowance = getAllowance[_allowanceId];
        
        if (allowance.spender != msg.sender || allowance.isDisabled) revert ExecutionDisallowed(_allowanceId);

        uint64 time = uint64(block.timestamp);
        if (time >= allowance.nextResetTime) {
            allowance.spent = 0;
            allowance.nextResetTime = time.applyShift(allowance.recurrency);
        }

        uint256 newSpent = allowance.spent + _amount;
        if (newSpent > allowance.amount) revert Overbudget(_allowanceId);

        allowance.spent = newSpent;

        _to; // TODO: actually execute the payment

        emit PaymentExecuted(_allowanceId, allowance.token, _to, _amount);
    }
}
