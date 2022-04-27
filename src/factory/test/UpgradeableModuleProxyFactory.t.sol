// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import {FirmTest} from  "../../common/test/lib/FirmTest.sol";
import {UpgradeableModuleProxyFactoryMock} from "./mocks/UpgradeableModuleProxyFactoryMock.sol";

contract Target {
    error SomeError();

    function upgrade(address _newTarget) external {
        bytes32 slot = bytes32(uint256(keccak256('eip1967.proxy.implementation')) - 1);
        assembly {
            sstore(slot, _newTarget)
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
