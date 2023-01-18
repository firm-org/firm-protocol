# Firm Protocol

## Development

### Install [Foundry](https://github.com/foundry-rs/foundry#installation)

```
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

### Build and test
```
git clone https://github.com/firm-org/firm-protocol.git
forge install
forge build
forge test
forge coverage --report lcov
```

### Local environment

Start Anvil:
```
anvil
```

Run the deployment script for the contracts; the sender address will be `0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266` which is anvil's default:
```
scripts/deploy-local
```

The forge script will return the addresses of both FirmFactory and the modules factory.
This will be at the beginning of script's output (before the transaction broadcasting)

The FirmFactory is the last deployed contract, you can verify that it
was correctly deployed by performing a call to it:
```
cast call [FirmFactory address] "moduleFactory()(address)"
```

## Live deployments

Make sure the git repo is not dirty and force a clean build:
```
forge build --force
```

Use `FirmFactoryDeploy` script to deploy to a live network (add flags to `forge script` for your deployment account to be used):
```
forge script scripts/FirmFactoryDeploy.s.sol:FirmFactoryDeployLive --broadcast --fork-url [JSON-RPC for network to deploy to]
```