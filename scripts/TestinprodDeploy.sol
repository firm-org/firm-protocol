// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import 'forge-std/Test.sol';

import "gnosis-safe/GnosisSafe.sol";
import "gnosis-safe/proxies/GnosisSafeProxyFactory.sol";

import {FirmFactory, UpgradeableModuleProxyFactory} from "../src/factory/FirmFactory.sol";
import {Roles, IRoles, IAvatar, ONLY_ROOT_ROLE} from "../src/roles/Roles.sol";
import {Budget, TimeShiftLib, NO_PARENT_ID} from "../src/budget/Budget.sol";

contract LocalDeploy is Test {

    FirmFactory factory;

    function run() public returns (FirmFactory) {
        vm.startBroadcast();

        factory = new FirmFactory(
            new GnosisSafeProxyFactory(),
            new UpgradeableModuleProxyFactory(),
            address(new GnosisSafe()),
            address(new Roles(IAvatar(address(10)))),
            address(new Budget(IAvatar(address(10)), IRoles(address(10))))
        );

        vm.stopBroadcast();

        return factory;
    }
}
