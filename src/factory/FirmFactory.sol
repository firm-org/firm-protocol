// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {GnosisSafe} from "gnosis-safe/GnosisSafe.sol";
import {GnosisSafeProxyFactory} from "gnosis-safe/proxies/GnosisSafeProxyFactory.sol";

import {FirmRelayer} from "../metatx/FirmRelayer.sol";

import {IAvatar} from "../bases/IZodiacModule.sol";
import {Roles} from "../roles/Roles.sol";
import {Budget} from "../budget/Budget.sol";

import {UpgradeableModuleProxyFactory} from "./UpgradeableModuleProxyFactory.sol";

import {BackdoorModule} from "./local-utils/BackdoorModule.sol";

contract FirmFactory {
    GnosisSafeProxyFactory public immutable safeFactory;
    UpgradeableModuleProxyFactory public immutable moduleFactory;

    FirmRelayer public immutable relayer;

    address public immutable safeImpl;
    Roles public immutable rolesImpl;
    Budget public immutable budgetImpl;

    error EnableModuleFailed();

    event NewFirm(address indexed creator, GnosisSafe indexed safe, Roles roles, Budget budget);
    event DeployedBackdoors(GnosisSafe indexed safe, address[] backdoors);

    constructor(
        GnosisSafeProxyFactory _safeFactory,
        UpgradeableModuleProxyFactory _moduleFactory,
        FirmRelayer _relayer,
        address _safeImpl,
        Roles _rolesImpl,
        Budget _budgetImpl
    ) {
        safeFactory = _safeFactory;
        moduleFactory = _moduleFactory;
        relayer = _relayer;
        safeImpl = _safeImpl;
        rolesImpl = _rolesImpl;
        budgetImpl = _budgetImpl;
    }

    function createFirm(address creator, bool withBackdoors) public returns (GnosisSafe safe) {
        address[] memory owners = new address[](1);
        owners[0] = creator;

        return createFirm(owners, 1, withBackdoors);
    }

    function createFirm(address[] memory owners, uint256 requiredSignatures, bool withBackdoors) public returns (GnosisSafe safe) {
        bytes memory installModulesData = abi.encodeCall(this.installModules, (withBackdoors));
        bytes memory safeInitData = abi.encodeCall(
            GnosisSafe.setup, (owners, requiredSignatures, address(this), installModulesData, address(0), address(0), 0, payable(0))
        );

        // We set a random nonce to allow for several firms to be created using
        // the same initial config. It is possible that at some point we will
        // want to allow for counterfactual instantiation which will require
        // meaningful nonces
        uint256 nonce = block.difficulty; // randao number in POS
        safe = GnosisSafe(payable(safeFactory.createProxyWithNonce(safeImpl, safeInitData, nonce)));

        // NOTE: We shouldn't be spending on-chain gas for something that can be fetched off-chain
        // However, the subgraph is struggling with this so we have this temporarily
        uint256 modulesDeployed = 1;
        (address[] memory modules,) = safe.getModulesPaginated(address(0x1), modulesDeployed);
        Budget budget = Budget(modules[0]);
        Roles roles = Roles(address(budget.roles()));

        emit NewFirm(msg.sender, safe, roles, budget);

        if (withBackdoors) {
            (address[] memory backdoors,) = safe.getModulesPaginated(address(budget), 2);

            emit DeployedBackdoors(safe, backdoors);
        }
    }

    function installModules(bool _withBackdoors) public {
        // Safe will delegatecall here as part of its setup
        // We don't need to explictly guard against this function being called with a regular call
        // since we both perform calls on 'this' with the ABI of a Safe (will fail on this contract)

        IAvatar safe = IAvatar(address(this));
        Roles roles =
            Roles(moduleFactory.deployUpgradeableModule(rolesImpl, abi.encodeCall(Roles.initialize, (safe, address(relayer))), 1));
        Budget budget =
            Budget(moduleFactory.deployUpgradeableModule(budgetImpl, abi.encodeCall(Budget.initialize, (safe, roles, address(relayer))), 1));

        // NOTE: important to enable all backdoors before the real modules so the getter
        // works as expected (HACK)
        if (_withBackdoors) {
            safe.enableModule(address(new BackdoorModule(safe, address(budget))));
            safe.enableModule(address(new BackdoorModule(safe, address(roles))));
        }

        // Could optimize it by writing to Safe storage directly
        safe.enableModule(address(budget));
    }
}
