// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {ZodiacModule, IAvatar, SafeEnums} from "../../bases/ZodiacModule.sol";

contract BackdoorModule is ZodiacModule {
    string public constant moduleId = "org.firm.backdoor";
    uint256 public constant moduleVersion = 0;

    address public immutable module;

    constructor(IAvatar safe_, address module_) {
        __init_setSafe(safe_);
        module = module_;
    }

    fallback() external {
        (bool ok, bytes memory data) = execAndReturnData(module, 0, msg.data, SafeEnums.Operation.Call);

        if (!ok) {
            assembly {
                revert(add(data, 0x20), mload(data))
            }
        }
    }
}
