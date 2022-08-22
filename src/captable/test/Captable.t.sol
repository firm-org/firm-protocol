// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {FirmTest} from "../../common/test/lib/FirmTest.sol";
import {AvatarStub} from "../../common/test/mocks/AvatarStub.sol";

import {Captable, IBouncer} from "../Captable.sol";
import {EquityToken} from "../EquityToken.sol";
import {VestingController} from "../VestingController.sol";

contract CaptableTest is FirmTest {
    Captable captable;
    AvatarStub safe = new AvatarStub();

    function setUp() public {
        captable = new Captable(safe, "TestCo", IBouncer(address(0)));
    }

    function testInitialState() public {
        assertEq(address(captable.safe()), address(safe));
        assertEq(captable.name(), "TestCo");
        // TODO: asserteq global controls

        assertEq(captable.classCount(), 0);

        bytes memory unexistentError = abi.encodeWithSelector(Captable.UnexistentClass.selector, 0);
        vm.expectRevert(unexistentError);
        captable.nameFor(0);
        vm.expectRevert(unexistentError);
        captable.tickerFor(0);
    }

    function testCreateClass() public {
        vm.prank(address(safe));
        (uint256 id, EquityToken token) = captable.createClass("Common", "TST-A", 100);
        assertEq(id, 0);

        assertEq(token.name(), "TestCo: Common");
        assertEq(token.symbol(), "TST-A");
        assertEq(token.authorized(), 100);
        assertEq(token.totalSupply(), 0);
    }
}

contract CaptableWithClassTest is FirmTest {
    Captable captable;
    EquityToken token;
    uint256 classId;

    AvatarStub safe = new AvatarStub();

    address HOLDER1 = account("Holder #1");
    address HOLDER2 = account("Holder #2");

    uint256 constant INITIAL_AUTHORIZED = 10000;

    function setUp() public {
        captable = new Captable(safe, "TestCo", IBouncer(address(0)));
        vm.prank(address(safe));
        (classId, token) = captable.createClass("Common", "TST-A", INITIAL_AUTHORIZED);
    }

    function testCanIssue(uint256 amount) public {
        vm.assume(amount > 0 && amount <= INITIAL_AUTHORIZED);
        captable.issue(HOLDER1, classId, amount);
        assertEq(token.balanceOf(HOLDER1), amount);
        assertEq(token.totalSupply(), amount);

        vm.prank(HOLDER1);
        token.transfer(HOLDER2, 1);
        assertEq(token.balanceOf(HOLDER2), 1);
    }

    function testCantIssueAboveAuthorized() public {
        vm.expectRevert(abi.encodeWithSelector(EquityToken.IssuingOverAuthorized.selector));
        captable.issue(HOLDER1, classId, INITIAL_AUTHORIZED + 1);
    }

    function testCanIssueWithVesting() public {
        uint256 amount = INITIAL_AUTHORIZED;

        VestingController vestingController = new VestingController(captable);
        VestingController.VestingParams memory vestingParams;
        vestingParams.startDate = 100;
        vestingParams.cliffDate = 120;
        vestingParams.endDate = 200;

        captable.issueWithController(HOLDER1, classId, amount, vestingController, abi.encode(vestingParams));
        assertEq(token.balanceOf(HOLDER1), amount);

        vm.startPrank(HOLDER1);
        vm.warp(vestingParams.startDate - 1);
        vm.expectRevert(
            abi.encodeWithSelector(Captable.TransferBlocked.selector, vestingController, HOLDER1, HOLDER2, classId, 1)
        );
        token.transfer(HOLDER2, 1);

        vm.warp(vestingParams.cliffDate);
        token.transfer(HOLDER2, 1);
        assertEq(token.balanceOf(HOLDER2), 1);

        vm.warp(vestingParams.endDate);
        token.transfer(HOLDER2, token.balanceOf(HOLDER1));
        assertEq(token.balanceOf(HOLDER2), amount);
    }

    function testCanRevokeVesting() public {
        uint256 amount = 100;

        VestingController vestingController = new VestingController(captable);
        VestingController.VestingParams memory vestingParams;
        vestingParams.startDate = 100;
        vestingParams.cliffDate = 100;
        vestingParams.endDate = 200;

        captable.issueWithController(HOLDER1, classId, amount, vestingController, abi.encode(vestingParams));
        assertEq(token.balanceOf(HOLDER1), amount);

        vm.warp(150);
        vm.prank(address(safe));
        vestingController.revokeVesting(HOLDER1, 150);

        assertEq(token.balanceOf(HOLDER1), amount / 2);
        assertEq(token.balanceOf(address(safe)), amount / 2);
    }
}
