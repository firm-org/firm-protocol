# Firm Core

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


### Igor Comments

First of all great job at writing the code and designing the architecture.
There are some code-specific comments inside the files and my general comments are
below.

What I like:
* Using factories for deployment.
* Having upgradeable UUPS proxies.
* Using meta-txs from day 0. They are super important for UX and user-focused features.
* Modular architecture
* Using Foundry for development.

What I recommend:
* All the Firm upgradeable contracts are 1976 UUPS proxies and they can be
  upgraded by the owner (safe) but it is unclear how all the firms would be upgraded
  in case of a bug is found. That would require each firm to upgrade on its own.
  It also means that multiple firms could be at different codebases at the same
  time which would make writing a dapp to support all of them pretty hard. I
  recommend considering using beacon proxies for Firms
  (https://docs.openzeppelin.com/contracts/4.x/api/proxy#BeaconProxy). They
  allow upgrading all the SC instances at once which simplifies DevOps,
  security, costs, and dapp development. That certainly begs the question of
  security (who should have this power) but current architecture would be a nightmare
  from a DevOps perspective, i.e., each firm has to upgrade on its own and pay
  the cost of deployment. People using Firm are likely not engineers.
* Foundry is the best tool at the moment though I would still recommend
  adding Hardhat for running some tests, scripts, deployment, and 3rd party
  plugins. Hardhat certainly has way more scripting capacity right now than
  Foundry.
* Not using ETK and other low-level EVM tools because they make reading and
  auditing code much harder. Pure Solidity gives the best security and
  productivity combo. Gas optimization always can be done later but for the initial
  design, I would focus on using pure Solidity.
* Consider using unlimited-size contracts (like eip2535). Putting all the
  functionality inside one contract makes a lot of sense in EVM due to gas
  overhead for calling external contacts, storage separation and it is much easy
  to interact with only one contract for outside contracts and dApps.
* Setup a deployment scripts in such a way that they would guarantee deploying to
  the same addresses on every chain.
* Using Github CI to run tests automatically.
* Using Linter and Prettier.
* Using automated security tools like Slither.


Risks I see:
* Building the architecture on top of Gnosis Safe makes total sense but it comes with
  some risks attached. If Gnosis Safe is hacked then some Firm users would
  certainly blame Firm.
* If Gnosis Safe updates to a new version with a different interface that would
  require some work and updating on-chain contracts.
* Protocol being too expensive to use daily. Right now we enjoy low
  gas prices on the mainnet but they are unlikely to stay like that. Every organization
  has a limit on how much they are willing to spend on gas to run the
  organization. It is important to fit in this budget for an average org and to
  set this number early. What is it? $100? $500?
* Using other protocols for integrations (Llamapay) introduces a dependency risk.
  In other words, if Llamapay is hacked then the Firm users lose money. It would be great to
  design architecture in a way to limit exposure to external protocols.

#### Notes on Budget architecture.

Budget has allowances mapping which makes total sense. Unfortunately, because allowances can be nested interacting with them has a linear growth in
terms of gas cost. It would be nice to design allowances in a way where it would
have a constant gas cost of CRUD operations. Another note is that right now it
is only possible to execute payments but it is easy to see the need for
different kinds of operations like approving allowances, signing messages
(EIP-1271), and even calling other contracts. It sounds like a general
architecture of approving the execution of arbitrary code should be possible. It
certainly would require security consideration but I think by safeguarding
balances and allowancing within one transaction it can be done safely.
Another one is storing all the allowances on-chain. Unless allowances have to
be consumed by external protocols it doesn't make sense to store them on-chain
because it is expensive. Instead, it should be possible to store and update 
cryptographic commitments of allowances--the proofs to spend a certain amount in a
certain time--a good example of this technique would be a Merkle tree for an NFT
whitelist. This approach could provide a constant gas cost for allowances CRUD
operations as well as gas savings.

First of all great job at writting the code and designing the architecture.
There are some code specific comments inside the files and my general comments are
below.
