// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import {RolesStub} from "src/bases/test/mocks/RolesStub.sol";

import {AccountControllerTest} from "./AccountControllerTest.sol";
import {VestingController, AccountController} from "../VestingController.sol";

contract VestingControllerTest is AccountControllerTest {
    VestingController vesting;
    RolesStub roles;

    function setUp() public override {
        super.setUp();

        roles = new RolesStub();
        vesting = VestingController(createProxy(new VestingController(), abi.encodeCall(VestingController.initialize, (captable, roles, address(0)))));
    }

    function controller() internal view override returns (AccountController) {
        return vesting;
    }

    function testVesting() public {
        // TODO
    }
}