// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import {FirmBase, ISafe} from "../../FirmBase.sol";
import {SemaphoreAuth, ISemaphore} from "../../SemaphoreAuth.sol";

contract SemaphoreAuthMock is FirmBase, SemaphoreAuth {
    string public constant moduleId = "test.firm.semaphore-auth-mock";
    uint256 public constant moduleVersion = 1;

    function initialize(ISafe safe_, ISemaphore semaphore_) public {
        __init_firmBase(safe_, address(0));
        _setSemaphore(semaphore_);
    }

    // Make ISemaphore internal functions public for testing

    function semaphoreCheckCall(address target, uint256 value, bytes memory data, bool isDelegateCall) public view {
        _semaphoreCheckCall(target, value, data, isDelegateCall);
    }

    function semaphoreCheckCalls(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory datas,
        bool isDelegateCall
    ) public view {
        _semaphoreCheckCalls(targets, values, datas, isDelegateCall);
    }

    function filterCallsToTarget(
        address filteredTarget,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas
    ) public pure returns (address[] memory, uint256[] memory, bytes[] memory) {
        return _filterCallsToTarget(filteredTarget, targets, values, calldatas);
    }
}
