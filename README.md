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

## Tokenomics

The protocol uses a governance token **FBLK** (`FreeTheBlocksToken`) plus contracts for emissions, locks, fee sharing, vesting, and buy-and-burn. Implementation lives under `my-dex-contracts/src/` (tokens, staking, tokenomics).

### FBLK supply and allocation

- **Fixed cap:** 100,000,000 FBLK (no further minting after deployment).
- **Initial split** (minted in the token constructor to the addresses passed in at deploy):

| Allocation | Share | Role |
|------------|-------|------|
| Liquidity mining | 40% | **MasterChef** — rewards for staking v3 LP NFTs |
| Treasury | 25% | DAO / timelock–style treasury |
| Team vesting | 20% | **VestingWallet** for team |
| Investor vesting | 10% | **VestingWallet** for investors |
| Community | 5% | Airdrops / community programs |

FBLK is **ERC20Permit** (gasless approvals) and **ERC20Snapshot** so balances can be frozen at points in time for voting or accounting. A designated **snapshot admin** can call `snapshot()` and transfer that role (e.g. to a timelock).

### Liquidity mining (MasterChef)

`MasterChef.sol` stakes **Uniswap v3–style LP positions** (NFTs from the NonfungiblePositionManager). Stakers earn **FBLK** proportional to their position’s liquidity in each registered pool.

- **Emissions:** Start at **10 FBLK per block**, then **halve roughly every year** (using a fixed block period tuned for ~12s blocks). After several halvings, emissions **floor at 1 FBLK per block**.
- **Pools:** The owner adds pools with an **allocation weight**; rewards split across pools by `allocPoint`.

### Locking FBLK → veFBLK (VotingEscrow)

`VotingEscrow.sol` lets users **lock FBLK** to receive **veFBLK**-style voting power (linearly decaying over the lock, similar in spirit to Curve’s veCRV).

- Lock duration is between **1 week** and **4 years** (aligned to **weekly** boundaries).
- Users can **add to an existing lock**, **extend** the unlock time, or **withdraw** after unlock.
- **FeeDistributor** reads `balanceOfAt` / `totalSupplyAt` at the **start of each fee epoch** so weekly protocol fees can be split fairly among lockers at that snapshot.

### Protocol fees → ve lockers (FeeDistributor)

`FeeDistributor.sol` implements **weekly epochs** (7 days).

1. **Register pools** — Owner adds v3 pool addresses that expose `collectProtocol`.
2. **Collect** — Anyone can call `collectFromPool` / `collectFromAllPools` to pull accumulated **protocol fees** into the distributor.
3. **Normalize** — Fees in arbitrary pool tokens can be swapped into a single **fee token** (e.g. WETH) via the **SwapRouter** (`convertFees`).
4. **Checkpoint** — After each epoch, `checkpointEpoch` finalizes how much fee token was collected and the **total veFBLK supply at epoch start**; a new epoch begins.
5. **Claim** — Each user’s share for a finalized epoch is **proportional to their ve balance at that epoch’s start**. Users call `claim` / `claimAll` to withdraw their fee token.

This ties **DEX revenue** to **long-term lockers**, not just raw FBLK holders.

### Buy and burn (BuyAndBurn)

`BuyAndBurn.sol` uses **DEX liquidity** to acquire FBLK and remove it from circulation:

- **ETH path:** Wrap ETH to WETH, swap WETH → FBLK through the router, then call **`FBLK.burn`** on the received amount.
- **ERC20 path:** A generic `buyAndBurnToken` swaps an approved token → FBLK and burns the outcome.

Configurable **minimum buy size**, **pool fee tier**, and **owner** controls keep operations sane. Counters track cumulative **FBLK burned** and **ETH spent** (for the ETH-based flow).

### Team and investor vesting (VestingWallet)

`VestingWallet.sol` holds a fixed **allocation** of an ERC20 (here FBLK) for **team** or **investors**:

- **Schedule:** No tokens until after a **cliff**; then **linear vesting** over a configured total duration (the contract is parameterized at deploy — typical use is a long cliff plus multi-year linear release).
- **Beneficiary** receives vested tokens via **`claim`**.
- **Owner** (e.g. multisig) can **cancel** vesting: unvested tokens return to **treasury**, vested amounts stay with the beneficiary.

Together, these pieces define **supply distribution**, **LP incentives**, **governance / lock-weighted fee share**, **deflationary pressure** via burn, and **aligned long-term unlocks** for insiders.

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
