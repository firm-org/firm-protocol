// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import "../../../factory/UpgradeableModuleProxyFactory.sol";
import {FirmBase} from "../../../bases/FirmBase.sol";

contract FirmTest is Test {
    UpgradeableModuleProxyFactory immutable proxyFactory = new UpgradeableModuleProxyFactory();

    string internal constant EIP1967_IMPL_SLOT = "eip1967.proxy.implementation";

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

        assertUnsStrg(address(impl), EIP1967_IMPL_SLOT, address(0xffff));
        assertUnsStrg(address(proxy), EIP1967_IMPL_SLOT, address(impl));
    }

    function getUnsStrg(address addr, string memory key) internal view returns (bytes32 value) {
        value = vm.load(addr, bytes32(uint256(keccak256(abi.encodePacked(key))) - 1));
    }

    function getImpl(address proxy) internal view returns (address impl) {
        impl = address(uint160(uint256(getUnsStrg(proxy, EIP1967_IMPL_SLOT))));
    }

    function assertUnsStrg(address addr, string memory key, bytes32 expectedValue) internal {
        assertEq(getUnsStrg(addr, key), expectedValue);
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
