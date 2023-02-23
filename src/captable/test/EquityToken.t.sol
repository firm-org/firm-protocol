// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import {BaseCaptableTest} from "./Captable.t.sol";

import {Captable, NO_CONVERSION_FLAG} from "../Captable.sol";
import {EquityToken} from "../EquityToken.sol";

contract EquityTokenTest is BaseCaptableTest {
    EquityToken token;
    uint256 classId;

    uint256 HOLDER_BALANCE = 1000;

    function setUp() public override {
        super.setUp();

        vm.startPrank(address(safe));
        (classId, token) = captable.createClass("Common", "TST.A", 10000, NO_CONVERSION_FLAG, 1, ALLOW_ALL_BOUNCER);
        captable.issue(HOLDER1, classId, HOLDER_BALANCE);
        vm.stopPrank();
    }

    function testInitialState() public {
        assertEq(token.classId(), classId);
        assertEq(address(token.captable()), address(captable));
        assertEq(token.totalSupply(), HOLDER_BALANCE);
        assertEq(token.decimals(), 18);
    }

    function testCantReinitialize() public {
        vm.expectRevert(abi.encodeWithSelector(EquityToken.AlreadyInitialized.selector));
        token.initialize(captable, 1);
    }

    function testCaptableCanPerformAdminActions() public {
        vm.startPrank(address(captable));

        token.mint(HOLDER2, 2);
        assertEq(token.balanceOf(HOLDER2), 2);

        token.burn(HOLDER2, 1);
        assertEq(token.balanceOf(HOLDER2), 1);

        token.forcedTransfer(HOLDER2, HOLDER1, 1);
        assertEq(token.balanceOf(HOLDER1), HOLDER_BALANCE + 1);
        assertEq(token.balanceOf(HOLDER2), 0);
        
        vm.stopPrank();
    }

    function testNonCaptableCannotPerformAdminActions() public {
        bytes memory onlyCaptableError = abi.encodeWithSelector(EquityToken.UnauthorizedNotCaptable.selector);
        
        vm.startPrank(address(safe));

        vm.expectRevert(onlyCaptableError);
        token.mint(HOLDER1, 1);

        vm.expectRevert(onlyCaptableError);
        token.burn(HOLDER1, 1);

        vm.expectRevert(onlyCaptableError);
        token.forcedTransfer(HOLDER1, HOLDER2, 1);

        vm.stopPrank();
    }
}
