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
    error SomeError();

    function upgrade(address _newTarget) external {
        assembly {
            sstore(
                0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc,
                _newTarget
            )
        }
    }

    function foo() virtual public pure returns (uint256) {
        return 42;
    }

    function bar() public pure returns (uint256) {
        revert SomeError();
    }
}

contract UpgradedTarget is Target {
    function foo() override public pure returns (uint256) {
        return 43;
    }
}

contract UpgradeableModuleProxyFactoryTest is FirmTest {
    Target target = new Target();
    UpgradeableModuleProxyFactoryMock factory = new UpgradeableModuleProxyFactoryMock();

    Target proxy;

    function setUp() public {
        proxy = Target(factory.createUpgradeableProxy(address(target)));
    }

    function testReturnData() public {
        assertEq(proxy.foo(), 42);
    }

    function testRevert() public {
        vm.expectRevert(abi.encodeWithSelector(Target.SomeError.selector));
        proxy.bar();
    }

    function testUpgrade() public {
        assertEq(proxy.foo(), 42);
        proxy.upgrade(address(new UpgradedTarget()));
        assertEq(proxy.foo(), 43);
    }
}
