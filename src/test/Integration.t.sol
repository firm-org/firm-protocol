// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "solmate/test/utils/DSTestPlus.sol";

import "gnosis-safe/GnosisSafe.sol";
import "gnosis-safe/proxies/GnosisSafeProxyFactory.sol";
import "gnosis-safe/common/Enum.sol";
import "zodiac/factory/ModuleProxyFactory.sol";

import "./lib/ERC20Token.sol";

import {Budget, TimeShiftLib} from "../budget/Budget.sol";

contract IntegrationTest is DSTestPlus {
    GnosisSafeProxyFactory immutable safeFactory = new GnosisSafeProxyFactory();
    ModuleProxyFactory immutable moduleFactory = new ModuleProxyFactory();

    address immutable safeImpl = address(new GnosisSafe());
    address immutable budgetImpl =
        address(new Budget(Budget.InitParams(address(10), address(10), address(10))));

    ERC20Token token;
    function setUp() public {
        token = new ERC20Token();
    }

    function testCreateSafeWithBudget() public {
        (GnosisSafe safe, Budget budget) = setupSafeWithBudget();
        assertTrue(safe.isModuleEnabled(address(budget)));
    }

    function testExecutingPaymentsFromBudget() public {
        (GnosisSafe safe, Budget budget) = setupSafeWithBudget();
        token.mint(address(safe), 100);

        address spender = address(10);
        address receiver = address(11);
        uint256 allowanceId = budget.createAllowance(
            spender,
            address(token),
            10,
            TimeShiftLib.TimeShift(TimeShiftLib.TimeUnit.Daily, 0)
        );

        hevm.startPrank(spender);
        budget.executePayment(allowanceId, receiver, 5);

        hevm.warp(block.timestamp + 1 days);
        budget.executePayment(allowanceId, receiver, 9);

        hevm.expectRevert(abi.encodeWithSelector(Budget.Overbudget.selector, allowanceId, address(token), receiver, 2, 1));
        budget.executePayment(allowanceId, receiver, 2);

        assertEq(token.balanceOf(receiver), 14);
    }

    function setupSafeWithBudget() internal returns (GnosisSafe safe, Budget budget) {
        address OWNER = address(this);

        address[] memory owners = new address[](1);
        owners[0] = OWNER;
        bytes memory safeInitData = abi.encodeWithSelector(
            GnosisSafe.setup.selector,
            owners,
            1,
            address(0),
            "",
            address(0),
            address(0),
            0,
            address(0)
        );
        safe = GnosisSafe(payable(safeFactory.createProxyWithNonce(safeImpl, safeInitData, 1)));
        budget = Budget(
            moduleFactory.deployModule(
                budgetImpl,
                abi.encodeWithSelector(
                    Budget.setUp.selector,
                    abi.encode(Budget.InitParams(OWNER, address(safe), address(safe)))
                ),
                1
            )
        );

        bytes memory addModuleData = abi.encodeWithSelector(ModuleManager.enableModule.selector, address(budget));
        bool success = safe.execTransaction(
            address(safe),
            0,
            addModuleData,
            Enum.Operation.Call,
            1000000,
            0,
            0,
            payable(0),
            payable(0),
            abi.encodePacked(abi.encode(address(this), 0), uint8(1))
        );
        assertTrue(success);
    }
}