// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

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
        (classId, token) = captable.createClass("Common", "TST-A", 10000, NO_CONVERSION_FLAG, 1, ALLOW_ALL_BOUNCER);
        captable.issue(HOLDER1, classId, HOLDER_BALANCE);
        vm.stopPrank();
    }

    function testInitialState() public {
        assertEq(token.classId(), classId);
        assertEq(address(token.captable()), address(captable));
        assertEq(token.totalSupply(), HOLDER_BALANCE);
        assertEq(token.decimals(), 18);
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
