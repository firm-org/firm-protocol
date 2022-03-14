// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "solmate/test/utils/DSTestPlus.sol";

import "../Roles.sol";

contract RolesTest is DSTestPlus {
    Roles roles;

    address ADMIN = address(1);
    address SOMEONE = address(2);
    address SOMEONE_ELSE = address(3);

    function setUp() public {
        roles = new Roles(ADMIN);
    }

    function testInitialAdmin() public {
        assertTrue(roles.hasRole(ADMIN, ROOT_ROLE));
        assertTrue(roles.isRoleAdmin(ADMIN, ROOT_ROLE));
        assertFalse(roles.hasRole(address(this), ROOT_ROLE));
        assertFalse(roles.isRoleAdmin(address(this), ROOT_ROLE));
    }

    function testAdminCanCreateRoles() public {
        hevm.startPrank(ADMIN);
        uint8 roleId = roles.createRole(ROOT_AS_ADMIN, "");
        assertEq(roleId, 1);

        assertTrue(roles.isRoleAdmin(ADMIN, roleId));
        assertFalse(roles.hasRole(ADMIN, roleId));
    }

    function testNonRootCannotCreateRoles() public {
        hevm.expectRevert(abi.encodeWithSelector(Roles.UnauthorizedNoRole.selector, ROOT_ROLE));
        roles.createRole(ROOT_AS_ADMIN, "");
    }

    function testCanOnlyHave256Roles() public {
        hevm.startPrank(ADMIN);
        for (uint256 i = 0; i < 255; i++) {
            roles.createRole(ROOT_AS_ADMIN, "");
        }
        assertEq(roles.roleCount(), 256);

        hevm.expectRevert(abi.encodeWithSelector(Roles.RoleLimitReached.selector));
        roles.createRole(ROOT_AS_ADMIN, "");
    }

    function testAdminCanGrantAndRevokeRoles() public {
        hevm.startPrank(ADMIN);
        uint8 roleId = roles.createRole(ROOT_AS_ADMIN, "");

        roles.setRole(SOMEONE, roleId, true);
        assertTrue(roles.hasRole(SOMEONE, roleId));
        assertTrue(roles.isRoleAdmin(ADMIN, roleId));
        assertFalse(roles.hasRole(ADMIN, roleId));

        roles.setRole(SOMEONE, roleId, false);
        assertFalse(roles.hasRole(SOMEONE, roleId));
    }

    function testNonAdminCannotGrantRole() public {
        hevm.startPrank(ADMIN);
        uint8 roleId = roles.createRole(ROOT_AS_ADMIN, "");
        roles.setRole(SOMEONE, roleId, true);

        hevm.startPrank(SOMEONE);
        hevm.expectRevert(abi.encodeWithSelector(Roles.UnauthorizedNotAdmin.selector, roleId));
        roles.setRole(SOMEONE_ELSE, roleId, true);
    }

    function testCanSetMultipleRoles() public {
        hevm.startPrank(ADMIN);
        uint8 roleOne = roles.createRole(ROOT_AS_ADMIN, ""); // Admin for role 1 is Role 0
        uint8 roleTwo = roles.createRole(bytes32(uint256((1 << 0) | (1 << 1))), ""); // Adming for role 2 is Role 0 and 1

        uint8[] memory rolesSomeone = new uint8[](2);
        rolesSomeone[0] = roleOne;
        rolesSomeone[1] = roleTwo;

        roles.setRoles(SOMEONE, rolesSomeone, new uint8[](0));

        assertTrue(roles.hasRole(SOMEONE, roleOne));
        assertTrue(roles.hasRole(SOMEONE, roleTwo));
        assertFalse(roles.isRoleAdmin(SOMEONE, roleOne));
        assertTrue(roles.isRoleAdmin(SOMEONE, roleTwo));
       
        hevm.prank(SOMEONE);
        roles.setRole(SOMEONE_ELSE, roleTwo, true);

        assertTrue(roles.hasRole(SOMEONE_ELSE, roleTwo));
        assertFalse(roles.isRoleAdmin(SOMEONE_ELSE, roleTwo));
    }
}