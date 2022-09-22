// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import 'forge-std/Test.sol';

import "gnosis-safe/GnosisSafe.sol";
import {Roles, IRoles, IAvatar, ONLY_ROOT_ROLE} from "../src/roles/Roles.sol";
import {Budget, TimeShiftLib, NO_PARENT_ID, NATIVE_ASSET} from "../src/budget/Budget.sol";
import {TimeShift} from "../src/budget/TimeShiftLib.sol";
import {BackdoorModule} from "../src/factory/local-utils/BackdoorModule.sol";
import {roleFlag} from "../src/common/test/mocks/RolesAuthMock.sol";

contract TestinProdSeedState is Test {
    // send some native asset to safe before running it
    function run(GnosisSafe safe) public {
        // only works for backdoored firms which have 3 modules: [budget, budgetBackdoor, rolesBackdoor]
        (address[] memory modules,) = safe.getModulesPaginated(address(0x1), 3);

        Budget budget = Budget(modules[0]);
        Roles roles = Roles(address(budget.roles()));
        Roles rolesBackdoor = Roles(modules[1]);
        Budget budgetBackdoor = Budget(modules[2]);

        // sanity check
        assertEq(budget.moduleId(), "org.firm.budget");
        assertEq(roles.moduleId(), "org.firm.roles");
        assertEq(budgetBackdoor.moduleId(), "org.firm.backdoor");
        assertEq(rolesBackdoor.moduleId(), "org.firm.backdoor");
        assertEq(BackdoorModule(address(budgetBackdoor)).module(), address(budget));
        assertEq(BackdoorModule(address(rolesBackdoor)).module(), address(roles));

        vm.startBroadcast();

        uint8 roleId = rolesBackdoor.createRole(ONLY_ROOT_ROLE, "Exec role");
        address[] memory safeOwners = safe.getOwners();
        for (uint256 i = 0; i < safeOwners.length; i++) {
            rolesBackdoor.setRole(safeOwners[i], roleId, true);
        }
        uint256 allowanceId = budgetBackdoor.createAllowance(
            NO_PARENT_ID,
            roleFlag(roleId),
            NATIVE_ASSET, 1 ether,
            TimeShift(TimeShiftLib.TimeUnit.Monthly, 0).encode(),
            "General budget"
        );
        budgetBackdoor.executePayment(
            allowanceId,
            0xB4FBF271143F4FBf7B91A5ded31805e42b2208d6, // goerli weth
            0.01 ether,
            "Wrap some eth"
        );

        vm.stopBroadcast();
    }
}