// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import "zodiac/factory/ModuleProxyFactory.sol";

contract UpgradeableModuleProxyFactory is ModuleProxyFactory {
    function createUpgradeableProxy(address _initialTarget, bytes32 _salt)
        internal
        returns (address addr)
    {
        // if (address(target) == address(0)) revert ZeroAddress(target);
        // Removed as this is a responsibility of the caller and we shouldn't pay for the check on each proxy creation
        bytes memory initcode = abi.encodePacked(
            hex"73",
            _initialTarget,
            hex"7f360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc55603b8060403d393df3363d3d3760393d3d3d3d3d363d7f360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc545af4913d913e3d9257fd5bf3"
        );

        assembly {
            addr := create2(0, add(initcode, 0x20), mload(initcode), _salt)
        }

        if (addr == address(0)) revert TakenAddress(addr);
    }

    function deployUpgradeableModule(
        address masterCopy,
        bytes memory initializer,
        uint256 saltNonce
    ) public returns (address proxy) {
        proxy = createUpgradeableProxy(
            masterCopy,
            keccak256(abi.encodePacked(keccak256(initializer), saltNonce))
        );

        (bool success, ) = proxy.call(initializer);
        if (!success) revert FailedInitialization();

        emit ModuleProxyCreation(proxy, masterCopy);
    }
}
