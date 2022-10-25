// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import 'forge-std/Test.sol';

import "gnosis-safe/GnosisSafe.sol";
import {Roles, IRoles, IAvatar, ONLY_ROOT_ROLE, ROOT_ROLE_ID} from "../src/roles/Roles.sol";
import {Budget, TimeShiftLib, NO_PARENT_ID, NATIVE_ASSET} from "../src/budget/Budget.sol";
import {TimeShift} from "../src/budget/TimeShiftLib.sol";
import {BackdoorModule} from "../src/factory/local-utils/BackdoorModule.sol";
import {roleFlag} from "../src/common/test/mocks/RolesAuthMock.sol";
import {TestnetTokenFaucet} from "../src/testnet/TestnetTokenFaucet.sol";

contract TestinprodSeedState is Test {
    error UnsupportedChain(uint256 chainId);

    // send some native asset to safe before running it
    function run(GnosisSafe safe) public {
        TestnetTokenFaucet faucet;
        if (block.chainid == 5) {
            faucet = TestnetTokenFaucet(0x88A135e2f78C6Ef38E1b72A4B75Ad835fBd50CCE);
        } else {
            revert UnsupportedChain(block.chainid);
        }

        // only works for backdoored firms which have 3 modules: [budget, rolesBackdoor, budgetBackdoor]
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

        faucet.drip("USDC", address(safe), 500000e6);
        faucet.drip("EUROC", address(safe), 47500e6);
        faucet.drip("WBTC", address(safe), 3.5e8);

        // make sure sender is root
        rolesBackdoor.setRole(msg.sender, ROOT_ROLE_ID, true);

        // create some roles
        uint8[] memory roleIds = new uint8[](3);
        roleIds[0] = rolesBackdoor.createRole(ONLY_ROOT_ROLE, "Executive role");
        roleIds[1] = rolesBackdoor.createRole(ONLY_ROOT_ROLE | bytes32(1 << roleIds[0]), "Team member role");
        roleIds[2] = rolesBackdoor.createRole(ONLY_ROOT_ROLE | bytes32(1 << roleIds[0]), "Dev role");

        uint8[] memory noRevokingRoles = new uint8[](0);

        // give all roles to all safe signers
        address[] memory safeOwners = safe.getOwners();
        for (uint256 i = 0; i < safeOwners.length; i++) {
            rolesBackdoor.setRoles(safeOwners[i], roleIds, noRevokingRoles);
        }

        // create some allowances
        uint256 generalAllowanceId = budgetBackdoor.createAllowance(
            NO_PARENT_ID,
            roleFlag(roleIds[0]),
            address(faucet.tokenWithSymbol("USDC")), 1_000_000e6,
            TimeShift(TimeShiftLib.TimeUnit.Yearly, 0).encode(),
            "General yearly budget"
        );
        uint256 subAllowanceId1 = budget.createAllowance(
            generalAllowanceId,
            roleFlag(roleIds[1]),
            address(faucet.tokenWithSymbol("USDC")), 25_000e6,
            TimeShift(TimeShiftLib.TimeUnit.Monthly, 0).encode(),
            "Monthly payroll budget"
        );
        uint256 subAllowanceId2 = budget.createAllowance(
            generalAllowanceId,
            roleFlag(roleIds[1]),
            address(faucet.tokenWithSymbol("USDC")), 30_000e6,
            TimeShift(TimeShiftLib.TimeUnit.Quarterly, 0).encode(),
            "Quarterly travel budget"
        );
        uint256 gasAllowanceId = budgetBackdoor.createAllowance(
            NO_PARENT_ID,
            roleFlag(roleIds[2]),
            NATIVE_ASSET, 1 ether,
            TimeShift(TimeShiftLib.TimeUnit.Weekly, 0).encode(),
            "Gas budget"
        );

        // create some payments from the allowances
        budgetBackdoor.executePayment(subAllowanceId2, 0x6b2b69c6e5490Be701AbFbFa440174f808C1a33B, 3600e6, "Devcon expenses");
        budgetBackdoor.executePayment(gasAllowanceId, 0x0FF6156B4bed7A1322f5F59eB5af46760De2b872, 0.01 ether, "v0.3 deployment gas");
        budgetBackdoor.executePayment(generalAllowanceId, 0xFaE470CD6bce7EBac42B6da5082944D72328bC3b, 3000e6, "Equipment for new hire");
        budgetBackdoor.executePayment(subAllowanceId1, 0xe688b84b23f322a994A53dbF8E15FA82CDB71127, 22000e6, "Process monthly payroll");
        budgetBackdoor.executePayment(generalAllowanceId, 0x328375e18E7db8F1CA9d9bA8bF3E9C94ee34136A, 3000e6, "Special bonus");

        vm.stopBroadcast();
    }
}