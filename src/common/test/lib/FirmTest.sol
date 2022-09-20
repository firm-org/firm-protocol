// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "forge-std/Test.sol";

contract FirmTest is Test {
    function account(string memory label) internal returns (address addr) {
        (addr,) = accountAndKey(label);
    }

    function accountAndKey(string memory label) internal returns (address addr, uint256 pk) {
        pk = uint256(keccak256(abi.encodePacked(label)));
        addr = vm.addr(pk);
        vm.label(addr, label);
    }
}
