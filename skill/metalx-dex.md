# MetalX DEX API Reference

> Complete API documentation for MetalX Decentralized Exchange on XPR Network

## Overview

MetalX is the primary decentralized exchange on XPR Network - a peer-to-peer marketplace for cryptocurrency trading with no gas fees.

### Features

- **Order Book Trading** - Limit, market, stop loss, take profit orders
- **Swap** - Instant token swaps via liquidity pools
- **Pools & Farms** - Yield farming and liquidity provision
- **Stop Loss / Take Profit** - Advanced order types

## Base URLs

| Environment | API Base URL | RPC URL |
|-------------|--------------|---------|
| **Mainnet** | `https://dex.api.mainnet.metalx.com` | `https://rpc.api.mainnet.metalx.com` |
| **Testnet** | `https://dex.api.testnet.metalx.com` | `https://rpc.api.testnet.metalx.com` |

### RPC Fallback Endpoints

If the primary RPC is unavailable, use these alternatives for chain queries:

1. `https://proton.eosusa.io` (recommended)
2. `https://proton.protonuk.io`
3. `https://proton.cryptolions.io`

> ⚠️ **CRITICAL: DEX Token Deposits**
>
> When transferring tokens to the `dex` contract for order placement, the memo **MUST be an empty string** (`""`).
> Using any other memo (e.g., `"deposit"`) will result in tokens being **permanently stuck** in the contract with no way to recover them.
> The `withdrawall` action will NOT return tokens deposited with a wrong memo.
>
> ```bash
> # ✅ CORRECT — empty memo
> proton action eosio.token transfer '{"from":"myaccount","to":"dex","quantity":"1000.0000 XPR","memo":""}' myaccount
>
> # ❌ WRONG — tokens will be lost forever
> proton action eosio.token transfer '{"from":"myaccount","to":"dex","quantity":"1000.0000 XPR","memo":"deposit"}' myaccount
> ```

---

## REST API Endpoints

### Markets

#### Get Markets
```
GET /dex/v1/markets/all
```
Returns all available trading markets/pairs.

#### Get OHLCV Chart
```
GET /dex/v1/chart/ohlcv
```
Returns OHLCV (Open, High, Low, Close, Volume) chart data.

**Query Parameters** (verified live):
- `symbol` (required) — market symbol, e.g. `XPR_XMD` (**not** `market_id`)
- `interval` (required) — one of `1D` (daily), `240` (4h), `60` (1h), `15` (15m), `5` (5m). Values like `1h` or `86400` return `Invalid interval`.
- `from` / `to` (required) — **ISO date strings** (e.g. `2026-05-09`), not epoch timestamps. Epoch values return HTTP 500.

```bash
curl "https://dex.api.mainnet.metalx.com/dex/v1/chart/ohlcv?symbol=XPR_XMD&interval=1D&from=2026-05-09&to=2026-05-16"
# → { sync, data: [{ time (ms), open, high, low, close, volume, volume_bid, count }] }
```

---

### Account

#### Get Account Balances
```
GET /dex/v1/account/balances
```

#### Get Transaction
```
GET /dex/v1/history/transaction
```

#### Get Actions
```
GET /dex/v1/history/actions
```

#### Get Transfers
```
GET /dex/v1/history/transfers
```

---

### Orders

#### Get Open Orders
```
GET /dex/v1/orders/open
```

#### Get Orders History
```
GET /dex/v1/orders/history
```

#### Get Orderbook Depth
```
GET /dex/v1/orders/depth
```

#### Get Order Lifecycle
```
GET /dex/v1/orders/lifecycle
```

**Query Parameters:**
- `ordinal_order_id` (string): The ordinal order ID (fork-resistant identifier)

**Example:**
```bash
curl "https://dex.api.mainnet.metalx.com/dex/v1/orders/lifecycle?ordinal_order_id=81321dc485b5dd8053c4b7d0c90273ce72645b4127524d1745aebe8b4f795e21"
```

#### Submit Order
```
POST /dex/v1/orders/submit
```

**Request Body:**
```json
{
  "serialized_tx_hex": "<hex_encoded_transaction>",
  "signatures": ["<signature>"]
}
```

**Response:**
Returns `order_id`, `ordinal_order_id`, and status of orders created.

#### Serialize Order
```
POST /dex/v1/orders/serialize
```

---

### Trades

#### Get Trades History
```
GET /dex/v1/trades/history
```

#### Get Daily Stats
```
GET /dex/v1/trades/daily
```

#### Get Recent Trades
```
GET /dex/v1/trades/recent
```

---

### Miscellaneous

#### Get Latest Sync Time
```
GET /dex/v1/status/sync
```

#### Get Sync History
```
GET /dex/v1/status/sync-history
```

#### Get Referral Totals
```
GET /dex/v1/referrals/totals
```

#### Get Referrals
```
GET /dex/v1/referrals/list
```

#### Get Leaderboard
```
GET /dex/v1/leaderboard/list
```

**Query Parameters:**
- `market_ids[]` (array, required): Market identifiers (e.g., `["1", "2"]`)
- `from` (string, required): Start date
- `to` (string, required): End date

**Example Response:**
```json
{
  "sync": 162062950,
  "data": [
    {"user": "jaytest", "total": 1000},
    {"user": "jaytest2", "total": 900}
  ]
}
```

#### Get Tax Exports
```
GET /dex/v1/tax/user
```

---

## Known Markets

Live MetalX DEX markets (18 total, May 2026 snapshot). The `market_id` is what you pass to `placeorder` etc. **Markets can be added or status-changed** — query `/dex/v1/markets/all` for the current set rather than hard-coding IDs in production tooling.

| ID | Symbol | Notes |
|----|--------|-------|
| 1 | `XPR_XMD` | |
| 2 | `XBTC_XMD` | **0% trading fees** (per [docs.metalx.com](https://docs.metalx.com/dex/what-is-metal-x/dex-fees-and-discounts)) |
| 3 | `XETH_XMD` | |
| 4 | `XMD_XUSDT` | Stablecoin pair |
| 5 | `XPR_XUSDC` | |
| 6 | `XBTC_XUSDC` | |
| 7 | `XMT_XMD` | |
| 8 | `XMT_XUSDC` | |
| 9 | `LOAN_XMD` | |
| 10 | `METAL_XMD` | |
| 11 | `XDC_XMD` | |
| 12 | `XDOGE_XMD` | |
| 13 | `XHBAR_XMD` | |
| 14 | `XLTC_XMD` | |
| 15 | `XXRP_XMD` | |
| 16 | `XSOL_XMD` | |
| 17 | `XXLM_XMD` | |
| 18 | `XADA_XMD` | |

```bash
# Fetch the current set
curl -s "https://dex.api.mainnet.metalx.com/dex/v1/markets/all" | jq '.data[] | {market_id, symbol, status_code}'
```

---

## Contract Mappings

### Order Types

| Value | Type | Description |
|-------|------|-------------|
| `0` | Orderbook | Order sitting in the order book waiting to be matched (internal state, not user-placeable) |
| `1` | Limit | Limit order with specified price. For **Market Buy**: set `price = 9223372036854775806`. For **Market Sell**: set `price = 1` |
| `2` | Stop Loss | Triggers when price drops to `trigger_price`, then executes at `price` |
| `3` | Take Profit | Triggers when price rises to `trigger_price`, then executes at `price` |

> **Note:** Market orders must use `fill_type = 1` (IOC - Immediate Or Cancel)

### Fill Types

| Value | Type | Description |
|-------|------|-------------|
| `0` | GTC | Good Till Cancel - order remains until filled or canceled |
| `1` | IOC | Immediate Or Cancel - fills immediately or cancels unfilled portion |
| `2` | POST_ONLY | Only adds liquidity; cancels if would match existing orders |

### Order Side

| Value | Side |
|-------|------|
| `1` | Buy |
| `2` | Sell |

### Order Status

| Status | Description |
|--------|-------------|
| `create` | Order successfully added to order queue |
| `transfer` | Order promoted to order book (eligible for execution based on last execution price) |
| `update` | Partial fill - represents remaining pending quantity |
| `cancel` | Remaining quantity canceled by user |
| `delete` | Order fully executed |

### Market Status Codes

| Value | Status | Description |
|-------|--------|-------------|
| `0` | INACTIVE | Market not active; orders cannot be placed |
| `1` | ACTIVE | Market active; orders can be placed |
| `2` | NOT_IN_USE | Market permanently disabled |
| `3` | DISABLE_ORDERS | New orders disabled; existing orders still processed |
| `4` | DISABLE_FILLS | Order matching disabled |
| `5` | DISABLE_ORDERS_FILLS | Both new orders and matching disabled |
| `6` | DISABLE_STOPLOSS_TAKEPROFIT | Stop loss and take profit orders disabled |

---

## Smart Contract

**Contract Account:** `dex`

### Actions

#### placeorder

Creates a new order and places it into the order queue or stop-loss/take-profit table.

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `market_id` | uint16 | Yes | Market pair ID |
| `account` | name | Yes | Account placing the order |
| `order_type` | uint8 | Yes | `1`=Limit, `2`=StopLoss, `3`=TakeProfit |
| `order_side` | uint8 | Yes | `1`=Buy, `2`=Sell |
| `quantity` | uint64 | Yes | Amount in raw units (e.g., `700.0000 XPR` → `7000000`) |
| `price` | uint64 | Yes | Price in raw units (e.g., `0.0021` with 6 decimals → `2100`) |
| `bid_symbol` | extended_symbol | Yes | `{sym: "PRECISION,SYMBOL", contract: "contract_name"}` |
| `ask_symbol` | extended_symbol | Yes | `{sym: "PRECISION,SYMBOL", contract: "contract_name"}` |
| `trigger_price` | uint64 | No | Required for stop loss/take profit orders; `0` otherwise |
| `fill_type` | uint8 | No | `0`=GTC, `1`=IOC, `2`=POST_ONLY |
| `referrer` | name | No | Referrer account (cannot be self) |

**Example:**
```json
{
  "account": "dex",
  "name": "placeorder",
  "data": {
    "market_id": 1,
    "account": "trader",
    "order_type": 1,
    "order_side": 2,
    "quantity": 7000000,
    "price": 2100,
    "bid_symbol": {
      "sym": "4,XPR",
      "contract": "eosio.token"
    },
    "ask_symbol": {
      "sym": "6,XMD",
      "contract": "xmd.token"
    },
    "trigger_price": 0,
    "fill_type": 0,
    "referrer": ""
  }
}
```

#### cancelorder

Cancels an order in the order queue, stop-loss table, or order book.

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `account` | name | Yes | Account that owns the order |
| `order_id` | uint64 | Yes | Order ID to cancel |

**Example:**
```json
{
  "account": "dex",
  "name": "cancelorder",
  "data": {
    "account": "alice",
    "order_id": 23
  }
}
```

#### process

Processes orders in the order queue across all markets.

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `q_size` | uint16 | Yes | Number of orders to process |
| `show_error_msg` | uint8 | No | `0` = suppress, `1` = show errors |

**Example:**
```json
{
  "account": "dex",
  "name": "process",
  "data": {
    "q_size": 20,
    "show_error_msg": 0
  }
}
```

#### processsltp

Processes stop-loss and take-profit orders for a specific market.

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `market_id` | uint16 | Yes | Market ID to process |
| `size` | uint16 | Yes | Number of orders to process |

**Example:**
```json
{
  "account": "dex",
  "name": "processsltp",
  "data": {
    "market_id": 2,
    "size": 20
  }
}
```

#### withdrawall

Withdraws all funds from DEX back to user's wallet.

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `account` | name | Yes | Account to withdraw funds for |

---

## Common Errors

### Place Order Errors

| Error Message | Cause |
|---------------|-------|
| `Contract is paused` | DEX contract is temporarily paused |
| `Market not found` | Invalid `market_id` |
| `Placing orders is disabled for this market` | Market status prevents new orders |
| `Invalid order type` | `order_type` must be `1`, `2`, or `3` |
| `Invalid order side` | `order_side` must be `1` (Buy) or `2` (Sell) |
| `Invalid price` | Price must be between `0` and `INT_MAX` |
| `Minimum order size is ...` | Order quantity below market minimum |
| `Invalid order type - add trigger price` | Stop loss/take profit requires `trigger_price > 0` |
| `Invalid referrer name, self referral not allowed` | Cannot set yourself as referrer |

### Cancel Order Errors

| Error Message | Cause |
|---------------|-------|
| `Contract is paused` | DEX contract is temporarily paused |
| `Invalid authorization` | User not authorized to cancel this order |
| `Invalid order id` | `order_id` must be greater than `0` |
| `Order not found` | Order doesn't exist or already executed |
| `Accounts mismatch, order cancellation not allowed` | Account doesn't own this order |
| `Market not found` | Order references non-existent market |

---

## Code Examples

### JavaScript: Submit Order

This places an order **directly on-chain** through the keychain-backed CLI session. The MetalX matching engine picks the order up from its chain indexer — you don't need to POST to `/orders/submit` for the order to exist. Look the resulting order up via `/orders/lifecycle` (see below) if you need MetalX's `ordinal_order_id`. If you need that ID synchronously in the submit response, see the legacy `signatureProvider` variant after this snippet.

```javascript
// Recommended: route signing through the proton CLI keychain (key never in process).
// One-time setup outside this script: `proton key:add` to load your key.
// See backend-patterns.md "Security: Key Isolation" for context.
const { createCliSession } = require('@xpr-agents/openclaw');

const USERNAME = 'youraccount';

const { rpc, session } = createCliSession({
  account: USERNAME,
  permission: 'active',
  rpcEndpoint: 'https://rpc.api.mainnet.metalx.com',
});

// `session.link.transact(...)` shells out to `proton transaction:push`.
// It always broadcasts and returns { transaction_id, processed } —
// there is no broadcast:false / serializedTransaction path on this shape.

const authorization = [{ actor: USERNAME, permission: 'active' }];

// Order parameters
const MARKET_ID = 1;
const ORDER_SIDE = 2;        // Sell
const ORDER_TYPE = 1;        // Limit
const FILL_TYPE = 0;         // GTC
const PRICE = 0.0021;
const AMOUNT = 700;

const BID_TOKEN = { contract: 'eosio.token', symbol: 'XPR', precision: 4 };
const ASK_TOKEN = { contract: 'xmd.token', symbol: 'XMD', precision: 6 };

const actions = [
  {
    account: BID_TOKEN.contract,
    name: 'transfer',
    data: {
      from: USERNAME,
      to: 'dex',
      quantity: `${AMOUNT.toFixed(BID_TOKEN.precision)} ${BID_TOKEN.symbol}`,
      memo: ''
    },
    authorization
  },
  {
    account: 'dex',
    name: 'placeorder',
    data: {
      market_id: MARKET_ID,
      account: USERNAME,
      order_type: ORDER_TYPE,
      order_side: ORDER_SIDE,
      fill_type: FILL_TYPE,
      bid_symbol: { sym: `${BID_TOKEN.precision},${BID_TOKEN.symbol}`, contract: BID_TOKEN.contract },
      ask_symbol: { sym: `${ASK_TOKEN.precision},${ASK_TOKEN.symbol}`, contract: ASK_TOKEN.contract },
      referrer: '',
      quantity: (AMOUNT * Math.pow(10, BID_TOKEN.precision)).toFixed(0),
      price: (PRICE * Math.pow(10, ASK_TOKEN.precision)).toFixed(0),
      trigger_price: 0
    },
    authorization
  },
  {
    account: 'dex',
    name: 'process',
    data: { q_size: 25, show_error_msg: 0 },
    authorization
  }
];

async function submitOrder() {
  // Atomic on-chain submission: transfer → placeorder → process in one tx.
  const { transaction_id, processed } = await session.link.transact({ actions });
  return { transaction_id, block_num: processed.block_num };
}
```

<details>
<summary>Legacy: <code>signatureProvider</code> for MetalX's <code>/orders/submit</code> endpoint (NOT recommended)</summary>

Use this **only** if you need the matching engine's `ordinal_order_id` in the submit response and can't wait for the chain indexer. `/orders/submit` wants a **signed-but-not-broadcast** serialized transaction, which `createCliSession` cannot produce — it always broadcasts. This is one of the few documented exceptions where the keychain pattern doesn't apply; the private key has to be in process memory long enough to sign locally.

```javascript
const { JsonRpc, Api } = require('@proton/js');
const { JsSignatureProvider } = require('eosjs/dist/eosjs-jssig');
const fetch = require('node-fetch');

const PRIVATE_KEY = process.env.XPR_PRIVATE_KEY; // ⚠️ key in process memory
const rpc = new JsonRpc('https://rpc.api.mainnet.metalx.com');
const api = new Api({
  rpc,
  signatureProvider: new JsSignatureProvider([PRIVATE_KEY]),
  textDecoder: new TextDecoder(),
  textEncoder: new TextEncoder(),
});

const SUBMIT_URL = 'https://dex.api.mainnet.metalx.com/dex/v1/orders/submit';

async function submitViaMatchingEngine(actions) {
  const { serializedTransaction, signatures } = await api.transact(
    { actions },
    { blocksBehind: 300, expireSeconds: 3000, broadcast: false }
  );

  const response = await fetch(SUBMIT_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      serialized_tx_hex: Buffer.from(serializedTransaction).toString('hex'),
      signatures,
    }),
  });

  return response.json(); // includes order_id and ordinal_order_id
}
```

</details>


### JavaScript: Cancel Order

```javascript
const actions = [
  {
    account: 'dex',
    name: 'cancelorder',
    data: { account: USERNAME, order_id: 23 },
    authorization
  },
  {
    account: 'dex',
    name: 'withdrawall',
    data: { account: USERNAME },
    authorization
  }
];
```

### JavaScript: Get Order Lifecycle

```javascript
const fetch = require('node-fetch');

async function getOrderLifecycle(ordinalId) {
  const url = `https://dex.api.mainnet.metalx.com/dex/v1/orders/lifecycle?ordinal_order_id=${ordinalId}`;
  const response = await fetch(url);
  return response.json();
}
```

### Python: Submit Order

Python signs and broadcasts via the **proton CLI keychain** through `subprocess` — the private key never enters the Python process. Same key-isolation guarantee as the JS path above; see `backend-patterns.md` "Security: Key Isolation" for the rationale.

One-time setup outside this script: `proton key:add` to load your key into the CLI keychain. The Python script needs no `XPR_PRIVATE_KEY`, no `.env`, no `pyeoskit`.

```python
import json
import subprocess
from math import pow

USERNAME = 'youraccount'

# Order parameters
MARKET_ID = 1
ORDER_SIDE = 2   # Sell
ORDER_TYPE = 1   # Limit
FILL_TYPE = 0    # GTC
PRICE = 0.0021
AMOUNT = 700

BID_TOKEN = {'contract': 'eosio.token', 'symbol': 'XPR', 'precision': 4}
ASK_TOKEN = {'contract': 'xmd.token', 'symbol': 'XMD', 'precision': 6}


def proton_action(contract: str, name: str, data: dict) -> str:
    """Run one signed action via the proton CLI. Private key never enters Python."""
    result = subprocess.run(
        ['proton', 'action', contract, name, json.dumps(data), USERNAME],
        check=True, capture_output=True, text=True,
    )
    return result.stdout


# 1) Deposit XPR to the DEX (empty memo is mandatory — see warning above)
proton_action(BID_TOKEN['contract'], 'transfer', {
    'from': USERNAME,
    'to': 'dex',
    'quantity': f'{AMOUNT:.{BID_TOKEN["precision"]}f} {BID_TOKEN["symbol"]}',
    'memo': '',
})

# 2) Place the order
proton_action('dex', 'placeorder', {
    'market_id': MARKET_ID,
    'account': USERNAME,
    'order_type': ORDER_TYPE,
    'order_side': ORDER_SIDE,
    'fill_type': FILL_TYPE,
    'bid_symbol': {'sym': f'{BID_TOKEN["precision"]},{BID_TOKEN["symbol"]}', 'contract': BID_TOKEN['contract']},
    'ask_symbol': {'sym': f'{ASK_TOKEN["precision"]},{ASK_TOKEN["symbol"]}', 'contract': ASK_TOKEN['contract']},
    'referrer': '',
    'quantity': int(AMOUNT * pow(10, BID_TOKEN['precision'])),
    'price': int(PRICE * pow(10, ASK_TOKEN['precision'])),
    'trigger_price': 0,
})

# 3) Tick the order queue
proton_action('dex', 'process', {'q_size': 25, 'show_error_msg': 0})
```

> **Atomicity trade-off.** The original Python example bundled all three actions into a single atomic EOSIO transaction (via `pyeoskit.generate_packed_transaction`). This rewrite runs each action as its own `proton action` call to keep the private key in the CLI keychain. If step 2 or 3 fails, step 1's deposit is recoverable via `proton action dex withdrawall '{"account":"youraccount"}' youraccount` — the funds aren't lost, they sit in the user's DEX deposit balance until withdrawn or used.
>
> If you need atomic multi-action signing, use the **JavaScript path above** — `createCliSession.link.transact({ actions })` bundles every action into a single on-chain transaction. If you specifically need MetalX's `/orders/submit` endpoint (e.g. for the synchronous `ordinal_order_id` in the response), no keychain path works: the endpoint wants a signed-but-not-broadcast serialized tx, which neither `createCliSession` nor `proton transaction:push` will produce. See the `<details>` legacy block under the JS Submit Order snippet for the `signatureProvider`-based escape hatch, and prefer the on-chain path plus `/orders/lifecycle` lookup unless you genuinely need the synchronous ID. `proton transaction` at the CLI level would be the obvious Python atomic equivalent, but `@proton/cli@0.1.98`'s `transaction` command is currently broken (missing `JSON.parse` on its argument; tracked upstream).

### Python: Get Order Lifecycle

```python
import requests

ordinal_id = '7c58750548702a4a8dc30aebe21fb1885923b7db42dbe81239f5a64e672b82d7'
url = f'https://dex.api.mainnet.metalx.com/dex/v1/orders/lifecycle?ordinal_order_id={ordinal_id}'

response = requests.get(url, headers={'accept': 'application/json'})
print(response.json())
```

---

## Frontend Integration

### TypeScript Service Class

```typescript
class MetalXService {
  private baseUrl = 'https://dex.api.mainnet.metalx.com';

  // Get all markets
  async getMarkets() {
    const res = await fetch(`${this.baseUrl}/dex/v1/markets/all`);
    return res.json();
  }

  // Get order book depth — takes symbol + step, NOT market_id
  async getOrderbook(symbol: string, step: number = 0.0001) {
    const res = await fetch(`${this.baseUrl}/dex/v1/orders/depth?symbol=${symbol}&step=${step}`);
    return res.json();
  }

  // Get account balances
  async getBalances(account: string) {
    const res = await fetch(`${this.baseUrl}/dex/v1/account/balances?account=${account}`);
    return res.json();
  }

  // Get open orders
  async getOpenOrders(account: string) {
    const res = await fetch(`${this.baseUrl}/dex/v1/orders/open?account=${account}`);
    return res.json();
  }

  // Get recent trades — takes symbol, NOT market_id
  async getRecentTrades(symbol: string) {
    const res = await fetch(`${this.baseUrl}/dex/v1/trades/recent?symbol=${symbol}`);
    return res.json();
  }

  // Get OHLCV data — takes symbol (not market_id); from/to are ISO date strings
  async getOHLCV(
    symbol: string,
    interval: '1D' | '240' | '60' | '15' | '5',
    from: string,  // ISO date, e.g. '2026-05-09' — epoch timestamps return HTTP 500
    to: string
  ) {
    const res = await fetch(
      `${this.baseUrl}/dex/v1/chart/ohlcv?symbol=${symbol}&interval=${interval}&from=${from}&to=${to}`
    );
    return res.json();
  }
}
```

---

## Libraries & Dependencies

Both paths assume the proton CLI is installed system-wide and your account's key has been added to its keychain:

```bash
npm install -g @proton/cli
proton key:add   # one-time, prompts for the private key, stores it encrypted in the OS keychain
```

### JavaScript
```bash
npm install @xpr-agents/openclaw node-fetch
```

`@xpr-agents/openclaw` provides `createCliSession`, which routes signing through `proton transaction:push` so the private key never enters the Node process. See `backend-patterns.md` "Security: Key Isolation".

### Python
```bash
pip install requests
```

That's the entire Python dependency footprint — no `pyeoskit`, no key library, no build toolchain. Signing happens in `proton` via `subprocess`; Python only constructs the action JSON and reads the result.

---

## Fee Structures

### DEX Trading Fees

#### Volume-Based Tiers (30-Day Volume)

| Tier | Volume | Maker Fee | Taker Fee |
|------|--------|-----------|-----------|
| I | < $250,000 | 0.10% | 0.10% |
| II | ≥ $250,000 | 0.08% | 0.08% |
| III | ≥ $500,000 | 0.06% | 0.06% |
| IV | ≥ $750,000 | 0.04% | 0.04% |
| V | ≥ $1,000,000 | 0.02% | 0.02% |
| VIP | ≥ $1,250,000 | 0.01% | 0.01% |
| Market Maker | - | 0% | 0% |

#### Staking-Based Discounts (Staked XPR)

| Tier | Staked XPR | Maker Fee | Taker Fee |
|------|------------|-----------|-----------|
| I | < 1,000,000 | 0.10% | 0.10% |
| II | ≥ 1,000,000 | 0.08% | 0.08% |
| III | ≥ 10,000,000 | 0.06% | 0.06% |
| IV | ≥ 20,000,000 | 0.04% | 0.04% |
| V | ≥ 60,000,000 | 0.02% | 0.02% |
| VIP | ≥ 100,000,000 | 0% | 0% |

#### NFT DEX Key Discount

Holders of limited edition NFT DEX Keys receive **100% fee discount**.

#### 0% Trading Fees on the XBTC Market

The **XBTC/XMD** market on the DEX has **zero trading fees** for all users regardless of tier. Documented at [docs.metalx.com → DEX fees and discounts](https://docs.metalx.com/dex/what-is-metal-x/dex-fees-and-discounts).

### Swap Fees

Canonical source: [docs.metalx.com → Swap fees and discounts](https://docs.metalx.com/swap-pools-and-farms/what-is-metal-x-swap/swap-fees-and-discounts).

**Per-trade fee on MetalX Swap: 0.3%**, split as:

- **0.2% → Liquidity providers** (LPs) of that pool
- **0.1% → XPR burns or XPR Grants** — converted to XPR and burned, or added to XPR Grants, at the end of each quarter

The MetalX Swap UI sits on top of the on-chain `proton.swaps` contract. For programmatic integrators talking to `proton.swaps` directly (without going through the MetalX UI), see [`defi-trading.md`](./defi-trading.md#proton-swaps-amm-liquidity-pools) for the AMM math, swap snippet, and contract-level details.

#### Swap Fee Discounts (by Staked XPR)

| Staked XPR | Discount |
|------------|----------|
| ≥ 100,000 | 33% |
| ≥ 1,000,000 | 66% |
| ≥ 10,000,000 | 100% |

### Referral Program

| Type | Discount/Reward |
|------|-----------------|
| Referrer | 25% of fees |
| Referee | 5% discount |

*Applies to DEX only (not Swap). Referee rewards last 1 year.*

---

## Swap (AMM)

MetalX Swap is an automated market maker (AMM) for instant token swaps.

> **Under the hood:** the MetalX Swap UI is a front-end on top of the chain-native **`proton.swaps`** contract — same pools, same liquidity, same v2 constant-product math. The MetalX app handles wallet, routing and fees-discount logic, but the on-chain venue is `proton.swaps`. For contract-level details (pool table layout, swap memo format, `liquidityadd` / `liquidityrmv` actions, multi-hop), see [`defi-trading.md`](./defi-trading.md) — the "Proton Swaps (AMM Liquidity Pools)" section. Programmatic integrators talk to `proton.swaps` directly; there is no separate MetalX-branded swap contract on chain (verified via `get_account` against likely candidates like `metalx.swap`, `swap.metalx`, etc. — none exist).

### Available Swap Tokens (actively traded, May 2026)

`XPR`, `XUSDC`, `XUSDT`, `XMD`, `METAL`, `XMT`, `LOAN`, `XBTC`, `XETH`, `XBNB`, `XADA`, `XLTC`, `XEOS`, `XDOGE`, `SNIPS`

The canonical MetalX [Swap FAQ](https://docs.metalx.com/swap-pools-and-farms/what-is-metal-x-swap/metal-x-swap-faq) lists additional historical tokens (e.g. `STRX`, `MINT`, `XUNI`, `XBCH`, `XLUNR`) that have very low or no recent on-chain activity. The list above filters to pools with measurable swap volume in the last 500 chain-recorded swaps. Query the `pools` table on `proton.swaps` for the complete on-chain set:

```bash
curl -s -X POST https://proton.eosusa.io/v1/chain/get_table_rows \
  -H 'Content-Type: application/json' \
  -d '{"code":"proton.swaps","scope":"proton.swaps","table":"pools","json":true,"limit":100}'
```

### Wrapped Tokens

Wrapped tokens (X-prefixed) are assets from other blockchains converted to XPR Network:
- Instant transaction times
- Near-zero fees
- 1:1 backing with original asset

### DEX vs Swap Comparison

| Feature | DEX | Swap |
|---------|-----|------|
| Type | Orderbook | AMM |
| Order Types | Limit, Market, Stop Loss, Take Profit | Market only |
| Fee | 0.01-0.10% | 0.3% |
| Best For | Precise price control | Instant trades |
| Liquidity | Order book depth | Pool liquidity |

---

## Liquidity Pools

### How Pools Work

1. Add equal USD value of both tokens in a pair
2. Receive LP (Liquidity Provider) tokens
3. Earn 0.2% of every trade proportional to your pool share
4. Withdraw anytime (no lockup period)

### Example

```
Pool: 9,000 XUSDC + 900,000 XPR
You add: 1,000 XUSDC + 100,000 XPR (10% of pool)
You earn: 10% of the 0.2% trading fees
```

### Impermanent Loss

When token prices change relative to deposit time, you may experience impermanent loss. Larger price changes = bigger loss.

---

## Farming (Yield Farming)

### How Farming Works

1. Become a liquidity provider (get LP tokens)
2. Stake LP tokens in farms
3. Earn rewards (variable APR)
4. Harvest rewards anytime

**Key Points:**
- **No lockup period** - withdraw anytime
- **Variable APR** - changes based on total staked and reward token value

---

## DEX Bot (Trading Bot)

Official open-source trading bot for automated trading on MetalX.

**Repository:** https://github.com/XPRNetwork/dex-bot

### Bot Types

#### Grid Bot
- Automatically buy low, sell high within price range
- Best for volatile markets
- Configurable grid levels and amounts

#### Market Maker Bot
- Places ladder of buy/sell orders around base price
- Direction-agnostic strategy
- Provides liquidity to order book

### Configuration Example

```json
{
  "cancelOpenOrdersOnExit": true,
  "strategy": "gridBot",
  "gridBot": {
    "pairs": [
      {
        "symbol": "XPR_XMD",
        "upperLimit": 0.0009000,
        "lowerLimit": 0.0006000,
        "gridLevels": 14,
        "bidAmountPerLevel": 40000
      }
    ]
  }
}
```

### Running the Bot

> ⚠️ **Security note.** The upstream `XPRNetwork/dex-bot` configuration uses `PROTON_PRIVATE_KEY` as an environment variable — i.e., the bot's process memory holds the chain key for its entire runtime. This is the pattern that's now discouraged for any server-side XPR signing; see [`backend-patterns.md`](./backend-patterns.md#security-key-isolation) for the rationale and the `createCliSession` (proton CLI keychain) path that keeps keys out of process memory. The commands below reflect the upstream README; if you adapt the bot to your own fork, prefer the keychain pattern.

```bash
# Clone repository
git clone https://github.com/XPRNetwork/dex-bot.git
cd dex-bot
npm install

# Upstream configuration — key in process memory (NOT recommended for production)
export PROTON_USERNAME=your_username
export PROTON_PRIVATE_KEY=your_private_key

# Run bot
npm run bot

# Stop: Ctrl+C
```

**Important Notes:**
- Minimum order: $1 or 1 XMD
- Bot auto-replaces filled orders
- **For production:** migrate to the proton CLI keychain pattern — see [`backend-patterns.md`](./backend-patterns.md#security-key-isolation) and [`agent-bootstrap.md`](../agent-bootstrap.md) Step 2
- Verify identity at https://identity.metalx.com if needed

---

## Bridge Withdrawal Fees

| Token | Fee |
|-------|-----|
| ADA | 1 |
| DOGE | 5 |
| EOS | 0.2 |
| HBAR | 10 |
| SOL | 0.01 |
| USDC | 1 |
| XLM | 1 |
| XRP | 0.5 |
| XPR | FREE |

*Bridge deposit fee: 0%*

---

## Additional Resources

- **MetalX App:** https://app.metalx.com
- **API Docs:** https://api.dex.docs.metalx.com/
- **Developer Docs:** https://docs.metalx.com/
- **WebAuth Wallet:** https://webauth.com/
- **DEX Bot:** https://github.com/XPRNetwork/dex-bot
- **LOAN Protocol:** https://lending.docs.metalx.com
- **Identity Verification:** https://identity.metalx.com
- **Support:** https://help.xprnetwork.org/
