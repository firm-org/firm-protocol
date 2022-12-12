// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import {IERC165} from "openzeppelin/interfaces/IERC165.sol";

import {FirmBase} from "./FirmBase.sol";
import {ISafe} from "./ISafe.sol";

/**
 * @title SafeModule
 * @dev More minimal implementation of Safe's Module.sol without an owner
 * and using unstructured storage
 * @dev Note that this contract doesn't have an initializer and SafeState
 * must be set explicly if desired, but defaults to being unset
 */
abstract contract SafeModule is FirmBase {
    /**
     * @dev Executes a transaction through the target intended to be executed by the avatar
     * @param to Address being called
     * @param value Ether value being sent
     * @param data Calldata
     * @param operation Operation type of transaction: 0 = call, 1 = delegatecall
     */
    function exec(address to, uint256 value, bytes memory data, ISafe.Operation operation)
        internal
        returns (bool success) {
        return safe().execTransactionFromModule(to, value, data, operation);
    }

    /**
     * @dev Executes a transaction through the target intended to be executed by the avatar
     * and returns the call status and the return data of the call
     * @param to Address being called
     * @param value Ether value being sent
     * @param data Calldata
     * @param operation Operation type of transaction: 0 = call, 1 = delegatecall
     */
    function execAndReturnData(address to, uint256 value, bytes memory data, ISafe.Operation operation)
        internal
        returns (bool success, bytes memory returnData)
    {
        return safe().execTransactionFromModuleReturnData(to, value, data, operation);
    }
}
