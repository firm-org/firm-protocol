// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {GnosisSafe} from "gnosis-safe/GnosisSafe.sol";
import {GnosisSafeProxyFactory} from "gnosis-safe/proxies/GnosisSafeProxyFactory.sol";

import {FirmRelayer} from "../metatx/FirmRelayer.sol";

import {ISafe} from "../bases/ISafe.sol";
import {FirmRoles} from "../roles/FirmRoles.sol";
import {FirmBudget} from "../budget/FirmBudget.sol";

import {UpgradeableModuleProxyFactory, LATEST_VERSION} from "./UpgradeableModuleProxyFactory.sol";

import {BackdoorModule} from "./local-utils/BackdoorModule.sol";

string constant ROLES_MODULE_ID = "org.firm.roles";
string constant BUDGET_MODULE_ID = "org.firm.budget";

contract FirmFactory {
    GnosisSafeProxyFactory public immutable safeFactory;
    address public immutable safeImpl;

    UpgradeableModuleProxyFactory public immutable moduleFactory;
    FirmRelayer public immutable relayer;

    uint256 internal immutable safeProxySize;

    error EnableModuleFailed();
    error InvalidContext();

    event NewFirmCreated(address indexed creator, GnosisSafe indexed safe, FirmRoles roles, FirmBudget budget);
    event BackdoorsDeployed(GnosisSafe indexed safe, address[] backdoors);

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

        safeProxySize = _safeFactory.proxyRuntimeCode().length;
    }

    function createFirm(address creator, bool withBackdoors, uint256 nonce) public returns (GnosisSafe safe) {
        address[] memory owners = new address[](1);
        owners[0] = creator;

        return createFirm(owners, 1, withBackdoors, nonce);
    }

    function createFirm(address[] memory owners, uint256 requiredSignatures, bool withBackdoors, uint256 nonce)
        public
        returns (GnosisSafe safe)
    {
        bytes memory installModulesData = abi.encodeCall(this.installModules, (withBackdoors));
        bytes memory safeInitData = abi.encodeCall(
            GnosisSafe.setup,
            (owners, requiredSignatures, address(this), installModulesData, address(0), address(0), 0, payable(0))
        );

        safe = GnosisSafe(payable(safeFactory.createProxyWithNonce(safeImpl, safeInitData, nonce)));

        // NOTE: We shouldn't be spending on-chain gas for something that can be fetched off-chain
        // However, the subgraph is struggling with this so we have this temporarily
        uint256 modulesDeployed = 1;
        (address[] memory modules,) = safe.getModulesPaginated(address(0x1), modulesDeployed);
        FirmBudget budget = FirmBudget(modules[0]);
        FirmRoles roles = FirmRoles(address(budget.roles()));

        emit NewFirmCreated(msg.sender, safe, roles, budget);

        if (withBackdoors) {
            (address[] memory backdoors,) = safe.getModulesPaginated(address(budget), 2);

            emit BackdoorsDeployed(safe, backdoors);
        }
    }

    // Safe will delegatecall here as part of its setup, can only run on a delegatecall
    function installModules(bool _withBackdoors) public {
        // Ensure that we are running on a delegatecall from a safe proxy
        if (address(this).code.length != safeProxySize) {
            revert InvalidContext();
        }

        // We don't need to explictly guard against this function being called with a regular call
        // since we both perform calls on 'this' with the ABI of a Safe (will fail on this contract)

        GnosisSafe safe = GnosisSafe(payable(address(this)));
        FirmRoles roles = FirmRoles(
            moduleFactory.deployUpgradeableModule(
                ROLES_MODULE_ID,
                LATEST_VERSION,
                abi.encodeCall(FirmRoles.initialize, (ISafe(payable(safe)), address(relayer))),
                1
            )
        );
        FirmBudget budget = FirmBudget(
            moduleFactory.deployUpgradeableModule(
                BUDGET_MODULE_ID,
                LATEST_VERSION,
                abi.encodeCall(FirmBudget.initialize, (ISafe(payable(safe)), roles, address(relayer))),
                1
            )
        );

        // NOTE: important to enable all backdoors before the real modules so the getter
        // works as expected (HACK)
        if (_withBackdoors) {
            safe.enableModule(address(new BackdoorModule(ISafe(payable(safe)), address(budget))));
            safe.enableModule(address(new BackdoorModule(ISafe(payable(safe)), address(roles))));
        }

        // Could optimize it by writing to Safe storage directly
        safe.enableModule(address(budget));
    }
}
