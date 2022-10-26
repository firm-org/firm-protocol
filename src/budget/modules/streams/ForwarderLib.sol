// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import {Bytes32AddressLib} from "solmate/utils/Bytes32AddressLib.sol";

library ForwarderLib {
    using Bytes32AddressLib for bytes32;

    type Forwarder is address;
    using ForwarderLib for Forwarder;

    error ForwarderAlreadyDeployed();

    function getForwarder(bytes32 salt) internal view returns (Forwarder) {
        return getForwarder(salt, address(this));
    }

    function getForwarder(bytes32 salt, address deployer) internal pure returns (Forwarder) {
        return Forwarder.wrap(keccak256(abi.encodePacked(
            bytes1(0xff),
            deployer,
            salt,
            keccak256(forwarderCreationCode(deployer))
        )).fromLast20Bytes());
    }

    function forwarderCreationCode(address owner) internal pure returns (bytes memory) {
        return abi.encodePacked(
            hex"60468060093d393df373",
            owner,
            hex"330360425760403d3d3d3d3d60148036106042573603803d3d373d34823560601c5af1913d913e3d9257fd5bf35b3d3dfd"
        );
    }

    function create(bytes32 salt) internal returns (Forwarder) {
        bytes memory initcode = forwarderCreationCode(address(this));
        address fwd_;

        assembly {
            fwd_ := create2(0, add(initcode, 0x20), mload(initcode), salt)
        }

        if (fwd_ == address(0)) {
            revert ForwarderAlreadyDeployed();
        }

        return Forwarder.wrap(fwd_);
    }

    function forward(Forwarder forwarder, address to, bytes memory data) internal returns (bool ok, bytes memory ret) {
        return forwarder.forward(to, 0, data);
    }

    function forward(Forwarder forwarder, address to, uint256 value, bytes memory data)
        internal
        returns (bool ok, bytes memory ret)
    {
        return forwarder.addr().call{value: value}(abi.encodePacked(data, to));
    }

    function forwardChecked(Forwarder forwarder, address to, bytes memory data) internal returns (bytes memory ret) {
        return forwarder.forwardChecked(to, 0, data);
    }

    function forwardChecked(Forwarder forwarder, address to, uint256 value, bytes memory data)
        internal
        returns (bytes memory ret)
    {
        bool ok;
        (ok, ret) = forwarder.forward(to, value, data);
        if (!ok) {
            assembly {
                revert(add(ret, 0x20), mload(ret))
            }
        }
    }

    function addr(Forwarder forwarder) internal pure returns (address) {
        return Forwarder.unwrap(forwarder);
    }
}
