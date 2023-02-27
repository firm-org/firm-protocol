![Firm Protocol][banner-image]

<div align="center">
  <!-- Releases -->
  <a href="https://github.com/firm-org/firm-protocol/releases">
    <img src="https://img.shields.io/github/v/release/firm-org/firm-protocol?style=flat-square" alt="Version" />
  </a>
  <!-- Security -->
  <a href="audits">
    <img src="https://img.shields.io/badge/security-audited-green?style=flat-square" alt="Security" />
  </a>
  <!-- CI -->
  <a href="https://github.com/firm-org/firm-protocol/actions/workflows/ci.yml">
    <img src="https://github.com/firm-org/firm-protocol/actions/workflows/ci.yml/badge.svg" />
  </a>
</div>

<div align="center">
  <h4>
    <a href="https://firm.org">
      Website
    </a>
    <span> | </span>
    <a href="https://docs.firm.org">
      Documentation
    </a>
    <span> | </span>
    <a href="https://github.com/firm-org/firm-protocol/releases">
      Releases
    </a>
    <span> | </span>
    <a href="https://twitter.com/firm">
      Twitter
    </a>
  </h4>
</div>

[![Version][version-badge]][version-link]
[![Test CI][ci-badge]][ci-link]
[![License][license-badge]][license-link]
[![Documentation][docs-badge]][docs-link]

[banner-image]: .github/img/Firm-banner.png
[version-badge]: https://img.shields.io/github/v/release/firm-org/firm-protocol
[version-link]: https://github.com/firm-org/firm-protocol/releases
[ci-badge]: https://github.com/firm-org/firm-protocol/actions/workflows/ci.yml/badge.svg
[ci-link]: https://github.com/firm-org/firm-protocol/actions/workflows/ci.yml
[license-badge]: https://img.shields.io/github/license/firm-org/firm-protocol
[license-link]: https://github.com/firm-org/firm-protocol/blob/master/LICENSE
[docs-badge]: https://img.shields.io/badge/Firm%20Protocol-documentation-blue
[docs-link]: https://docs.firm.org

# Firm protocol
A protocol to create and run internet-native companies.
  
## Background
Firm protocol is our interpretation of what the software core of internet-native companies should be. The protocol is non-custodial and allows founders to create and run a company whose basic rules and rights are controlled and enforced with code.

See the full [protocol documentation][docs-link].

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

## Audits
TODO

## License
[GPL 3.0][license-link]
