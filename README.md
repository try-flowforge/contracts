# FlowForge Contracts

Solidity smart contracts built with Foundry. Part of the FlowForge stack—deployables and on-chain logic used by the backend and frontend (e.g. Safe factory, Safe module, relay).

## Project Structure

```bash
contracts/
├── src/                 # Solidity sources
├── script/              # Deployment scripts (Forge scripts)
├── test/                # Forge tests
├── lib/                 # Dependencies (forge-std, safe-contracts, openzeppelin-contracts)
├── foundry.toml         # Foundry config
└── foundry.lock
```

## Setup

**Prerequisites:** [Foundry](https://book.getfoundry.sh/getting-started/installation) (Forge, Cast, Anvil, Chisel)

```bash
# Install dependencies (git submodules)
forge install
```

Copy env example and set variables used by the deploy scripts:

```bash
cp .env.example .env
# Edit .env: set PRIVATE_KEY, RPC_URL, and for module deploy EXECUTOR_ADDRESS
```

## Deployment

### 1. Safe contracts (Ethereum + Arbitrum)

```bash
forge script script/1_deployFlowForgeSafeContracts.s.sol:DeployFlowForgeSafeContracts --broadcast
```

If the combined script is not supported due to multiple forks, run per chain:

```bash
forge script script/1_deployFlowForgeSafeContracts.s.sol:DeployFlowForgeSafeContractsL1 --broadcast
forge script script/1_deployFlowForgeSafeContracts.s.sol:DeployFlowForgeSafeContractsL2 --broadcast
```

## LICENSE

[MIT License](LICENSE)
