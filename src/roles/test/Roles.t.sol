// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {FirmTest} from "../../common/test/lib/FirmTest.sol";
import {SafeStub} from "../../common/test/mocks/SafeStub.sol";

import {SafeAware} from "../../bases/SafeAware.sol";
import "../Roles.sol";

contract RolesTest is FirmTest {
    SafeStub safe;
    Roles roles;

    address SOMEONE = account("someone");
    address SOMEONE_ELSE = account("someone else");
    address SAFE_OWNER = account("safe owner");

    function setUp() public {
        safe = new SafeStub();
        safe.setOwner(SAFE_OWNER, true);

        roles = Roles(createProxy(new Roles(), abi.encodeCall(Roles.initialize, (ISafe(payable(safe)), address(0)))));
    }

    function testInitialRoot() public {
        assertTrue(roles.hasRole(address(safe), ROOT_ROLE_ID));
        assertTrue(roles.isRoleAdmin(address(safe), ROOT_ROLE_ID));
        assertFalse(roles.hasRole(address(this), ROOT_ROLE_ID));
        assertFalse(roles.isRoleAdmin(address(this), ROOT_ROLE_ID));

        assertTrue(roles.hasRole(address(safe), ROLE_MANAGER_ROLE_ID));
        assertTrue(roles.isRoleAdmin(address(safe), ROLE_MANAGER_ROLE_ID));
        assertFalse(roles.hasRole(address(this), ROLE_MANAGER_ROLE_ID));
        assertFalse(roles.isRoleAdmin(address(this), ROLE_MANAGER_ROLE_ID));

        assertTrue(roles.roleExists(ROLE_MANAGER_ROLE_ID));
        assertFalse(roles.roleExists(ROLE_MANAGER_ROLE_ID + 1));
        assertTrue(roles.roleExists(SAFE_OWNER_ROLE_ID));
    }

    function testCannotReinit() public {
        vm.expectRevert(abi.encodeWithSelector(SafeAware.AlreadyInitialized.selector));
        roles.initialize(ISafe(payable(address(2))), address(0));
    }

    function testAdminCanCreateRoles() public {
        vm.prank(address(safe));
        uint8 roleId = roles.createRole(ONLY_ROOT_ROLE_AS_ADMIN, "");
        assertEq(roleId, ROLE_MANAGER_ROLE_ID + 1);

        assertTrue(roles.isRoleAdmin(address(safe), roleId));
        assertTrue(roles.hasRole(address(safe), roleId));
    }

    function testCannotCreateRolesWithoutRolesManagerRole() public {
        vm.expectRevert(abi.encodeWithSelector(Roles.UnauthorizedNoRole.selector, ROLE_MANAGER_ROLE_ID));
        roles.createRole(ONLY_ROOT_ROLE_AS_ADMIN, "");
    }

    function testCannotCreateRoleWithNoAdmins() public {
        vm.prank(address(safe));
        vm.expectRevert(abi.encodeWithSelector(Roles.InvalidRoleAdmins.selector));
        roles.createRole(NO_ROLE_ADMINS, "");
    }

    function testSomeoneWithPermissionCanCreateRolesUntilRevoked() public {
        vm.prank(address(safe));
        roles.setRole(SOMEONE, ROLE_MANAGER_ROLE_ID, true);

        vm.prank(SOMEONE);
        uint8 roleId = roles.createRole(ONLY_ROOT_ROLE_AS_ADMIN, "");
        assertEq(roleId, ROLE_MANAGER_ROLE_ID + 1);

        vm.prank(address(safe));
        roles.setRole(SOMEONE, ROLE_MANAGER_ROLE_ID, false);

        vm.prank(SOMEONE);
        testCannotCreateRolesWithoutRolesManagerRole();
    }

    function testCanOnlyHave255RegularRoles() public {
        vm.startPrank(address(safe));
        for (uint256 i = 0; i < 253; i++) {
            roles.createRole(ONLY_ROOT_ROLE_AS_ADMIN, "");
        }
        assertEq(roles.roleCount(), 255);

        vm.expectRevert(abi.encodeWithSelector(Roles.RoleLimitReached.selector));
        roles.createRole(ONLY_ROOT_ROLE_AS_ADMIN, "");
    }

    function testAdminCanGrantAndRevokeRoles() public {
        vm.startPrank(address(safe));
        uint8 roleId = roles.createRole(ONLY_ROOT_ROLE_AS_ADMIN, "");

        roles.setRole(SOMEONE, roleId, true);
        assertTrue(roles.hasRole(SOMEONE, roleId));
        assertTrue(roles.isRoleAdmin(address(safe), roleId));

        roles.setRole(SOMEONE, roleId, false);
        assertFalse(roles.hasRole(SOMEONE, roleId));
    }

    function testNonAdminCannotGrantRole() public {
        vm.startPrank(address(safe));
        uint8 roleId = roles.createRole(ONLY_ROOT_ROLE_AS_ADMIN, "");
        roles.setRole(SOMEONE, roleId, true);
        vm.stopPrank();

        vm.prank(SOMEONE);
        vm.expectRevert(abi.encodeWithSelector(Roles.UnauthorizedNotAdmin.selector, roleId));
        roles.setRole(SOMEONE_ELSE, roleId, true);
    }

    function testCanSetAndRevokeMultipleRoles() public {
        vm.startPrank(address(safe));
        uint8 roleOne = roles.createRole(ONLY_ROOT_ROLE_AS_ADMIN, ""); // Admin for role one is ROOT_ROLE_ID
        uint8 roleTwo = roles.createRole(ONLY_ROOT_ROLE_AS_ADMIN | bytes32(1 << uint256(roleOne)), ""); // Admin for role 2 is ROOT_ROLE_ID and roleOne

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

        vm.prank(address(safe));
        roles.setRoles(SOMEONE, new uint8[](0), rolesSomeone);

        assertFalse(roles.hasRole(SOMEONE, roleOne));
        assertFalse(roles.hasRole(SOMEONE, roleTwo));
    }

    function testCanChangeRoleAdmin() public {
        vm.startPrank(address(safe));
        uint8 newRoleId = roles.createRole(ONLY_ROOT_ROLE_AS_ADMIN, "");
        roles.setRole(SOMEONE, newRoleId, true);
        vm.stopPrank();

        vm.prank(SOMEONE);
        vm.expectRevert(abi.encodeWithSelector(Roles.UnauthorizedNotAdmin.selector, newRoleId));
        roles.setRole(SOMEONE_ELSE, newRoleId, true);

        vm.prank(address(safe));
        bytes32 newRoleAdmin = ONLY_ROOT_ROLE_AS_ADMIN | bytes32(1 << uint256(newRoleId));
        roles.setRoleAdmins(newRoleId, newRoleAdmin); // those with newRoleId are admins
        assertEq(roles.getRoleAdmins(newRoleId), newRoleAdmin);

        vm.prank(SOMEONE);
        roles.setRole(SOMEONE_ELSE, newRoleId, true); // action that was previously reverting, now succeeds

        assertTrue(roles.hasRole(SOMEONE_ELSE, newRoleId));
    }

    function testCannotChangeRoleAdminWithoutRolesManagerRole() public {
        vm.startPrank(address(safe));
        uint8 newRoleId = roles.createRole(ONLY_ROOT_ROLE_AS_ADMIN, "");
        roles.setRole(SOMEONE, newRoleId, true);
        vm.stopPrank();

        vm.prank(SOMEONE);
        vm.expectRevert(abi.encodeWithSelector(Roles.UnauthorizedNoRole.selector, ROLE_MANAGER_ROLE_ID));
        roles.setRoleAdmins(newRoleId, ONLY_ROOT_ROLE_AS_ADMIN);
    }

    function testCannotChangeRoleNameWithoutRolesManagerRole() public {
        vm.startPrank(address(safe));
        uint8 newRoleId = roles.createRole(ONLY_ROOT_ROLE_AS_ADMIN, "");
        roles.setRole(SOMEONE, newRoleId, true);
        vm.stopPrank();

        vm.prank(SOMEONE);
        vm.expectRevert(abi.encodeWithSelector(Roles.UnauthorizedNoRole.selector, ROLE_MANAGER_ROLE_ID));
        roles.setRoleName(newRoleId, "Some name");
    }

    function testCannotChangeRoleAdminToNoAdmin() public {
        vm.startPrank(address(safe));
        uint8 newRoleId = roles.createRole(ONLY_ROOT_ROLE_AS_ADMIN, "");
        vm.expectRevert(abi.encodeWithSelector(Roles.InvalidRoleAdmins.selector));
        roles.setRoleAdmins(newRoleId, NO_ROLE_ADMINS);
        vm.stopPrank();
    }

    function testAdminCanChangeAdminForAdminRole() public {
        bytes32 newRoleAdmin = ONLY_ROOT_ROLE_AS_ADMIN | bytes32(1 << uint256(ROLE_MANAGER_ROLE_ID));
        vm.prank(address(safe));
        roles.setRoleAdmins(ROOT_ROLE_ID, newRoleAdmin);
        assertEq(roles.getRoleAdmins(ROOT_ROLE_ID), newRoleAdmin);
    }

    function testNonAdminCantChangeAdminForAdminRole() public {
        vm.prank(address(safe));
        roles.setRole(SOMEONE, ROLE_MANAGER_ROLE_ID, true);

        // As SOMEONE is granted ROLE_MANAGER_ROLE_ID, it can change the admin for all roles, including ROLE_MANAGER_ROLE_ID
        vm.startPrank(SOMEONE);
        bytes32 newRoleAdmin = ONLY_ROOT_ROLE_AS_ADMIN | bytes32(1 << uint256(ROLE_MANAGER_ROLE_ID));
        roles.setRoleAdmins(ROLE_MANAGER_ROLE_ID, newRoleAdmin);
        assertEq(roles.getRoleAdmins(ROLE_MANAGER_ROLE_ID), newRoleAdmin);

        // However, when attempting to change the admin role, it will fail
        vm.expectRevert(abi.encodeWithSelector(Roles.UnauthorizedNotAdmin.selector, ROOT_ROLE_ID));
        roles.setRoleAdmins(ROOT_ROLE_ID, newRoleAdmin);
    }

    function testRoleAdminHasRole() public {
        vm.startPrank(address(safe));
        uint8 roleOneId = roles.createRole(ONLY_ROOT_ROLE_AS_ADMIN, "");
        uint8 roleTwoId = roles.createRole(ONLY_ROOT_ROLE_AS_ADMIN | bytes32(1 << uint256(roleOneId)), "");

        assertFalse(roles.hasRole(SOMEONE, roleTwoId));
        roles.setRole(SOMEONE, roleOneId, true);
        assertTrue(roles.hasRole(SOMEONE, roleTwoId));
        vm.stopPrank();
    }

    function testCannotSetAdminRolesOnUnexistentRole() public {
        uint8 unexistentRoleId = 100;
        vm.startPrank(address(safe));
        vm.expectRevert(abi.encodeWithSelector(Roles.UnexistentRole.selector, unexistentRoleId));
        roles.setRoleAdmins(unexistentRoleId, ONLY_ROOT_ROLE_AS_ADMIN);
    }

    function testCannotSetRoleNameOnUnexistentRole() public {
        uint8 unexistentRoleId = 100;
        vm.startPrank(address(safe));
        vm.expectRevert(abi.encodeWithSelector(Roles.UnexistentRole.selector, unexistentRoleId));
        roles.setRoleName(unexistentRoleId, "new name");
    }

    function testSafeOwnerHasRole() public {
        assertTrue(roles.hasRole(SAFE_OWNER, SAFE_OWNER_ROLE_ID));
        assertFalse(roles.hasRole(SOMEONE, SAFE_OWNER_ROLE_ID));
        // safe is not a safe owner but has root role
        assertTrue(roles.hasRole(address(safe), SAFE_OWNER_ROLE_ID));
    }

    function testSafeOwnerRoleCannotBeGrantedNorRevoked() public {
        vm.startPrank(address(safe));

        vm.expectRevert(abi.encodeWithSelector(Roles.UnauthorizedNotAdmin.selector, SAFE_OWNER_ROLE_ID));
        roles.setRole(SOMEONE, SAFE_OWNER_ROLE_ID, true);

        vm.expectRevert(abi.encodeWithSelector(Roles.UnauthorizedNotAdmin.selector, SAFE_OWNER_ROLE_ID));
        roles.setRole(SAFE_OWNER, SAFE_OWNER_ROLE_ID, false);

        uint8[] memory roleArray = new uint8[](1);
        roleArray[0] = SAFE_OWNER_ROLE_ID;

        vm.expectRevert(abi.encodeWithSelector(Roles.UnauthorizedNotAdmin.selector, SAFE_OWNER_ROLE_ID));
        roles.setRoles(SOMEONE, roleArray, new uint8[](0));

        vm.expectRevert(abi.encodeWithSelector(Roles.UnauthorizedNotAdmin.selector, SAFE_OWNER_ROLE_ID));
        roles.setRoles(SAFE_OWNER, new uint8[](0), roleArray);

        vm.stopPrank();
    }

    function testCannotSetAdminRolesOnSafeOwnerRole() public {
        vm.prank(address(safe));
        vm.expectRevert(abi.encodeWithSelector(Roles.UnauthorizedNotAdmin.selector, SAFE_OWNER_ROLE_ID));
        roles.setRoleAdmins(SAFE_OWNER_ROLE_ID, ONLY_ROOT_ROLE_AS_ADMIN);
    }

    function testSafeOwnerRoleCanBeRoleAdmin() public {
        vm.prank(address(safe));
        uint8 newRole = roles.createRole(bytes32(uint256(1 << SAFE_OWNER_ROLE_ID)), "");
        vm.prank(SAFE_OWNER);
        roles.setRole(SOMEONE, newRole, true);
        assertTrue(roles.hasRole(SOMEONE, newRole));

        // Remove as safe owner and try granting the role to someone else
        safe.setOwner(SAFE_OWNER, false);
        vm.prank(SAFE_OWNER);
        vm.expectRevert(abi.encodeWithSelector(Roles.UnauthorizedNotAdmin.selector, newRole));
        roles.setRole(SOMEONE_ELSE, newRole, true);
    }

    event RoleNameChanged(uint8 indexed roleId, string name, address indexed actor);

    function testSafeOwnerRoleNameCanBeChanged() public {
        vm.prank(address(safe));
        vm.expectEmit(true, true, true, false);
        emit RoleNameChanged(SAFE_OWNER_ROLE_ID, "new name", address(safe));
        roles.setRoleName(SAFE_OWNER_ROLE_ID, "new name");
    }
}

contract RolesRootRoleTest is FirmTest {
    SafeStub safe;
    Roles roles;

    address ROOT = account("Root");
    address ROLE_MANAGER = account("Role Manager");
    address SOMEONE = account("Someone");
    uint8 someRoleId;

    function setUp() public {
        safe = new SafeStub();

        roles = Roles(createProxy(new Roles(), abi.encodeCall(Roles.initialize, (ISafe(payable(safe)), address(0)))));
        vm.startPrank(address(safe));
        someRoleId = roles.createRole(ONLY_ROOT_ROLE_AS_ADMIN, "");
        // Separate the roles
        roles.setRole(ROOT, ROOT_ROLE_ID, true);
        roles.setRole(ROLE_MANAGER, ROLE_MANAGER_ROLE_ID, true);
        roles.setRole(SOMEONE, someRoleId, true);
        vm.stopPrank();
    }

    function testRootHasAllRoles() public {
        assertTrue(roles.hasRole(ROOT, ROOT_ROLE_ID));
        assertTrue(roles.hasRole(ROOT, ROLE_MANAGER_ROLE_ID));
        assertTrue(roles.hasRole(ROOT, someRoleId));
    }

    function testRootCanRemoveSafeAsRoot() public {
        vm.prank(ROOT);
        roles.setRole(address(safe), ROOT_ROLE_ID, false);

        assertFalse(roles.hasRole(address(safe), ROOT_ROLE_ID));
        assertFalse(roles.hasRole(address(safe), ROLE_MANAGER_ROLE_ID));
        assertFalse(roles.hasRole(address(safe), someRoleId));
    }

    function testRootCanSetNoAdminsFromRootRole() public {
        // As admin, root can grant the root role
        vm.prank(ROOT);
        roles.setRole(SOMEONE, ROOT_ROLE_ID, true);
        assertTrue(roles.hasRole(SOMEONE, ROOT_ROLE_ID));

        // As root holder, root can set the admins of the root role (which allows setting it to no admins)
        vm.prank(ROOT);
        roles.setRoleAdmins(ROOT_ROLE_ID, bytes32(0));

        // Root can no longer revoke the root role and it is fixed
        vm.prank(ROOT);
        vm.expectRevert(abi.encodeWithSelector(Roles.UnauthorizedNotAdmin.selector, ROOT_ROLE_ID));
        roles.setRole(SOMEONE, ROOT_ROLE_ID, false);
    }

    function testRoleManagerCannotChangeRootRoleAdmins() public {
        vm.prank(ROLE_MANAGER);
        vm.expectRevert(abi.encodeWithSelector(Roles.UnauthorizedNotAdmin.selector, ROOT_ROLE_ID));
        roles.setRoleAdmins(ROOT_ROLE_ID, bytes32(0));
    }

    function testCannotSetNoAdminsForRootManagerRole() public {
        vm.prank(ROOT);
        vm.expectRevert(abi.encodeWithSelector(Roles.InvalidRoleAdmins.selector));
        roles.setRoleAdmins(ROLE_MANAGER_ROLE_ID, bytes32(0));
    }

    function testSomeRoleCanAdminRootRole() public {
        vm.prank(ROOT);
        roles.setRoleAdmins(ROOT_ROLE_ID, bytes32(uint256(1 << someRoleId)));
        assertTrue(roles.hasRole(SOMEONE, someRoleId)); // transitively gets the root role as admin

        vm.prank(SOMEONE);
        roles.setRole(SOMEONE, ROOT_ROLE_ID, true);
        assertTrue(roles.hasRole(SOMEONE, ROOT_ROLE_ID));
    }
}
