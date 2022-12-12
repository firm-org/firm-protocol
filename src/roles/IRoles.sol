// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

uint8 constant ROOT_ROLE_ID = 0;
uint8 constant ROLE_MANAGER_ROLE = 1;
bytes32 constant ONLY_ROOT_ROLE = bytes32(uint256(1));
// The last possible role is an unassingable role which is dynamic
// and having it or not depends on whether the user is an owner in the Safe
uint8 constant SAFE_OWNER_ROLE_ID = 255;

interface IRoles {
    function roleExists(uint8 roleId) external view returns (bool);
    function hasRole(address user, uint8 roleId) external view returns (bool);
}
