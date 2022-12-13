// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {FirmTest} from "../../common/test/lib/FirmTest.sol";
import {RolesStub} from "../../common/test/mocks/RolesStub.sol";
import {roleFlag} from "../../common/test/mocks/RolesAuthMock.sol";
import {SafeStub} from "../../common/test/mocks/SafeStub.sol";
import {TestnetERC20 as ERC20Token} from "../../testnet/TestnetTokenFaucet.sol";
import {UpgradeableModuleProxyFactory} from "../../factory/UpgradeableModuleProxyFactory.sol";

import {TimeShift, DateTimeLib} from "../../budget/TimeShiftLib.sol";
import {SafeAware} from "../../bases/SafeAware.sol";
import "../Budget.sol";

abstract contract BudgetTest is FirmTest {
    SafeStub safe;
    RolesStub roles;
    Budget budget;
    address token;

    address SPENDER = account("spender");
    address RECEIVER = account("receiver");
    address SOMEONE_ELSE = account("someone else");

    function setUp() public virtual {
        safe = new SafeStub();
        roles = new RolesStub();
        budget = Budget(createProxy(new Budget(), abi.encodeCall(Budget.initialize, (safe, roles, address(0)))));
    }

    function testInitialState() public {
        assertEq(address(budget.safe()), address(safe));
        assertEq(address(budget.roles()), address(roles));
    }

    function testCannotReinit() public {
        vm.expectRevert(abi.encodeWithSelector(SafeAware.AlreadyInitialized.selector));
        budget.initialize(safe, roles, address(0));
    }

    function testCreateAllowance() public returns (uint256 allowanceId) {
        vm.prank(address(safe));
        vm.warp(0);
        allowanceId = createDailyAllowance(SPENDER, 1);
        (
            uint256 parentId,
            uint256 amount,
            uint256 spent,
            address token_,
            uint40 nextResetTime,
            address spender,
            EncodedTimeShift recurrency,
            bool isDisabled
        ) = budget.allowances(allowanceId);

        assertEq(parentId, NO_PARENT_ID);
        assertEq(amount, 10);
        assertEq(spent, 0);
        assertEq(token_, address(token));
        assertEq(nextResetTime, 1 days);
        assertEq(spender, SPENDER);
        assertEq(
            bytes32(EncodedTimeShift.unwrap(recurrency)),
            bytes32(EncodedTimeShift.unwrap(TimeShift(TimeShiftLib.TimeUnit.Daily, 0).encode()))
        );
        assertFalse(isDisabled);
    }

    function testUpdateAllowanceParams() public {
        uint256 allowanceId = testCreateAllowance();

        vm.startPrank(address(safe));
        budget.setAllowanceSpender(allowanceId, RECEIVER);
        budget.setAllowanceAmount(allowanceId, 1);
        budget.setAllowanceName(allowanceId, "new name");

        (, uint256 amount,,, uint40 nextResetTime, address spender,,) = budget.allowances(allowanceId);

        assertEq(amount, 1);
        assertEq(nextResetTime, 1 days);
        assertEq(spender, RECEIVER);
    }

    function testNotOwnerCannotCreateTopLevelAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(Budget.UnauthorizedNotAllowanceAdmin.selector, 0));
        createDailyAllowance(SPENDER, 0);
    }

    function testBadTimeshiftsRevert() public {
        vm.prank(address(safe));
        vm.expectRevert(abi.encodeWithSelector(TimeShiftLib.InvalidTimeShift.selector));
        budget.createAllowance(
            NO_PARENT_ID, SPENDER, address(0), 10, TimeShift(TimeShiftLib.TimeUnit.Inherit, 0).encode(), ""
        );
    }

    function testMalformedInheritedTimeshiftReverts() public {
        vm.startPrank(address(safe));
        uint256 allowanceId = createDailyAllowance(address(safe), 1);
        // can create suballowance with valid inheritance flag
        budget.createAllowance(
            allowanceId, SPENDER, token, 10, TimeShift(TimeShiftLib.TimeUnit.Inherit, 0).encode(), ""
        );
        // fails suballowance with valid inheritance flag (not interpreted as inherit as the offset is not 0)
        vm.expectRevert(abi.encodeWithSelector(TimeShiftLib.InvalidTimeShift.selector));
        budget.createAllowance(
            allowanceId, SPENDER, token, 10, TimeShift(TimeShiftLib.TimeUnit.Inherit, 1).encode(), ""
        );
        vm.stopPrank();
    }

    function testInvalidSpenderReverts() public {
        uint8 badRoleId = 101; // RolesStub returns false to roleExists when id > 100
        vm.prank(address(safe));
        vm.expectRevert(abi.encodeWithSelector(RolesAuth.UnexistentRole.selector, badRoleId));
        budget.createAllowance(
            NO_PARENT_ID, roleFlag(badRoleId), address(0), 10, TimeShift(TimeShiftLib.TimeUnit.Daily, 0).encode(), ""
        );
    }

    function testAllowanceIsKeptTrackOfOnSingle() public {
        uint40 initialTime = uint40(DateTimeLib.timestampFromDateTime(2022, 1, 1, 0, 0, 0));
        uint256 allowanceId = 1;

        vm.prank(address(safe));
        vm.warp(initialTime);
        createDailyAllowance(SPENDER, allowanceId);

        assertExecutePayment(SPENDER, allowanceId, RECEIVER, 7, initialTime + 1 days);

        vm.warp(initialTime + 1 days);
        assertExecutePayment(SPENDER, allowanceId, RECEIVER, 7, initialTime + 2 days);
        assertExecutePayment(SPENDER, allowanceId, RECEIVER, 2, initialTime + 2 days);

        vm.prank(SPENDER);
        vm.expectRevert(abi.encodeWithSelector(Budget.Overbudget.selector, allowanceId, 7, 1));
        budget.executePayment(allowanceId, RECEIVER, 7, "");
    }

    function testAllowanceIsKeptTrackOfOnMulti() public {
        uint40 initialTime = uint40(DateTimeLib.timestampFromDateTime(2022, 1, 1, 0, 0, 0));
        uint256 allowanceId = 1;

        vm.prank(address(safe));
        vm.warp(initialTime);
        createDailyAllowance(SPENDER, allowanceId);

        // max out allowance doing 5 payments of 2
        (address[] memory tos, uint256[] memory amounts) = _generateMultiPaymentArrays(5, RECEIVER, 2);
        vm.prank(SPENDER);
        budget.executeMultiPayment(allowanceId, tos, amounts, "");

        vm.prank(SPENDER);
        vm.expectRevert(abi.encodeWithSelector(Budget.Overbudget.selector, allowanceId, 1, 0));
        budget.executePayment(allowanceId, RECEIVER, 1, "");

        vm.warp(initialTime + 1 days);
        // almost max out allowance doing 4 payments of 2
        (tos, amounts) = _generateMultiPaymentArrays(4, RECEIVER, 2);
        vm.prank(SPENDER);
        budget.executeMultiPayment(allowanceId, tos, amounts, "");

        // max out on second payment
        (tos, amounts) = _generateMultiPaymentArrays(2, RECEIVER, 2);
        vm.prank(SPENDER);
        vm.expectRevert(abi.encodeWithSelector(Budget.Overbudget.selector, allowanceId, 4, 2));
        budget.executeMultiPayment(allowanceId, tos, amounts, "");
    }

    function testMultipleAllowances() public {
        uint40 initialTime = uint40(DateTimeLib.timestampFromDateTime(2022, 1, 1, 0, 0, 0));

        uint256 firstAllowanceId = 1;
        uint256 secondAllowanceId = 2;

        vm.warp(initialTime);
        vm.startPrank(address(safe));
        createDailyAllowance(SPENDER, firstAllowanceId);
        createDailyAllowance(SPENDER, secondAllowanceId);
        vm.stopPrank();

        assertExecutePayment(SPENDER, firstAllowanceId, RECEIVER, 7, initialTime + 1 days);
        assertExecutePayment(SPENDER, secondAllowanceId, RECEIVER, 7, initialTime + 1 days);

        vm.warp(initialTime + 1 days);
        assertExecutePayment(SPENDER, firstAllowanceId, RECEIVER, 7, initialTime + 2 days);
        assertExecutePayment(SPENDER, secondAllowanceId, RECEIVER, 7, initialTime + 2 days);
    }

    function testCreateSuballowance() public returns (uint256 topLevelAllowance, uint256 subAllowance) {
        uint40 initialTime = uint40(DateTimeLib.timestampFromDateTime(2022, 1, 1, 0, 0, 0));
        vm.warp(initialTime);

        vm.prank(address(safe));
        topLevelAllowance = budget.createAllowance(
            NO_PARENT_ID, SPENDER, address(0), 10, TimeShift(TimeShiftLib.TimeUnit.Monthly, 0).encode(), ""
        );
        vm.prank(SPENDER);
        subAllowance = budget.createAllowance(
            topLevelAllowance, SOMEONE_ELSE, address(0), 5, TimeShift(TimeShiftLib.TimeUnit.Daily, 0).encode(), ""
        );

        assertExecutePayment(SOMEONE_ELSE, subAllowance, RECEIVER, 5, initialTime + 1 days);
    }

    function testNonAdminCannotUpdateAllowanceParams() public {
        (uint256 topLevelAllowanceId, uint256 subAllowanceId) = testCreateSuballowance();

        vm.startPrank(SPENDER);

        vm.expectRevert(abi.encodeWithSelector(Budget.UnauthorizedNotAllowanceAdmin.selector, NO_PARENT_ID));
        budget.setAllowanceSpender(topLevelAllowanceId, RECEIVER);

        vm.expectRevert(abi.encodeWithSelector(Budget.UnauthorizedNotAllowanceAdmin.selector, NO_PARENT_ID));
        budget.setAllowanceAmount(topLevelAllowanceId, 1);

        vm.expectRevert(abi.encodeWithSelector(Budget.UnauthorizedNotAllowanceAdmin.selector, NO_PARENT_ID));
        budget.setAllowanceName(topLevelAllowanceId, "new name");

        vm.stopPrank();

        vm.startPrank(address(safe));

        vm.expectRevert(abi.encodeWithSelector(Budget.UnauthorizedNotAllowanceAdmin.selector, topLevelAllowanceId));
        budget.setAllowanceSpender(subAllowanceId, RECEIVER);

        vm.expectRevert(abi.encodeWithSelector(Budget.UnauthorizedNotAllowanceAdmin.selector, topLevelAllowanceId));
        budget.setAllowanceAmount(subAllowanceId, 1);

        vm.expectRevert(abi.encodeWithSelector(Budget.UnauthorizedNotAllowanceAdmin.selector, topLevelAllowanceId));
        budget.setAllowanceName(subAllowanceId, "new name");

        vm.stopPrank();
    }

    function testCreateSuballowanceWithInheritedRecurrency() public {
        uint40 initialTime = uint40(DateTimeLib.timestampFromDateTime(2022, 1, 1, 0, 0, 0));
        vm.warp(initialTime);

        vm.prank(address(safe));
        uint256 topLevelAllowance = budget.createAllowance(
            NO_PARENT_ID, SPENDER, address(0), 10, TimeShift(TimeShiftLib.TimeUnit.Daily, 0).encode(), ""
        );
        vm.prank(SPENDER);
        uint256 subAllowance = budget.createAllowance(
            topLevelAllowance, SOMEONE_ELSE, address(0), 5, TimeShift(TimeShiftLib.TimeUnit.Inherit, 0).encode(), ""
        );

        assertExecutePayment(SOMEONE_ELSE, subAllowance, RECEIVER, 5, initialTime + 1 days);
    }

    function testAllowanceChain() public {
        uint40 initialTime = uint40(DateTimeLib.timestampFromDateTime(2022, 1, 1, 0, 0, 0));
        vm.warp(initialTime);

        vm.prank(address(safe));
        uint256 allowance1 = budget.createAllowance(
            NO_PARENT_ID, SPENDER, address(0), 10, TimeShift(TimeShiftLib.TimeUnit.Monthly, 0).encode(), ""
        );
        vm.startPrank(SPENDER);
        uint256 allowance2 = budget.createAllowance(
            allowance1, SPENDER, address(0), 5, TimeShift(TimeShiftLib.TimeUnit.Inherit, 0).encode(), ""
        );
        uint256 allowance3 = budget.createAllowance(
            allowance2, SPENDER, address(0), 2, TimeShift(TimeShiftLib.TimeUnit.Daily, 0).encode(), ""
        );
        uint256 allowance4 = budget.createAllowance(
            allowance3, SPENDER, address(0), 1, TimeShift(TimeShiftLib.TimeUnit.Inherit, 0).encode(), ""
        );
        vm.stopPrank();

        assertExecutePayment(SPENDER, allowance4, RECEIVER, 1, initialTime + 1 days);

        vm.warp(initialTime + 1 days);
        assertExecutePayment(SPENDER, allowance3, RECEIVER, 2, initialTime + 2 days);

        (,, uint256 spent1,,,,,) = budget.allowances(allowance1);
        (,, uint256 spent2,,,,,) = budget.allowances(allowance2);
        (,, uint256 spent3,,,,,) = budget.allowances(allowance3);
        (,, uint256 spent4,,,,,) = budget.allowances(allowance4);

        assertEq(spent1, 3);
        assertEq(spent2, 3);
        assertEq(spent3, 2);
        assertEq(spent4, 1); // It's one because the state doesn't get reset until a payment involving this allowance

        vm.expectRevert(abi.encodeWithSelector(Budget.Overbudget.selector, allowance3, 1, 0));
        vm.prank(SPENDER);
        budget.executePayment(allowance4, SPENDER, 1, "");
    }

    function testDisablingAllowanceBreaksChain() public {
        uint256 topLevelAllowanceId = 1;
        uint256 childAllowanceId = 4;

        testAllowanceChain(); // sets up the chain

        vm.prank(address(safe));
        budget.setAllowanceState(topLevelAllowanceId, false);

        vm.prank(SPENDER);
        vm.expectRevert(abi.encodeWithSelector(Budget.DisabledAllowance.selector, topLevelAllowanceId));
        budget.executePayment(childAllowanceId, RECEIVER, 1, "");
    }

    function testOnlyParentAdminCanDisableAllowance() public {
        uint256 topLevelAllowanceId = 1;
        uint256 childAllowanceId = 4;

        testAllowanceChain(); // sets up the chain

        vm.prank(SPENDER);
        vm.expectRevert(abi.encodeWithSelector(Budget.UnauthorizedNotAllowanceAdmin.selector, 0));
        budget.setAllowanceState(topLevelAllowanceId, false);

        vm.prank(address(safe));
        vm.expectRevert(abi.encodeWithSelector(Budget.UnauthorizedNotAllowanceAdmin.selector, childAllowanceId - 1));
        budget.setAllowanceState(childAllowanceId, false);
    }

    function testCantExecuteIfNotAuthorized() public {
        vm.prank(address(safe));
        uint256 allowanceId = 1;
        createDailyAllowance(SPENDER, allowanceId);

        vm.prank(RECEIVER);
        vm.expectRevert(abi.encodeWithSelector(Budget.UnauthorizedPaymentExecution.selector, allowanceId, RECEIVER));
        budget.executePayment(allowanceId, RECEIVER, 7, "");
    }

    function testAllowanceSpenderWithRoleFlags() public {
        uint256 allowanceId = 1;
        uint8 roleId = 1;
        vm.prank(address(safe));
        createDailyAllowance(roleFlag(roleId), allowanceId);

        vm.startPrank(SPENDER);
        vm.expectRevert(abi.encodeWithSelector(Budget.UnauthorizedPaymentExecution.selector, allowanceId, SPENDER));
        budget.executePayment(allowanceId, RECEIVER, 7, ""); // execution fails since SPENDER doesn't have the required role yet

        roles.setRole(SPENDER, roleId, true);
        budget.executePayment(allowanceId, RECEIVER, 7, ""); // as soon as it gets the role, the payment executes
    }

    function testCantExecuteInexistentAllowance() public {
        vm.prank(SPENDER);
        vm.expectRevert(abi.encodeWithSelector(Budget.UnexistentAllowance.selector, 0));
        budget.executePayment(0, RECEIVER, 7, "");
    }

    function testCantExecuteMultiIfNotAuthorized() public {
        vm.prank(address(safe));
        uint256 allowanceId = 1;
        createDailyAllowance(SPENDER, allowanceId);

        vm.prank(RECEIVER);
        vm.expectRevert(abi.encodeWithSelector(Budget.UnauthorizedPaymentExecution.selector, allowanceId, RECEIVER));
        (address[] memory tos, uint256[] memory amounts) = _generateMultiPaymentArrays(2, RECEIVER, 7);
        budget.executeMultiPayment(allowanceId, tos, amounts, "");
    }

    function testRevertOnBadInputToMultiPayment() public {
        vm.prank(address(safe));
        uint256 allowanceId = 1;
        createDailyAllowance(SPENDER, allowanceId);

        vm.prank(SPENDER);
        vm.expectRevert(abi.encodeWithSelector(Budget.BadInput.selector));
        (address[] memory tos, uint256[] memory amounts) = _generateMultiPaymentArrays(2, RECEIVER, 7);
        tos = new address[](1);
        budget.executeMultiPayment(allowanceId, tos, amounts, "");
    }

    function testCanDebitAllowance() public {
        vm.prank(address(safe));
        uint256 allowanceId = 1;
        createDailyAllowance(SPENDER, allowanceId);

        // Since the budget allows spending 10, allowance should be full after the first
        // payment execution, but since 5 are debited, another execution of 5 is allowed
        uint256 spent;
        vm.prank(SPENDER);
        budget.executePayment(allowanceId, RECEIVER, 10, "");
        (,, spent,,,,,) = budget.allowances(allowanceId);
        assertEq(spent, 10);

        performDebit(RECEIVER, allowanceId, 5);
        (,, spent,,,,,) = budget.allowances(allowanceId);
        assertEq(spent, 5);

        vm.prank(SPENDER);
        budget.executePayment(allowanceId, RECEIVER, 5, "");
        (,, spent,,,,,) = budget.allowances(allowanceId);
        assertEq(spent, 10);
    }

    function testCanDebitOnChains() public {
        vm.prank(address(safe));
        uint256 allowanceId1 = budget.createAllowance(
            NO_PARENT_ID, SPENDER, address(token), 10, TimeShift(TimeShiftLib.TimeUnit.Daily, 0).encode(), ""
        );
        vm.startPrank(SPENDER);
        uint256 allowanceId2 = budget.createAllowance(
            allowanceId1, SPENDER, address(token), 10, TimeShift(TimeShiftLib.TimeUnit.Daily, 0).encode(), ""
        );
        uint256 allowanceId3 = budget.createAllowance(
            allowanceId2, SPENDER, address(token), 10, TimeShift(TimeShiftLib.TimeUnit.Daily, 0).encode(), ""
        );

        budget.executePayment(allowanceId1, RECEIVER, 3, "");
        budget.executePayment(allowanceId2, RECEIVER, 2, "");
        budget.executePayment(allowanceId3, RECEIVER, 1, "");
        vm.stopPrank();
        uint256 spent;

        performDebit(RECEIVER, allowanceId3, 2);
        (,, spent,,,,,) = budget.allowances(allowanceId1);
        assertEq(spent, 4);
        (,, spent,,,,,) = budget.allowances(allowanceId2);
        assertEq(spent, 1);
        (,, spent,,,,,) = budget.allowances(allowanceId3);
        assertEq(spent, 0);

        performDebit(RECEIVER, allowanceId1, 4);
        (,, spent,,,,,) = budget.allowances(allowanceId1);
        assertEq(spent, 0);
        (,, spent,,,,,) = budget.allowances(allowanceId2);
        assertEq(spent, 1);
        (,, spent,,,,,) = budget.allowances(allowanceId3);
        assertEq(spent, 0);
    }

    function createDailyAllowance(address spender, uint256 expectedId) public returns (uint256 allowanceId) {
        allowanceId = budget.createAllowance(
            NO_PARENT_ID, spender, address(token), 10, TimeShift(TimeShiftLib.TimeUnit.Daily, 0).encode(), ""
        );
        assertEq(allowanceId, expectedId);
    }

    function performDebit(address debiter, uint256 allowanceId, uint256 amount) internal {
        vm.startPrank(debiter);
        if (token == NATIVE_ASSET) {
            budget.debitAllowance{value: amount}(allowanceId, amount, "");
        } else {
            ERC20Token(token).approve(address(budget), amount);
            budget.debitAllowance(allowanceId, amount, "");
        }
        vm.stopPrank();
    }

    function _generateMultiPaymentArrays(uint256 num, address to, uint256 amount)
        internal
        pure
        returns (address[] memory tos, uint256[] memory amounts)
    {
        tos = new address[](num);
        amounts = new uint256[](num);
        for (uint256 i = 0; i < num; i++) {
            tos[i] = to;
            amounts[i] = amount;
        }
    }

    event PaymentExecuted(
        uint256 indexed allowanceId,
        address indexed actor,
        address token,
        address indexed to,
        uint256 amount,
        uint40 nextResetTime,
        string descrition
    );

    function assertExecutePayment(
        address actor,
        uint256 allowanceId,
        address to,
        uint256 amount,
        uint40 expectedNextResetTime
    ) public {
        (,, uint256 initialSpent, address token_, uint40 initialNextReset,, EncodedTimeShift shift,) =
            budget.allowances(allowanceId);

        if (block.timestamp >= initialNextReset) {
            initialSpent = 0;
        }

        vm.prank(actor);
        vm.expectEmit(true, true, true, true);
        emit PaymentExecuted(allowanceId, actor, token_, to, amount, expectedNextResetTime, "");
        budget.executePayment(allowanceId, to, amount, "");

        (,, uint256 spent,, uint40 nextResetTime,,,) = budget.allowances(allowanceId);

        assertEq(spent, initialSpent + amount);
        assertEq(nextResetTime, shift.isInherited() ? 0 : expectedNextResetTime);
    }
}

contract TokenBudgetTest is BudgetTest {
    function setUp() public override {
        super.setUp();

        ERC20Token token_ = new ERC20Token("", "", 0);
        token_.mint(address(safe), 1e6 ether);
        token = address(token_);
    }
}

contract EtherBudgetTest is BudgetTest {
    function setUp() public override {
        super.setUp();

        token = NATIVE_ASSET;
        vm.deal(address(safe), 1e6 ether);
    }
}
