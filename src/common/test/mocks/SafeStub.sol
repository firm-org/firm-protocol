// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {ISafe} from "src/bases/ISafe.sol";

contract SafeStub is ISafe {
    function execTransactionFromModule(address to, uint256 value, bytes memory data, ISafe.Operation operation)
        external
        returns (bool success)
    {
        (success,) = execTransactionFromModuleReturnData(to, value, data, operation);
    }

    function execTransactionFromModuleReturnData(address to, uint256 value, bytes memory data, ISafe.Operation operation)
        public
        returns (bool success, bytes memory returnData)
    {
        return operation == ISafe.Operation.Call ? to.call{value: value}(data) : to.delegatecall(data);
    }

    // Functions to comply with interface

    function isOwner(address) external pure returns (bool) {
        return true;
    }

    receive() external payable {}
}
