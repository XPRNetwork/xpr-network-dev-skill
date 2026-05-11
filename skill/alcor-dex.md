# Alcor Exchange — Order Book + v3 AMM DEX on XPR Network

Alcor is a multi-chain (WAX, EOS, Telos, XPR Network) DEX that ships **both** an on-chain limit order book and a Uniswap v3-style concentrated-liquidity AMM, plus an OTC venue. It is the only XPR Network venue with v3-style ticks/positions/incentives.

> **What's NOT on XPR Network:** Alcor's UI advertises NFT marketplace (`alcornftswap`), liquid staking (`liquid.alcor`), and the LSW token (`lsw.alcor`). These accounts **do not exist on XPR Network** — they only run on Alcor's WAX/EOS instances. Do not build against them here.

## Quick Reference

| Item | Value |
|------|-------|
| Order book contract | `alcor` |
| AMM contract (v3-style) | `swap.alcor` |
| OTC contract | `alcorotc` |
| XPR token | `eosio.token` (4,XPR) |
| API base | `https://proton.alcor.exchange/api/v2` |
| Frontend | `https://proton.alcor.exchange` |
| Market creation fee | `50,000.0000 XPR` |
| Fee recipient | `avral` |
| Open-source UI | https://github.com/alcorexchange/alcor-ui |
| Swap SDK | https://github.com/alcorexchange/alcor-v2-sdk (`@alcorexchange/alcor-swap-sdk`) |

Other chains use their own subdomain (e.g. `wax.alcor.exchange`, `eos.alcor.exchange`) — endpoint paths are identical.

---

## REST API

Base: `https://proton.alcor.exchange/api/v2`. Timestamps in milliseconds. Real-time via Socket.IO.

### Token & Market Discovery

| Endpoint | Description |
|----------|-------------|
| `GET /tokens` | All token prices |
| `GET /tokens/{token_id}` | Single token; id format `symbol-contract` (e.g. `xpr-eosio.token`) |
| `GET /pairs` | All trading pairs |
| `GET /tickers` | All market tickers |
| `GET /tickers/{ticker_id}` | Single ticker; id format `base-contract_quote-contract` (e.g. `loan-loan.token_xusdc-xtokens`) |
| `GET /analytics/global` | TVL, pool count, swap count, volumes |

### Order Book Market Data

| Endpoint | Description |
|----------|-------------|
| `GET /tickers/{ticker_id}/orderbook` | Depth |
| `GET /tickers/{ticker_id}/latest_trades` | Recent fills |
| `GET /tickers/{ticker_id}/historical_trades` | Trade history |
| `GET /tickers/{ticker_id}/charts` | OHLCV candles |

### AMM (swap.alcor)

| Endpoint | Description |
|----------|-------------|
| `GET /swap/pools` | All pools |
| `GET /swap/pools/{pool_id}` | Single pool with current tick, sqrtPrice, liquidity |
| `GET /swap/pools/{pool_id}/swaps` | Swap history |
| `GET /swap/pools/{pool_id}/positions` | LP positions |
| `GET /swapRouter/getRoute` | Quote: optimal route + expected output |

### Account History

| Endpoint | Description |
|----------|-------------|
| `GET /account/{account}/deals` | Spot trade history |
| `GET /account/{account}/positions` | Active LP positions |
| `GET /account/{account}/swap-history` | Swap history |

```bash
curl https://proton.alcor.exchange/api/v2/analytics/global
curl https://proton.alcor.exchange/api/v2/tickers/loan-loan.token_xusdc-xtokens
```

---

## On-Chain Tables

All reads use standard `get_table_rows`. Fallback RPCs: `https://proton.greymass.com`, `https://proton.eosusa.io`, `https://proton-api.alcor.exchange`.

### `alcor` (order book)

| Table | Scope | Description |
|-------|-------|-------------|
| `markets` | `alcor` | `id`, `base_token {sym, contract}`, `quote_token {sym, contract}`, `min_buy`, `min_sell`, `frozen`, `fee` |
| `buyorder` | `<market_id>` | `id`, `account`, `bid` (quote offered), `ask` (base wanted), `unit_price`, `timestamp` |
| `sellorder` | `<market_id>` | `id`, `account`, `bid` (base offered), `ask` (quote wanted), `unit_price`, `timestamp` |
| `account` | `alcor` | User balances held inside the DEX |
| `settings` | `alcor` | Global settings |
| `freeorders` | `alcor` | Free-CPU order tracking |
| `ban` | `alcor` | Ban list |

```bash
# List all markets
curl -s -X POST https://proton.greymass.com/v1/chain/get_table_rows \
  -H 'Content-Type: application/json' \
  -d '{"code":"alcor","scope":"alcor","table":"markets","limit":500,"json":true}'

# Sell-side depth for market id 2 (XUSDT/XPR)
curl -s -X POST https://proton.greymass.com/v1/chain/get_table_rows \
  -H 'Content-Type: application/json' \
  -d '{"code":"alcor","scope":"2","table":"sellorder","limit":50,"json":true}'
```

Scope for `buyorder` / `sellorder` is the **market id as a string**.

### `swap.alcor` (AMM — Uniswap v3-style)

| Table | Scope | Description |
|-------|-------|-------------|
| `pools` | `swap.alcor` | `id`, `active`, `tokenA {quantity, contract}`, `tokenB`, `fee`, `tickSpacing`, `currSlot {sqrtPriceX64, tick}`, `feeGrowthGlobalAX64`, `feeGrowthGlobalBX64`, `liquidity` |
| `positions` | `<pool_id>` | LP positions |
| `ticks` | `<pool_id>` | Tick data |
| `bitmaps` | `<pool_id>` | Tick bitmaps |
| `observations` | `<pool_id>` | TWAP oracle |
| `incentives` | `swap.alcor` | Farm incentives |
| `stakes` | `swap.alcor` | Staked positions |
| `stakingpos` | `swap.alcor` | Staking position records |
| `balances` | `swap.alcor` | User balances |
| `markets` | `swap.alcor` | Per-token market metadata |
| `whitelist` | `swap.alcor` | Allowed tokens |

```bash
# Inspect all AMM pools
curl -s -X POST https://proton.greymass.com/v1/chain/get_table_rows \
  -H 'Content-Type: application/json' \
  -d '{"code":"swap.alcor","scope":"swap.alcor","table":"pools","limit":50,"json":true}'
```

### `alcorotc` (OTC)

| Table | Scope | Description |
|-------|-------|-------------|
| `orders` | `alcorotc` | Active OTC orders |
| `results` | `alcorotc` | Completed deals |
| `banned` | `alcorotc` | Ban list |

---

## Order Book Actions (`alcor`)

Most operational actions live in the ABI, but **placing a limit order is done via `transfer` with a memo**, not a direct action.

### Place a limit order (transfer + memo)

Send the token you're offering to `alcor` with a memo describing what you want back:

```
memo = "<ask_amount> <BASE_SYMBOL>@<base_contract>"
```

```bash
# Buy: offer 7977.4902 XPR for 7109.9992 TDBN
proton action eosio.token transfer \
  '{"from":"trader","to":"alcor","quantity":"7977.4902 XPR","memo":"7109.9992 TDBN@tokencreate"}' \
  trader
```

For a **sell**, invert: transfer the base token and put the desired quote `amount SYM@contract` in the memo.

> **Caveat:** the memo encoding above is observed from live on-chain activity, not from official Alcor documentation. Cross-check against `alcor-ui` source (`src/utils/orders.js` / `marketStore`) before building production integrations.

### Direct actions (verified from ABI)

```
alcor::cancelbuy   { executor: name, market_id: uint64, order_id: uint64 }
alcor::cancelsell  { executor: name, market_id: uint64, order_id: uint64 }
alcor::openmarket  { base_con: name, base_sym: asset, quote_con: name, quote_sym: asset }   # 50,000 XPR fee
alcor::buymatch    # internal matching engine
alcor::sellmatch   # internal matching engine
alcor::setmins     # admin: set min order sizes
alcor::setfrozen   # admin: freeze a market
alcor::payforcpu   # CPU sponsorship hook
```

Other admin / receipt / notification actions in the ABI: `buyreceipt`, `sellreceipt`, `news`, `closemarket`, `consumefords`, `consumeords`, `setacclimit`, `setmfee`, `setmfrozen`, `ban`, `unban`, `rmaccount`.

---

## AMM Actions (`swap.alcor`)

The AMM follows Uniswap v3 semantics: pools have a fee tier, a current `sqrtPriceX64`, a tick spacing, and positions are bounded by `[tickLower, tickUpper]`.

### Swap (transfer + memo)

```
memo = "swapexactin#<pool_id_or_route>#<recipient>#<min_output asset@contract>#<deadline>"
```

```bash
# Single-hop: swap XXRP -> XPR via pool 248, min 1.9823 XPR out, no deadline (0)
proton action xtokens transfer \
  '{"from":"trader","to":"swap.alcor","quantity":"0.003810 XXRP","memo":"swapexactin#248#trader#1.9823 XPR@eosio.token#0"}' \
  trader

# Multi-hop: comma-separated pool ids define the route
proton action xtokens transfer \
  '{"from":"trader","to":"swap.alcor","quantity":"0.003810 XXRP","memo":"swapexactin#3993,2845,248#trader#1.9823 XPR@eosio.token#0"}' \
  trader
```

Use `GET /api/v2/swapRouter/getRoute` to compute the optimal route and `min_output` before signing.

> **Caveat:** memo format reverse-engineered from live swaps. Confirm against `alcor-ui` (`src/store/modules/swap.js`) or `@alcorexchange/alcor-swap-sdk` for production use.

### Direct actions (verified from ABI)

```
swap.alcor::createpool { account: name, tokenA: extended_asset, tokenB: extended_asset,
                         sqrtPriceX64: uint128, fee: uint32 }

swap.alcor::addliquid  { poolId: uint64, owner: name,
                         tokenADesired: asset, tokenBDesired: asset,
                         tickLower: int32, tickUpper: int32,
                         tokenAMin: asset, tokenBMin: asset, deadline: uint32 }

swap.alcor::subliquid  { poolId: uint64, owner: name, liquidity: uint64,
                         tickLower: int32, tickUpper: int32,
                         tokenAMin: asset, tokenBMin: asset, deadline: uint32 }

swap.alcor::collect    { poolId: uint64, owner: name, recipient: name,
                         tickLower: int32, tickUpper: int32,
                         tokenAMax: asset, tokenBMax: asset }
```

Farming / staking actions: `stake`, `unstake`, `stakelastpos`, `unstakepos`, `transferpos`, `newincentive`, `setincentfee`, `getreward`, `getstakes`, `getfees`, `withdraw`.

Admin: `freezepool`, `lockpool`, `rmvpool`, `setfee`, `setactive`, `setactivefee`, `banacc`, `cfgtoken`, `regmarket`, `addoraclerow`, `init`.

---

## SDK Usage (AMM)

Alcor publishes a TypeScript SDK that models the v3 pools client-side, mirroring Uniswap's `@uniswap/v3-sdk` patterns:

```bash
npm install @alcorexchange/alcor-swap-sdk
```

```ts
import { Pool, Token, computePoolAddress } from '@alcorexchange/alcor-swap-sdk'

// Fetch pool row from get_table_rows, then construct a Pool instance
// to compute prices, input→output amounts, multi-hop routes, etc.
```

Repo: https://github.com/alcorexchange/alcor-v2-sdk. The SDK consumes the same `pools` rows the API exposes.

---

## Identifying a Pool from the API

```bash
# Discover the LOAN/XUSDC pool
curl -s "https://proton.alcor.exchange/api/v2/swap/pools" | \
  jq '.[] | select(.tokenA.symbol=="LOAN" and .tokenB.symbol=="XUSDC")'
```

Pool ids are stable `uint64` values. Save the id; use it in swap memos and `addliquid` / `subliquid` calls.

---

## Positioning vs Other XPR Network DEXes

| Venue | Model | Best for | Documented in |
|-------|-------|----------|---------------|
| **MetalX** | Order book + v2-style swap pools | Pro traders, market makers, stop-loss / take-profit, institutional flow | `metalx-dex.md` |
| **SimpleDEX** | v2 AMM + bonding-curve token launchpad | Memecoin launches, retail token discovery | `simpledex.md` |
| **Alcor** | Order book + Uniswap v3 concentrated-liquidity AMM + OTC | Concentrated LP positions, multi-hop routing, cross-chain users familiar from WAX/EOS | This file |

Alcor is the only venue here exposing v3 ticks, range positions, and on-chain farm incentives.

---

## Resources

- **Frontend (XPR Network):** https://proton.alcor.exchange
- **API base (XPR Network):** https://proton.alcor.exchange/api/v2
- **Hosted API docs:** https://api.alcor.exchange
- **GitHub org:** https://github.com/alcorexchange
- **UI source:** https://github.com/alcorexchange/alcor-ui
- **Swap SDK:** https://github.com/alcorexchange/alcor-v2-sdk
- **Multi-venue gateway:** https://alcor.exchange
