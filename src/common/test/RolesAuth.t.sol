// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "solmate/test/utils/DSTestPlus.sol";

import "./lib/RolesAuthMock.sol";
import "./lib/RolesStub.sol";

contract RolesAuthTest is DSTestPlus {
    RolesStub roles;
    RolesAuthMock rolesAuth;

    address constant SOMEONE = address(0x1234567890123456789012345678901234567890);

    function setUp() public {
        roles = new RolesStub();
        rolesAuth = new RolesAuthMock(roles);
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

        assertTrue(rolesAuth.isAuthorized(SOMEONE,  0x0000000000000000000000000000000000000201));
        assertFalse(rolesAuth.isAuthorized(SOMEONE, 0x0000000000000000000000000000000000000301));
        assertFalse(rolesAuth.isAuthorized(SOMEONE, 0x0000000000000000000000000000000000000200));
        assertFalse(rolesAuth.isAuthorized(SOMEONE, 0x0000000000000000000000000000000000000202));
        assertFalse(rolesAuth.isAuthorized(SOMEONE, 0x0000000000000000000000000000000000010201));
        assertFalse(rolesAuth.isAuthorized(SOMEONE, 0xaBababaBabABabaBAbabAbAbABabaBABABAB0201));
    }

    function roleFlag(uint8 role) internal pure returns (address) {
        return address(uint160(uint256(role) << 8) + 1);
    }
}