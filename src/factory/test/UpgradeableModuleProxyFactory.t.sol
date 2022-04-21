// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import {FirmTest} from  "../../common/test/lib/FirmTest.sol";
import "../UpgradeableModuleProxyFactory.sol";

contract UpgradeableModuleProxyFactoryMock is UpgradeableModuleProxyFactory {
    function createUpgradeableProxy(address _target) public returns (address addr) {
        return createUpgradeableProxy(_target, bytes32(0));
    }
}

contract Target {
    function foo() public pure returns (uint) {
        return 42;
    }
}

contract UpgradeableModuleProxyFactoryCreationTest is FirmTest {
    Target target = new Target();
    UpgradeableModuleProxyFactoryMock factory = new UpgradeableModuleProxyFactoryMock();

    function testGas() virtual public returns (address) {
        return factory.createUpgradeableProxy(address(target));
    }
}

contract UpgradeableModuleProxyFactoryCallTest is UpgradeableModuleProxyFactoryCreationTest {
    Target proxy;

    function setUp() public {
        proxy = Target(super.testGas());
    }

    function testGas() public override returns (address) {
        proxy.foo();
    }
}

