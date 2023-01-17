// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {FirmBase, IModuleMetadata} from "../../../bases/FirmBase.sol";
import {ISafe} from "../../../bases/interfaces/ISafe.sol";

abstract contract TargetBase is FirmBase {
    string public constant moduleId = "org.firm.test-target";

    uint256 public someNumber;

    error SomeError();

    function init(ISafe safe) public {
        __init_firmBase(safe, address(0));
    }

    function setNumber(uint256 number) public virtual;
    function getNumber() public view virtual returns (uint256);
}

contract TargetV1 is TargetBase {
    uint256 public constant moduleVersion = 1;

    function setNumber(uint256 number) public override {
        someNumber = number;
    }

    function getNumber() public view override returns (uint256) {
        return someNumber;
    }
}

contract TargetV2 is TargetBase {
    uint256 public constant moduleVersion = 2;

    function setNumber(uint256) public pure override {
        revert SomeError();
    }

    function getNumber() public view override returns (uint256) {
        return someNumber * 2;
    }
}
