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

    // votes only count when a delegation is set
    function _selfDelegateHolders(EquityToken token) internal {
        vm.prank(HOLDER1);
        token.delegate(HOLDER1);
        vm.prank(HOLDER2);
        token.delegate(HOLDER2);
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

    function testCannotCreateMoreClassesThanLimit() public {
        uint256 CLASSES_LIMIT = 128;

        for (uint256 i = 0; i < CLASSES_LIMIT; i++) {
            vm.prank(address(safe));
            captable.createClass("", "", 0, 0);
        }
        assertEq(captable.classCount(), CLASSES_LIMIT);

        vm.prank(address(safe));
        vm.expectRevert(abi.encodeWithSelector(Captable.ClassCreationAboveLimit.selector));
        captable.createClass("", "", 0, 0);
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
        
        _selfDelegateHolders(token1);
        _selfDelegateHolders(token2);

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

    function _issueInitialShares() internal {
        captable.issue(HOLDER1, classId1, holder1InitialBalance1);
        captable.issue(HOLDER1, classId2, holder1InitialBalance2);
        // captable.issue(HOLDER2, classId1, holder2InitialBalance1); // issuing 0 fails
        captable.issue(HOLDER2, classId2, holder2InitialBalance2);
    }
}

contract CaptableClassLimit1Test is BaseCaptableTest {
    uint256 constant classesLimit = 128;
    uint256 constant transfersLimit = 64;

    // Holder gets token in each of the classes
    function setUp() override public {
        super.setUp();

        for (uint256 i = 0; i < classesLimit; i++) {
            vm.roll(0);
            vm.prank(address(safe));
            (uint256 classId, EquityToken token) = captable.createClass("", "", transfersLimit, 1);
            _selfDelegateHolders(token);
        
            // Artificially create checkpoints by issuing one share per block
            for (uint256 j = 0; j < transfersLimit; j++) {
                vm.roll(j);
                captable.issue(HOLDER1, classId, 1);
            }
        }
    }

    function testGetVotesGas() public {
        vm.roll(transfersLimit);
        assertEq(captable.getVotes(HOLDER1), classesLimit * transfersLimit);
    }

    function testGetTotalVotesGas() public {
        vm.roll(transfersLimit);
        assertEq(captable.getTotalVotes(), classesLimit * transfersLimit);
    }

    function testGetPastVotesGas() public {
        vm.roll(transfersLimit);
        // look for a checkpoint close to the worst case in the binary search
        assertEq(captable.getPastVotes(HOLDER1, transfersLimit - 2), classesLimit * (transfersLimit - 1));
    }

    function testGetPastTotalSupplyGas() public {
        vm.roll(transfersLimit);
        // look for a checkpoint close to the worst case in the binary search
        assertEq(captable.getPastTotalSupply(transfersLimit - 2), classesLimit * (transfersLimit - 1));
    }
}

contract CaptableClassLimit2Test is BaseCaptableTest {
    uint256 constant classesLimit = 128;
    uint256 constant transfersLimit = 64;

    // Holder just has tokens in one class
    function setUp() override public {
        super.setUp();

        for (uint256 i = 0; i < classesLimit; i++) {
            vm.roll(0);
            vm.prank(address(safe));
            (uint256 classId, EquityToken token) = captable.createClass("", "", transfersLimit, 1);
            _selfDelegateHolders(token);
        
            if (i == 0) {
                for (uint256 j = 0; j < transfersLimit; j++) {
                    vm.roll(j);
                    captable.issue(HOLDER1, classId, 1);
                }
            }
        }
    }

    function testGetVotesGas() public {
        vm.roll(transfersLimit);
        assertEq(captable.getVotes(HOLDER1), transfersLimit);
    }

    function testGetTotalVotesGas() public {
        vm.roll(transfersLimit);
        assertEq(captable.getTotalVotes(), transfersLimit);
    }

    function testGetPastVotesGas() public {
        vm.roll(transfersLimit);
        // look for a checkpoint close to the worst case in the binary search
        assertEq(captable.getPastVotes(HOLDER1, transfersLimit - 2), transfersLimit - 1);
    }

    function testGetPastTotalSupplyGas() public {
        vm.roll(transfersLimit);
        // look for a checkpoint close to the worst case in the binary search
        assertEq(captable.getPastTotalSupply(transfersLimit - 2), transfersLimit - 1);
    }
}