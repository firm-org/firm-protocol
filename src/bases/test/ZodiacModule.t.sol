// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "solmate/utils/Bytes32AddressLib.sol";

import {FirmTest} from "../../common/test/lib/FirmTest.sol";
import {CallRecipient} from "../../common/test/mocks/CallRecipient.sol";
import {IGuard} from "../ZodiacModule.sol";

import "./BasesTest.t.sol";

contract ZodiacModuleTest is BasesTest {
    using Bytes32AddressLib for bytes32;

    function testInitialState() public {
        assertEq(address(module.avatar()), address(avatar));
        assertEq(address(module.target()), address(avatar));
        assertEq(module.foo(), MODULE_ONE_FOO);
        assertEq(module.bar(), INITIAL_BAR);
    }

    function testRawStorage() public {
        // Bar (first declared storage variable of ModuleMock) is stored on slot 0
        assertEq(uint256(vm.load(address(module), 0)), INITIAL_BAR);

        address fakeTarget = address(1);
        address fakeGuard = address(2);
        // Mock calls to fakeGuard so it appears as if it was a real guard
        vm.mockCall(
            fakeGuard,
            abi.encodeWithSignature("supportsInterface(bytes4)"),
            abi.encode(true)
        );
        vm.startPrank(address(avatar));
        module.setTarget(IAvatar(fakeTarget));
        module.setGuard(IGuard(fakeGuard));
        vm.stopPrank();
        // Check that moduleState is stored on its corresponding slots
        uint256 zodiacStateBaseSlot = 0x1bcb284404f22ead428604605be8470a4a8a14c8422630d8a717460f9331147d;
        assertEq(
            vm
                .load(address(module), bytes32(zodiacStateBaseSlot))
                .fromLast20Bytes(),
            fakeTarget
        );
        assertEq(
            vm
                .load(address(module), bytes32(zodiacStateBaseSlot + 1))
                .fromLast20Bytes(),
            fakeGuard
        );
        assertEq(
            bytes32(zodiacStateBaseSlot + 2),
            keccak256("firm.zodiacmodule.state")
        );

        uint256 safeSlot = 0xb2c095c1a3cccf4bf97d6c0d6a44ba97fddb514f560087d9bf71be2c324b6c44;
        assertEq(
            vm.load(address(module), bytes32(safeSlot)).fromLast20Bytes(),
            address(avatar)
        );
    }

    function testCannotReinitialize() public {
        vm.expectRevert(
            abi.encodeWithSelector(SafeAware.AlreadyInitialized.selector)
        );
        module.initialize(avatar, INITIAL_BAR);
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
        vm.expectRevert(
            abi.encodeWithSelector(SafeAware.UnauthorizedNotSafe.selector)
        );
        module.setTarget(avatar);
    }

    function testAvatarCanAddGuard() public {
        // TODO
    }

    function testNonAvatarCannotAddGuard() public {
        // TODO
    }
}
