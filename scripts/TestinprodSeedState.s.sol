// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import 'forge-std/Test.sol';

import "gnosis-safe/GnosisSafe.sol";
import {Roles, IRoles, ISafe, ONLY_ROOT_ROLE_AS_ADMIN, ROOT_ROLE_ID} from "../src/roles/Roles.sol";
import {Budget, TimeShiftLib, NO_PARENT_ID, NATIVE_ASSET} from "../src/budget/Budget.sol";
import {TimeShift} from "../src/budget/TimeShiftLib.sol";
import {BackdoorModule} from "../src/factory/local-utils/BackdoorModule.sol";
import {roleFlag} from "../src/common/test/mocks/RolesAuthMock.sol";
import {TestnetTokenFaucet} from "../src/testnet/TestnetTokenFaucet.sol";

import {LlamaPayStreams, BudgetModule, IERC20, ForwarderLib} from "src/budget/modules/streams/LlamaPayStreams.sol";
import {TestinprodFactory, UpgradeableModuleProxyFactory, LATEST_VERSION} from "src/factory/TestinprodFactory.sol";

string constant LLAMAPAYSTREAMS_MODULE_ID = "org.firm.budget.llamapay-streams";

contract TestinprodSeedState is Test {
    error UnsupportedChain(uint256 chainId);

    TestnetTokenFaucet faucet;
    UpgradeableModuleProxyFactory moduleFactory;
    address USDC;

    // send some native asset to safe before running it
    function run(GnosisSafe safe) public {
        if (block.chainid == 5) {
            faucet = TestnetTokenFaucet(0x88A135e2f78C6Ef38E1b72A4B75Ad835fBd50CCE);
            moduleFactory = UpgradeableModuleProxyFactory(0x2Ef2b36AD44D5c5fdeECC5a6a38464BFe50b5Da2);
        } else if (block.chainid == 137) {
            faucet = TestnetTokenFaucet(0xA1dD2A67E26DC400b6dd31354bA653ea4EeF86F5);
            moduleFactory = UpgradeableModuleProxyFactory(0xCb3Dee447443B7F34aCd640AC8e304188512c2EC);
        } else {
            revert UnsupportedChain(block.chainid);
        }

        USDC = address(faucet.tokenWithSymbol("USDC"));

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
        {
            roleIds[0] = rolesBackdoor.createRole(ONLY_ROOT_ROLE_AS_ADMIN, "Executive role");
            roleIds[1] = rolesBackdoor.createRole(ONLY_ROOT_ROLE_AS_ADMIN | bytes32(1 << roleIds[0]), "Team member role");
            roleIds[2] = rolesBackdoor.createRole(ONLY_ROOT_ROLE_AS_ADMIN | bytes32(1 << roleIds[0]), "Dev role");

            uint8[] memory noRevokingRoles = new uint8[](0);

            // give all roles to all safe signers
            address[] memory safeOwners = safe.getOwners();
            for (uint256 i = 0; i < safeOwners.length; i++) {
                rolesBackdoor.setRoles(safeOwners[i], roleIds, noRevokingRoles);
            }
        }

        // create some allowances
        uint256 generalAllowanceId = budgetBackdoor.createAllowance(
            NO_PARENT_ID,
            roleFlag(roleIds[0]),
            USDC, 1_000_000e6,
            TimeShift(TimeShiftLib.TimeUnit.Yearly, 0).encode(),
            "General yearly budget"
        );
        uint256 subAllowanceId1 = budget.createAllowance(
            generalAllowanceId,
            roleFlag(roleIds[1]),
            USDC, 25_000e6,
            TimeShift(TimeShiftLib.TimeUnit.Monthly, 0).encode(),
            "Monthly payroll budget"
        );
        uint256 subAllowanceId2 = budget.createAllowance(
            generalAllowanceId,
            roleFlag(roleIds[1]),
            USDC, 30_000e6,
            TimeShift(TimeShiftLib.TimeUnit.NonRecurrent, int40(uint40(block.timestamp + 90 days))).encode(),
            "Quarter travel budget"
        );
        uint256 gasAllowanceId = budgetBackdoor.createAllowance(
            NO_PARENT_ID,
            roleFlag(roleIds[2]),
            NATIVE_ASSET, 1 ether,
            TimeShift(TimeShiftLib.TimeUnit.Weekly, 0).encode(),
            "Gas budget"
        );

        LlamaPayStreams streams = LlamaPayStreams(
            moduleFactory.deployUpgradeableModule(
                LLAMAPAYSTREAMS_MODULE_ID,
                LATEST_VERSION,
                abi.encodeCall(BudgetModule.initialize, (budget, address(0))),
                1
            )
        );
        uint256 streamsAllowanceId = budget.createAllowance(subAllowanceId1, address(streams), USDC, 0, TimeShift(TimeShiftLib.TimeUnit.Inherit, 0).encode(), "Streams module");
        streams.configure(streamsAllowanceId, 30 days);
        streams.startStream(streamsAllowanceId, 0xF1F182B70255AC4846E28fd56038F9019c8d36b0, uint256(1000 * 10 ** 20) / (30 days), "f1 salary");

        // create some payments from the allowances
        budgetBackdoor.executePayment(subAllowanceId2, 0x6b2b69c6e5490Be701AbFbFa440174f808C1a33B, 3600e6, "Devcon expenses");
        // budgetBackdoor.executePayment(gasAllowanceId, 0x0FF6156B4bed7A1322f5F59eB5af46760De2b872, 0.01 ether, "v0.3 deployment gas");
        budgetBackdoor.executePayment(generalAllowanceId, 0xFaE470CD6bce7EBac42B6da5082944D72328bC3b, 3000e6, "Equipment for new hire");
        budgetBackdoor.executePayment(subAllowanceId1, 0xe688b84b23f322a994A53dbF8E15FA82CDB71127, 22000e6, "Process monthly payroll");
        budgetBackdoor.executePayment(generalAllowanceId, 0x328375e18E7db8F1CA9d9bA8bF3E9C94ee34136A, 3000e6, "Special bonus");

        vm.stopBroadcast();
    }
}