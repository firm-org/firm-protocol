// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {FirmTest} from "../../common/test/lib/FirmTest.sol";
import {IAvatar, SafeAware} from "../../bases/SafeAware.sol";

import {UpgradeableModuleProxyFactory, LATEST_VERSION, Ownable} from "../UpgradeableModuleProxyFactory.sol";
import {TargetBase, TargetV1, TargetV2, IModuleMetadata} from "./lib/TestTargets.sol";

contract UpgradeableModuleProxyRegistryTest is FirmTest {
    UpgradeableModuleProxyFactory factory;
    TargetV1 implV1;

    address OWNER = account("Owner");
    address SOMEONE = account("Someone");

    function setUp() public {
        vm.prank(OWNER);
        factory = new UpgradeableModuleProxyFactory();

        implV1 = new TargetV1();
    }

    function testInitialState() public {
        assertEq(factory.owner(), OWNER);
        assertEq(factory.latestModuleVersion("org.firm.test-target"), 0);
        vm.expectRevert(abi.encodeWithSelector(UpgradeableModuleProxyFactory.UnexistentModuleVersion.selector));
        factory.getImplementation("org.firm.test-target", 1);
        vm.expectRevert(abi.encodeWithSelector(UpgradeableModuleProxyFactory.UnexistentModuleVersion.selector));
        factory.getImplementation("org.firm.test-target", LATEST_VERSION);
    }

    function testOwnerCanRegister() public {
        vm.prank(OWNER);
        factory.register(implV1);

        assertEq(address(factory.getImplementation("org.firm.test-target", 1)), address(implV1));
        assertEq(address(factory.getImplementation("org.firm.test-target", LATEST_VERSION)), address(implV1));
        assertEq(factory.latestModuleVersion("org.firm.test-target"), implV1.moduleVersion());
    }

    function testCanRegisterMultipleVersions() public {
        testOwnerCanRegister();

        TargetV2 implV2 = new TargetV2();
        vm.prank(OWNER);
        factory.register(implV2);

        assertEq(address(factory.getImplementation("org.firm.test-target", 2)), address(implV2));
        assertEq(address(factory.getImplementation("org.firm.test-target", LATEST_VERSION)), address(implV2));

        assertEq(factory.latestModuleVersion("org.firm.test-target"), implV2.moduleVersion());
        assertEq(address(factory.getImplementation("org.firm.test-target", 1)), address(implV1));
        assertEq(address(factory.getImplementation("org.firm.test-target", 2)), address(implV2));
    }

    function testNotOwnerCannotRegister() public {
        vm.prank(SOMEONE);
        vm.expectRevert("Ownable: caller is not the owner");
        factory.register(implV1);
    }

    function testCantReregisterSameVersion() public {
        vm.prank(OWNER);
        factory.register(implV1);
        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(UpgradeableModuleProxyFactory.ModuleVersionAlreadyRegistered.selector));
        factory.register(implV1);
    }

    function testOwnerCanChangeOwner() public {
        vm.prank(OWNER);
        factory.transferOwnership(SOMEONE);

        assertEq(factory.owner(), SOMEONE);
    }

    function testNotOwnerCantChangeOwner() public {
        vm.prank(SOMEONE);
        vm.expectRevert("Ownable: caller is not the owner");
        factory.transferOwnership(OWNER);
    }
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

    function testRevertsIfInitializerReverts() public {
        vm.expectRevert(abi.encodeWithSelector(UpgradeableModuleProxyFactory.FailedInitialization.selector));
        factory.deployUpgradeableModule("org.firm.test-target", 2, abi.encodeCall(TargetBase.setNumber, (1)), 1);
    }

    function testRevertsIfRepeatingNonce() public {
        uint256 nonce = 1;
        factory.deployUpgradeableModule("org.firm.test-target", 1, abi.encodeCall(TargetBase.init, (IAvatar(SAFE))), nonce);
        factory.deployUpgradeableModule("org.firm.test-target", 2, abi.encodeCall(TargetBase.init, (IAvatar(SAFE))), nonce);
        
        vm.expectRevert(abi.encodeWithSelector(UpgradeableModuleProxyFactory.ProxyAlreadyDeployedForNonce.selector));
        factory.deployUpgradeableModule("org.firm.test-target", 1, abi.encodeCall(TargetBase.init, (IAvatar(SAFE))), nonce);
    }
}
