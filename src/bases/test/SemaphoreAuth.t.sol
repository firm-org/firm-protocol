// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import {FirmTest} from "./lib/FirmTest.sol";
import {SafeStub} from "./mocks/SafeStub.sol";
import {SafeAware} from "../SafeAware.sol";

import {SemaphoreAuthMock, ISafe, ISemaphore} from "./mocks/SemaphoreAuthMock.sol";
import {SemaphoreStub} from "./mocks/SemaphoreStub.sol";

contract SemaphoreAuthTest is FirmTest {
    SafeStub safe;
    SemaphoreAuthMock semaphoreAuth;
    SemaphoreStub semaphore;

    address someTarget = account("Some target");
    address someOtherTarget = account("Some other target");

    function setUp() public {
        safe = new SafeStub();
        semaphore = new SemaphoreStub();
        semaphoreAuth = SemaphoreAuthMock(createProxy(new SemaphoreAuthMock(), abi.encodeCall(SemaphoreAuthMock.initialize, (ISafe(payable(safe)), semaphore))));
    }

    function testInitialState() public {
        assertEq(address(semaphoreAuth.safe()), address(safe));
        assertEq(address(semaphoreAuth.semaphore()), address(semaphore));
        assertUnsStrg(address(semaphoreAuth), "firm.semaphoreauth.semaphore", address(semaphore));
    }

    function testSafeCanSetSemaphore() public {
        SemaphoreStub newSemaphore = new SemaphoreStub();
        vm.prank(address(safe));
        semaphoreAuth.setSemaphore(newSemaphore);
        assertEq(address(semaphoreAuth.semaphore()), address(newSemaphore));
    }

    function testNonSafeCannotSetSemaphore() public {
        SemaphoreStub newSemaphore = new SemaphoreStub();
        vm.expectRevert(abi.encodeWithSelector(SafeAware.UnauthorizedNotSafe.selector));
        semaphoreAuth.setSemaphore(newSemaphore);
    }

    function testRevertOnNonAuthorizedSingleCall() public {
        // Initially doesn't revert
        semaphoreAuth.semaphoreCheckCall(someTarget, 1, bytes(""), false);

        // Target is market as disallowed by semaphore mock
        semaphore.setDisallowed(someTarget, true);

        vm.expectRevert(abi.encodeWithSelector(ISemaphore.SemaphoreDisallowed.selector));
        semaphoreAuth.semaphoreCheckCall(someTarget, 1, bytes(""), false);

        // Can still perform calls to other targets
        semaphoreAuth.semaphoreCheckCall(someOtherTarget, 1, bytes(""), false);

        // Until caller is disallowed completely
        semaphore.setDisallowed(address(semaphoreAuth), false);

        vm.expectRevert(abi.encodeWithSelector(ISemaphore.SemaphoreDisallowed.selector));
        semaphoreAuth.semaphoreCheckCall(someOtherTarget, 1, bytes(""), false);
    }

    function testRevertOnNonAuthorizedCallsWithFilter() public {
        address[] memory targets = new address[](3);
        targets[0] = someTarget;
        targets[1] = someOtherTarget;
        targets[2] = account("Another target");

        uint256[] memory values = new uint256[](3);
        bytes[] memory datas = new bytes[](3);

        // Initially doesn't revert
        semaphoreAuth.semaphoreCheckCalls(targets, values, datas, false);

        // Target is market as disallowed by semaphore mock
        semaphore.setDisallowed(someTarget, true);

        vm.expectRevert(abi.encodeWithSelector(ISemaphore.SemaphoreDisallowed.selector));
        semaphoreAuth.semaphoreCheckCalls(targets, values, datas, false);

        // We filter some target (the one causing the revert) out
        (address[] memory filteredTargets, uint256[] memory filteredValues, bytes[] memory filteredDatas) = semaphoreAuth.filterCallsToTarget(someTarget, targets, values, datas);

        // And now it doesn't revert
        semaphoreAuth.semaphoreCheckCalls(filteredTargets, filteredValues, filteredDatas, false);

        // As the caller is disallowed, multicheck reverts
        semaphore.setDisallowed(address(semaphoreAuth), false);

        vm.expectRevert(abi.encodeWithSelector(ISemaphore.SemaphoreDisallowed.selector));
        semaphoreAuth.semaphoreCheckCalls(filteredTargets, filteredValues, filteredDatas, false);
    }

    function testTargetFilterWithParcialMatch() public {
        address[] memory targets = new address[](2);
        targets[0] = someTarget;
        targets[1] = someOtherTarget;

        uint256[] memory values = new uint256[](2);
        values[0] = 1;
        values[1] = 2;

        bytes[] memory datas = new bytes[](2);
        datas[0] = bytes("data1");
        datas[1] = bytes("data2");

        (address[] memory filteredTargets, uint256[] memory filteredValues, bytes[] memory filteredDatas) = semaphoreAuth.filterCallsToTarget(someTarget, targets, values, datas);

        assertEq(filteredTargets.length, 1);
        assertEq(filteredTargets[0], someOtherTarget);

        assertEq(filteredValues.length, 1);
        assertEq(filteredValues[0], 2);

        assertEq(filteredDatas.length, 1);
        assertEq(filteredDatas[0], bytes("data2"));
    }

    function testTargetFilterWithNoMatch() public {
        address[] memory targets = new address[](2);
        targets[0] = someTarget;
        targets[1] = someOtherTarget;

        uint256[] memory values = new uint256[](2);
        values[0] = 1;
        values[1] = 2;

        bytes[] memory datas = new bytes[](2);
        datas[0] = bytes("data1");
        datas[1] = bytes("data2");

        (address[] memory filteredTargets, uint256[] memory filteredValues, bytes[] memory filteredDatas) = semaphoreAuth.filterCallsToTarget(account("Another target"), targets, values, datas);

        assertEq(filteredTargets.length, 2);
        assertEq(filteredTargets[0], someTarget);
        assertEq(filteredTargets[1], someOtherTarget);

        assertEq(filteredValues.length, 2);
        assertEq(filteredValues[0], 1);
        assertEq(filteredValues[1], 2);

        assertEq(filteredDatas.length, 2);
        assertEq(filteredDatas[0], bytes("data1"));
        assertEq(filteredDatas[1], bytes("data2"));
    }

    function testTargetFilterWithFullMatch() public {
        address[] memory targets = new address[](2);
        targets[0] = someTarget;
        targets[1] = someTarget;

        uint256[] memory values = new uint256[](2);
        values[0] = 1;
        values[1] = 2;

        bytes[] memory datas = new bytes[](2);
        datas[0] = bytes("data1");
        datas[1] = bytes("data2");

        (address[] memory filteredTargets, uint256[] memory filteredValues, bytes[] memory filteredDatas) = semaphoreAuth.filterCallsToTarget(someTarget, targets, values, datas);

        assertEq(filteredTargets.length, 0);
        assertEq(filteredValues.length, 0);
        assertEq(filteredDatas.length, 0);
    }
}