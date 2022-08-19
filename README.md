# Firm Core

## Development

### Install [Foundry](https://github.com/gakonst/foundry#installation)
```
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

### Install dependencies in `npm`
```
yarn install
```

### Build and test
```
forge build
forge test
```

### Local environment

Start Anvil:
```
anvil
```

Fund the deployment address (`0xF1F182B70255AC4846E28fd56038F9019c8d36b0` with 1000 ETH):
```
curl -XPOST -H "Content-type: application/json" -d '{"jsonrpc": "2.0", "id": 1, "method": "anvil_setBalance", "params": ["0xF1F182B70255AC4846E28fd56038F9019c8d36b0", "1000000000000000000000"]}' 'http://localhost:8545'
```

Run the deployment script:
```
 forge script ./scripts/deploy.sol:FirmDeploy --fork-url http://localhost:8545 --broadcast --private-key 0x56be6b8d0f4319371c440be28e1e209ec2615a00b67c25dd5c40fb12b6d55c4b
```

The FirmFactory address will be the last deployed contract, you can verify that it
was completely deployed by performing a call to it:
```
cast call [FirmFactory address] "safeImpl()(address)"
```