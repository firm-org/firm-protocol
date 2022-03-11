// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "zodiac/interfaces/IAvatar.sol";

contract AvatarStub is IAvatar {
    event AvatarExecuted(address to, uint256 value, bytes data);

    function enableModule(address module) external {}
    function disableModule(address prevModule, address module) external {}

    function execTransactionFromModule(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation
    ) external returns (bool success) {
        (success,) = execTransactionFromModuleReturnData(to, value, data, operation);
    }

    function execTransactionFromModuleReturnData(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation
    ) public returns (bool success, bytes memory returnData) {
        emit AvatarExecuted(to, value, data);

        return (operation == Enum.Operation.Call, abi.encode(true));
    }

    function isModuleEnabled(address) external pure returns (bool) { return true; }

    function getModulesPaginated(address start, uint256 pageSize)
        external
        pure
        returns (address[] memory array, address next) {}
}