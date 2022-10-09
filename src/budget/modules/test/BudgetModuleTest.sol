// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {FirmTest} from "../../../common/test/lib/FirmTest.sol";
import {AvatarStub} from "../../../common/test/mocks/AvatarStub.sol";
import {RolesStub} from "../../../common/test/mocks/RolesStub.sol";
import {TimeShift} from "../../../budget/TimeShiftLib.sol";
import {ERC20Token} from "../../../factory/test/lib/ERC20Token.sol";

import "../../Budget.sol";
import {BudgetModule} from "../BudgetModule.sol";

abstract contract BudgetModuleTest is FirmTest {
    AvatarStub avatar;
    RolesStub roles;
    Budget budget;
    ERC20Token token = new ERC20Token(); // use the same token all the time to mimic using previously used llamapay instances

    function setUp() public virtual {
        avatar = new AvatarStub();
        roles = new RolesStub();
        budget = Budget(createProxy(new Budget(), abi.encodeCall(Budget.initialize, (avatar, roles, address(0)))));
    }

    function dailyAllowanceFor(address spender, uint256 amount) internal returns (uint256 allowanceId) {
        token.mint(address(avatar), amount * 356 * 1000); // give it tokens so allowance is good for 1,000 years
        vm.prank(address(avatar));
        return budget.createAllowance(
            NO_PARENT_ID, spender, address(token), amount, TimeShift(TimeShiftLib.TimeUnit.Daily, 0).encode(), ""
        );
    }

    function moduleInitData() internal view returns (bytes memory) {
        return abi.encodeCall(BudgetModule.initialize, (budget, address(0)));
    }
}
