// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {SafeModule, ISafe} from "../../bases/SafeModule.sol";

contract BackdoorModule is SafeModule {
    string public constant moduleId = "org.firm.backdoor";
    uint256 public constant moduleVersion = 0;

    address public immutable module;

    constructor(ISafe safe_, address module_) {
        __init_setSafe(safe_);
        module = module_;
    }

    fallback() external {
        (bool ok, bytes memory data) = _moduleExecAndReturnData(module, 0, msg.data, ISafe.Operation.Call);

        if (!ok) {
            assembly {
                revert(add(data, 0x20), mload(data))
            }
        } else {
            assembly {
                return(add(data, 0x20), mload(data))
            }
        }
    }
}
