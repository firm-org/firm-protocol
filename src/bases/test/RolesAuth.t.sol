// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import {FirmTest} from "./lib/FirmTest.sol";

import {roleFlag} from "./lib/RolesAuthFlags.sol";
import {RolesAuthMock} from "./mocks/RolesAuthMock.sol";

import {RolesStub} from "./mocks/RolesStub.sol";

contract RolesAuthTest is FirmTest {
    RolesStub roles;
    RolesAuthMock rolesAuth;

    address SOMEONE = account("someone");

    function setUp() public {
        roles = new RolesStub();
        rolesAuth = new RolesAuthMock(roles);
    }

    function testRolesIsSaved() public {
        assertEq(address(rolesAuth.roles()), address(roles));
        assertUnsStrg(address(rolesAuth), "firm.rolesauth.roles", address(roles));
    }

    function testExplicitAddrIsAuthorized() public {
        assertTrue(rolesAuth.isAuthorized(SOMEONE, SOMEONE));
        assertFalse(rolesAuth.isAuthorized(address(this), SOMEONE));
    }

    function testRoleFlags(uint8 roleId) public {
        roles.setRole(SOMEONE, roleId, true);

        assertTrue(rolesAuth.isAuthorized(SOMEONE, roleFlag(roleId)));
        assertFalse(rolesAuth.isAuthorized(address(this), roleFlag(roleId)));
    }

    function testRoleFlagsEdgeCases() public {
        roles.setRole(SOMEONE, 2, true);

        assertTrue(rolesAuth.isAuthorized(SOMEONE, 0x0000000000000000000000000000000000000201));
        assertFalse(rolesAuth.isAuthorized(SOMEONE, 0x0000000000000000000000000000000000000301));
        assertFalse(rolesAuth.isAuthorized(SOMEONE, 0x0000000000000000000000000000000000000200));
        assertFalse(rolesAuth.isAuthorized(SOMEONE, 0x0000000000000000000000000000000000000202));
        assertFalse(rolesAuth.isAuthorized(SOMEONE, 0x0000000000000000000000000000000000010201));
        assertFalse(rolesAuth.isAuthorized(SOMEONE, 0xaBababaBabABabaBAbabAbAbABabaBABABAB0201));
    }
}
