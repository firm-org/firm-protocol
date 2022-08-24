// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {ZodiacModule, IAvatar, SafeEnums} from "../../bases/ZodiacModule.sol";

contract BackdoorModule is ZodiacModule {
    string public constant moduleId = "org.firm.backdoor";
    uint256 public constant moduleVersion = 0;

    address immutable public module;
    constructor(IAvatar safe_, address module_) {
        __init_setSafe(safe_);
        module = module_;
    }

    fallback() external {
        exec(module, 0, msg.data, SafeEnums.Operation.Call);
    }
}
