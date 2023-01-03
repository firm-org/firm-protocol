// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "forge-std/Test.sol";

import "../../../factory/UpgradeableModuleProxyFactory.sol";
import {FirmBase} from "../../../bases/FirmBase.sol";

contract FirmTest is Test {
    UpgradeableModuleProxyFactory immutable proxyFactory = new UpgradeableModuleProxyFactory();

    function account(string memory label) internal returns (address addr) {
        (addr,) = accountAndKey(label);
    }

    function accountAndKey(string memory label) internal returns (address addr, uint256 pk) {
        pk = uint256(keccak256(abi.encodePacked(label)));
        addr = vm.addr(pk);
        vm.label(addr, label);
    }

    function createProxy(FirmBase impl, bytes memory initdata) internal returns (address proxy) {
        proxy = proxyFactory.deployUpgradeableModule(impl, initdata, 0);
        vm.label(proxy, "Proxy");

        assertUnsStrg(address(impl), "eip1967.proxy.implementation", address(0xffff));
        assertUnsStrg(address(proxy), "eip1967.proxy.implementation", address(impl));
    }

    function assertUnsStrg(address addr, string memory key, bytes32 expectedValue) internal {
        assertEq(vm.load(addr, bytes32(uint256(keccak256(abi.encodePacked(key))) - 1)), expectedValue);
    }

    function assertUnsStrg(address addr, string memory key, address expectedAddr) internal {
        assertUnsStrg(addr, key, bytes32(uint256(uint160(expectedAddr))));
    }

    function timetravel(uint256 time) internal {
        vm.warp(block.timestamp + time);
    }

    function blocktravel(uint256 blocks) internal {
        vm.roll(block.number + blocks);
    }
}
