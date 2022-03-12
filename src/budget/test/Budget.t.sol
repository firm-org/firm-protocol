// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "solmate/test/utils/DSTestPlus.sol";
import "zodiac/factory/ModuleProxyFactory.sol";

import "../Budget.sol";
import "./lib/AvatarStub.sol";

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

contract BudgetAllowanceTest is DSTestPlus {
    using TimeShiftLib for *;

    AvatarStub avatar;
    Budget budget;

    address internal constant OWNER = address(1);
    address internal constant SPENDER = address(5);

    function setUp() public virtual {
        avatar = new AvatarStub();
        budget = new Budget(Budget.InitParams(OWNER, address(avatar), address(avatar)));
    }

    function testCreateAllowance() public {
        hevm.prank(OWNER);
        createDailyAllowance(0);        
    }

    function testNotOwnerCannotCreateAllowance() public {
        hevm.expectRevert(
            bytes("Ownable: caller is not the owner")
        );
        createDailyAllowance(0);
    }

    function testAllowanceIsKeptTrackOf() public {
        uint64 initialTime = uint64(DateTimeLib.timestampFromDateTime(2022, 1, 1, 0, 0, 0));

        hevm.prank(OWNER);
        hevm.warp(initialTime);
        createDailyAllowance(0);

        hevm.startPrank(SPENDER);
        
        budget.executePayment(0, OWNER, 7);

        hevm.warp(initialTime + 1 days);
        budget.executePayment(0, OWNER, 7);
        budget.executePayment(0, OWNER, 2);

        hevm.expectRevert(abi.encodeWithSelector(Budget.Overbudget.selector, 0, address(0), OWNER, 7, 1));
        budget.executePayment(0, OWNER, 7);
    }

    function testMultipleAllowances() public {
        uint64 initialTime = uint64(DateTimeLib.timestampFromDateTime(2022, 1, 1, 0, 0, 0));

        hevm.startPrank(OWNER);
        hevm.warp(initialTime);
        createDailyAllowance(0);
        createDailyAllowance(1);

        hevm.startPrank(SPENDER);
        budget.executePayment(0, OWNER, 7);
        budget.executePayment(1, OWNER, 7);

        hevm.warp(initialTime + 1 days);
        budget.executePayment(0, OWNER, 7);
        budget.executePayment(1, OWNER, 7);
    }

    function createDailyAllowance(uint256 expectedId) public {
        uint256 allowanceId = budget.createAllowance(
            SPENDER,
            address(0),
            10,
            TimeShiftLib.TimeShift(TimeShiftLib.TimeUnit.Daily, 0).encode()
        );
        assertEq(allowanceId, expectedId);
    }
}
