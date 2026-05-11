# SimpleDEX — Token Launch & AMM DEX on XPR Network

SimpleDEX is a non-custodial decentralized exchange and token launch platform on XPR Network, built by Proton NZ. Two products in one set of contracts: a constant-product AMM with liquidity pools, and a bonding-curve launchpad that atomically graduates new tokens onto the DEX.

## Quick Reference

| Item | Value |
|------|-------|
| DEX contract | `simpledex` |
| Launch contract | `simplelaunch` |
| Token contract | `simpletoken` |
| XPR token | `eosio.token` (4,XPR) |
| RPC endpoint | `https://api.protonnz.com` |
| Analytics API | `https://indexer.protonnz.com` |
| Frontend | `https://simpledex.fun` (canonical) |
| Legacy frontend | `https://dex.protonnz.com` (mirrors simpledex.fun; emits `canonical = simpledex.fun` and will 301 once Google has fully indexed the new domain) |
| Treasury | `dex.protonnz` |
| Official X | [@SimpleDEXFun](https://x.com/SimpleDEXFun) (auto-posts every new launch) |

All token amounts use integers with 4 decimal places. `1.0000 XPR` = raw value `10000`. Multiply human amounts by 10,000.

> **Agent guide:** SimpleDEX publishes a full AI-agent guide at
> `https://simpledex.fun/llms.txt` (index) plus per-topic files
> `llms-setup.txt`, `llms-analytics.txt`, `llms-trading.txt`,
> `llms-launches.txt`, `llms-reference.txt`. Prefer those for canonical,
> always-fresh action templates. This skill page covers the high-level
> shape; see the per-topic files for full curl/proton-cli examples.

---

## Analytics API

Public REST API with CORS enabled. Base: `https://indexer.protonnz.com`. Refreshes every 5 minutes.

### Key Endpoints

| Endpoint | Description |
|----------|-------------|
| `GET /api/stats` | Platform overview (~200 bytes) |
| `GET /api/prices` | All token prices with 24h/7d changes |
| `GET /api/prices/SYMBOL/history` | Price time-series (~5 min intervals, 30 days) |
| `GET /api/tokens` | Tokens with filters (symbol, creator, graduated) |
| `GET /api/tokens?tokenId=N` | Live state for a specific token — use this before templating buy/sell |
| `GET /api/pools` | All pools with TVL, fees, volume, depth metrics |
| `GET /api/movers` | Top gainers/losers by 24h % |
| `GET /api/tvl` | Aggregate TVL history |
| `GET /api/volume` | Daily volume time-series |
| `GET /api/tokens/:id/trades` | Token trades (paginated, max 200) |
| `GET /api/tokens/:id/holders` | Top token holders (zero RPC cost — pre-computed) |
| `GET /api/pools/:id/trades` | Pool trades; add `?live=1` for near-real-time |
| `GET /api/portfolio/:account/pnl` | Per-token P&L, holdings, LP positions |
| `GET /api/portfolio/:account/trades` | Trade history (paginated) |
| `GET /api/portfolio/:account/export?format=koinly` | Tax export (Koinly or standard CSV) |
| `GET /api/leaderboard/profit` | Top traders by realized P&L |
| `GET /api/overview` | Complete platform snapshot (~15KB) |
| `GET /api/events` | Graduation events |
| `GET /api/og/:symbol?id=N` | OG image (PNG) — token-specific card; chain-fallback for brand-new tokens |
| `GET /health` | Health check + structured `warnings[]` codes |

**Rate Limits:** 120 req/min (general); 50 req/min (trades, holders, OG, exports).

---

## Reading On-Chain State

All reads use standard EOSIO `get_table_rows` RPC calls.

### Contract Tables

| Contract | Table | Scope | Description |
|----------|-------|-------|-------------|
| `simpledex` | `pools` | `simpledex` | Pool reserves, fee rates, LP supply |
| `simpledex` | `lp` | user account | LP token positions per pool |
| `simpledex` | `deposits` | user account | Pending deposits |
| `simpledex` | `allowedctrs` | `simpledex` | Whitelisted token contracts (for `createpool`) |
| `simplelaunch` | `curves` | `simplelaunch` | Bonding curves, graduation status |
| `simplelaunch` | `holdings` | user account | Pre-graduation token holdings |
| `simplelaunch` | `fees` | `simplelaunch` | **Live** buy/sell/creation fee config |
| `simplelaunch` | `config` | `simplelaunch` | Treasury account, next token ID, paused flag |
| `simplelaunch` | `antisnipe` | `simplelaunch` | Anti-snipe windows |
| `simplelaunch` | `community` | `simplelaunch` | Token community profiles |
| `simplelaunch` | `reserved` | `simplelaunch` | Reserved symbols (cannot be launched) |
| `simplelaunch` | `hidden` | `simplelaunch` | Tokens hidden from listings |
| `simplelaunch` | `blacklist` | `simplelaunch` | Creators blocked from launching |

### Query Pool

```bash
curl -s -X POST https://api.protonnz.com/v1/chain/get_table_rows \
  -H 'Content-Type: application/json' \
  -d '{"code":"simpledex","scope":"simpledex","table":"pools","limit":50,"json":true}'
```

### Query LP Position

```bash
curl -s -X POST https://api.protonnz.com/v1/chain/get_table_rows \
  -H 'Content-Type: application/json' \
  -d '{"code":"simpledex","scope":"myaccount","table":"lp","limit":10,"json":true}'
```

### Query Live Creation Fee (changeable parameter!)

```bash
curl -s -X POST https://api.protonnz.com/v1/chain/get_table_rows \
  -H 'Content-Type: application/json' \
  -d '{"code":"simplelaunch","scope":"simplelaunch","table":"fees","limit":1,"json":true}'
# Returns: { creationFee: <raw u64>, buyFeeBps: 100, sellFeeBps: 100, creatorFeeShareBps: 5000 }
# Divide creationFee by 10000 for human XPR amount.
```

---

## DEX Swaps

### Memo-Based Swap (Recommended)

Transfer input token to `simpledex` with memo format: `swap:POOL_ID:MIN_OUT:IS_TOKEN_A_IN`

```bash
# Swap 1000 XPR for a token on pool 1 (min 950000 raw output, tokenA=XPR is input)
proton action eosio.token transfer \
  '["myaccount","simpledex","1000.0000 XPR","swap:1:950000:true"]' \
  myaccount@active
```

Multiple memo swaps can chain in a single transaction (memo-based swaps are NOT rate-limited on-chain; only direct `swap`/`multihopswap` actions hit a 1-second cooldown).

### Output Calculation (Constant Product)

```
amountOut = (reserveOut * amountIn * (10000 - feeRate))
          / (reserveIn * 10000 + amountIn * (10000 - feeRate))
```

```typescript
function calculateSwapOutput(
  amountIn: number,
  reserveIn: number,
  reserveOut: number,
  feeRate: number = 30  // 0.3% = 30 bps
): number {
  const inputWithFee = amountIn * (10000 - feeRate);
  return Math.floor((reserveOut * inputWithFee) / (reserveIn * 10000 + inputWithFee));
}
```

### Multi-Hop Swaps

Route through up to 4 pools. Deposit first, then call `multihopswap` with the pool sequence and per-hop `isTokenAIns` flags.

### Swap Constraints

| Constraint | Value |
|-----------|-------|
| Max swap | 50% of input reserve |
| Cooldown (direct actions only) | 1 second between calls |
| AMM fee | 0.3% (30 bps) — kept by LPs via reserve growth |
| Protocol fee | 50% of the fee-equivalent on output → treasury (`dex.protonnz`) |
| Effective user cost | ~0.45% total per swap |

---

## Liquidity Provision

### Add Liquidity

Deposit both tokens (two transfers), then call `execaddliq`. The first deposit into a new pool locks 1,000 LP tokens permanently (MINIMUM_LIQUIDITY constant).

**LP Token Calculation:**
- Initial: `lpTokens = sqrt(amountA * amountB) - 1000`
- Subsequent: `lpTokens = min(amountA * totalLP / reserveA, amountB * totalLP / reserveB)`

### Remove Liquidity

Call `remliquidity` with `poolId`, LP amount, and minimum outputs for slippage protection.

LPs earn the full 0.3% fee through reserve growth. No separate claim — earnings realize on withdrawal.

### Token Contract Whitelist

`createpool` requires the token contract to be whitelisted in the `allowedctrs` table on `simpledex`. Trusted contracts currently include: `eosio.token`, `simpletoken`, `xtokens`, `xmd.token`, `loan.token`, `snipcoins`. The graduation path (`gradcreate`, called inline by `simplelaunch.graduate`) bypasses the whitelist.

---

## Token Launch (Bonding Curve)

### Acting on a Specific Token — Always Fetch Live State First

```
GET https://indexer.protonnz.com/api/tokens?tokenId=N
```

Response includes `tokenId`, `symbol`, `name`, `graduated`, `dexPoolId` (if graduated), `price`, `realXpr`, `realTokensSold`, plus enough metadata to template every action below.

### Create Token (Step 1: Pay Fee)

Transfer the **live creation fee** to `simplelaunch` with memo `create`. At time of writing this fee is **20,000 XPR** (raw `200000000` in `simplelaunch::fees.creationFee`). The fee is mutable by admin, so read the table before charging:

```bash
proton action eosio.token transfer \
  '["myaccount","simplelaunch","20000.0000 XPR","create"]' \
  myaccount@active
```

### Create Token (Step 2: Register)

```bash
proton action simplelaunch createtoken \
  '["myaccount","4,MYTOKEN","My Token","A token","https://your-ipfs-gateway/ipfs/QmHash"]' \
  myaccount@active
```

- Max 7-character symbol (uppercase A-Z only)
- Symbol format: `"PRECISION,NAME"` (e.g. `"4,MYTOKEN"`)
- Image must be IPFS URL
- Some symbols are reserved (`simplelaunch::reserved`)

### Buy on Curve

```bash
# Buy with 100 XPR (minimum 5,000,000 raw tokens out for slippage protection)
proton action eosio.token transfer \
  '["myaccount","simplelaunch","100.0000 XPR","buy:1:5000000"]' \
  myaccount@active
```

Memo: `buy:TOKEN_ID[:MIN_TOKENS_OUT]`. Recommended to always include `MIN_TOKENS_OUT` (compute from current curve state via the analytics API).

### Sell on Curve

```bash
proton action simplelaunch sell \
  '["myaccount",1,5000000,8000]' \
  myaccount@active
```

Parameters: `[seller, tokenId, tokenAmount, minXprOut]`. `tokenAmount` is raw (multiply human × 10000); `minXprOut` is also raw.

### Bonding Curve Pricing

```
Buy:  tokensOut = (virtualTokens * xprAfterFee) / (virtualXpr + xprAfterFee)
Sell: xprOut    = (virtualXpr * tokensIn) / (virtualTokens + tokensIn) − sell fee
```

- Buy fee: 1% (`buyFeeBps=100`)
- Sell fee: 1% (`sellFeeBps=100`)
- 50% of fees → creator, 50% → treasury (`creatorFeeShareBps=5000`)

### Anti-Snipe Protection

| Phase | Duration | Restriction |
|-------|----------|-------------|
| Creator-only | 0–60s | Only creator can buy |
| Early bird | 60–360s | Max 5,000 XPR per transaction |
| Open | 360s+ | No restrictions |

### Graduation

When `realXpr >= 50,000 XPR`, anyone can call `graduate`:

```bash
proton action simplelaunch graduate '[1]' youraccount@active
```

This is **atomic** — a single transaction runs 7 inline actions:

1. Set graduated flag on the curve
2. Set graduated on the token contract
3. Issue DEX allocation tokens (200M = 20% of supply)
4. `gradcreate` on `simpledex` (creates the pool)
5. Transfer XPR deposit to `simpledex`
6. Transfer token deposit to `simpledex`
7. `gradaddliq` on `simpledex` adds the liquidity and sends `setpoolid` back to `simplelaunch` so the curve row records its `dexPoolId`

After graduation, users who bought on the curve must call `claim` to mint their real tokens:

```bash
proton action simplelaunch claim '["youraccount",1]' youraccount@active
```

> **Critical for V2:** Do NOT call `finishgrad`. That was the V1 two-step pattern. V2's `graduate` is one-shot atomic; calling `finishgrad` on V2 would double-deposit funds.

### Supply Model

| Allocation | Amount |
|-----------|--------|
| Max supply | 1,000,000,000 |
| Curve (virtual) | 800,000,000 (80%) |
| DEX pool (minted at graduation) | 200,000,000 (20%) |
| Typical circulating after claims | 700–750M |

Unsold curve tokens never mint. Burns work by transfer to `token.burn` (not `retire()`).

---

## Token Metadata & Moderation

### Update Token Info (Creator Only)

```bash
proton action simplelaunch updatetoken \
  '["myaccount",1,"New Name","New desc","https://..."]' \
  myaccount@active
```

### Community Profile

Creator sets for free via `setcommunit`. Non-creators pay 100,000 XPR via deposit + `updcommunit`. Fields: description, website, telegram, twitter, discord, banner image URL.

### Admin Moderation (require `protonnz@active` via msig)

| Action | Effect |
|--------|--------|
| `reservename(symbol, reserve)` | Reserve/unreserve a symbol to prevent impersonation |
| `blacklist(account, blocked)` | Block/unblock a creator from launching new tokens |
| `hidetoken(tokenId, hide)` | Hide a token from listings (still accessible via direct URL — for graceful exits) |
| `addcontract(tokenContract)` | Whitelist a token contract for `createpool` |
| `rmcontract(tokenContract)` | Remove a token contract from the whitelist |

CLI gotcha: the action name is `reservename`, not `reserve` — the latter fails with a serialization error in proton-cli.

---

## Protocol Parameters

| Parameter | Value |
|-----------|-------|
| DEX swap AMM fee | 0.3% (30 bps) |
| DEX protocol fee share | 50% to treasury |
| Max swap per tx | 50% of reserves |
| Swap cooldown (direct action) | 1 second |
| Minimum liquidity lock | 1,000 LP tokens |
| Deposit expiry | 24 hours |
| Max multi-hop | 4 pools |
| Launch buy/sell fee | 1% each |
| Creator fee share | 50% |
| Graduation threshold | 50,000 XPR |
| **Creation fee** | **20,000 XPR** (live in `simplelaunch::fees.creationFee` — always read before charging) |
| Creator-only window | 60 seconds |
| Early-bird cap | 5,000 XPR per tx for 5 minutes |
| Token precision | 4 decimals (all amounts × 10000) |

---

## Error Handling

| Error | Cause | Resolution |
|-------|-------|-----------|
| Swap exceeds maximum | Input > 50% reserve | Split into smaller swaps |
| Slippage exceeded | Price moved past minAmountOut | Increase tolerance or retry |
| Pool paused | Admin/guardian action | Use alternate pool |
| Token not graduated | DEX operation on curve token | Use `simplelaunch` buy/sell instead |
| Swap cooldown active | < 1 second elapsed (direct action only) | Wait, or use memo-based swap |
| Deposit expired | > 24 hours old | Withdraw and re-deposit |
| Symbol reserved | Tried to create a reserved ticker | Pick a different symbol |
| Creator blacklisted | Account is in `simplelaunch::blacklist` | Cannot launch; can still trade |
| Token contract not whitelisted | `createpool` on a contract not in `allowedctrs` | Use a whitelisted contract |
| Insufficient RAM | Account storage limit | Buy RAM via the resources portal |

---

## Resources

- **Frontend:** https://simpledex.fun (canonical) — legacy `dex.protonnz.com` still serves and emits the new canonical
- **Agent Guide (index):** https://simpledex.fun/llms.txt
- **Agent Guide (full):** https://simpledex.fun/llms-full.txt
- **Topic files (recommended — smaller for chunked agent reads):**
  - https://simpledex.fun/llms-setup.txt — CLI + key/account setup
  - https://simpledex.fun/llms-analytics.txt — read-only API
  - https://simpledex.fun/llms-trading.txt — swaps + liquidity
  - https://simpledex.fun/llms-launches.txt — bonding curve + token creation
  - https://simpledex.fun/llms-reference.txt — params, patterns, errors
- **Testnet:** https://testnet.dex.protonnz.com
- **Testnet Agent Guide:** https://testnet.dex.protonnz.com/llms-testnet.txt
- **Official X:** [@SimpleDEXFun](https://x.com/SimpleDEXFun)
- **Report Bugs:** https://protonnz.com
