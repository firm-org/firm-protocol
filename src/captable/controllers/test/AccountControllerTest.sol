// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import {FirmTest} from "src/bases/test/lib/FirmTest.sol";
import {SafeStub} from "src/bases/test/mocks/SafeStub.sol";

import "../../Captable.sol";
import {bouncerFlag, EmbeddedBouncerType} from "../../test/lib/BouncerFlags.sol";
import {AccountController} from "../AccountController.sol";

abstract contract AccountControllerTest is FirmTest {
    SafeStub safe;
    Captable captable;
    uint256 classId;
    EquityToken token;
    uint128 authorizedAmount = 1e6;

    IBouncer ALLOW_ALL_BOUNCER = bouncerFlag(EmbeddedBouncerType.AllowAll);

    function setUp() public virtual {
        safe = new SafeStub();
        captable =
            Captable(createProxy(new Captable(), abi.encodeCall(Captable.initialize, ("TestCo", safe, address(0)))));
        vm.prank(address(safe));
        (classId, token) =
            captable.createClass("Common", "TST.A", authorizedAmount, NO_CONVERSION_FLAG, 1, ALLOW_ALL_BOUNCER);
    }

    function controller() internal view virtual returns (AccountController);

    function testInitialState() public {
        assertEq(address(controller().captable()), address(captable));
        assertUnsStrg(address(controller()), "firm.accountcontroller.captable", address(captable));

        assertEq(address(controller().safe()), address(safe));
        assertUnsStrg(address(controller()), "firm.safeaware.safe", address(safe));
    }
}
