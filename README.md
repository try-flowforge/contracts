# FlowForge Contracts

Solidity smart contracts built with Foundry. Part of the FlowForge stack—deployables and on-chain logic used by the backend and frontend (e.g. Safe factory, Safe module, relay).

## Chains

| Contract(s) | Chain(s) | Note |
| ----------- | -------- | ---- |
| **FlowForgeSafeFactory**, **FlowForgeSafeModule** | Arbitrum Sepolia, Arbitrum One (and optionally Ethereum) | Your app chain(s). Deploy where you run relay and DeFi. |

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
# Edit .env: set PRIVATE_KEY, RPC_URL, EXECUTOR_ADDRESS, and RELAYER_ADDRESS (see below)
```

## Deployment

### Safe contracts (Ethereum + Arbitrum)

```bash
forge script script/1_deployFlowForgeSafeContracts.s.sol:DeployFlowForgeSafeContracts --broadcast
```

If the combined script is not supported due to multiple forks, run per chain:

```bash
forge script script/1_deployFlowForgeSafeContracts.s.sol:DeployFlowForgeSafeContractsL1 --broadcast
forge script script/1_deployFlowForgeSafeContracts.s.sol:DeployFlowForgeSafeContractsL2 --broadcast
```

**Relayer must be factory owner:** `createSafeWallet` is `onlyOwner`. The backend relayer sends the create-Safe tx, so it must be the owner. The deploy script uses CREATE3; with CREATE3, `msg.sender` in the factory constructor is the CREATE3 proxy (not your EOA), so you **must** set `RELAYER_ADDRESS` in `.env` to your relayer EOA (the address from `RELAYER_PRIVATE_KEY`). The script passes it as the factory's initial owner—no `transferOwnership` step needed.

If you already deployed with an older script (no `RELAYER_ADDRESS`), the factory owner is the CREATE3 proxy and you cannot transfer from it. Redeploy using the current script (with `RELAYER_ADDRESS` set); the factory uses salt `v1_1` so it gets a **new** address. Update `contracts/deployments.json` and the backend chain config with the new factory address.

### Deploy only Arbitrum (Safe contracts)

To support only Arbitrum Sepolia and Arbitrum One, run the L2 script once per chain (no L1 Safe deploy needed):

```bash
# Arbitrum Sepolia: set ARB_RPC_URL and ARB_SAFE_PROXY_FACTORY / ARB_SAFE_SINGLETON for Sepolia
forge script script/1_deployFlowForgeSafeContracts.s.sol:DeployFlowForgeSafeContractsL2 --broadcast

# Arbitrum One: switch .env to mainnet ARB_* and run again
forge script script/1_deployFlowForgeSafeContracts.s.sol:DeployFlowForgeSafeContractsL2 --broadcast
```

### Deploy test contract

```bash
forge script script/2_deployFlowForgeTestContract.s.sol:DeployFlowForgeTestContract --broadcast
```

Add the deployed address to `deployments.json` or set `FLOWFORGE_TEST_CONTRACT` when running the full-flow test.

## Testing

- **FlowForgeDeployed** (`test/FlowForgeDeployed.t.sol`): view checks on deployed factory/module/policy. Run: `forge test --match-contract FlowForgeDeployed --fork-url $ARB_SEPOLIA_RPC_URL`.
- **FlowForgeFullFlow** (`test/FlowForgeFullFlow.t.sol`): full flow on fork—create Safe, enable module, set policy, `execTask` to `FlowForgeTestContract`. Set `PRIVATE_KEY` (executor) and `FLOWFORGE_TEST_CONTRACT`, then: `forge test --match-contract FlowForgeFullFlow --fork-url $ARB_SEPOLIA_RPC_URL`.

## LICENSE

[MIT License](LICENSE)
