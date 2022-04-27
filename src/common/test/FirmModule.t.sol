// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import "solmate/utils/Bytes32AddressLib.sol";

import {FirmTest} from "./lib/FirmTest.sol";

import {UpgradeableModuleProxyFactory} from "../../factory/UpgradeableModuleProxyFactory.sol";

import {ModuleMock, FirmModule} from "./mocks/ModuleMock.sol";
import {AvatarStub} from "./mocks/AvatarStub.sol";
import {CallRecipient} from "./mocks/CallRecipient.sol";

contract FirmModuleTest is FirmTest {
    using Bytes32AddressLib for bytes32;

    UpgradeableModuleProxyFactory factory = new UpgradeableModuleProxyFactory();
    
    // Parameter in constructor is saved to an immutable variable 'foo'
    ModuleMock moduleOneImpl = new ModuleMock(MODULE_ONE_FOO);
    ModuleMock moduleTwoImpl = new ModuleMock(MODULE_TWO_FOO);

    ModuleMock module;
    AvatarStub avatar;

    uint256 internal constant MODULE_ONE_FOO = 1;
    uint256 internal constant MODULE_TWO_FOO = 2;
    uint256 internal constant INITIAL_BAR = 3;

    function setUp() public {
        avatar = new AvatarStub();
        module = ModuleMock(factory.deployModule(
            address(moduleOneImpl),
            abi.encodeCall(moduleOneImpl.setUp, (avatar, avatar, INITIAL_BAR)),
            0,
            true
        ));
        vm.label(address(module), "Proxy");
        vm.label(address(moduleOneImpl), "ModuleOne");
        vm.label(address(moduleTwoImpl), "ModuleTwo");
    }

    function testInitialState() public {
        assertEq(address(module.avatar()), address(avatar));
        assertEq(address(module.target()), address(avatar));
        assertEq(module.foo(), MODULE_ONE_FOO);
        assertEq(module.bar(), INITIAL_BAR);
    }

    function testRawStorage() public {
        // Bar (first declared storage variable of ModuleMock) is stored on slot 0
        assertEq(uint256(vm.load(address(module), 0)), INITIAL_BAR);

        // Check that moduleState is stored on its corresponding slots
        uint256 moduleStateBaseSlot = 0xa5b7510e75e06df92f176662510e3347b687605108b9f72b4260aa7cf56ebb12;
        assertEq(vm.load(address(module), bytes32(moduleStateBaseSlot)).fromLast20Bytes(), address(avatar));
        assertEq(vm.load(address(module), bytes32(moduleStateBaseSlot + 1)).fromLast20Bytes(), address(avatar));
        assertEq(vm.load(address(module), bytes32(moduleStateBaseSlot + 2)).fromLast20Bytes(), address(0)); // guard not set yet
        assertEq(bytes32(moduleStateBaseSlot + 3), keccak256("firm.module.state"));

        assertImplAtEIP1967Slot(address(moduleOneImpl));
    }

    function testCannotReinitialize() public {
        vm.expectRevert(abi.encodeWithSelector(FirmModule.AlreadyInitialized.selector));
        module.initialize(avatar, avatar);

        vm.expectRevert(abi.encodeWithSelector(FirmModule.AlreadyInitialized.selector));
        module.setUp(avatar, avatar, INITIAL_BAR);
    }

    event Upgraded(address indexed implementation);
    function testAvatarCanUpgradeModule() public {
        vm.prank(address(avatar));
        vm.expectEmit(true, true, false, false);
        emit Upgraded(address(moduleTwoImpl));
        module.upgrade(address(moduleTwoImpl));

        assertImplAtEIP1967Slot(address(moduleTwoImpl));
        assertEq(module.foo(), MODULE_TWO_FOO);
        assertEq(module.bar(), INITIAL_BAR);
    }

    function testNonAvatarCannotUpgrade() public {
        vm.expectRevert(abi.encodeWithSelector(FirmModule.UnauthorizedNotAvatar.selector));
        module.upgrade(address(moduleTwoImpl));
    }

    event ReceiveCall(address indexed from, uint256 value, bytes data);
    function testCanExecuteCall() public {
        address recipient = address(new CallRecipient());
        bytes memory data = hex"abcd";

        assertEq(recipient.balance, 0);

        address target = address(module.target());
        vm.deal(target, 1 ether);
        vm.expectCall(recipient, data);
        vm.expectEmit(true, true, false, false);
        emit ReceiveCall(target, 1 ether, data);
        module.execCall(recipient, 1 ether, data);

        assertEq(recipient.balance, 1 ether);
    }

    function testAvatarCanChangeTarget() public {
        AvatarStub newTarget = new AvatarStub();
        vm.prank(address(avatar));
        module.setTarget(newTarget);

        assertEq(address(module.target()), address(newTarget));
        testCanExecuteCall();
    }

    function testNonAvatarCannotChangeTarget() public {
        vm.expectRevert(abi.encodeWithSelector(FirmModule.UnauthorizedNotAvatar.selector));
        module.setTarget(avatar);
    }

    function testAvatarCanChangeAvatar() public {
        AvatarStub newAvatar = new AvatarStub();

        vm.prank(address(avatar));
        module.setAvatar(newAvatar);
        assertEq(address(module.avatar()), address(newAvatar));

        vm.prank(address(newAvatar));
        module.setAvatar(avatar);
        assertEq(address(module.avatar()), address(avatar));
    }

    function testNonAvatarCannotChangeAvatar() public {
        vm.expectRevert(abi.encodeWithSelector(FirmModule.UnauthorizedNotAvatar.selector));
        module.setAvatar(avatar);
    }

    function assertImplAtEIP1967Slot(address _impl) internal {
        bytes32 implSlot = bytes32(uint256(keccak256('eip1967.proxy.implementation')) - 1);
        assertEq(vm.load(address(module), implSlot).fromLast20Bytes(), _impl);
    }
}