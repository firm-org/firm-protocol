// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {UpgradeableModule} from "../../../bases/UpgradeableModule.sol";
import {ZodiacModule, IAvatar, SafeEnums} from "../../../bases/ZodiacModule.sol";

contract ModuleMock is UpgradeableModule, ZodiacModule {
    uint256 public immutable foo;
    uint256 public bar;

    constructor(uint256 _foo) {
        foo = _foo;
    }

    function initialize(IAvatar _safe, uint256 _bar) public {
        __init_setSafe(_safe);
        bar = _bar;
    }

    function setBar(uint256 _bar) public onlySafe {
        bar = _bar;
    }

    function execCall(address to, uint256 value, bytes memory data) public returns (bool success) {
        return exec(to, value, data, SafeEnums.Operation.Call);
    }

    function moduleId() public pure override returns (bytes32) {
        return keccak256("org.firm.modulemock");
    }

    function moduleVersion() public pure override returns (uint256) {
        return 0;
    }
}
