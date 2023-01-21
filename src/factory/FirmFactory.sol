// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import {GnosisSafe} from "gnosis-safe/GnosisSafe.sol";
import {GnosisSafeProxyFactory} from "gnosis-safe/proxies/GnosisSafeProxyFactory.sol";

import {FirmRelayer} from "../metatx/FirmRelayer.sol";

import {ISafe} from "../bases/interfaces/ISafe.sol";
import {Roles} from "../roles/Roles.sol";
import {Budget, EncodedTimeShift} from "../budget/Budget.sol";
import {Captable, IBouncer} from "../captable/Captable.sol";
import {Voting} from "../voting/Voting.sol";

import {UpgradeableModuleProxyFactory, LATEST_VERSION} from "./UpgradeableModuleProxyFactory.sol";

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
        // if false, only roles and budget are created
        bool withCaptableAndVoting;
        // budget and roles are always created
        BudgetConfig budgetConfig;
        RolesConfig rolesConfig;
        // optional depending on 'withCaptableAndVoting'
        CaptableConfig captableConfig;
        VotingConfig votingConfig;
    }

    struct BudgetConfig {
        AllowanceCreationInput[] allowances;
    }

    struct AllowanceCreationInput {
        uint256 parentAllowanceId;
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

    struct CaptableConfig {
        string name;
        ClassCreationInput[] classes;
        ShareIssuanceInput[] issuances;
    }

    struct ClassCreationInput {
        string className;
        string ticker;
        uint256 authorized;
        uint32 convertsToClassId;
        uint64 votingWeight;
        IBouncer bouncer;
    }

    struct ShareIssuanceInput {
        uint256 classId;
        address account;
        uint256 amount;
    }

    struct VotingConfig {
        uint256 quorumNumerator;
        uint256 votingDelay;
        uint256 votingPeriod;
        uint256 proposalThreshold;
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
            (
                safeConfig.owners,
                safeConfig.requiredSignatures,
                address(this),
                setupFirmData,
                address(0),
                address(0),
                0,
                payable(0)
            )
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
        safe.enableModule(address(budget));

        if (config.withCaptableAndVoting) {
            Captable captable = setupCaptable(config.captableConfig, nonce);
            Voting voting = setupVoting(config.votingConfig, captable, nonce);
            safe.enableModule(address(voting));
        }
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
                allowance.parentAllowanceId,
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

    function setupCaptable(CaptableConfig calldata config, uint256 nonce) internal returns (Captable captable) {
        // Function should only be run in Safe context. It assumes that this check already ocurred
        captable = Captable(
            moduleFactory.deployUpgradeableModule(
                CAPTABLE_MODULE_ID,
                LATEST_VERSION,
                abi.encodeCall(Captable.initialize, (config.name, ISafe(payable(address(this))), address(relayer))),
                nonce
            )
        );

        // As we are the safe, we can just create the classes and issue shares
        uint256 classCount = config.classes.length;
        for (uint256 i = 0; i < classCount;) {
            ClassCreationInput memory class = config.classes[i];
            captable.createClass(
                class.className,
                class.ticker,
                class.authorized,
                class.convertsToClassId,
                class.votingWeight,
                class.bouncer
            );

            unchecked {
                ++i;
            }
        }

        uint256 issuanceCount = config.issuances.length;
        for (uint256 i = 0; i < issuanceCount;) {
            ShareIssuanceInput memory issuance = config.issuances[i];
            // it is possible that this reverts if the class does not exist or
            // the amount to be issued goes over the authorized amount
            captable.issue(issuance.account, issuance.classId, issuance.amount);

            unchecked {
                ++i;
            }
        }
    }

    function setupVoting(VotingConfig calldata config, Captable captable, uint256 nonce)
        internal
        returns (Voting voting)
    {
        // Function should only be run in Safe context. It assumes that this check already ocurred
        bytes memory votingInitData = abi.encodeCall(
            Voting.initialize,
            (
                ISafe(payable(address(this))),
                captable,
                config.quorumNumerator,
                config.votingDelay,
                config.votingPeriod,
                config.proposalThreshold,
                address(relayer)
            )
        );
        voting = Voting(
            payable(moduleFactory.deployUpgradeableModule(VOTING_MODULE_ID, LATEST_VERSION, votingInitData, nonce))
        );
    }

    function defaultOneOwnerSafeConfig(address owner) public pure returns (SafeConfig memory) {
        address[] memory owners = new address[](1);
        owners[0] = owner;
        return SafeConfig({owners: owners, requiredSignatures: 1});
    }

    function defaultBarebonesFirmConfig() public pure returns (FirmConfig memory) {
        BudgetConfig memory budgetConfig = BudgetConfig({allowances: new AllowanceCreationInput[](0)});
        RolesConfig memory rolesConfig = RolesConfig({roles: new RoleCreationInput[](0)});
        CaptableConfig memory captableConfig;
        VotingConfig memory votingConfig;

        return FirmConfig({
            withCaptableAndVoting: false,
            budgetConfig: budgetConfig,
            rolesConfig: rolesConfig,
            captableConfig: captableConfig,
            votingConfig: votingConfig
        });
    }
}
