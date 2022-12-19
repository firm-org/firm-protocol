# Firm Protocol

## Development

### Install [Foundry](https://github.com/gakonst/foundry#installation)

```
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

### Build and test
```
forge install
forge build
forge test
```

### Local environment

Start Anvil:
```
anvil
```

Run the deployment script for the contracts; the sender address will be `0xF1F182B70255AC4846E28fd56038F9019c8d36b0`:
```
scripts/deploy-local.sh
```

The FirmFactory address will be the last deployed contract, you can verify that it
was completely deployed by performing a call to it:
```
cast call [FirmFactory address] "safeImpl()(address)"
```
