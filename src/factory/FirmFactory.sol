// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "gnosis-safe/GnosisSafe.sol";
import "gnosis-safe/proxies/GnosisSafeProxyFactory.sol";
import "zodiac/factory/ModuleProxyFactory.sol";
import "zodiac/interfaces/IAvatar.sol";

import {Roles} from "../roles/Roles.sol";
import {Budget} from "../budget/Budget.sol";

contract FirmFactory {
    GnosisSafeProxyFactory immutable safeFactory;
    ModuleProxyFactory immutable moduleFactory;

    address immutable safeImpl;
    address immutable rolesImpl;
    address immutable budgetImpl;

    error EnableModuleFailed();

    constructor(
        GnosisSafeProxyFactory _safeFactory,
        ModuleProxyFactory _moduleFactory,
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

    function createFirm(address _creator) public returns (GnosisSafe safe, Budget budget, Roles roles) {
        address[] memory owners = new address[](1);
        owners[0] = _creator;
        bytes memory safeInitData = abi.encodeWithSelector(
            GnosisSafe.setup.selector,
            owners,
            1,
            address(this),
            abi.encodeWithSelector(this.installModules.selector),
            address(0),
            address(0),
            0,
            address(0)
        );
        safe = GnosisSafe(payable(safeFactory.createProxyWithNonce(safeImpl, safeInitData, 1)));
        
        (address[] memory modules,) = safe.getModulesPaginated(address(0x1), 1);
        budget = Budget(modules[0]);
        roles = Roles(address(budget.roles()));
    }
    
    function installModules() public {
        // Safe will delegatecall here as part of its setup
        // We don't need to explictly guard against this function being called with a regular call
        // since we both perform calls on 'this' with the ABI of a Safe (will fail on this contract)

        GnosisSafe safe = GnosisSafe(payable(address(this)));
        Roles roles = Roles(
            moduleFactory.deployModule(
                rolesImpl,
                abi.encodeWithSelector(
                    Roles.setUp.selector,
                    address(safe)
                ),
                1
            )
        );
        Budget budget = Budget(
            moduleFactory.deployModule(
                budgetImpl,
                abi.encodeWithSelector(
                    Budget.setUp.selector,
                    Budget.InitParams(IAvatar(address(safe)), IAvatar(address(safe)), roles)
                ),
                1
            )
        );
        
        // Could optimize it by writing to Safe storage directly
        safe.enableModule(address(budget));
    }
}