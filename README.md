# Firm Core

## Development

### Install [Foundry](https://github.com/gakonst/foundry#installation)
```
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

### Build and test
```
forge build
forge test
```

### Local environment

Start Ganache (`0xF1F182B70255AC4846E28fd56038F9019c8d36b0` funded with 1000 ETH):
```
ganache -l 100000000 --chain.allowUnlimitedContractSize --wallet.accounts 0x56be6b8d0f4319371c440be28e1e209ec2615a00b67c25dd5c40fb12b6d55c4b,1000000000000000000000
```

Create deploy contract (deploys all dependencies on constructor):
```
forge create --rpc-url http://localhost:8545 --private-key 0x56be6b8d0f4319371c440be28e1e209ec2615a00b67c25dd5c40fb12b6d55c4b --legacy LocalDeploy
```

Fetch FirmFactory address:
```
cast call [LocalDeploy addr] "firmFactory()(address)"
```