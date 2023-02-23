// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import {FirmTest} from "../../bases/test/lib/FirmTest.sol";
import {SafeStub} from "../../bases/test/mocks/SafeStub.sol";

import {SafeAware} from "../../bases/SafeAware.sol";
import {Semaphore} from "../Semaphore.sol";

contract SemaphoreTest is FirmTest {
    SafeStub safe;
    Semaphore semaphore;
    address OTHER_CALLER = account("Other caller");

    function setUp() public {
        safe = new SafeStub();
        semaphore = Semaphore(createProxy(new Semaphore(), abi.encodeCall(Semaphore.initialize, (safe, true, address(0)))));
    }

    function testInitialState(address target, uint256 value, bytes memory data) public {
        (
            Semaphore.DefaultMode defaultMode,
            bool allowsDelegateCalls,
            bool allowsValueCalls,
            uint64 numTotalExceptions,
            uint32 numSigExceptions,
            uint32 numTargetExceptions,
            uint32 numTargetSigExceptions
        ) = semaphore.state(address(safe));
        assertEq(uint8(defaultMode), uint8(Semaphore.DefaultMode.Allow));
        assertTrue(allowsDelegateCalls);
        assertTrue(allowsValueCalls);
        assertEq(numTotalExceptions, 0);
        assertEq(numSigExceptions, 0);
        assertEq(numTargetExceptions, 0);
        assertEq(numTargetSigExceptions, 0);

        assertCanPerform(true, address(safe), target, value, data, false);
        assertCanPerform(true, address(safe), target, value, data, true);

        assertCanPerform(false, OTHER_CALLER, target, value, data, false);
        assertCanPerform(false, OTHER_CALLER, target, value, data, true);
    }

    function testCannotReinit() public {
        vm.expectRevert(abi.encodeWithSelector(SafeAware.AlreadyInitialized.selector));
        semaphore.initialize(safe, true, address(0));
    }

    function testCanSetState(address target, uint256 value, bytes memory data) public {
        vm.assume(value > 0);
        vm.prank(address(safe));
        semaphore.setSemaphoreState(address(safe), Semaphore.DefaultMode.Disallow, false, false);
        (
            Semaphore.DefaultMode defaultMode,
            bool allowsDelegateCalls,
            bool allowsValueCalls,
            ,,,
        ) = semaphore.state(address(safe));
        assertEq(uint8(defaultMode), uint8(Semaphore.DefaultMode.Disallow));
        assertFalse(allowsDelegateCalls);
        assertFalse(allowsValueCalls);

        assertCanPerform(false, address(safe), target, value, data, false);
        assertCanPerform(false, address(safe), target, value, data, true);

        vm.prank(address(safe));
        semaphore.setSemaphoreState(OTHER_CALLER, Semaphore.DefaultMode.Allow, true, true);
        (
            defaultMode,
            allowsDelegateCalls,
            allowsValueCalls,
            ,
            ,
            ,
        ) = semaphore.state(OTHER_CALLER);
        assertEq(uint8(defaultMode), uint8(Semaphore.DefaultMode.Allow));
        assertTrue(allowsDelegateCalls);
        assertTrue(allowsValueCalls);

        assertCanPerform(true, OTHER_CALLER, target, value, data, false);
        assertCanPerform(true, OTHER_CALLER, target, value, data, true);
    }

    function testNonSafeCannotSetState() public {
        vm.expectRevert(abi.encodeWithSelector(SafeAware.UnauthorizedNotSafe.selector));
        semaphore.setSemaphoreState(address(safe), Semaphore.DefaultMode.Disallow, false, false);
    }

    function testCanSetSigExceptions() public {
        address anyTarget = account("Any target");
        address someOtherTarget = account("Some other target");
        bytes4 sig = this.testCanSetSigExceptions.selector;

        Semaphore.ExceptionInput[] memory exceptions = new Semaphore.ExceptionInput[](2);
        exceptions[0] = Semaphore.ExceptionInput(true, Semaphore.ExceptionType.Sig, address(safe), anyTarget, sig);
        exceptions[1] = Semaphore.ExceptionInput(true, Semaphore.ExceptionType.Sig, OTHER_CALLER, anyTarget, sig);
        vm.prank(address(safe));
        semaphore.setExceptions(exceptions);

        assertCanPerform(false, address(safe), anyTarget, 0, abi.encodeWithSelector(sig), false);
        assertCanPerform(true, OTHER_CALLER, anyTarget, 0, abi.encodeWithSelector(sig), false);
        assertCanPerform(false, address(safe), someOtherTarget, 0, abi.encodeWithSelector(sig), false);
        assertCanPerform(true, OTHER_CALLER, someOtherTarget, 0, abi.encodeWithSelector(sig), false);

        // Other caller cannot do calls with value or delegate calls until the state is set
        assertCanPerform(false, OTHER_CALLER, anyTarget, 0, abi.encodeWithSelector(sig), true);
        assertCanPerform(false, OTHER_CALLER, anyTarget, 1, abi.encodeWithSelector(sig), false);

        // Setting the state for the other caller should value and delegatecalls
        vm.prank(address(safe));
        semaphore.setSemaphoreState(OTHER_CALLER, Semaphore.DefaultMode.Disallow, true, true);

        assertCanPerform(true, OTHER_CALLER, anyTarget, 0, abi.encodeWithSelector(sig), true);
        assertCanPerform(true, OTHER_CALLER, anyTarget, 1, abi.encodeWithSelector(sig), false);

        // Changing the default mode for other caller, reverts the effect of the exceptions
        vm.prank(address(safe));
        semaphore.setSemaphoreState(OTHER_CALLER, Semaphore.DefaultMode.Allow, true, true);

        assertCanPerform(false, OTHER_CALLER, anyTarget, 0, abi.encodeWithSelector(sig), false);
        assertCanPerform(false, OTHER_CALLER, anyTarget, 1, abi.encodeWithSelector(sig), false);
        assertCanPerform(false, OTHER_CALLER, anyTarget, 0, abi.encodeWithSelector(sig), true);
    }

    function testCanSetTargetExceptions() public {
        address target = account("Target");

        Semaphore.ExceptionInput[] memory exceptions = new Semaphore.ExceptionInput[](2);
        exceptions[0] = Semaphore.ExceptionInput(true, Semaphore.ExceptionType.Target, address(safe), target, bytes4(0));
        exceptions[1] = Semaphore.ExceptionInput(true, Semaphore.ExceptionType.Target, OTHER_CALLER, target, bytes4(0));

        vm.prank(address(safe));
        semaphore.setExceptions(exceptions);

        assertCanPerform(false, address(safe), target, 0, "", false);
        assertCanPerform(true, OTHER_CALLER, target, 0, "", false);
    }

    function testCanSetTargetSigExceptions() public {
        address target = account("Target");
        bytes4 sig = this.testCanSetTargetSigExceptions.selector;

        Semaphore.ExceptionInput[] memory exceptions = new Semaphore.ExceptionInput[](2);
        exceptions[0] = Semaphore.ExceptionInput(true, Semaphore.ExceptionType.TargetSig, address(safe), target, sig);
        exceptions[1] = Semaphore.ExceptionInput(true, Semaphore.ExceptionType.TargetSig, OTHER_CALLER, target, sig);

        vm.prank(address(safe));
        semaphore.setExceptions(exceptions);

        assertCanPerform(false, address(safe), target, 0, abi.encodeWithSelector(sig), false);
        assertCanPerform(true, OTHER_CALLER, target, 0, abi.encodeWithSelector(sig), false);
    }

    function testCanSetMultipleExceptions() public {
        address anyTarget = account("Any target");
        address target = account("Target");
        bytes4 sig = this.testCanSetMultipleExceptions.selector;

        Semaphore.ExceptionInput[] memory exceptions = new Semaphore.ExceptionInput[](4);
        exceptions[0] = Semaphore.ExceptionInput(true, Semaphore.ExceptionType.Sig, address(safe), anyTarget, sig);
        exceptions[1] = Semaphore.ExceptionInput(true, Semaphore.ExceptionType.Sig, OTHER_CALLER, anyTarget, sig);
        exceptions[2] = Semaphore.ExceptionInput(true, Semaphore.ExceptionType.Target, address(safe), target, bytes4(0));
        exceptions[3] = Semaphore.ExceptionInput(true, Semaphore.ExceptionType.Target, OTHER_CALLER, target, bytes4(0));

        vm.prank(address(safe));
        semaphore.setExceptions(exceptions);

        assertCanPerform(false, address(safe), anyTarget, 0, abi.encodeWithSelector(sig), false);
        assertCanPerform(true, OTHER_CALLER, anyTarget, 0, abi.encodeWithSelector(sig), false);
        assertCanPerform(false, address(safe), target, 0, abi.encodeWithSelector(sig), false);
        assertCanPerform(true, OTHER_CALLER, target, 0, abi.encodeWithSelector(sig), false);
    }

    function testCanRemoveExceptions() public {
        address anyTarget = account("Any target");
        bytes4 sig = this.testCanSetSigExceptions.selector;
        
        vm.startPrank(address(safe));

        Semaphore.ExceptionInput[] memory exceptions = new Semaphore.ExceptionInput[](2);
        exceptions[0] = Semaphore.ExceptionInput(true, Semaphore.ExceptionType.Sig, address(safe), anyTarget, sig);
        exceptions[1] = Semaphore.ExceptionInput(true, Semaphore.ExceptionType.Sig, OTHER_CALLER, anyTarget, sig);
        semaphore.setExceptions(exceptions);

        assertCanPerform(false, address(safe), anyTarget, 0, abi.encodeWithSelector(sig), false);
        assertCanPerform(true, OTHER_CALLER, anyTarget, 0, abi.encodeWithSelector(sig), false);

        exceptions[0].add = false;
        exceptions[1].add = false;

        semaphore.setExceptions(exceptions);

        assertCanPerform(true, address(safe), anyTarget, 0, abi.encodeWithSelector(sig), false);
        assertCanPerform(false, OTHER_CALLER, anyTarget, 0, abi.encodeWithSelector(sig), false);

        (,,,
            uint64 numTotalExceptionsSafe,
            uint32 numSigExceptionsSafe,
        ,) = semaphore.state(address(safe));
        assertEq(numTotalExceptionsSafe, 0);
        assertEq(numSigExceptionsSafe, 0);
        
        (,,,
            uint64 numTotalExceptionsOther,
            uint32 numSigExceptionsOther,
        ,) = semaphore.state(OTHER_CALLER);
        assertEq(numTotalExceptionsOther, 0);
        assertEq(numSigExceptionsOther, 0);

        // Cannot remove them again
        vm.expectRevert(abi.encodeWithSelector(Semaphore.ExceptionAlreadySet.selector, exceptions[0]));
        semaphore.setExceptions(exceptions);

        vm.stopPrank();
    }

    function testNonSafeCannotSetExceptions() public {
        vm.expectRevert(abi.encodeWithSelector(SafeAware.UnauthorizedNotSafe.selector));
        semaphore.setExceptions(new Semaphore.ExceptionInput[](0));
    }

    function testCannotSetExistingExceptions() public {
        Semaphore.ExceptionInput[] memory exceptions = new Semaphore.ExceptionInput[](3);
        exceptions[0] = Semaphore.ExceptionInput(true, Semaphore.ExceptionType.Sig, address(safe), address(safe), bytes4(0));
        exceptions[1] = Semaphore.ExceptionInput(true, Semaphore.ExceptionType.Target, address(safe), address(safe), bytes4(0));
        exceptions[2] = Semaphore.ExceptionInput(true, Semaphore.ExceptionType.TargetSig, address(safe), address(safe), bytes4(0));

        vm.startPrank(address(safe));
        semaphore.setExceptions(exceptions);

        vm.expectRevert(abi.encodeWithSelector(Semaphore.ExceptionAlreadySet.selector, exceptions[0]));
        semaphore.setExceptions(exceptions);

        // Flip the first exception so it errors on the second
        exceptions[0] = Semaphore.ExceptionInput(false, Semaphore.ExceptionType.Sig, address(safe), address(safe), bytes4(0));
        vm.expectRevert(abi.encodeWithSelector(Semaphore.ExceptionAlreadySet.selector, exceptions[1]));
        semaphore.setExceptions(exceptions);

        // Flip the second exception so it errors on the third
        exceptions[1] = Semaphore.ExceptionInput(false, Semaphore.ExceptionType.Target, address(safe), address(safe), bytes4(0));
        vm.expectRevert(abi.encodeWithSelector(Semaphore.ExceptionAlreadySet.selector, exceptions[2]));
        semaphore.setExceptions(exceptions);

        vm.stopPrank();
    }

    function assertCanPerform(bool expected, address caller, address target, uint256 value, bytes memory data, bool isDelegateCall) public {
        assertEq(semaphore.canPerform(caller, target, value, data, isDelegateCall), expected);
        
        address[] memory targets = new address[](1);
        targets[0] = target;
        uint256[] memory values = new uint256[](1);
        values[0] = value;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = data;
        assertEq(semaphore.canPerformMany(caller, targets, values, calldatas, isDelegateCall), expected);
    }
}