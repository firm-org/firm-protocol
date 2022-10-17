// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {FirmTest} from "../../common/test/lib/FirmTest.sol";
import {IAvatar, SafeAware} from "../../bases/SafeAware.sol";

import {UpgradeableModuleProxyFactory, IModuleMetadata} from "../UpgradeableModuleProxyFactory.sol";
import {TargetBase, TargetV1, TargetV2} from "./lib/TestTargets.sol";

contract UpgradeableModuleProxyRegistryTest is FirmTest {

}

contract UpgradeableModuleProxyDeployTest is FirmTest {
    UpgradeableModuleProxyFactory factory;
    address SAFE = account("Safe");
    address SOMEONE = account("Someone");

    TargetBase proxy;

    function setUp() public {
        factory = new UpgradeableModuleProxyFactory();
        factory.register(new TargetV1());
        factory.register(new TargetV2());
        proxy = TargetBase(factory.deployUpgradeableModule("org.firm.test-target", 1, abi.encodeCall(TargetBase.init, (IAvatar(SAFE))), 0));
    }

    function testReturnDataOnUpgradedVersion() public {
        proxy.setNumber(42);
        assertEq(proxy.getNumber(), 42);
        vm.startPrank(SAFE);
        proxy.upgrade(factory.getImplementation("org.firm.test-target", 2));
        vm.stopPrank();
        assertEq(proxy.getNumber(), 42 * 2);
    }

    function testFirstStorageSlotIsZero() public {
        assertEq(vm.load(address(proxy), 0), bytes32(proxy.getNumber()));
        proxy.setNumber(42);
        assertEq(vm.load(address(proxy), 0), bytes32(proxy.getNumber()));
    }

    function testRevertsOnUpgradedVersion() public {
        vm.startPrank(SAFE);
        proxy.upgrade(factory.getImplementation("org.firm.test-target", 2));
        vm.stopPrank();
        vm.expectRevert(abi.encodeWithSelector(TargetBase.SomeError.selector));
        proxy.setNumber(43);
    }
    
    event ModuleProxyCreation(address indexed proxy, IModuleMetadata indexed implementation);
    event Initialized(IAvatar indexed safe, IModuleMetadata indexed implementation);
    event Upgraded(IModuleMetadata indexed implementation, string moduleId, uint256 version);
    function testEventsAreEmittedInOrder() public {
        IModuleMetadata implV1 = factory.getImplementation("org.firm.test-target", 1);
        IModuleMetadata implV2 = factory.getImplementation("org.firm.test-target", 2);

        vm.expectEmit(false, true, false, false, address(factory));
        emit ModuleProxyCreation(address(0), implV1);
        vm.expectEmit(true, true, false, false);
        emit Initialized(IAvatar(SAFE), implV1);
        proxy = TargetBase(factory.deployUpgradeableModule("org.firm.test-target", 1, abi.encodeCall(TargetBase.init, (IAvatar(SAFE))), 1));
        
        vm.prank(SAFE);
        vm.expectEmit(true, false, false, true, address(proxy));
        emit Upgraded(implV2, "org.firm.test-target", 2);
        proxy.upgrade(implV2);
    }

    function testRevertsIfUpgraderIsNotSafe() public {
        IModuleMetadata newImpl = factory.getImplementation("org.firm.test-target", 2);
        vm.prank(SOMEONE);
        vm.expectRevert(abi.encodeWithSelector(SafeAware.UnauthorizedNotSafe.selector));
        proxy.upgrade(newImpl);
    }
}
