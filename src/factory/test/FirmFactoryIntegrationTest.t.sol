// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import "gnosis-safe/GnosisSafe.sol";
import "gnosis-safe/proxies/GnosisSafeProxyFactory.sol";

import {FirmTest} from "../../common/test/lib/FirmTest.sol";
import {roleFlag} from "../../common/test/mocks/RolesAuthMock.sol";
import {ModuleMock} from "../../common/test/mocks/ModuleMock.sol";
import "./lib/ERC20Token.sol";

import {FirmFactory, UpgradeableModuleProxyFactory} from "../FirmFactory.sol";
import {Budget, TimeShiftLib, NO_PARENT_ID} from "../../budget/Budget.sol";
import {TimeShift} from "../../budget/TimeShiftLib.sol";
import {Roles, IRoles, IAvatar, ONLY_ROOT_ROLE} from "../../roles/Roles.sol";
import {SafeEnums} from "../../bases/IZodiacModule.sol";

contract FirmFactoryIntegrationTest is FirmTest {
    using TimeShiftLib for *;

    FirmFactory factory;
    ERC20Token token;

    function setUp() public {
        token = new ERC20Token();
        factory = new FirmFactory(
            new GnosisSafeProxyFactory(),
            new UpgradeableModuleProxyFactory(),
            address(new GnosisSafe()),
            address(new Roles(IAvatar(address(10)))),
            address(new Budget(IAvatar(address(10)), IRoles(address(10))))
        );
    }

    function testFactoryGas() public {
        createFirm(address(this));
    }

    event NewFirm(address indexed creator, GnosisSafe indexed safe, Roles roles, Budget budget);

    function testInitialState() public {
        // we don't match the deployed contract addresses for simplicity (could precalculate them but unnecessary)
        vm.expectEmit(true, false, false, false);
        emit NewFirm(address(this), GnosisSafe(payable(0)), Roles(address(0)), Budget(address(0)));

        (GnosisSafe safe, Budget budget, Roles roles) = createFirm(address(this));

        assertTrue(safe.isModuleEnabled(address(budget)));
        assertTrue(roles.hasRootRole(address(safe)));
    }

    function testExecutingPaymentsFromBudget() public {
        (GnosisSafe safe, Budget budget, Roles roles) = createFirm(address(this));
        token.mint(address(safe), 100);

        address spender = account("spender");
        address receiver = account("receiver");

        vm.startPrank(address(safe));
        uint8 roleId = roles.createRole(ONLY_ROOT_ROLE, "Executive");
        roles.setRole(spender, roleId, true);

        uint256 allowanceId = budget.createAllowance(
            NO_PARENT_ID, roleFlag(roleId), address(token), 10, TimeShift(TimeShiftLib.TimeUnit.Daily, 0).encode()
        );
        vm.stopPrank();

        vm.startPrank(spender);
        budget.executePayment(allowanceId, receiver, 4);
        budget.executePayment(allowanceId, receiver, 1);

        vm.warp(block.timestamp + 1 days);
        budget.executePayment(allowanceId, receiver, 9);

        vm.expectRevert(abi.encodeWithSelector(Budget.Overbudget.selector, allowanceId, address(token), receiver, 2, 1));
        budget.executePayment(allowanceId, receiver, 2);

        assertEq(token.balanceOf(receiver), 14);
    }

    function testModuleUpgrades() public {
        (GnosisSafe safe, Budget budget,) = createFirm(address(this));

        address moduleMockImpl = address(new ModuleMock(1));
        vm.prank(address(safe));
        budget.upgrade(moduleMockImpl);

        assertEq(ModuleMock(address(budget)).foo(), 1);
    }

    function createFirm(address owner) internal returns (GnosisSafe safe, Budget budget, Roles roles) {
        (safe, budget, roles) = factory.createFirm(owner);
        vm.label(address(budget), "BudgetProxy");
        vm.label(address(roles), "RolesProxy");
    }
}
