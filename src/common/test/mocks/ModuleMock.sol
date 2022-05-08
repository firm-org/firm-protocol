// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import {FirmModule, IAvatar, Enum} from "../../FirmModule.sol";

contract ModuleMock is FirmModule {
    uint256 immutable public foo;
    uint256 public bar;

    constructor(uint256 _foo) {
        foo = _foo;
    }

    function setUp(IAvatar _avatar, IAvatar _target, uint256 _bar) public {
        initialize(_avatar, _target);
        bar = _bar;
    }

    function setBar(uint256 _bar) public onlyAvatar {
        bar = _bar;
    }

    function execCall(
        address to,
        uint256 value,
        bytes memory data
    ) public returns (bool success) {
        return exec(to, value, data, Enum.Operation.Call);
    }
}