// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

interface IModuleMetadata {
    function moduleId() external pure returns (string memory);
    function moduleVersion() external pure returns (uint256);
}
