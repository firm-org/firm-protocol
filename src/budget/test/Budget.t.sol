// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {FirmTest} from "../../common/test/lib/FirmTest.sol";
import {RolesStub} from "../../common/test/mocks/RolesStub.sol";
import {roleFlag} from "../../common/test/mocks/RolesAuthMock.sol";
import {AvatarStub} from "../../common/test/mocks/AvatarStub.sol";
import {UpgradeableModuleProxyFactory} from "../../factory/UpgradeableModuleProxyFactory.sol";

import {TimeShift, DateTimeLib} from "../../budget/TimeShiftLib.sol";
import {SafeAware} from "../../bases/SafeAware.sol";
import "../Budget.sol";

contract BudgetTest is FirmTest {
    AvatarStub avatar;
    RolesStub roles;
    Budget budget;

    address SPENDER = account("spender");
    address RECEIVER = account("receiver");
    address SOMEONE_ELSE = account("someone else");

    function setUp() public virtual {
        avatar = new AvatarStub();
        roles = new RolesStub();
        budget = new Budget(avatar, roles);
    }

    function testInitialState() public {
        assertEq(address(budget.avatar()), address(avatar));
        assertEq(address(budget.target()), address(avatar));
        assertEq(address(budget.roles()), address(roles));
    }

    function testCannotReinit() public {
        vm.expectRevert(
            abi.encodeWithSelector(SafeAware.AlreadyInitialized.selector)
        );
        budget.initialize(avatar, roles);
    }

    function testCreateAllowance() public {
        uint256 allowanceId = 1;
        vm.prank(address(avatar));
        vm.warp(0);
        createDailyAllowance(SPENDER, allowanceId);
        (
            uint256 parentId,
            uint256 amount,
            uint256 spent,
            address token,
            uint64 nextResetTime,
            address spender,
            EncodedTimeShift recurrency,
            bool isDisabled
        ) = budget.getAllowance(allowanceId);

        assertEq(parentId, NO_PARENT_ID);
        assertEq(amount, 10);
        assertEq(spent, 0);
        assertEq(token, address(0));
        assertEq(nextResetTime, 1 days);
        assertEq(spender, SPENDER);
        assertEq(
            bytes32(EncodedTimeShift.unwrap(recurrency)),
            bytes32(
                EncodedTimeShift.unwrap(
                    TimeShift(TimeShiftLib.TimeUnit.Daily, 0).encode()
                )
            )
        );
        assertFalse(isDisabled);
    }

    function testNotOwnerCannotCreateAllowance() public {
        vm.expectRevert(
            abi.encodeWithSelector(SafeAware.UnauthorizedNotSafe.selector)
        );
        createDailyAllowance(SPENDER, 0);
    }

    function testBadTimeshiftsRevert() public {
        vm.startPrank(address(avatar));

        vm.expectRevert(
            abi.encodeWithSelector(TimeShiftLib.InvalidTimeShift.selector)
        );
        budget.createAllowance(
            NO_PARENT_ID,
            SPENDER,
            address(0),
            10,
            TimeShift(TimeShiftLib.TimeUnit.Inherit, 0).encode()
        );
    }

    function testAllowanceIsKeptTrackOf() public {
        uint64 initialTime = uint64(
            DateTimeLib.timestampFromDateTime(2022, 1, 1, 0, 0, 0)
        );
        uint256 allowanceId = 1;

        vm.prank(address(avatar));
        vm.warp(initialTime);
        createDailyAllowance(SPENDER, allowanceId);

        assertExecutePayment(
            SPENDER,
            allowanceId,
            RECEIVER,
            7,
            initialTime + 1 days
        );

        vm.warp(initialTime + 1 days);
        assertExecutePayment(
            SPENDER,
            allowanceId,
            RECEIVER,
            7,
            initialTime + 2 days
        );
        assertExecutePayment(
            SPENDER,
            allowanceId,
            RECEIVER,
            2,
            initialTime + 2 days
        );

        vm.prank(SPENDER);
        vm.expectRevert(
            abi.encodeWithSelector(
                Budget.Overbudget.selector,
                allowanceId,
                address(0),
                RECEIVER,
                7,
                1
            )
        );
        budget.executePayment(allowanceId, RECEIVER, 7);
    }

    function testMultipleAllowances() public {
        uint64 initialTime = uint64(
            DateTimeLib.timestampFromDateTime(2022, 1, 1, 0, 0, 0)
        );

        uint256 firstAllowanceId = 1;
        uint256 secondAllowanceId = 2;

        vm.warp(initialTime);
        vm.startPrank(address(avatar));
        createDailyAllowance(SPENDER, firstAllowanceId);
        createDailyAllowance(SPENDER, secondAllowanceId);
        vm.stopPrank();

        assertExecutePayment(
            SPENDER,
            firstAllowanceId,
            RECEIVER,
            7,
            initialTime + 1 days
        );
        assertExecutePayment(
            SPENDER,
            secondAllowanceId,
            RECEIVER,
            7,
            initialTime + 1 days
        );

        vm.warp(initialTime + 1 days);
        assertExecutePayment(
            SPENDER,
            firstAllowanceId,
            RECEIVER,
            7,
            initialTime + 2 days
        );
        assertExecutePayment(
            SPENDER,
            secondAllowanceId,
            RECEIVER,
            7,
            initialTime + 2 days
        );
    }

    function testCreateSuballowance() public {
        uint64 initialTime = uint64(
            DateTimeLib.timestampFromDateTime(2022, 1, 1, 0, 0, 0)
        );
        vm.warp(initialTime);

        vm.prank(address(avatar));
        uint256 topLevelAllowance = budget.createAllowance(
            NO_PARENT_ID,
            SPENDER,
            address(0),
            10,
            TimeShift(TimeShiftLib.TimeUnit.Monthly, 0).encode()
        );
        vm.prank(SPENDER);
        uint256 subAllowance = budget.createAllowance(
            topLevelAllowance,
            SOMEONE_ELSE,
            address(0),
            5,
            TimeShift(TimeShiftLib.TimeUnit.Daily, 0).encode()
        );

        assertExecutePayment(
            SOMEONE_ELSE,
            subAllowance,
            RECEIVER,
            5,
            initialTime + 1 days
        );
    }

    function testCreateSuballowanceWithInheritedRecurrency() public {
        uint64 initialTime = uint64(
            DateTimeLib.timestampFromDateTime(2022, 1, 1, 0, 0, 0)
        );
        vm.warp(initialTime);

        vm.prank(address(avatar));
        uint256 topLevelAllowance = budget.createAllowance(
            NO_PARENT_ID,
            SPENDER,
            address(0),
            10,
            TimeShift(TimeShiftLib.TimeUnit.Daily, 0).encode()
        );
        vm.prank(SPENDER);
        uint256 subAllowance = budget.createAllowance(
            topLevelAllowance,
            SOMEONE_ELSE,
            address(0),
            5,
            TimeShift(TimeShiftLib.TimeUnit.Inherit, 0).encode()
        );

        assertExecutePayment(
            SOMEONE_ELSE,
            subAllowance,
            RECEIVER,
            5,
            initialTime + 1 days
        );
    }

    function testAllowanceChain() public {
        uint64 initialTime = uint64(
            DateTimeLib.timestampFromDateTime(2022, 1, 1, 0, 0, 0)
        );
        vm.warp(initialTime);

        vm.prank(address(avatar));
        uint256 allowance1 = budget.createAllowance(
            NO_PARENT_ID,
            SPENDER,
            address(0),
            10,
            TimeShift(TimeShiftLib.TimeUnit.Monthly, 0).encode()
        );
        vm.startPrank(SPENDER);
        uint256 allowance2 = budget.createAllowance(
            allowance1,
            SPENDER,
            address(0),
            5,
            TimeShift(TimeShiftLib.TimeUnit.Inherit, 0).encode()
        );
        uint256 allowance3 = budget.createAllowance(
            allowance2,
            SPENDER,
            address(0),
            2,
            TimeShift(TimeShiftLib.TimeUnit.Daily, 0).encode()
        );
        uint256 allowance4 = budget.createAllowance(
            allowance3,
            SPENDER,
            address(0),
            1,
            TimeShift(TimeShiftLib.TimeUnit.Inherit, 0).encode()
        );
        vm.stopPrank();

        assertExecutePayment(
            SPENDER,
            allowance4,
            RECEIVER,
            1,
            initialTime + 1 days
        );

        vm.warp(initialTime + 1 days);
        assertExecutePayment(
            SPENDER,
            allowance3,
            RECEIVER,
            2,
            initialTime + 2 days
        );

        (, , uint256 spent1, , , , , ) = budget.getAllowance(allowance1);
        (, , uint256 spent2, , , , , ) = budget.getAllowance(allowance2);
        (, , uint256 spent3, , , , , ) = budget.getAllowance(allowance3);
        (, , uint256 spent4, , , , , ) = budget.getAllowance(allowance4);

        assertEq(spent1, 3);
        assertEq(spent2, 3);
        assertEq(spent3, 2);
        assertEq(spent4, 1); // It's one because the state doesn't get reset until a payment involving this allowance

        vm.expectRevert(
            abi.encodeWithSelector(
                Budget.Overbudget.selector,
                allowance3,
                address(0),
                SPENDER,
                1,
                0
            )
        );
        vm.prank(SPENDER);
        budget.executePayment(allowance4, SPENDER, 1);
    }

    function testCantExecuteIfNotAuthorized() public {
        vm.prank(address(avatar));
        uint256 allowanceId = 1;
        createDailyAllowance(SPENDER, allowanceId);

        vm.prank(RECEIVER);
        vm.expectRevert(
            abi.encodeWithSelector(
                Budget.ExecutionDisallowed.selector,
                allowanceId,
                RECEIVER
            )
        );
        budget.executePayment(allowanceId, RECEIVER, 7);
    }

    function testCantExecuteInexistentAllowance() public {
        vm.prank(SPENDER);
        vm.expectRevert(
            abi.encodeWithSelector(
                Budget.ExecutionDisallowed.selector,
                0,
                SPENDER
            )
        );
        budget.executePayment(0, RECEIVER, 7);
    }

    function testAllowanceSpenderWithRoleFlags() public {
        uint256 allowanceId = 1;
        uint8 roleId = 1;
        vm.prank(address(avatar));
        createDailyAllowance(roleFlag(roleId), allowanceId);

        vm.startPrank(SPENDER);
        vm.expectRevert(
            abi.encodeWithSelector(
                Budget.ExecutionDisallowed.selector,
                allowanceId,
                SPENDER
            )
        );
        budget.executePayment(allowanceId, RECEIVER, 7); // execution fails since SPENDER doesn't have the required role yet

        roles.setRole(SPENDER, roleId, true);
        budget.executePayment(allowanceId, RECEIVER, 7); // as soon as it gets the role, the payment executes
    }

    function createDailyAllowance(address spender, uint256 expectedId) public {
        uint256 allowanceId = budget.createAllowance(
            NO_PARENT_ID,
            spender,
            address(0),
            10,
            TimeShift(TimeShiftLib.TimeUnit.Daily, 0).encode()
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

    function assertExecutePayment(
        address actor,
        uint256 allowanceId,
        address to,
        uint256 amount,
        uint64 expectedNextResetTime
    ) public {
        (
            ,
            ,
            uint256 initialSpent,
            address token,
            uint64 initialNextReset,
            ,
            EncodedTimeShift shift,

        ) = budget.getAllowance(allowanceId);

        if (block.timestamp >= initialNextReset) {
            initialSpent = 0;
        }

        vm.prank(actor);
        vm.expectEmit(true, true, true, true);
        emit PaymentExecuted(
            allowanceId,
            actor,
            token,
            to,
            amount,
            expectedNextResetTime
        );
        budget.executePayment(allowanceId, to, amount);

        (, , uint256 spent, , uint64 nextResetTime, , , ) = budget.getAllowance(
            allowanceId
        );

        assertEq(spent, initialSpent + amount);
        assertEq(
            nextResetTime,
            shift.isInherited() ? 0 : expectedNextResetTime
        );
    }
}

contract BudgetWithProxyTest is BudgetTest {
    UpgradeableModuleProxyFactory immutable factory =
        new UpgradeableModuleProxyFactory();
    address immutable budgetImpl =
        address(new Budget(IAvatar(address(10)), IRoles(address(10))));

    function setUp() public override {
        avatar = new AvatarStub();
        roles = new RolesStub();
        budget = Budget(
            factory.deployUpgradeableModule(
                budgetImpl,
                abi.encodeCall(Budget.initialize, (avatar, roles)),
                0
            )
        );
        vm.label(address(roles), "BudgetProxy");
    }
}
