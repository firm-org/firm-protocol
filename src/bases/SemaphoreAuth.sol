// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {SafeAware} from "./SafeAware.sol";

import {ISemaphore} from "../semaphore/interfaces/ISemaphore.sol";

ISemaphore constant NO_SEMAPHORE = ISemaphore(address(0));
abstract contract SemaphoreAuth is SafeAware {
    // SEMAPHORE_SLOT = keccak256("firm.semaphoreauth.semaphore") - 1
    bytes32 internal constant SEMAPHORE_SLOT = 0x3e4ab72c2ecd29625ea852b1de3f6381681f0f5fb2b0bab359fabdd96dbc1b94;

    event SemaphoreSet(ISemaphore semaphore);

    function semaphore() public view returns (ISemaphore semaphoreAddr) {
        assembly {
            semaphoreAddr := sload(SEMAPHORE_SLOT)
        }
    }

    function setSemaphore(ISemaphore semaphore_) public onlySafe {
        _setSemaphore(semaphore_);
    }

    function _setSemaphore(ISemaphore semaphore_) internal {
        assembly {
            sstore(SEMAPHORE_SLOT, semaphore_)
        }
        emit SemaphoreSet(semaphore_);
    }

    function _semaphoreCheckCall(address target, uint256 value, bytes memory data, bool isDelegateCall) internal view {
        ISemaphore semaphore_ = semaphore();
        if (semaphore_ != NO_SEMAPHORE &&
            !semaphore_.canPerform(address(this), target, value, data, isDelegateCall)
        ) {
            revert ISemaphore.SemaphoreDisallowed();
        }
    }

    function _semaphoreCheckCalls(address[] memory targets, uint256[] memory values, bytes[] memory datas, bool isDelegateCall) internal view {
        ISemaphore semaphore_ = semaphore();
        if (semaphore_ != NO_SEMAPHORE &&
            !semaphore_.canPerformMany(address(this), targets, values, datas, isDelegateCall)
        ) {
            revert ISemaphore.SemaphoreDisallowed();
        }
    }
}
