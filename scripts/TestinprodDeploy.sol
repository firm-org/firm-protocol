// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import 'forge-std/Test.sol';

import "gnosis-safe/GnosisSafe.sol";
import "gnosis-safe/proxies/GnosisSafeProxyFactory.sol";

import {TestinprodFactory, UpgradeableModuleProxyFactory} from "../src/factory/TestinprodFactory.sol";
import {Roles, IRoles, IAvatar, ONLY_ROOT_ROLE} from "../src/roles/Roles.sol";
import {Budget, TimeShiftLib, NO_PARENT_ID} from "../src/budget/Budget.sol";

contract TestinprodDeploy is Test {
    error UnsupportedChain(uint256 chainId);

    function run() public returns (TestinprodFactory factory) {
        // using v1.3.0 from https://github.com/safe-global/safe-deployments/blob/8dea757/src/assets/v1.3.0/proxy_factory.json
        address safeProxyFactory;
        address safeImpl;
        
        if (block.chainid == 1) {
            // Mainnet
            safeProxyFactory = 0xa6B71E26C5e0845f74c812102Ca7114b6a896AB2;
            safeImpl = 0xd9Db270c1B5E3Bd161E8c8503c55cEABeE709552;
        } else if (block.chainid == 5) {
            // Goerli
            safeProxyFactory = 0xa6B71E26C5e0845f74c812102Ca7114b6a896AB2;
            safeImpl = 0xd9Db270c1B5E3Bd161E8c8503c55cEABeE709552;
        } else {
            revert UnsupportedChain(block.chainid);
        }

        factory = new TestinprodFactory(
            GnosisSafeProxyFactory(safeProxyFactory),
            new UpgradeableModuleProxyFactory(),
            safeImpl,
            address(new Roles(IAvatar(address(10)))),
            address(new Budget(IAvatar(address(10)), IRoles(address(10))))
        );

        vm.stopBroadcast();
    }
}
