# Alcor Exchange — Order Book + v3 AMM DEX on XPR Network

Alcor is a multi-chain (WAX, EOS, Telos, XPR Network) DEX that ships **both** an on-chain limit order book and a Uniswap v3-style concentrated-liquidity AMM, plus an OTC venue. It is the only XPR Network venue with v3-style ticks/positions/incentives.

> **What's NOT on XPR Network:** Alcor's UI advertises NFT marketplace (`alcornftswap`), liquid staking (`liquid.alcor`), and the LSW token (`lsw.alcor`). These accounts **do not exist on XPR Network** — they only run on Alcor's WAX/EOS instances. Do not build against them here.

> **Policy for AI agents:** All chain **writes** in this doc use `proton` CLI — private keys stay in the OS keyring, never in the agent's context. **Reads** use direct RPC (`get_table_rows`) and the Alcor REST API. Do not introduce signing patterns that pass raw keys to the agent (e.g. `new JsSignatureProvider(['PRIV_KEY'])`, `wallet.import_key('...')`).

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
| `GET /tickers/{ticker_id}/charts` | OHLCV candles — **requires** `resolution`, `from`, `to` (Unix seconds); returns `[]` if range/resolution has no data |

### AMM (swap.alcor)

| Endpoint | Description |
|----------|-------------|
| `GET /swap/pools` | All pools |
| `GET /swap/pools/{pool_id}` | Single pool with current tick, sqrtPrice, liquidity |
| `GET /swap/pools/{pool_id}/swaps` | Swap history |
| `GET /swap/pools/{pool_id}/positions` | LP positions |
| `GET /swapRouter/getRoute` | Quote: optimal route + **memo string ready to use** (see below) |

#### `swapRouter/getRoute` parameters

Required: `trade_type` (`EXACT_INPUT` or `EXACT_OUTPUT`), `input`, `output` (each as `symbol-contract`), `amount`.
Optional: `slippage` (default `0.3`), `receiver` (defaults to placeholder `<receiver>`), `maxHops` (capped at 3), `includePoolDetails`, `v2`.

The response includes a `memo` field already formatted for the swap transfer — substitute `<receiver>` if you didn't pass it.

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

Verified against the live ABI on `proton.greymass.com` (2026-05).

| Table | Scope | Description |
|-------|-------|-------------|
| `pools` | `swap.alcor` | `id`, `active`, `tokenA {quantity, contract}`, `tokenB`, `fee`, `tickSpacing`, `currSlot {sqrtPriceX64, tick}`, `feeGrowthGlobalAX64`, `feeGrowthGlobalBX64`, `liquidity` |
| `positions` | `<pool_id>` | LP positions |
| `ticks` | `<pool_id>` | Tick data |
| `bitmaps` | `<pool_id>` | Tick bitmaps |
| `observations` | `<pool_id>` | TWAP oracle |
| `incentives` | `swap.alcor` | Farm incentives |
| `incentivefee` | `swap.alcor` | Incentive fee config |
| `stakes` | `swap.alcor` | Staked positions |
| `stakingpos` | `swap.alcor` | Staking position records |
| `stakereturn` | `swap.alcor` | Staking return tracking |
| `balances` | `swap.alcor` | User balances |
| `banlist` | `swap.alcor` | Banned accounts |
| `forzenpools` | `swap.alcor` | Frozen pool list (**note: table name is misspelled in the deployed contract — use `forzenpools`, not `frozenpools`**) |
| `markets` | `swap.alcor` | Per-token market metadata |
| `system` | `swap.alcor` | System / global config |
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

Single rule that covers both directions:

- **Transfer** the token you want to *offer*.
- **Memo** describes the token + amount you want to *receive*, in the form `<amount> <SYM>@<contract>`.

The implied unit price is `quantity_transferred : amount_in_memo`. The order goes to the buy or sell side depending on which token of the pair you transferred.

```bash
# BUY TDBN with XPR — transfer XPR, ask for TDBN in memo
proton action eosio.token transfer \
  '{"from":"trader","to":"alcor","quantity":"7977.4902 XPR","memo":"7109.9992 TDBN@tokencreate"}' \
  trader

# SELL TDBN for XPR — transfer TDBN, ask for XPR in memo
proton action tokencreate transfer \
  '{"from":"trader","to":"alcor","quantity":"7109.9992 TDBN","memo":"7977.4902 XPR@eosio.token"}' \
  trader
```

> **Source:** Verified against `store/market.js` `fetchBuy` / `fetchSell` in [alcor-ui](https://github.com/alcorexchange/alcor-ui/blob/master/store/market.js). Both actions construct the memo as `<desired_amount> <desired_symbol>@<desired_contract>`.

### Cancel an order

```bash
proton action alcor cancelbuy \
  '{"executor":"trader","market_id":2,"order_id":123}' trader

proton action alcor cancelsell \
  '{"executor":"trader","market_id":2,"order_id":123}' trader
```

Look up your `order_id` via `get_table_rows` on `buyorder` / `sellorder` with scope = market id (string).

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

### Swap (recommended: getRoute → transfer)

The `swapRouter/getRoute` endpoint computes the optimal multi-hop route **and returns the memo string ready to use** — just substitute the receiver. This is the path the official `alcor-ui` and the `@alcorexchange/alcor-swap-sdk` use.

```bash
curl "https://proton.alcor.exchange/api/v2/swapRouter/getRoute\
?trade_type=EXACT_INPUT\
&input=xpr-eosio.token\
&output=xusdc-xtokens\
&amount=10\
&slippage=0.3\
&receiver=trader"
```

Response (verified live):

```json
{
  "route": [394, 9476, 9023],
  "memo": "swapexactin#394,9476,9023#trader#0.027783 XUSDC@xtokens#0",
  "input": "10.0000",
  "output": "0.027867",
  "minReceived": "0.027783",
  "maxSent": "10.0000",
  "priceImpact": "0.72",
  "executionPrice": { "numerator": "27867", "denominator": "100000" }
}
```

Then transfer with the returned memo:

```bash
proton action eosio.token transfer \
  '{"from":"trader","to":"swap.alcor","quantity":"10.0000 XPR","memo":"swapexactin#394,9476,9023#trader#0.027783 XUSDC@xtokens#0"}' \
  trader
```

#### Memo format reference

For callers that compute the route themselves (e.g. with the swap SDK):

```
swapexactin#<pool_id_or_route_csv>#<recipient>#<min_output asset@contract>#<deadline>
```

| Segment | Meaning |
|---------|---------|
| `<pool_id_or_route_csv>` | Single pool id, or comma-separated list for multi-hop (`3993,2845,248`) |
| `<recipient>` | Account that receives the output |
| `<min_output asset@contract>` | Minimum acceptable output amount as an extended asset, e.g. `0.027783 XUSDC@xtokens` |
| `<deadline>` | Unix seconds, or `0` for no deadline |

> **Source:** Format authoritatively defined in [`examples/getTrateRoute.ts`](https://github.com/alcorexchange/alcor-v2-sdk/blob/main/examples/getTrateRoute.ts) of the official Swap SDK: `` `swapexactin#${route.join(',')}#${receiver}#${minReceived.toExtendedAsset()}#0` ``. The live `getRoute` API returns this same string ready for transfer.

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
