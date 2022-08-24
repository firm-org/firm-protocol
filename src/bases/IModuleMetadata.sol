// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

interface IModuleMetadata {
    function moduleId() external pure returns (string memory);
    function moduleVersion() external pure returns (uint256);
}
