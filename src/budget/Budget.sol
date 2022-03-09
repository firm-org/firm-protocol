// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "zodiac/core/Module.sol";

contract Budget is Module {
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
        address spender;
        uint256 spent;
        uint64 nextResetTime;
    }
}
