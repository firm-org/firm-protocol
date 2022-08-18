// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

uint8 constant ROOT_ROLE_ID = 0;
uint8 constant ROLE_MANAGER_ROLE = 1;
bytes32 constant ONLY_ROOT_ROLE = bytes32(uint256(1));

interface IRoles {
    function hasRole(address _user, uint8 _roleId) external view returns (bool);
}
