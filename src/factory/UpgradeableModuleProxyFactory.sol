// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {EIP1967Upgradeable} from "../bases/EIP1967Upgradeable.sol";

contract UpgradeableModuleProxyFactory {
    error TakenAddress(address proxy);
    error FailedInitialization();

    event ModuleProxyCreation(address indexed proxy, EIP1967Upgradeable indexed implementation);

    function createUpgradeableProxy(EIP1967Upgradeable implementation, bytes32 salt) internal returns (address addr) {
        // if (address(target) == address(0)) revert ZeroAddress(target);
        // Removed as this is a responsibility of the caller and we shouldn't pay for the check on each proxy creation
        bytes memory initcode = abi.encodePacked(
            hex"73",
            implementation,
            hex"7f360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc55603b8060403d393df3363d3d3760393d3d3d3d3d363d7f360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc545af4913d913e3d9257fd5bf3"
        );

        assembly {
            addr := create2(0, add(initcode, 0x20), mload(initcode), salt)
        }

        if (addr == address(0)) {
            revert TakenAddress(addr);
        }
    }

    function deployUpgradeableModule(EIP1967Upgradeable implementation, bytes memory initializer, uint256 salt)
        public
        returns (address proxy)
    {
        proxy = createUpgradeableProxy(implementation, keccak256(abi.encodePacked(keccak256(initializer), salt)));

        (bool success,) = proxy.call(initializer);
        if (!success) {
            revert FailedInitialization();
        }

        emit ModuleProxyCreation(proxy, implementation);
    }
}
