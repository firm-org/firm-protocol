// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {GnosisSafe} from "gnosis-safe/GnosisSafe.sol";
import {GnosisSafeProxyFactory} from "gnosis-safe/proxies/GnosisSafeProxyFactory.sol";
import {LlamaPayFactory} from "llamapay/LlamaPayFactory.sol";

import {DeployBase} from "./TestinprodDeploy.s.sol";

contract LocalDeploy is DeployBase {
    function baseContracts() internal override returns (address safeProxyFactory, address safeImpl, address llamaPayFactory) {
        vm.startBroadcast();
        
        safeProxyFactory = address(new GnosisSafeProxyFactory());
        safeImpl = address(new GnosisSafe());
        llamaPayFactory = address(new LlamaPayFactory());
        
        vm.stopBroadcast();
    }
}
