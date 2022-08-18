// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import "../../../roles/Roles.sol";

contract RolesStub is IRoles {
    mapping(address => mapping(uint8 => bool)) public hasRole;

    function setRole(address user, uint8 role, bool grant) public {
        hasRole[user][role] = grant;
    }
}
