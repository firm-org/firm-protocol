// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

interface IModuleMetadata {
    function moduleId() external pure returns (bytes32);
    function moduleVersion() external pure returns (uint256);
}
