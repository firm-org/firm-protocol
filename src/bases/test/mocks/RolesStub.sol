// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "../../../roles/Roles.sol";

contract RolesStub is IRoles {
    mapping(address => mapping(uint8 => bool)) public hasRole;

    function setRole(address user, uint8 roleId, bool grant) public {
        hasRole[user][roleId] = grant;
    }

    function roleExists(uint8 roleId) external pure returns (bool) {
        return roleId < 100;
    }
}
