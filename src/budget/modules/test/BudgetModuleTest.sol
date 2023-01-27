// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import {FirmTest} from "src/bases/test/lib/FirmTest.sol";
import {SafeStub} from "src/bases/test/mocks/SafeStub.sol";
import {RolesStub} from "src/bases/test/mocks/RolesStub.sol";
import {TimeShift} from "src/budget/TimeShiftLib.sol";
import {TestnetERC20 as ERC20Token} from "src/testnet/TestnetTokenFaucet.sol";

import "../../Budget.sol";
import {BudgetModule} from "../BudgetModule.sol";

abstract contract BudgetModuleTest is FirmTest {
    SafeStub safe;
    RolesStub roles;
    Budget budget;
    ERC20Token token = new ERC20Token("", "", 0); // use the same token all the time to mimic using previously used llamapay instances

    function setUp() public virtual {
        safe = new SafeStub();
        roles = new RolesStub();
        budget = Budget(createProxy(new Budget(), abi.encodeCall(Budget.initialize, (safe, roles, address(0)))));
    }

    function module() internal view virtual returns (BudgetModule);

    function testInitialState() public {
        assertEq(address(module().budget()), address(budget));
        assertUnsStrg(address(module()), "firm.budgetmodule.budget", address(budget));

        assertEq(address(module().safe()), address(safe));
        assertUnsStrg(address(module()), "firm.safeaware.safe", address(safe));
    }

    function dailyAllowanceFor(address spender, uint256 amount) internal returns (uint256 allowanceId) {
        token.mint(address(safe), amount * 356 * 1000); // give it tokens so allowance is good for 1,000 years
        vm.prank(address(safe));
        return budget.createAllowance(
            NO_PARENT_ID, spender, address(token), amount, TimeShift(TimeShiftLib.TimeUnit.Daily, 0).encode(), ""
        );
    }

    function moduleInitData() internal view returns (bytes memory) {
        return abi.encodeCall(BudgetModule.initialize, (budget, address(0)));
    }
}
