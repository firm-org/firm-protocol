// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.17;

interface IBouncer {
    function isTransferAllowed(address from, address to, uint256 classId, uint256 amount)
        external
        view
        returns (bool);
}
