// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import {Test} from "forge-std/Test.sol";

import {GnosisSafe} from "safe/GnosisSafe.sol";
import {Roles, IRoles, ISafe, ONLY_ROOT_ROLE_AS_ADMIN, ROOT_ROLE_ID} from "src/roles/Roles.sol";
import {Budget, TimeShiftLib, NO_PARENT_ID, NATIVE_ASSET} from "src/budget/Budget.sol";
import {Captable, NO_CONVERSION_FLAG} from "src/captable/Captable.sol";
import {Voting} from "src/voting/Voting.sol";
import {Semaphore} from "src/semaphore/Semaphore.sol";
import {TimeShift} from "src/budget/TimeShiftLib.sol";
import {roleFlag} from "src/bases/test/lib/RolesAuthFlags.sol";
import {targetFlag, SemaphoreTargetsFlag} from "src/factory/config/SemaphoreTargets.sol";
import {bouncerFlag, EmbeddedBouncerType} from "src/captable/test/lib/BouncerFlags.sol";
import {TestnetTokenFaucet} from "src/testnet/TestnetTokenFaucet.sol";

import {LlamaPayStreams, BudgetModule, IERC20, ForwarderLib} from "src/budget/modules/streams/LlamaPayStreams.sol";
import {FirmFactory, UpgradeableModuleProxyFactory, LATEST_VERSION} from "src/factory/FirmFactory.sol";

import {FirmFactoryDeployLocal} from "./FirmFactoryDeploy.s.sol";
import {TestnetFaucetDeploy} from "./TestnetFaucetDeploy.s.sol";

string constant LLAMAPAYSTREAMS_MODULE_ID = "org.firm.budget.llamapay-streams";

contract CreateFirmSeedState is Test {
    error UnsupportedChain(uint256 chainId);

    TestnetTokenFaucet faucet;
    FirmFactory factory;
    UpgradeableModuleProxyFactory moduleFactory;
    address USDC;

    function run() public returns (GnosisSafe safe) {
        if (block.chainid == 5) { // goerli
            faucet = TestnetTokenFaucet(0x88A135e2f78C6Ef38E1b72A4B75Ad835fBd50CCE);
            factory = FirmFactory(0x1Ce5621D386B2801f5600F1dBe29522805b8AC11); // v1.0
        } else if (block.chainid == 137) { // matic
            faucet = TestnetTokenFaucet(0xA1dD2A67E26DC400b6dd31354bA653ea4EeF86F5);
            factory = FirmFactory(0xaC722c66312fC581Bc57Ee4141871Fe0bf22fA08); // v1.0
        } else if (block.chainid == 31337) { // anvil
            faucet = (new TestnetFaucetDeploy()).run();
            factory = FirmFactory(0x3Aa5ebB10DC797CAC828524e59A333d0A371443c);
            
            // On local env, deploy the factory if it hasn't been deployed yet
            if (address(factory).code.length == 0) {
                (factory,) = (new FirmFactoryDeployLocal()).run();
            }
        } else {
            revert UnsupportedChain(block.chainid);
        }
        moduleFactory = factory.moduleFactory();
        USDC = address(faucet.tokenWithSymbol("USDC"));

        FirmFactory.SafeConfig memory safeConfig = factory.defaultOneOwnerSafeConfig(msg.sender);
        FirmFactory.FirmConfig memory firmConfig = buildFirmConfig();

        vm.broadcast();
        safe = factory.createFirm(safeConfig, firmConfig, block.timestamp);

        (address[] memory modules,) = safe.getModulesPaginated(address(0x1), 2);
        Budget budget = Budget(modules[1]);
        Roles roles = Roles(address(budget.roles()));
        Voting voting = Voting(payable(modules[0]));
        Captable captable = Captable(address(voting.token()));

        // sanity check
        assertEq(budget.moduleId(), "org.firm.budget");
        assertEq(roles.moduleId(), "org.firm.roles");

        vm.startBroadcast();
        faucet.drip("USDC", address(safe), 500000e6);
        faucet.drip("EUROC", address(safe), 47500e6);
        faucet.drip("WBTC", address(safe), 3.5e8);

        LlamaPayStreams streams = LlamaPayStreams(
            moduleFactory.deployUpgradeableModule(
                LLAMAPAYSTREAMS_MODULE_ID,
                LATEST_VERSION,
                abi.encodeCall(BudgetModule.initialize, (budget, address(0))),
                1
            )
        );
        uint256 generalAllowanceId = 1;
        uint256 subAllowanceId1 = 2;
        uint256 streamsAllowanceId = budget.createAllowance(subAllowanceId1, address(streams), USDC, 0, TimeShift(TimeShiftLib.TimeUnit.Inherit, 0).encode(), "Streams module");
        streams.configure(streamsAllowanceId, 30 days);
        streams.startStream(streamsAllowanceId, 0xF1F182B70255AC4846E28fd56038F9019c8d36b0, uint256(1000 * 10 ** 20) / (30 days), "f1 salary");

        // create some payments from the allowances
        budget.executePayment(subAllowanceId1 + 1, 0x6b2b69c6e5490Be701AbFbFa440174f808C1a33B, 3600e6, "Devcon expenses");
        // budgetBackdoor.executePayment(gasAllowanceId, 0x0FF6156B4bed7A1322f5F59eB5af46760De2b872, 0.01 ether, "v0.3 deployment gas");
        budget.executePayment(generalAllowanceId, 0xFaE470CD6bce7EBac42B6da5082944D72328bC3b, 3000e6, "Equipment for new hire");
        budget.executePayment(subAllowanceId1, 0xe688b84b23f322a994A53dbF8E15FA82CDB71127, 22000e6, "Process monthly payroll");
        budget.executePayment(generalAllowanceId, 0x328375e18E7db8F1CA9d9bA8bF3E9C94ee34136A, 3000e6, "Special bonus");

        // trigger a share conversion
        captable.convert(1, 100_000);

        vm.stopBroadcast();
    }

    function buildFirmConfig() internal view returns (FirmFactory.FirmConfig memory) {
        address owner = msg.sender;

        // Roles config
        address[] memory grantees = new address[](1);
        grantees[0] = owner;
        FirmFactory.RoleCreationInput[] memory roles = new FirmFactory.RoleCreationInput[](3);
        uint8 executiveRoleId = 2;
        roles[0] = FirmFactory.RoleCreationInput(ONLY_ROOT_ROLE_AS_ADMIN, "Executive role", grantees);
        roles[1] = FirmFactory.RoleCreationInput(ONLY_ROOT_ROLE_AS_ADMIN | bytes32(1 << executiveRoleId), "Team member role", grantees);
        roles[2] = FirmFactory.RoleCreationInput(ONLY_ROOT_ROLE_AS_ADMIN | bytes32(1 << executiveRoleId), "Dev role", grantees);

        // Budget config
        FirmFactory.AllowanceCreationInput[] memory allowances = new FirmFactory.AllowanceCreationInput[](4);
        uint256 generalAllowanceId = 1;
        allowances[0] = FirmFactory.AllowanceCreationInput(
            NO_PARENT_ID,
            roleFlag(executiveRoleId),
            USDC, 1_000_000e6,
            TimeShift(TimeShiftLib.TimeUnit.Yearly, 0).encode(),
            "General yearly budget"
        );
        allowances[1] = FirmFactory.AllowanceCreationInput(
            generalAllowanceId,
            roleFlag(executiveRoleId + 1),
            USDC, 25_000e6,
            TimeShift(TimeShiftLib.TimeUnit.Monthly, 0).encode(),
            "Monthly payroll budget"
        );
        allowances[2] = FirmFactory.AllowanceCreationInput(
            generalAllowanceId,
            roleFlag(executiveRoleId + 1),
            USDC, 30_000e6,
            TimeShift(TimeShiftLib.TimeUnit.NonRecurrent, int40(uint40(block.timestamp + 90 days))).encode(),
            "Quarter travel budget"
        );
        allowances[3] = FirmFactory.AllowanceCreationInput(
            NO_PARENT_ID,
            roleFlag(executiveRoleId + 2),
            NATIVE_ASSET, 1 ether,
            TimeShift(TimeShiftLib.TimeUnit.Weekly, 0).encode(),
            "Gas budget"
        );

        // Captable config
        FirmFactory.ClassCreationInput[] memory classes = new FirmFactory.ClassCreationInput[](2);
        classes[0] = FirmFactory.ClassCreationInput(
            "Common", "SDC-A",
            100_000_000 ether,
            NO_CONVERSION_FLAG,
            1,
            bouncerFlag(EmbeddedBouncerType.AllowAll)
        );
        classes[1] = FirmFactory.ClassCreationInput(
            "Supervoting", "SDC-B",
            classes[0].authorized / 100, // 1% of the authorized can be issued as supervoting shares
            0,
            10, // 10x voting power
            bouncerFlag(EmbeddedBouncerType.DenyAll)
        );

        FirmFactory.ShareIssuanceInput[] memory issuances = new FirmFactory.ShareIssuanceInput[](3);
        issuances[0] = FirmFactory.ShareIssuanceInput(0, msg.sender, 5_000_000 ether);
        issuances[1] = FirmFactory.ShareIssuanceInput(1, msg.sender, 500_000 ether);
        issuances[2] = FirmFactory.ShareIssuanceInput(0, 0x6b2b69c6e5490Be701AbFbFa440174f808C1a33B, 3_000_000 ether);

        // Voting config
        FirmFactory.VotingConfig memory votingConfig = FirmFactory.VotingConfig({
            quorumNumerator: 100, // 1%
            votingDelay: 0, // 0 blocks
            votingPeriod: 100, // 100 blocks
            proposalThreshold: 1 // Any shareholder can start a vote
        });

        FirmFactory.SemaphoreException[] memory semaphoreExceptions = new FirmFactory.SemaphoreException[](1);
        semaphoreExceptions[0] = FirmFactory.SemaphoreException({
            exceptionType: Semaphore.ExceptionType.Target,
            target: targetFlag(SemaphoreTargetsFlag.Safe),
            sig: bytes4(0)
        });

        // Semaphore config
        FirmFactory.SemaphoreConfig memory semaphoreConfig = FirmFactory.SemaphoreConfig({
            safeDefaultAllowAll: true,
            safeAllowDelegateCalls: true,
            votingAllowValueCalls: false,
            semaphoreExceptions: semaphoreExceptions
        });

        return FirmFactory.FirmConfig({
            withCaptableAndVoting: true,
            withSemaphore: true,
            rolesConfig: FirmFactory.RolesConfig(roles),
            budgetConfig: FirmFactory.BudgetConfig(allowances),
            captableConfig: FirmFactory.CaptableConfig("Seed Company, Inc.", classes, issuances),
            votingConfig: votingConfig,
            semaphoreConfig: semaphoreConfig
        });
    }
}