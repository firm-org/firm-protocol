// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {GnosisSafe} from "gnosis-safe/GnosisSafe.sol";
import {GnosisSafeProxyFactory} from "gnosis-safe/proxies/GnosisSafeProxyFactory.sol";

import {IAvatar} from "../bases/IZodiacModule.sol";
import {Roles} from "../roles/Roles.sol";
import {Budget} from "../budget/Budget.sol";

import {UpgradeableModuleProxyFactory} from "./UpgradeableModuleProxyFactory.sol";

contract FirmFactory {
    GnosisSafeProxyFactory public immutable safeFactory;
    UpgradeableModuleProxyFactory public immutable moduleFactory;

    address public immutable safeImpl;
    address public immutable rolesImpl;
    address public immutable budgetImpl;

    error EnableModuleFailed();

    event NewFirm(address indexed creator, GnosisSafe indexed safe);

    constructor(
        GnosisSafeProxyFactory _safeFactory,
        UpgradeableModuleProxyFactory _moduleFactory,
        address _safeImpl,
        address _rolesImpl,
        address _budgetImpl
    ) {
        safeFactory = _safeFactory;
        moduleFactory = _moduleFactory;
        safeImpl = _safeImpl;
        rolesImpl = _rolesImpl;
        budgetImpl = _budgetImpl;
    }

    function createFirm(address _creator) public returns (GnosisSafe safe) {
        address[] memory owners = new address[](1);
        owners[0] = _creator;
        // TODO: Use abi.encodeCall when it supports implicit type conversion for external calls (memory -> calldata)
        // https://github.com/ethereum/solidity/issues/12718
        bytes memory safeInitData = abi.encodeWithSelector(
            GnosisSafe.setup.selector,
            owners,
            1,
            address(this),
            abi.encodeCall(this.installModules, ()),
            address(0),
            address(0),
            0,
            address(0)
        );
        safe = GnosisSafe(payable(safeFactory.createProxyWithNonce(safeImpl, safeInitData, 1)));

        emit NewFirm(_creator, safe);
    }

    function installModules() public {
        // Safe will delegatecall here as part of its setup
        // We don't need to explictly guard against this function being called with a regular call
        // since we both perform calls on 'this' with the ABI of a Safe (will fail on this contract)

        IAvatar safe = IAvatar(address(this));
        Roles roles =
            Roles(moduleFactory.deployUpgradeableModule(rolesImpl, abi.encodeCall(Roles.initialize, (safe)), 1));
        Budget budget =
            Budget(moduleFactory.deployUpgradeableModule(budgetImpl, abi.encodeCall(Budget.initialize, (safe, roles)), 1));

        // Could optimize it by writing to Safe storage directly
        safe.enableModule(address(budget));
    }
}
