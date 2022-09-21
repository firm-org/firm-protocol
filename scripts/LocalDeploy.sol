// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import 'forge-std/Test.sol';

import "gnosis-safe/GnosisSafe.sol";
import "gnosis-safe/proxies/GnosisSafeProxyFactory.sol";

import {FirmFactory, UpgradeableModuleProxyFactory} from "../src/factory/FirmFactory.sol";
import {FirmRelayer} from "../src/metatx/FirmRelayer.sol";
import {Roles, IRoles, IAvatar, ONLY_ROOT_ROLE} from "../src/roles/Roles.sol";
import {Budget, TimeShiftLib, NO_PARENT_ID} from "../src/budget/Budget.sol";

contract LocalDeploy is Test {
    function run() public returns (FirmFactory factory) {
        vm.startBroadcast();

        factory = new FirmFactory(
            new GnosisSafeProxyFactory(),
            new UpgradeableModuleProxyFactory(),
            new FirmRelayer(),
            address(new GnosisSafe()),
            address(new Roles(IAvatar(address(10)), address(0))),
            address(new Budget(IAvatar(address(10)), IRoles(address(10)), address(0)))
        );

        vm.stopBroadcast();
    }
}
