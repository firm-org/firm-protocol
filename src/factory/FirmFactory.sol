// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {GnosisSafe} from "gnosis-safe/GnosisSafe.sol";
import {GnosisSafeProxyFactory} from "gnosis-safe/proxies/GnosisSafeProxyFactory.sol";

import {FirmRelayer} from "../metatx/FirmRelayer.sol";

import {ISafe} from "../bases/ISafe.sol";
import {Roles} from "../roles/Roles.sol";
import {Budget, EncodedTimeShift, NO_PARENT_ID} from "../budget/Budget.sol";

import {UpgradeableModuleProxyFactory, LATEST_VERSION} from "./UpgradeableModuleProxyFactory.sol";

import {BackdoorModule} from "./local-utils/BackdoorModule.sol";

string constant ROLES_MODULE_ID = "org.firm.roles";
string constant BUDGET_MODULE_ID = "org.firm.budget";
string constant CAPTABLE_MODULE_ID = "org.firm.captable";
string constant VOTING_MODULE_ID = "org.firm.voting";

contract FirmFactory {
    GnosisSafeProxyFactory public immutable safeFactory;
    address public immutable safeImpl;

    UpgradeableModuleProxyFactory public immutable moduleFactory;
    FirmRelayer public immutable relayer;

    address internal immutable cachedThis;

    error EnableModuleFailed();
    error InvalidContext();

    event NewFirmCreated(address indexed creator, GnosisSafe indexed safe);

    constructor(
        GnosisSafeProxyFactory _safeFactory,
        UpgradeableModuleProxyFactory _moduleFactory,
        FirmRelayer _relayer,
        address _safeImpl
    ) {
        safeFactory = _safeFactory;
        moduleFactory = _moduleFactory;
        relayer = _relayer;
        safeImpl = _safeImpl;

        cachedThis = address(this);
    }

    struct SafeConfig {
        address[] owners;
        uint256 requiredSignatures;
    }

    struct FirmConfig {
        BudgetConfig budgetConfig;
        RolesConfig rolesConfig;
        bool withCaptableAndVoting;
    }

    struct BudgetConfig {
        AllowanceCreationInput[] allowances;
    }
    struct AllowanceCreationInput {
        address spender;
        address token;
        uint256 amount;
        EncodedTimeShift recurrency;
        string name;
    }

    struct RolesConfig {
        RoleCreationInput[] roles;
    }
    struct RoleCreationInput {
        bytes32 roleAdmins;
        string name;
        address[] grantees;
    }

    function createBarebonesFirm(address owner, uint256 nonce) public returns (GnosisSafe safe) {
        return createFirm(defaultOneOwnerSafeConfig(owner), defaultBarebonesFirmConfig(), nonce);
    }
    
    function createFirm(SafeConfig memory safeConfig, FirmConfig memory firmConfig, uint256 nonce)
        public
        returns (GnosisSafe safe)
    {
        bytes memory setupFirmData = abi.encodeCall(this.setupFirm, (firmConfig, nonce));
        bytes memory safeInitData = abi.encodeCall(
            GnosisSafe.setup,
            (safeConfig.owners, safeConfig.requiredSignatures, address(this), setupFirmData, address(0), address(0), 0, payable(0))
        );

        safe = GnosisSafe(payable(safeFactory.createProxyWithNonce(safeImpl, safeInitData, nonce)));

        emit NewFirmCreated(msg.sender, safe);
    }

    // Safe will delegatecall here as part of its setup, can only run on a delegatecall
    function setupFirm(FirmConfig calldata config, uint256 nonce) external {
        // Ensure that we are running on a delegatecall and not in a direct call to this external function
        // cachedThis is set to the address of this contract in the constructor as an immutable
        GnosisSafe safe = GnosisSafe(payable(address(this)));
        if (address(safe) == cachedThis) {
            revert InvalidContext();
        }

        Roles roles = setupRoles(config.rolesConfig, nonce);
        Budget budget = setupBudget(config.budgetConfig, roles, nonce);

        // Could gas optimize it by writing to Safe storage directly
        safe.enableModule(address(budget));
    }

    function setupBudget(BudgetConfig calldata config, Roles roles, uint256 nonce) internal returns (Budget budget) {
        // Function should only be run in Safe context. It assumes that this check already ocurred
        budget = Budget(
            moduleFactory.deployUpgradeableModule(
                BUDGET_MODULE_ID,
                LATEST_VERSION,
                abi.encodeCall(Budget.initialize, (ISafe(payable(address(this))), roles, address(relayer))),
                nonce
            )
        );

        // As we are the safe, we can just create the top-level allowances as the safe has that power
        uint256 allowanceCount = config.allowances.length;
        for (uint256 i = 0; i < allowanceCount;) {
            AllowanceCreationInput memory allowance = config.allowances[i];

            budget.createAllowance(
                NO_PARENT_ID,
                allowance.spender,
                allowance.token,
                allowance.amount,
                allowance.recurrency,
                allowance.name
            );

            unchecked {
                ++i;
            }
        }
    }

    function setupRoles(RolesConfig calldata config, uint256 nonce) internal returns (Roles roles) {
        // Function should only be run in Safe context. It assumes that this check already ocurred
        roles = Roles(
            moduleFactory.deployUpgradeableModule(
                ROLES_MODULE_ID,
                LATEST_VERSION,
                abi.encodeCall(Roles.initialize, (ISafe(payable(address(this))), address(relayer))),
                nonce
            )
        );

        // As we are the safe, we can just create the roles and assign them as the safe has the root role
        uint256 roleCount = config.roles.length;
        for (uint256 i = 0; i < roleCount;) {
            RoleCreationInput memory role = config.roles[i];
            uint8 roleId = roles.createRole(role.roleAdmins, role.name);

            uint256 granteeCount = role.grantees.length;
            for (uint256 j = 0; j < granteeCount;) {
                roles.setRole(role.grantees[j], roleId, true);

                unchecked {
                    ++j;
                }
            }

            unchecked {
                ++i;
            }
        }
    }

    function defaultOneOwnerSafeConfig(address owner) internal pure returns (SafeConfig memory) {
        address[] memory owners = new address[](1);
        owners[0] = owner;
        return SafeConfig({ owners: owners, requiredSignatures: 1 });
    }

    function defaultBarebonesFirmConfig() internal pure returns (FirmConfig memory) {
        BudgetConfig memory budgetConfig = BudgetConfig({ allowances: new AllowanceCreationInput[](0) });
        RolesConfig memory rolesConfig = RolesConfig({ roles: new RoleCreationInput[](0) });
        return FirmConfig({
            budgetConfig: budgetConfig,
            rolesConfig: rolesConfig,
            withCaptableAndVoting: false
        });
    }
}
