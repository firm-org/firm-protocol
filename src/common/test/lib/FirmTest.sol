// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "../../../factory/UpgradeableModuleProxyFactory.sol";
import {UpgradeableModule} from "../../../bases/UpgradeableModule.sol";

contract FirmTest is Test {
    UpgradeableModuleProxyFactory immutable proxyFactory = new UpgradeableModuleProxyFactory();

    function account(string memory _label) internal returns (address addr) {
        addr = vm.addr(uint256(keccak256(abi.encodePacked(_label))));
        vm.label(addr, _label);
    }

    // TODO: move to firm base or erc upgradeable
    function createProxy(UpgradeableModule impl, bytes memory initdata) internal returns (address proxy) {
        proxy = proxyFactory.deployUpgradeableModule(impl, initdata, 0);
        vm.label(proxy, "Proxy");
    }
}
