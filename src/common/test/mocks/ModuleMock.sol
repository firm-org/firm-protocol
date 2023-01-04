// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {FirmBase} from "src/bases/FirmBase.sol";
import {ISafe, SafeModule} from "src/bases/SafeModule.sol";

contract ModuleMock is FirmBase, SafeModule {
    string public constant moduleId = "org.firm.modulemock";
    uint256 public constant moduleVersion = 0;

    uint256 public immutable foo;
    uint256 public bar;

    constructor(uint256 _foo) {
        foo = _foo;
    }

    function initialize(ISafe _safe, uint256 _bar) public {
        __init_firmBase(_safe, address(0));
        bar = _bar;
    }

    function setBar(uint256 _bar) public onlySafe {
        bar = _bar;
    }

    function execCall(address to, uint256 value, bytes memory data) public returns (bool success) {
        return _exec(to, value, data, ISafe.Operation.Call);
    }
}
