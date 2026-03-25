# FreeTheBlocks DEX (Uniswap-style clone)

A full-stack decentralized exchange project: a **React** swap UI wired to **Uniswap v3–style** smart contracts on **Ethereum Sepolia**, plus a **Foundry** workspace for pools, routing, liquidity, and tokenomics.

## What this project is

- **Frontend** — A swap experience similar in spirit to Uniswap: pick tokens, see a quote, approve if needed, and swap through an on-chain router. The app is branded **FreeTheBlocks** and targets **Sepolia** testnet.
- **Smart contracts** (`my-dex-contracts/`) — Solidity code organized like a v3 DEX: factory and pool logic, periphery (e.g. swap router, position manager, quoter), test tokens, staking (`MasterChef`), fee distribution, vesting, and related scripts for deploy and pool setup.

Deployed addresses for Sepolia are recorded in `deployments/sepolia.json` and consumed by the app via `src/constants/deployments.ts`.

## Tech stack

| Area | Tools |
|------|--------|
| UI | [React 19](https://react.dev/), [TypeScript](https://www.typescriptlang.org/) |
| Build & dev server | [Vite 8](https://vite.dev/) |
| Styling | [Tailwind CSS](https://tailwindcss.com/), [clsx](https://github.com/lukeed/clsx) |
| Wallet & chain | [Wagmi](https://wagmi.sh/), [Viem](https://viem.sh/), [RainbowKit](https://www.rainbowkit.com/) |
| Data fetching / cache | [TanStack Query](https://tanstack.com/query) |
| State | [Zustand](https://zustand-demo.pmnd.rs/) |
| Routing | [React Router](https://reactrouter.com/) |
| Icons | [Lucide React](https://lucide.dev/) |
| Contracts | [Foundry](https://book.getfoundry.sh/) (Forge, Anvil, Cast), Solidity |

## How it works (high level)

1. **Wallet** — The user connects with RainbowKit. `main.tsx` configures Wagmi for **Sepolia** and optional Alchemy RPC via `VITE_ALCHEMY_API_KEY`.
2. **Addresses** — Contract addresses come from `deployments/sepolia.json` (factory, router, quoter, tokens, etc.).
3. **Swap page** — `SwapWidget` uses hooks such as `useSwapQuote` and `useSwapExecute` to call the on-chain **Quoter** for estimates and the **SwapRouter** for approvals and swaps, using token metadata from `src/constants/tokens.ts`.
4. **Testnet helper** — Route `/testnet` exposes utilities for working on Sepolia (see `TestnetHelper` page).
5. **Contracts repo** — Under `my-dex-contracts/`, Foundry builds and tests the protocol; `forge script` / `CreatePool` style scripts deploy and configure pools. Dependencies are managed with `foundry.toml` and `remappings.txt` (libraries live under `lib/` after `forge install` — see `.gitignore`).

## Repository layout

```
├── src/                    # React app (pages, components, hooks, constants)
├── deployments/            # JSON deployment artifacts (e.g. sepolia.json)
├── public/                 # Static assets
├── my-dex-contracts/       # Foundry project (Solidity, scripts, tests)
└── package.json
```

## Prerequisites

- **Node.js** (LTS recommended) and npm  
- **Foundry** — [install](https://book.getfoundry.sh/getting-started/installation) for building and testing contracts

## Frontend setup

```bash
npm install
npm run dev
```

Optional: create a `.env` file in the repo root for the variables below.

Open the URL Vite prints (usually `http://localhost:5173`).

| Script | Purpose |
|--------|---------|
| `npm run dev` | Start dev server with HMR |
| `npm run build` | Typecheck + production build |
| `npm run preview` | Serve production build locally |
| `npm run lint` | ESLint |

### Environment variables (frontend)

Create a `.env` in the project root (Vite exposes only variables prefixed with `VITE_`):

| Variable | Purpose |
|----------|---------|
| `VITE_WALLET_CONNECT_PROJECT_ID` | [WalletConnect / Reown Cloud](https://cloud.reown.com/) project ID (required for reliable WalletConnect) |
| `VITE_ALCHEMY_API_KEY` | Optional; uses Alchemy for Sepolia HTTP RPC when set |

## Contracts setup

```bash
cd my-dex-contracts
forge install    # install libs from remappings / foundry.lock if needed
forge build
forge test
```

For Sepolia deploys, configure RPC and keys in line with `foundry.toml` (e.g. `SEPOLIA_RPC_URL`, `ETHERSCAN_API_KEY` for verification). See scripts under `my-dex-contracts/script/`.
