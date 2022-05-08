# Minimal EIP-1967 Upgradeable Proxy

[ERC-1967](https://eips.ethereum.org/EIPS/eip-1967) standardizes the storage slot where the implementation contract address is stored for an upgradeable proxy.

This is an implementation of a proxy written in EVM assembly which looks for its target contract in that standard slot. The proxy only performs a `delagatecall` to the address in such slot and forwards the return/revert data back to the caller.

The runtime code of the proxy is currentl 59 bytes.

Given that it doesn't have any other logic at the proxy level, the actual upgradeability feature is a responsibility of the target contract. If the proxy is every upgraded to a contract that doesn't implement a way to upgrade the proxy, the proxy won't be upgradeable.

## Usage

### Install `etk`

We use [EVM Toolkit (etk)](https://github.com/quilt/etk) for compiling the EVM assembly code into EVM bytecode.

To install (requires `rustc` version `1.51`):
```
cargo install --features cli etk-asm etk-dasm
```

### Build

```
eas src/initcode.etk proxy.bin
```

Note: `ffffffffffffffffffffffffffffffffffffffff` needs to be replaced by the initial implementation address that the proxy will use. See [UpgradeableModuleProxyFactory](../UpgradeableModuleProxyFactory.sol) to see how to deploy the proxies from Solidity.

### Warning

If the runtime code length of the proxy changes (`runtime.etk`), a change is necessary in `initcode.etk` since the length of the runtime code is hardcoded as an optimization.

The length is currently 59 bytes.