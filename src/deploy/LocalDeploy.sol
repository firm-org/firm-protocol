// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import "../factory/FirmFactory.sol";
import {IRoles} from "../roles/Roles.sol";

contract LocalDeploy {
    GnosisSafeProxyFactory public safeProxyFactory = new GnosisSafeProxyFactory();
    ModuleProxyFactory public moduleProxyFactory = new ModuleProxyFactory();
    address public safeImpl = address(new GnosisSafe());
    address public rolesImpl = address(new Roles(address(10)));
    address public budgetImpl = address(new Budget(Budget.InitParams(IAvatar(address(10)), IAvatar(address(10)), IRoles(address(10)))));

    FirmFactory public firmFactory = new FirmFactory(
        safeProxyFactory,
        moduleProxyFactory,
        safeImpl,
        rolesImpl,
        budgetImpl
    );

    constructor() {
        // deploy a test firm
        firmFactory.createFirm(msg.sender);
    }
}