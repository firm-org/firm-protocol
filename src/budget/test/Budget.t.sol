// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "solmate/test/utils/DSTestPlus.sol";
import "zodiac/factory/ModuleProxyFactory.sol";

import "../Budget.sol";

contract BudgetInitTest is DSTestPlus {
    Budget budget;

    address internal constant OWNER = address(1);
    address internal constant AVATAR = address(2);
    address internal constant TARGET = address(3);

    function setUp() public virtual {
        budget = new Budget(Budget.InitParams(OWNER, AVATAR, TARGET));
    }

    function testInitialState() public {
        assertEq(budget.owner(), OWNER);
        assertEq(budget.avatar(), AVATAR);
        assertEq(budget.target(), TARGET);
    }

    function testCannotReinit() public {
        hevm.expectRevert(
            bytes("Initializable: contract is already initialized")
        );
        budget.setUp(abi.encode(Budget.InitParams(OWNER, AVATAR, TARGET)));
    }
}

contract BudgetWithProxyInitTest is BudgetInitTest {
    ModuleProxyFactory immutable factory = new ModuleProxyFactory();
    Budget immutable budgetImpl =
        new Budget(Budget.InitParams(address(10), address(10), address(10)));

    function setUp() public override {
        budget = Budget(
            factory.deployModule(
                address(budgetImpl),
                abi.encodeWithSelector(
                    budgetImpl.setUp.selector,
                    abi.encode(Budget.InitParams(OWNER, AVATAR, TARGET))
                ),
                0
            )
        );
    }
}
