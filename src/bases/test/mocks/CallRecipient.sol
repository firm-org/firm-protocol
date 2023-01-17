// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

contract CallRecipient {
    event ReceiveCall(address indexed from, uint256 value, bytes data);

    fallback() external payable {
        emit ReceiveCall(msg.sender, msg.value, msg.data);
    }
}
