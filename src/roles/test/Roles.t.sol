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

    function testInitialRoot() public {
        assertTrue(roles.hasRole(ADMIN, ROOT_ROLE_ID));
        assertTrue(roles.isRoleAdmin(ADMIN, ROOT_ROLE_ID));
        assertFalse(roles.hasRole(address(this), ROOT_ROLE_ID));
        assertFalse(roles.isRoleAdmin(address(this), ROOT_ROLE_ID));

        assertTrue(roles.hasRole(ADMIN, ROLE_MANAGER_ROLE));
        assertTrue(roles.isRoleAdmin(ADMIN, ROLE_MANAGER_ROLE));
        assertFalse(roles.hasRole(address(this), ROLE_MANAGER_ROLE));
        assertFalse(roles.isRoleAdmin(address(this), ROLE_MANAGER_ROLE));
    }

    function testAdminCanCreateRoles() public {
        hevm.prank(ADMIN);
        uint8 roleId = roles.createRole(ONLY_ROOT_ROLE, "");
        assertEq(roleId, ROLE_MANAGER_ROLE + 1);

        assertTrue(roles.isRoleAdmin(ADMIN, roleId));
        assertTrue(roles.hasRole(ADMIN, roleId));
    }

    function testCannotCreateRolesWithoutRolesManagerRole() public {
        hevm.expectRevert(abi.encodeWithSelector(Roles.UnauthorizedNoRole.selector, ROLE_MANAGER_ROLE));
        roles.createRole(ONLY_ROOT_ROLE, "");
    }

    function testSomeoneWithPermissionCanCreateRolesUntilRevoked() public {
        hevm.prank(ADMIN);
        roles.setRole(SOMEONE, ROLE_MANAGER_ROLE, true);

        hevm.prank(SOMEONE);
        uint8 roleId = roles.createRole(ONLY_ROOT_ROLE, "");
        assertEq(roleId, ROLE_MANAGER_ROLE + 1);

        hevm.prank(ADMIN);
        roles.setRole(SOMEONE, ROLE_MANAGER_ROLE, false);

        hevm.prank(SOMEONE);
        testCannotCreateRolesWithoutRolesManagerRole();
    }

    function testCanOnlyHave256Roles() public {
        hevm.startPrank(ADMIN);
        for (uint256 i = 0; i < 254; i++) {
            roles.createRole(ONLY_ROOT_ROLE, "");
        }
        assertEq(roles.roleCount(), 256);

        hevm.expectRevert(abi.encodeWithSelector(Roles.RoleLimitReached.selector));
        roles.createRole(ONLY_ROOT_ROLE, "");
    }

    function testAdminCanGrantAndRevokeRoles() public {
        hevm.startPrank(ADMIN);
        uint8 roleId = roles.createRole(ONLY_ROOT_ROLE, "");

        roles.setRole(SOMEONE, roleId, true);
        assertTrue(roles.hasRole(SOMEONE, roleId));
        assertTrue(roles.isRoleAdmin(ADMIN, roleId));

        roles.setRole(SOMEONE, roleId, false);
        assertFalse(roles.hasRole(SOMEONE, roleId));
    }

    function testNonAdminCannotGrantRole() public {
        hevm.startPrank(ADMIN);
        uint8 roleId = roles.createRole(ONLY_ROOT_ROLE, "");
        roles.setRole(SOMEONE, roleId, true);

        hevm.prank(SOMEONE);
        hevm.expectRevert(abi.encodeWithSelector(Roles.UnauthorizedNotAdmin.selector, roleId));
        roles.setRole(SOMEONE_ELSE, roleId, true);
    }

    function testCanSetMultipleRoles() public {
        hevm.startPrank(ADMIN);
        uint8 roleOne = roles.createRole(ONLY_ROOT_ROLE, ""); // Admin for role one is ROOT_ROLE_ID
        uint8 roleTwo = roles.createRole(ONLY_ROOT_ROLE | bytes32(1 << uint256(roleOne)), ""); // Admin for role 2 is ROOT_ROLE_ID and roleOne

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

    function testCanChangeRoleAdmin() public {
        hevm.startPrank(ADMIN);
        uint8 newRoleId = roles.createRole(ONLY_ROOT_ROLE, "");
        roles.setRole(SOMEONE, newRoleId, true);

        hevm.prank(SOMEONE);
        hevm.expectRevert(abi.encodeWithSelector(Roles.UnauthorizedNotAdmin.selector, newRoleId));
        roles.setRole(SOMEONE_ELSE, newRoleId, true);

        hevm.prank(ADMIN);
        bytes32 newRoleAdmin = ONLY_ROOT_ROLE | bytes32(1 << uint256(newRoleId));
        roles.setRoleAdmin(newRoleId, newRoleAdmin); // those with newRoleId are admins
        assertEq(roles.getRoleAdmin(newRoleId), newRoleAdmin);

        hevm.prank(SOMEONE);
        roles.setRole(SOMEONE_ELSE, newRoleId, true); // action that was previously reverting, now succeeds

        assertTrue(roles.hasRole(SOMEONE_ELSE, newRoleId));
    }

    function testCannotChangeRoleAdminWithoutRolesManagerRole() public {
        hevm.startPrank(ADMIN);
        uint8 newRoleId = roles.createRole(ONLY_ROOT_ROLE, "");
        roles.setRole(SOMEONE, newRoleId, true);

        hevm.prank(SOMEONE);
        hevm.expectRevert(abi.encodeWithSelector(Roles.UnauthorizedNoRole.selector, ROLE_MANAGER_ROLE));
        roles.setRoleAdmin(newRoleId, ONLY_ROOT_ROLE);
    }

    function testAdminCanChangeAdminForAdminRole() public {
        bytes32 newRoleAdmin = ONLY_ROOT_ROLE | bytes32(1 << uint256(ROLE_MANAGER_ROLE));
        hevm.prank(ADMIN);
        roles.setRoleAdmin(ROOT_ROLE_ID, newRoleAdmin);
        assertEq(roles.getRoleAdmin(ROOT_ROLE_ID), newRoleAdmin);
    }

    function testNonAdminCantChangeAdminForAdminRole() public {
        hevm.prank(ADMIN);
        roles.setRole(SOMEONE, ROLE_MANAGER_ROLE, true);

        // As SOMEONE is granted ROLE_MANAGER_ROLE, it can change the admin for all roles, including ROLE_MANAGER_ROLE
        hevm.startPrank(SOMEONE);
        bytes32 newRoleAdmin = ONLY_ROOT_ROLE | bytes32(1 << uint256(ROLE_MANAGER_ROLE));
        roles.setRoleAdmin(ROLE_MANAGER_ROLE, newRoleAdmin);
        assertEq(roles.getRoleAdmin(ROLE_MANAGER_ROLE), newRoleAdmin);

        // However, when attempting to change the admin role, it will fail
        hevm.expectRevert(abi.encodeWithSelector(Roles.UnauthorizedNotAdmin.selector, ROOT_ROLE_ID));
        roles.setRoleAdmin(ROOT_ROLE_ID, newRoleAdmin);
    }
}