// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import {FirmTest} from "../../../bases/test/lib/FirmTest.sol";
import {SafeStub} from "../../../bases/test/mocks/SafeStub.sol";

import "../../Captable.sol";
import {AccountController} from "../AccountController.sol";

abstract contract AccountControllerTest is FirmTest {
    SafeStub safe;
    Captable captable;

    function setUp() public virtual {
        safe = new SafeStub();
        captable = Captable(createProxy(new Captable(), abi.encodeCall(Captable.initialize, ("TestCo", safe, address(0)))));
    }

    function controller() internal view virtual returns (AccountController);

    function testInitialState() public {
        assertEq(address(controller().captable()), address(captable));
        assertUnsStrg(address(controller()), "firm.accountcontroller.captable", address(captable));

        assertEq(address(controller().safe()), address(safe));
        assertUnsStrg(address(controller()), "firm.safeaware.safe", address(safe));
    }
}