// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import {RolesStub} from "src/bases/test/mocks/RolesStub.sol";
import {roleFlag} from "src/bases/test/lib/RolesAuthFlags.sol";

import {AccountControllerTest} from "./AccountControllerTest.sol";
import {VestingController, AccountController} from "../VestingController.sol";

contract VestingControllerTest is AccountControllerTest {
    VestingController vesting;
    RolesStub roles;

    address HOLDER = account("Holder");
    address REVOKER = account("Revoker");
    uint8 REVOKER_ROLE = 50;
    uint256 issuedAmount = authorizedAmount / 10;

    function setUp() public override {
        super.setUp();

        vm.warp(0);

        roles = new RolesStub();
        vesting = VestingController(
            createProxy(
                new VestingController(), abi.encodeCall(VestingController.initialize, (captable, roles, address(0)))
            )
        );

        roles.setRole(REVOKER, REVOKER_ROLE, true);
    }

    function controller() internal view override returns (AccountController) {
        return vesting;
    }

    function testNonCaptableCannotAddAccount() public {
        vm.expectRevert(abi.encodeWithSelector(AccountController.UnauthorizedNotCaptable.selector));
        vesting.addAccount(HOLDER, classId, authorizedAmount - 1, bytes(""));
    }

    function testCaptableAddsAccount() public returns (uint40 startDate, uint40 cliffDate, uint40 endDate) {
        vm.prank(address(safe));
        VestingController.VestingParams memory vestingParams = VestingController.VestingParams({
            startDate: 10,
            cliffDate: 20,
            endDate: 30,
            revoker: roleFlag(REVOKER_ROLE)
        });
        captable.issueAndSetController(HOLDER, classId, issuedAmount, vesting, abi.encode(vestingParams));

        (uint256 amount, VestingController.VestingParams memory params) = vesting.accounts(HOLDER, classId);
        assertEq(amount, issuedAmount);
        assertEq(params.startDate, 10);
        assertEq(params.cliffDate, 20);
        assertEq(params.endDate, 30);
        assertEq(params.revoker, roleFlag(REVOKER_ROLE));

        return (vestingParams.startDate, vestingParams.cliffDate, vestingParams.endDate);
    }

    function testCannotAddAccountTwice() public {
        testCaptableAddsAccount();

        vm.expectRevert(abi.encodeWithSelector(AccountController.AccountAlreadyExists.selector));
        testCaptableAddsAccount();
    }

    function testCannotAddAccountWithInvalidParameters() public {
        vm.startPrank(address(captable));

        vm.expectRevert(abi.encodeWithSelector(VestingController.InvalidVestingParameters.selector));
        vesting.addAccount(
            HOLDER,
            classId,
            authorizedAmount - 1,
            abi.encode(
                VestingController.VestingParams({
                    startDate: 21,
                    cliffDate: 20,
                    endDate: 30,
                    revoker: roleFlag(REVOKER_ROLE)
                })
            )
        );

        vm.expectRevert(abi.encodeWithSelector(VestingController.InvalidVestingParameters.selector));
        vesting.addAccount(
            HOLDER,
            classId,
            authorizedAmount - 1,
            abi.encode(
                VestingController.VestingParams({
                    startDate: 10,
                    cliffDate: 31,
                    endDate: 30,
                    revoker: roleFlag(REVOKER_ROLE)
                })
            )
        );

        vm.stopPrank();
    }

    function testTransferCheckOverTime() public {
        (uint40 startDate, uint40 cliffDate, uint40 endDate) = testCaptableAddsAccount();
        assertFalse(vesting.isTransferAllowed(HOLDER, HOLDER, classId, 1));
        vm.warp(startDate);
        assertFalse(vesting.isTransferAllowed(HOLDER, HOLDER, classId, 1));
        vm.warp(cliffDate - 1);
        assertFalse(vesting.isTransferAllowed(HOLDER, HOLDER, classId, 1));
        vm.warp(cliffDate);
        assertTrue(vesting.isTransferAllowed(HOLDER, HOLDER, classId, 1));
        assertTrue(vesting.isTransferAllowed(HOLDER, HOLDER, classId, issuedAmount / 2));
        assertFalse(vesting.isTransferAllowed(HOLDER, HOLDER, classId, issuedAmount / 2 + 1));
        vm.warp(cliffDate + (endDate - cliffDate) / 2);
        assertTrue(vesting.isTransferAllowed(HOLDER, HOLDER, classId, issuedAmount * 3 / 4 - 1));
        vm.warp(endDate - 1);
        assertTrue(vesting.isTransferAllowed(HOLDER, HOLDER, classId, issuedAmount * 9 / 10));
        assertFalse(vesting.isTransferAllowed(HOLDER, HOLDER, classId, issuedAmount));
        vm.warp(endDate);
        assertTrue(vesting.isTransferAllowed(HOLDER, HOLDER, classId, issuedAmount));
    }

    function testRevokerCanRevokeAtThisTime() public {
        (, uint40 cliffDate,) = testCaptableAddsAccount();
        vm.warp(cliffDate);
        vm.prank(REVOKER);
        vesting.revokeVesting(HOLDER, classId);

        assertEq(captable.balanceOf(HOLDER, classId), issuedAmount / 2);

        assertAccountWasCleanedUp();
    }

    function testRevokerCanRevokeInTheFuture() public {
        (uint40 startDate, uint40 cliffDate,) = testCaptableAddsAccount();
        vm.warp(startDate);
        vm.prank(REVOKER);
        vesting.revokeVesting(HOLDER, classId, cliffDate);

        assertEq(captable.balanceOf(HOLDER, classId), issuedAmount / 2);

        assertAccountWasCleanedUp();
    }

    function testRevokerCantRevokeInThePast() public {
        (, uint40 cliffDate,) = testCaptableAddsAccount();
        vm.warp(cliffDate);
        vm.prank(REVOKER);
        vm.expectRevert(abi.encodeWithSelector(VestingController.EffectiveDateInThePast.selector));
        vesting.revokeVesting(HOLDER, classId, cliffDate - 1);
    }

    function testRevokerCantRevokeAfterVestingEnded() public {
        (,, uint40 endDate) = testCaptableAddsAccount();

        vm.warp(endDate);
        vm.prank(REVOKER);
        vm.expectRevert(abi.encodeWithSelector(VestingController.InvalidVestingState.selector));
        vesting.revokeVesting(HOLDER, classId);
    }

    function testAnyoneCanCleanupAfterVestingEnds() public {
        (,, uint40 endDate) = testCaptableAddsAccount();
        vm.warp(endDate);
        vm.prank(account("Someone random"));
        vesting.cleanupFullyVestedAccount(HOLDER, classId);
        assertAccountWasCleanedUp();
    }

    function testCantCleanupBeforeVestingEnds() public {
        (,, uint40 endDate) = testCaptableAddsAccount();
        vm.warp(endDate - 1);
        vm.expectRevert(abi.encodeWithSelector(VestingController.InvalidVestingState.selector));
        vesting.cleanupFullyVestedAccount(HOLDER, classId);
    }

    function testCantCleanupUnexistingAccount() public {
        testAnyoneCanCleanupAfterVestingEnds();
        vm.expectRevert(abi.encodeWithSelector(AccountController.AccountDoesntExist.selector));
        vesting.cleanupFullyVestedAccount(HOLDER, classId);
    }

    function assertAccountWasCleanedUp() internal {
        (uint256 amount, VestingController.VestingParams memory params) = vesting.accounts(HOLDER, classId);
        assertEq(amount, 0);
        assertEq(params.startDate, 0);
        assertEq(params.cliffDate, 0);
        assertEq(params.endDate, 0);
        assertEq(params.revoker, address(0));
    }

    function testTransferCheckRevertsIfAccountDoesntExist() public {
        vm.expectRevert(abi.encodeWithSelector(AccountController.AccountDoesntExist.selector));
        vesting.isTransferAllowed(HOLDER, HOLDER, classId, 1);
    }

    function testRevokeRevertsIfAccountDoesntExist() public {
        vm.expectRevert(abi.encodeWithSelector(AccountController.AccountDoesntExist.selector));
        vesting.revokeVesting(HOLDER, classId, 1);
    }
}
