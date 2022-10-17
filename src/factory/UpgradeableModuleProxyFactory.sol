// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {Ownable} from "openzeppelin/access/Ownable.sol";
import {FirmBase} from "../bases/FirmBase.sol";

uint256 constant LATEST_VERSION = type(uint256).max;

contract UpgradeableModuleProxyFactory is Ownable {
    error TakenAddress(address proxy);
    error FailedInitialization();
    error ModuleVersionAlreadyRegistered();
    error UnexistentModule();

    event ModuleRegistered(FirmBase indexed implementation, string moduleId, uint256 version);
    event ModuleProxyCreation(address indexed proxy, FirmBase indexed implementation);

    mapping(string => mapping(uint256 => FirmBase)) public modules;
    mapping(string => uint256) public latestModuleVersion;

    function register(FirmBase implementation) external onlyOwner {
        string memory moduleId = implementation.moduleId();
        uint256 version = implementation.moduleVersion();

        if (address(modules[moduleId][version]) != address(0)) {
            revert ModuleVersionAlreadyRegistered();
        }

        modules[moduleId][version] = implementation;

        if (version > latestModuleVersion[moduleId]) {
            latestModuleVersion[moduleId] = version;
        }

        emit ModuleRegistered(implementation, moduleId, version);
    }

    function deployUpgradeableModule(string memory moduleId, uint256 version, bytes memory initializer, uint256 salt)
        public
        returns (address proxy)
    {
        if (version == LATEST_VERSION) {
            version = latestModuleVersion[moduleId];
        }
        FirmBase implementation = modules[moduleId][version];
        if (address(implementation) == address(0)) {
            revert UnexistentModule();
        }

        return deployUpgradeableModule(implementation, initializer, salt);
    }

    function deployUpgradeableModule(FirmBase implementation, bytes memory initializer, uint256 salt)
        public
        returns (address proxy)
    {
        proxy = createProxy(implementation, keccak256(abi.encodePacked(keccak256(initializer), salt)));

        (bool success,) = proxy.call(initializer);
        if (!success) {
            revert FailedInitialization();
        }

        emit ModuleProxyCreation(proxy, implementation);
    }

    function createProxy(FirmBase implementation, bytes32 salt) internal returns (address addr) {
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
}
