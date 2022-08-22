// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {FirmTest} from "../../common/test/lib/FirmTest.sol";
import {AvatarStub} from "../../common/test/mocks/AvatarStub.sol";

import {Captable, IBouncer} from "../Captable.sol";
import {EquityToken} from "../EquityToken.sol";

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

    uint256 constant INITIAL_AUTHORIZED = 10000;

    function setUp() public {
        captable = new Captable(safe, "TestCo", IBouncer(address(0)));
        vm.prank(address(safe));
        (classId, token) = captable.createClass("Common", "TST-A", INITIAL_AUTHORIZED);
    }

    function testCanIssue(uint256 amount) public {
        vm.assume(amount <= INITIAL_AUTHORIZED);
        captable.issue(classId, HOLDER1, amount);
        assertEq(token.balanceOf(HOLDER1), amount);
        assertEq(token.totalSupply(), amount);
    }

    function testCantIssueAboveAuthorized() public {
        vm.expectRevert(abi.encodeWithSelector(EquityToken.IssuingOverAuthorized.selector));
        captable.issue(classId, HOLDER1, INITIAL_AUTHORIZED + 1);
    }
}