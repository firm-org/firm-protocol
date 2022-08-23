# Firm Core

## Development

### Install [Foundry](https://github.com/gakonst/foundry#installation)
```
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

### Install dependencies using `pnpm`
```
pnpm install
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

Run the deployment script:
```
source src/deploy-local.sh
```

The FirmFactory address will be the last deployed contract, you can verify that it
was completely deployed by performing a call to it:
```
cast call [FirmFactory address] "safeImpl()(address)"
```
