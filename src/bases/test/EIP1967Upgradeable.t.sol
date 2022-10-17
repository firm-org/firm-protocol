// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {SafeAware} from "../SafeAware.sol";

import "./BasesTest.t.sol";

contract EIP1967UpgradeableTest is BasesTest {
    using Bytes32AddressLib for bytes32;

    ModuleMock moduleTwoImpl = new ModuleMock(MODULE_TWO_FOO);

    function setUp() public override {
        super.setUp();

        vm.label(address(moduleTwoImpl), "ModuleTwo");
    }

    function testRawStorage() public {
        // Bar (first declared storage variable of ModuleMock) is stored on slot 0
        assertEq(uint256(vm.load(address(module), 0)), INITIAL_BAR);
        assertImplAtEIP1967Slot(address(moduleOneImpl));
    }

    function assertImplAtEIP1967Slot(address _impl) internal {
        bytes32 implSlot = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);
        assertEq(vm.load(address(module), implSlot).fromLast20Bytes(), _impl);
    }

    event Upgraded(address indexed implementation, string moduleId, uint256 version);

    function testAvatarCanUpgradeModule() public {
        vm.prank(address(avatar));
        vm.expectEmit(true, true, false, true);
        emit Upgraded(address(moduleTwoImpl), "org.firm.modulemock", 0);
        module.upgrade(moduleTwoImpl);

        assertImplAtEIP1967Slot(address(moduleTwoImpl));
        assertEq(module.foo(), MODULE_TWO_FOO);
        assertEq(module.bar(), INITIAL_BAR);
    }

    function testNonAvatarCannotUpgrade() public {
        vm.expectRevert(abi.encodeWithSelector(SafeAware.UnauthorizedNotSafe.selector));
        module.upgrade(moduleTwoImpl);
    }
}
