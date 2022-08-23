// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {FirmTest} from "../../common/test/lib/FirmTest.sol";
import {AvatarStub} from "../../common/test/mocks/AvatarStub.sol";

import {Captable, IBouncer} from "../Captable.sol";
import {EquityToken} from "../EquityToken.sol";
import {VestingController} from "../VestingController.sol";

contract BaseCaptableTest is FirmTest {
    Captable captable;
    AvatarStub safe = new AvatarStub();

    address HOLDER1 = account("Holder #1");
    address HOLDER2 = account("Holder #2");

    function setUp() public virtual {
        captable = new Captable(safe, "TestCo", IBouncer(address(0)));
    }
}

contract CaptableInitTest is BaseCaptableTest {
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
        (uint256 id, EquityToken token) = captable.createClass("Common", "TST-A", 100, 1);
        assertEq(id, 0);

        assertEq(token.name(), "TestCo: Common");
        assertEq(token.symbol(), "TST-A");
        assertEq(token.authorized(), 100);
        assertEq(token.totalSupply(), 0);
    }
}

contract CaptableOneClassTest is BaseCaptableTest {
    EquityToken token;
    uint256 classId;

    uint256 constant INITIAL_AUTHORIZED = 10000;

    function setUp() public override {
        super.setUp();

        vm.prank(address(safe));
        (classId, token) = captable.createClass("Common", "TST-A", INITIAL_AUTHORIZED, 1);
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

contract CaptableMulticlassTest is BaseCaptableTest {
    uint256 classId1;
    EquityToken token1;
    uint64 weight1 = 1;
    
    uint256 classId2;
    EquityToken token2;
    uint64 weight2 = 5;

    uint256 holder1InitialBalance1 = 100;
    uint256 holder1InitialBalance2 = 100;

    uint256 holder2InitialBalance1 = 0;
    uint256 holder2InitialBalance2 = 150;

    function setUp() public override {
        super.setUp();

        vm.prank(address(safe));
        (classId1, token1) = captable.createClass("Common", "TST-A", 1000, weight1);
        vm.prank(address(safe));
        (classId2, token2) = captable.createClass("Founder", "TST-B", 1000, weight2);
        
        _selfDelegateHolders();

        vm.roll(2); // set block number to 2
        _issueInitialShares();
    }

    function testVotingWeights() public {
        vm.roll(3);

        assertEq(captable.getVotes(HOLDER1), holder1InitialBalance1 + holder1InitialBalance2 * weight2);
        assertEq(captable.getVotes(HOLDER2), holder2InitialBalance2 * weight2);
        assertEq(captable.getTotalVotes(), holder1InitialBalance1 + (holder1InitialBalance1 + holder2InitialBalance2) * weight2);

        assertEq(captable.getPastVotes(HOLDER1, 1), 0);
        assertEq(captable.getPastVotes(HOLDER2, 1), 0);
        assertEq(captable.getPastTotalSupply(1), 0);

        assertEq(captable.getPastVotes(HOLDER1, 2), holder1InitialBalance1 + holder1InitialBalance2 * weight2);
        assertEq(captable.getPastVotes(HOLDER2, 2), holder2InitialBalance2 * weight2);
        assertEq(captable.getPastTotalSupply(2), holder1InitialBalance1 + (holder1InitialBalance1 + holder2InitialBalance2) * weight2);
    }

    function testVotesUpdateOnTransfer() public {
        vm.roll(3);
        
        vm.prank(HOLDER1);
        token1.transfer(HOLDER2, 50);

        assertEq(captable.getVotes(HOLDER1), holder1InitialBalance1 - 50 + holder1InitialBalance2 * weight2);
        assertEq(captable.getVotes(HOLDER2), 50 + holder2InitialBalance2 * weight2);

        // at height 2, balances stay unchanged
        assertEq(captable.getPastVotes(HOLDER1, 2), holder1InitialBalance1 + holder1InitialBalance2 * weight2);
        assertEq(captable.getPastVotes(HOLDER2, 2), holder2InitialBalance2 * weight2);
    }

    // votes only count when a delegation is set
    function _selfDelegateHolders() internal {
        vm.prank(HOLDER1);
        token1.delegate(HOLDER1);
        vm.prank(HOLDER1);
        token2.delegate(HOLDER1);
        vm.prank(HOLDER2);
        token1.delegate(HOLDER2);
        vm.prank(HOLDER2);
        token2.delegate(HOLDER2);
    }

    function _issueInitialShares() internal {
        captable.issue(HOLDER1, classId1, holder1InitialBalance1);
        captable.issue(HOLDER1, classId2, holder1InitialBalance2);
        // captable.issue(HOLDER2, classId1, holder2InitialBalance1); // issuing 0 fails
        captable.issue(HOLDER2, classId2, holder2InitialBalance2);
    }
}