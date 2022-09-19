// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {FirmTest} from "../../common/test/lib/FirmTest.sol";
import "../../factory/UpgradeableModuleProxyFactory.sol";

import {SafeAware} from "../../bases/SafeAware.sol";
import "../Roles.sol";

contract RolesTest is FirmTest {
    Roles roles;

    address ADMIN = account("admin");
    address SOMEONE = account("someone");
    address SOMEONE_ELSE = account("someone else");

    function setUp() public virtual {
        roles = new Roles(IAvatar(ADMIN));
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

    function testCannotReinit() public {
        vm.expectRevert(abi.encodeWithSelector(SafeAware.AlreadyInitialized.selector));
        roles.initialize(IAvatar(address(2)));
    }

    function testAdminCanCreateRoles() public {
        vm.prank(ADMIN);
        uint8 roleId = roles.createRole(ONLY_ROOT_ROLE, "");
        assertEq(roleId, ROLE_MANAGER_ROLE + 1);

        assertTrue(roles.isRoleAdmin(ADMIN, roleId));
        assertTrue(roles.hasRole(ADMIN, roleId));
    }

    function testCannotCreateRolesWithoutRolesManagerRole() public {
        vm.expectRevert(abi.encodeWithSelector(Roles.UnauthorizedNoRole.selector, ROLE_MANAGER_ROLE));
        roles.createRole(ONLY_ROOT_ROLE, "");
    }

    function testSomeoneWithPermissionCanCreateRolesUntilRevoked() public {
        vm.prank(ADMIN);
        roles.setRole(SOMEONE, ROLE_MANAGER_ROLE, true);

        vm.prank(SOMEONE);
        uint8 roleId = roles.createRole(ONLY_ROOT_ROLE, "");
        assertEq(roleId, ROLE_MANAGER_ROLE + 1);

        vm.prank(ADMIN);
        roles.setRole(SOMEONE, ROLE_MANAGER_ROLE, false);

        vm.prank(SOMEONE);
        testCannotCreateRolesWithoutRolesManagerRole();
    }

    function testCanOnlyHave256Roles() public {
        vm.startPrank(ADMIN);
        for (uint256 i = 0; i < 254; i++) {
            roles.createRole(ONLY_ROOT_ROLE, "");
        }
        assertEq(roles.roleCount(), 256);

        vm.expectRevert(abi.encodeWithSelector(Roles.RoleLimitReached.selector));
        roles.createRole(ONLY_ROOT_ROLE, "");
    }

    function testAdminCanGrantAndRevokeRoles() public {
        vm.startPrank(ADMIN);
        uint8 roleId = roles.createRole(ONLY_ROOT_ROLE, "");

        roles.setRole(SOMEONE, roleId, true);
        assertTrue(roles.hasRole(SOMEONE, roleId));
        assertTrue(roles.isRoleAdmin(ADMIN, roleId));

        roles.setRole(SOMEONE, roleId, false);
        assertFalse(roles.hasRole(SOMEONE, roleId));
    }

    function testNonAdminCannotGrantRole() public {
        vm.startPrank(ADMIN);
        uint8 roleId = roles.createRole(ONLY_ROOT_ROLE, "");
        roles.setRole(SOMEONE, roleId, true);
        vm.stopPrank();

        vm.prank(SOMEONE);
        vm.expectRevert(abi.encodeWithSelector(Roles.UnauthorizedNotAdmin.selector, roleId));
        roles.setRole(SOMEONE_ELSE, roleId, true);
    }

    function testCanSetMultipleRoles() public {
        vm.startPrank(ADMIN);
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

        vm.stopPrank();
        vm.prank(SOMEONE);
        roles.setRole(SOMEONE_ELSE, roleTwo, true);

        assertTrue(roles.hasRole(SOMEONE_ELSE, roleTwo));
        assertFalse(roles.isRoleAdmin(SOMEONE_ELSE, roleTwo));
    }

    function testCanChangeRoleAdmin() public {
        vm.startPrank(ADMIN);
        uint8 newRoleId = roles.createRole(ONLY_ROOT_ROLE, "");
        roles.setRole(SOMEONE, newRoleId, true);
        vm.stopPrank();

        vm.prank(SOMEONE);
        vm.expectRevert(abi.encodeWithSelector(Roles.UnauthorizedNotAdmin.selector, newRoleId));
        roles.setRole(SOMEONE_ELSE, newRoleId, true);

        vm.prank(ADMIN);
        bytes32 newRoleAdmin = ONLY_ROOT_ROLE | bytes32(1 << uint256(newRoleId));
        roles.setRoleAdmin(newRoleId, newRoleAdmin); // those with newRoleId are admins
        assertEq(roles.getRoleAdmins(newRoleId), newRoleAdmin);

        vm.prank(SOMEONE);
        roles.setRole(SOMEONE_ELSE, newRoleId, true); // action that was previously reverting, now succeeds

        assertTrue(roles.hasRole(SOMEONE_ELSE, newRoleId));
    }

    function testCannotChangeRoleAdminWithoutRolesManagerRole() public {
        vm.startPrank(ADMIN);
        uint8 newRoleId = roles.createRole(ONLY_ROOT_ROLE, "");
        roles.setRole(SOMEONE, newRoleId, true);
        vm.stopPrank();

        vm.prank(SOMEONE);
        vm.expectRevert(abi.encodeWithSelector(Roles.UnauthorizedNoRole.selector, ROLE_MANAGER_ROLE));
        roles.setRoleAdmin(newRoleId, ONLY_ROOT_ROLE);
    }

    function testAdminCanChangeAdminForAdminRole() public {
        bytes32 newRoleAdmin = ONLY_ROOT_ROLE | bytes32(1 << uint256(ROLE_MANAGER_ROLE));
        vm.prank(ADMIN);
        roles.setRoleAdmin(ROOT_ROLE_ID, newRoleAdmin);
        assertEq(roles.getRoleAdmins(ROOT_ROLE_ID), newRoleAdmin);
    }

    function testNonAdminCantChangeAdminForAdminRole() public {
        vm.prank(ADMIN);
        roles.setRole(SOMEONE, ROLE_MANAGER_ROLE, true);

        // As SOMEONE is granted ROLE_MANAGER_ROLE, it can change the admin for all roles, including ROLE_MANAGER_ROLE
        vm.startPrank(SOMEONE);
        bytes32 newRoleAdmin = ONLY_ROOT_ROLE | bytes32(1 << uint256(ROLE_MANAGER_ROLE));
        roles.setRoleAdmin(ROLE_MANAGER_ROLE, newRoleAdmin);
        assertEq(roles.getRoleAdmins(ROLE_MANAGER_ROLE), newRoleAdmin);

        // However, when attempting to change the admin role, it will fail
        vm.expectRevert(abi.encodeWithSelector(Roles.UnauthorizedNotAdmin.selector, ROOT_ROLE_ID));
        roles.setRoleAdmin(ROOT_ROLE_ID, newRoleAdmin);
    }
}

contract RolesWithProxyTest is RolesTest {
    UpgradeableModuleProxyFactory immutable factory = new UpgradeableModuleProxyFactory();
    address immutable rolesImpl = address(new Roles(IAvatar(address(1))));

    function setUp() public override {
        roles = Roles(factory.deployUpgradeableModule(rolesImpl, abi.encodeCall(Roles.initialize, (IAvatar(ADMIN))), 0));
        vm.label(address(roles), "RolesProxy");
    }
}
