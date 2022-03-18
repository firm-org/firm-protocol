// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import "solmate/test/utils/DSTestPlus.sol";
import "solmate/utils/Bytes32AddressLib.sol";
import "zodiac/factory/ModuleProxyFactory.sol";

import "../../common/test/lib/RolesStub.sol";
import {roleFlag} from "../../common/test/lib/RolesAuthMock.sol";

import "../Budget.sol";
import "./lib/AvatarStub.sol";

contract BudgetTest is DSTestPlus {
    using Bytes32AddressLib for bytes32;

    AvatarStub avatar;
    RolesStub roles;
    Budget budget;

    address internal constant SPENDER = address(5);
    address internal constant RECEIVER = address(6);

    function setUp() public virtual {
        avatar = new AvatarStub();
        roles = new RolesStub();
        budget = new Budget(Budget.InitParams(avatar, avatar, roles));
    }

    function testInitialState() public {
        assertEq(address(budget.avatar()), address(avatar));
        assertEq(address(budget.target()), address(avatar));
        assertEq(address(budget.roles()), address(roles));
    }

    // To be moved into FirmModule unit tests
    function testModuleStateRawStorage() public {
        // change target to make it different from avatar
        address someTarget = address(7);
        hevm.prank(address(avatar));
        budget.setTarget(IAvatar(someTarget));

        uint256 moduleStateBaseSlot = 0xa5b7510e75e06df92f176662510e3347b687605108b9f72b4260aa7cf56ebb12;
        assertEq(hevm.load(address(budget), 0).fromLast20Bytes(), address(roles));
        assertEq(hevm.load(address(budget), bytes32(moduleStateBaseSlot)).fromLast20Bytes(), address(avatar));
        assertEq(hevm.load(address(budget), bytes32(moduleStateBaseSlot + 1)).fromLast20Bytes(), someTarget);
        assertEq(hevm.load(address(budget), bytes32(moduleStateBaseSlot + 2)).fromLast20Bytes(), address(0)); // guard not set yet
        assertEq(bytes32(moduleStateBaseSlot + 3), keccak256("firm.module.state"));
    }

    function testCannotReinit() public {
        hevm.expectRevert(abi.encodeWithSelector(FirmModule.AlreadyInitialized.selector));
        budget.setUp(Budget.InitParams(avatar, avatar, roles));
    }

    function testCreateAllowance() public {
        uint256 allowanceId = 0;
        hevm.prank(address(avatar));
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
            bytes32(EncodedTimeShift.unwrap(TimeShift(TimeShiftLib.TimeUnit.Daily, 0).encode()))
        );
        assertFalse(isDisabled);
    }

    function testNotOwnerCannotCreateAllowance() public {
        hevm.expectRevert(abi.encodeWithSelector(FirmModule.UnauthorizedNotAvatar.selector));
        createDailyAllowance(SPENDER, 0);
    }

    function testAllowanceIsKeptTrackOf() public {
        uint64 initialTime = uint64(DateTimeLib.timestampFromDateTime(2022, 1, 1, 0, 0, 0));
        uint256 allowanceId = 0;

        hevm.prank(address(avatar));
        hevm.warp(initialTime);
        createDailyAllowance(SPENDER, allowanceId);

        assertExecutePayment(SPENDER, allowanceId, RECEIVER, 7, initialTime + 1 days);

        hevm.warp(initialTime + 1 days);
        assertExecutePayment(SPENDER, allowanceId, RECEIVER, 7, initialTime + 2 days);
        assertExecutePayment(SPENDER, allowanceId, RECEIVER, 2, initialTime + 2 days);

        hevm.prank(SPENDER);
        hevm.expectRevert(abi.encodeWithSelector(Budget.Overbudget.selector, 0, address(0), RECEIVER, 7, 1));
        budget.executePayment(allowanceId, RECEIVER, 7);
    }

    function testMultipleAllowances() public {
        uint64 initialTime = uint64(DateTimeLib.timestampFromDateTime(2022, 1, 1, 0, 0, 0));

        hevm.startPrank(address(avatar));
        hevm.warp(initialTime);
        createDailyAllowance(SPENDER, 0);
        createDailyAllowance(SPENDER, 1);

        assertExecutePayment(SPENDER, 0, RECEIVER, 7, initialTime + 1 days);
        assertExecutePayment(SPENDER, 1, RECEIVER, 7, initialTime + 1 days);

        hevm.warp(initialTime + 1 days);
        assertExecutePayment(SPENDER, 0, RECEIVER, 7, initialTime + 2 days);
        assertExecutePayment(SPENDER, 1, RECEIVER, 7, initialTime + 2 days);
    }

    function testCantExecuteIfNotAuthorized() public {
        hevm.prank(address(avatar));
        createDailyAllowance(SPENDER, 0);
        
        hevm.prank(RECEIVER);
        hevm.expectRevert(abi.encodeWithSelector(Budget.ExecutionDisallowed.selector, 0, RECEIVER));
        budget.executePayment(0, RECEIVER, 7);
    }

    function testCantExecuteInexistentAllowance() public {
        hevm.prank(SPENDER);
        hevm.expectRevert(abi.encodeWithSelector(Budget.ExecutionDisallowed.selector, 0, SPENDER));
        budget.executePayment(0, RECEIVER, 7);
    }

    function testAllowanceSpenderWithRoleFlags() public {
        uint8 roleId = 1;
        hevm.prank(address(avatar));
        createDailyAllowance(roleFlag(roleId), 0);

        hevm.startPrank(SPENDER);
        hevm.expectRevert(abi.encodeWithSelector(Budget.ExecutionDisallowed.selector, 0, SPENDER));
        budget.executePayment(0, RECEIVER, 7); // execution fails since SPENDER doesn't have the required role yet

        roles.setRole(SPENDER, roleId, true);
        budget.executePayment(0, RECEIVER, 7); // as soon as it gets the role, the payment executes
    }

    function createDailyAllowance(address spender, uint256 expectedId) public {
        uint256 allowanceId = budget.createAllowance(
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

contract BudgetWithProxyTest is BudgetTest {
    ModuleProxyFactory immutable factory = new ModuleProxyFactory();
    address immutable budgetImpl =
        address(new Budget(Budget.InitParams(IAvatar(address(10)), IAvatar(address(10)), IRoles(address(10)))));

    function setUp() public override {
        avatar = new AvatarStub();
        roles = new RolesStub();
        budget = Budget(
            factory.deployModule(
                budgetImpl,
                abi.encodeCall(Budget.setUp, (Budget.InitParams(avatar, avatar, roles))),
                0
            )
        );
        hevm.label(address(roles), "BudgetProxy");
    }
}
