// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "../../UpgradeableModuleProxyFactory.sol";

contract UpgradeableModuleProxyFactoryMock is UpgradeableModuleProxyFactory {
    function createUpgradeableProxy(address _target) public returns (address addr) {
        return createUpgradeableProxy(EIP1967Upgradeable(_target), bytes32(0));
    }
}
