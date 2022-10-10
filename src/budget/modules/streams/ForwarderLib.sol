// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

// TODO: implement in assembly using etk
contract OwnedForwarder {
    address internal immutable owner;

    constructor(address owner_) {
        owner = owner_;
    }

    fallback() external payable {
        require(msg.sender == owner);
        require(msg.data.length >= 20);

        uint256 toSeparator = msg.data.length - 20;
        address to = address(bytes20(msg.data[toSeparator:]));
        bytes memory data = msg.data[:toSeparator];
        (bool ok, bytes memory ret) = to.call{value: msg.value}(data);

        if (ok) {
            assembly {
                return(add(ret, 0x20), mload(ret))
            }
        } else {
            assembly {
                revert(add(ret, 0x20), mload(ret))
            }
        }
    }
}

library ForwarderLib {
    type Forwarder is address;
    using ForwarderLib for Forwarder;

    function create(bytes32 salt) internal returns (Forwarder) {
        return Forwarder.wrap(address(new OwnedForwarder{salt: salt}(address(this))));
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

    function addr(Forwarder forwarder) internal view returns (address) {
        return Forwarder.unwrap(forwarder);
    }
}
