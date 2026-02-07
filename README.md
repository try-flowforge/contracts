# FlowForge Contracts

Solidity smart contracts built with Foundry. Part of the FlowForge stack—deployables and on-chain logic used by the backend and frontend (e.g. Safe modules, relay, workflow-related contracts).

## Project Structure

```bash
contracts/
├── src/                 # Solidity sources
├── script/              # Deployment scripts (Forge scripts)
├── test/                # Forge tests
├── lib/                 # Dependencies (e.g. forge-std)
├── foundry.toml         # Foundry config
└── foundry.lock
```

## Setup & Run

**Prerequisites:** [Foundry](https://book.getfoundry.sh/getting-started/installation) (Forge, Cast, Anvil, Chisel)

```bash
# Install dependencies (forge-std via git submodule)
forge install
```

## LICENSE

[MIT License](LICENSE)
