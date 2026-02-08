# FlowForge Contracts

Solidity smart contracts built with Foundry. Part of the FlowForge stack—deployables and on-chain logic used by the backend and frontend (e.g. Safe factory, Safe module, relay).

## Chains

| Contract(s) | Chain(s) | Note |
| ----------- | -------- | ---- |
| **FlowForgeSafeFactory**, **FlowForgeSafeModule** | Arbitrum Sepolia, Arbitrum One (and optionally Ethereum) | Your app chain(s). Deploy where you run relay and DeFi. |
| **FlowForgeSubdomainRegistry**, **FlowForgeEthUsdcPricer** | **Ethereum mainnet only** | ENS lives on Ethereum L1; subdomains (e.g. `alice.flowforge.eth`) are registered there. Cannot be deployed on Arbitrum. |

**Arbitrum-only product:** Deploy Safe factory + module on **Arbitrum Sepolia** and **Arbitrum One** only (use script 1 L2 with `ARB_RPC_URL` and `ARB_SAFE_*` for each). Deploy the ENS registry + pricer once on **Ethereum mainnet** so users can claim subdomains; your backend reads subdomain expiry from Ethereum and grants sponsorship on Arbitrum.

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

### 2. ENS subdomain registry + pricer (Ethereum mainnet, one go)

Requires `ENS_NAME_WRAPPER`, `USDC_ADDRESS`, `CHAINLINK_ETH_USD_FEED`, and `ETH_RPC_URL` in `.env` (see `.env.example`).

```bash
forge script script/2_deployFlowForgeSubdomainRegistry.s.sol:DeployFlowForgeEnsRegistryAndPricer --broadcast
```

Deploys **FlowForgeSubdomainRegistry** and **FlowForgeEthUsdcPricer** (2 USDC per 4 weeks; ETH or USDC via Chainlink). After deployment:

1. As owner of the wrapped parent name (e.g. `flowforge.eth`), call **Name Wrapper**: `setApprovalForAll(registry, true)`.
2. Call **Registry**: `setupDomain(parentNode, pricer, beneficiary, true)`.

Users pay in ETH or USDC for the same expiry (e.g. 5 USDC or equivalent ETH ⇒ 10 weeks). Use **registry.registerWithToken(..., address(0))** to pay in ETH, **registerWithToken(..., USDC)** to pay in USDC; same for **renewWithToken** and batch variants.

The registry supports Option A from the ENS gas-sponsorship plan: users register/renew subdomains; expiry gates off-chain sponsorship (e.g. `remaining_sponsored_txs`).

### Deploy only Arbitrum (Safe contracts)

To support only Arbitrum Sepolia and Arbitrum One, run the L2 script once per chain (no L1 Safe deploy needed):

```bash
# Arbitrum Sepolia: set ARB_RPC_URL and ARB_SAFE_PROXY_FACTORY / ARB_SAFE_SINGLETON for Sepolia
forge script script/1_deployFlowForgeSafeContracts.s.sol:DeployFlowForgeSafeContractsL2 --broadcast

# Arbitrum One: switch .env to mainnet ARB_* and run again
forge script script/1_deployFlowForgeSafeContracts.s.sol:DeployFlowForgeSafeContractsL2 --broadcast
```

ENS registry and pricer stay on Ethereum mainnet (see Chains above).

## LICENSE

[MIT License](LICENSE)
