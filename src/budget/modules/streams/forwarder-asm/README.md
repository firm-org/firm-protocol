# OwnedForwarder assembly implementation

## Usage

### Install `etk`

We use [EVM Toolkit (etk)](https://github.com/quilt/etk) for compiling the EVM assembly code into EVM bytecode.

To install (requires `rustc` version `1.51`):
```
cargo install --features cli etk-asm etk-dasm
```

### Build

```
eas src/initcode.etk forwarder.bin
```

Note: `ffffffffffffffffffffffffffffffffffffffff` needs to be replaced by the address of the owner allowed to use the forwarder

## Reference

```sol
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
```