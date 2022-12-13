// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import {IRoles} from "../roles/IRoles.sol";

uint256 constant ROLE_FLAG_MASK = ~uint160(0xFF00);

abstract contract RolesAuth {
    // ROLES_SLOT = keccak256("firm.rolesauth.roles") - 1
    bytes32 constant internal ROLES_SLOT = 0x7aaf26e54f46558e57a4624b01631a5da30fe5fe9ba2f2500c3aee185f8fb90b;

    function roles() public view returns (IRoles rolesAddr) {
        assembly {
            rolesAddr := sload(ROLES_SLOT)
        }
    }

    function _setRoles(IRoles roles_) internal {
        assembly {
            sstore(ROLES_SLOT, roles_)
        }
    }

    error UnexistentRole(uint8 roleId);

    function _validateAuthorizedAddress(address authorizedAddr) internal view {
        if (_isRoleFlag(authorizedAddr)) {
            uint8 roleId = _roleFromFlag(authorizedAddr);
            if (!roles().roleExists(roleId)) {
                revert UnexistentRole(roleId);
            }
        }
    }

    function _isAuthorized(address actor, address authorizedAddr) internal view returns (bool) {
        if (_isRoleFlag(authorizedAddr)) {
            return roles().hasRole(actor, _roleFromFlag(authorizedAddr));
        } else {
            return actor == authorizedAddr;
        }
    }

    function _isRoleFlag(address addr) internal pure returns (bool) {
        // An address 0x00...00[roleId byte]01 is interpreted as a flag for roleId
        // Eg. 0x0000000000000000000000000000000000000201 for roleId=2
        // Therefore if any other byte other than the roleId byte or the 0x01 byte
        // is set, it will be considered not to be a valid role flag
        return uint160(addr) & ROLE_FLAG_MASK == 0x01;
    }

    function _roleFromFlag(address roleFlag) internal pure returns (uint8) {
        return uint8(uint160(roleFlag) >> 8);
    }
}
