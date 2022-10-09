// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {LlamaPay, LlamaPayFactory} from "llamapay/LlamaPayFactory.sol";

import {BudgetModule} from "./BudgetModule.sol";

contract LlamaPayStreams is BudgetModule {
    string public constant moduleId = "org.firm.budget.llamapay-streams";
    uint256 public constant moduleVersion = 1;

    LlamaPayFactory internal immutable llamaPayFactory;

    constructor(LlamaPayFactory llamaPayFactory_) {
        // IMPORTANT: This immutable value is set in the constructor of the implementation contract
        // and all proxies will read from it as it gets saved in the bytecode
        llamaPayFactory = llamaPayFactory_;
    }
}