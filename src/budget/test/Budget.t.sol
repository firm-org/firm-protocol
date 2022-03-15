// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "solmate/test/utils/DSTestPlus.sol";
import "zodiac/factory/ModuleProxyFactory.sol";

import "../../common/test/lib/RolesStub.sol";
import {roleFlag} from "../../common/test/lib/RolesAuthMock.sol";

import "../Budget.sol";
import "./lib/AvatarStub.sol";

contract BudgetInitTest is DSTestPlus {
    Budget budget;

    address internal constant OWNER = address(1);
    address internal constant AVATAR = address(2);
    address internal constant TARGET = address(3);
    address internal constant ROLES = address(4);

    function setUp() public virtual {
        budget = new Budget(Budget.InitParams(OWNER, AVATAR, TARGET, ROLES));
    }

    function testInitialState() public {
        assertEq(budget.owner(), OWNER);
        assertEq(budget.avatar(), AVATAR);
        assertEq(budget.target(), TARGET);
        assertEq(address(budget.roles()), ROLES);
    }

    function testCannotReinit() public {
        hevm.expectRevert(
            bytes("Initializable: contract is already initialized")
        );
        budget.setUp(abi.encode(Budget.InitParams(OWNER, AVATAR, TARGET, ROLES)));
    }
}

contract BudgetWithProxyInitTest is BudgetInitTest {
    ModuleProxyFactory immutable factory = new ModuleProxyFactory();
    Budget immutable budgetImpl =
        new Budget(Budget.InitParams(address(10), address(10), address(10), address(10)));

    function setUp() public override {
        budget = Budget(
            factory.deployModule(
                address(budgetImpl),
                abi.encodeWithSelector(
                    budgetImpl.setUp.selector,
                    abi.encode(Budget.InitParams(OWNER, AVATAR, TARGET, ROLES))
                ),
                0
            )
        );
    }
}

contract BudgetAllowanceTest is DSTestPlus {
    using TimeShiftLib for *;

    AvatarStub avatar;
    RolesStub roles;
    Budget budget;

    address internal constant OWNER = address(1);
    address internal constant SPENDER = address(5);

    function setUp() public virtual {
        avatar = new AvatarStub();
        roles = new RolesStub();
        budget = new Budget(Budget.InitParams(OWNER, address(avatar), address(avatar), address(roles)));
    }

    function testCreateAllowance() public {
        uint256 allowanceId = 0;
        hevm.prank(OWNER);
        hevm.warp(0);
        createDailyAllowance(SPENDER, allowanceId);
        (
            uint256 amount,
            uint256 spent,
            address token,
            uint64 nextResetTime,
            address spender,
            EncodedTimeShift recurrency,
            bool isDisabled
        ) = budget.getAllowance(allowanceId);

        assertEq(amount, 10);
        assertEq(spent, 0);
        assertEq(token, address(0));
        assertEq(nextResetTime, 1 days);
        assertEq(spender, SPENDER);
        assertEq(
            bytes32(EncodedTimeShift.unwrap(recurrency)),
            bytes32(EncodedTimeShift.unwrap(TimeShiftLib.TimeShift(TimeShiftLib.TimeUnit.Daily, 0).encode()))
        );
        assertFalse(isDisabled);
    }

    function testNotOwnerCannotCreateAllowance() public {
        hevm.expectRevert(
            bytes("Ownable: caller is not the owner")
        );
        createDailyAllowance(SPENDER, 0);
    }

    function testAllowanceIsKeptTrackOf() public {
        uint64 initialTime = uint64(DateTimeLib.timestampFromDateTime(2022, 1, 1, 0, 0, 0));
        uint256 allowanceId = 0;

        hevm.prank(OWNER);
        hevm.warp(initialTime);
        createDailyAllowance(SPENDER, allowanceId);

        assertExecutePayment(SPENDER, allowanceId, OWNER, 7, initialTime + 1 days);

        hevm.warp(initialTime + 1 days);
        assertExecutePayment(SPENDER, allowanceId, OWNER, 7, initialTime + 2 days);
        assertExecutePayment(SPENDER, allowanceId, OWNER, 2, initialTime + 2 days);

        hevm.prank(SPENDER);
        hevm.expectRevert(abi.encodeWithSelector(Budget.Overbudget.selector, 0, address(0), OWNER, 7, 1));
        budget.executePayment(allowanceId, OWNER, 7);
    }

    function testMultipleAllowances() public {
        uint64 initialTime = uint64(DateTimeLib.timestampFromDateTime(2022, 1, 1, 0, 0, 0));

        hevm.startPrank(OWNER);
        hevm.warp(initialTime);
        createDailyAllowance(SPENDER, 0);
        createDailyAllowance(SPENDER, 1);

        assertExecutePayment(SPENDER, 0, OWNER, 7, initialTime + 1 days);
        assertExecutePayment(SPENDER, 1, OWNER, 7, initialTime + 1 days);

        hevm.warp(initialTime + 1 days);
        assertExecutePayment(SPENDER, 0, OWNER, 7, initialTime + 2 days);
        assertExecutePayment(SPENDER, 1, OWNER, 7, initialTime + 2 days);
    }

    function testCantExecuteIfNotAuthorized() public {
        hevm.startPrank(OWNER);
        createDailyAllowance(SPENDER, 0);
        
        hevm.expectRevert(abi.encodeWithSelector(Budget.ExecutionDisallowed.selector, 0, OWNER));
        budget.executePayment(0, OWNER, 7);
    }

    function testCantExecuteInexistentAllowance() public {
        hevm.prank(SPENDER);
        hevm.expectRevert(abi.encodeWithSelector(Budget.ExecutionDisallowed.selector, 0, SPENDER));
        budget.executePayment(0, OWNER, 7);
    }

    function testAllowanceSpenderWithRoleFlags() public {
        uint8 roleId = 1;
        hevm.prank(OWNER);
        createDailyAllowance(roleFlag(roleId), 0);

        hevm.startPrank(SPENDER);
        hevm.expectRevert(abi.encodeWithSelector(Budget.ExecutionDisallowed.selector, 0, SPENDER));
        budget.executePayment(0, OWNER, 7); // execution fails since SPENDER doesn't have the required role yet

        roles.setRole(SPENDER, roleId, true);
        budget.executePayment(0, OWNER, 7); // as soon as it gets the role, the payment executes
    }

    function createDailyAllowance(address spender, uint256 expectedId) public {
        uint256 allowanceId = budget.createAllowance(
            spender,
            address(0),
            10,
            TimeShiftLib.TimeShift(TimeShiftLib.TimeUnit.Daily, 0).encode()
        );
        assertEq(allowanceId, expectedId);
    }

    event PaymentExecuted(
        uint256 indexed allowanceId,
        address indexed actor,
        address token,
        address indexed to,
        uint256 amount,
        uint64 nextResetTime
    );
    function assertExecutePayment(address actor, uint256 allowanceId, address to, uint256 amount, uint64 expectedNextResetTime) public {
        (,uint256 initialSpent, address token, uint64 initialNextReset,,,) = budget.getAllowance(allowanceId);

        if (block.timestamp >= initialNextReset) {
            initialSpent = 0;
        }

        hevm.prank(actor);
        hevm.expectEmit(true, true, true, true);
        emit PaymentExecuted(allowanceId, actor, token, to, amount, expectedNextResetTime);
        budget.executePayment(allowanceId, to, amount);

        (,uint256 spent,,uint64 nextResetTime,,,) = budget.getAllowance(allowanceId);

        assertEq(spent, initialSpent + amount);
        assertEq(nextResetTime, expectedNextResetTime);
    }
}
