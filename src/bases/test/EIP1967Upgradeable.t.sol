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
        assertUnsStrg(address(moduleOneImpl), "eip1967.proxy.implementation", address(0xffff));
        assertUnsStrg(address(moduleTwoImpl), "eip1967.proxy.implementation", address(0xffff));

        // Bar (first declared storage variable of ModuleMock) is stored on slot 0
        assertEq(uint256(vm.load(address(module), 0)), INITIAL_BAR);
        assertUnsStrg(address(module), "eip1967.proxy.implementation", address(moduleOneImpl));
    }

    event Upgraded(address indexed implementation, string moduleId, uint256 version);

    function testSafeCanUpgradeModule() public {
        vm.prank(address(safe));
        vm.expectEmit(true, true, false, true);
        emit Upgraded(address(moduleTwoImpl), "org.firm.modulemock", 0);
        module.upgrade(moduleTwoImpl);

        assertUnsStrg(address(module), "eip1967.proxy.implementation", address(moduleTwoImpl));
        assertEq(module.foo(), MODULE_TWO_FOO);
        assertEq(module.bar(), INITIAL_BAR);
    }

    function testNonSafeCannotUpgrade() public {
        vm.expectRevert(abi.encodeWithSelector(SafeAware.UnauthorizedNotSafe.selector));
        module.upgrade(moduleTwoImpl);
    }
}
