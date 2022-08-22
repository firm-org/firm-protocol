// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.16;

interface IBouncer {
    function isTransferAllowed(
        address from,
        address to,
        uint256 classId, // TODO: consider making token address the class id
        uint256 amount
    )
        external
        view
        returns (bool);
}
