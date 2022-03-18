// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import "solmate/test/utils/DSTestPlus.sol";

import "gnosis-safe/GnosisSafe.sol";
import "gnosis-safe/proxies/GnosisSafeProxyFactory.sol";
import "gnosis-safe/common/Enum.sol";
import "zodiac/factory/ModuleProxyFactory.sol";
import "zodiac/interfaces/IAvatar.sol";

import "./lib/ERC20Token.sol";
import {roleFlag} from "../../common/test/lib/RolesAuthMock.sol";

import {FirmFactory} from "../FirmFactory.sol";
import {Budget, TimeShiftLib} from "../../budget/Budget.sol";
import {Roles, IRoles, ONLY_ROOT_ROLE} from "../../roles/Roles.sol";

contract FirmFactoryIntegrationTest is DSTestPlus {
    using TimeShiftLib for *;

    FirmFactory factory;
    ERC20Token token;

    function setUp() public {
        token = new ERC20Token();
        factory = new FirmFactory(
            new GnosisSafeProxyFactory(),
            new ModuleProxyFactory(),
            address(new GnosisSafe()),
            address(new Roles(address(10))),
            address(new Budget(Budget.InitParams(IAvatar(address(10)), IAvatar(address(10)), IRoles(address(10)))))
        );
    }

    function testFactoryGas() public {
        factory.createFirm(address(this));
    }

    function testInitialState() public {
        (GnosisSafe safe, Budget budget, Roles roles) = factory.createFirm(address(this));
        assertTrue(safe.isModuleEnabled(address(budget)));
        assertTrue(roles.hasRootRole(address(safe)));
    }

    function testExecutingPaymentsFromBudget() public {
        (GnosisSafe safe, Budget budget, Roles roles) = factory.createFirm(address(this));
        token.mint(address(safe), 100);

        address spender = address(10);
        address receiver = address(11);

        hevm.startPrank(address(safe));
        uint8 roleId = roles.createRole(ONLY_ROOT_ROLE, "Executive");
        roles.setRole(spender, roleId, true);

        uint256 allowanceId = budget.createAllowance(
            roleFlag(roleId),
            address(token),
            10,
            TimeShiftLib.TimeShift(TimeShiftLib.TimeUnit.Daily, 0).encode()
        );

        hevm.startPrank(spender);
        budget.executePayment(allowanceId, receiver, 4);
        budget.executePayment(allowanceId, receiver, 1);

        hevm.warp(block.timestamp + 1 days);
        budget.executePayment(allowanceId, receiver, 9);

        hevm.expectRevert(abi.encodeWithSelector(Budget.Overbudget.selector, allowanceId, address(token), receiver, 2, 1));
        budget.executePayment(allowanceId, receiver, 2);

        assertEq(token.balanceOf(receiver), 14);
    }
}