// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import {ISemaphore} from "src/semaphore/interfaces/ISemaphore.sol";

contract SemaphoreStub is ISemaphore {
    mapping (address => bool) public disallowedTargets;
    mapping (address => bool) public disallowedCallers;

    function setDisallowed(address addr, bool targetOrCaller) external {
        if (targetOrCaller) {
            disallowedTargets[addr] = true;
        } else {
            disallowedCallers[addr] = true;
        }
    }

    function canPerform(address caller, address target, uint256, bytes calldata, bool) public view returns (bool) {
        if (disallowedTargets[target]) {
            return false;
        }
        if (disallowedCallers[caller]) {
            return false;
        }
        return true;
    }

    function canPerformMany(address caller, address[] calldata targets, uint256[] calldata values, bytes[] calldata calldatas, bool isDelegateCall) external view returns (bool) {
        for (uint256 i = 0; i < targets.length; i++) {
            if (!canPerform(caller, targets[i], values[i], calldatas[i], isDelegateCall)) {
                return false;
            }
        }
        return true;
    }
}