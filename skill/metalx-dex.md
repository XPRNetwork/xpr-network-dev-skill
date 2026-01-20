# Metal X DEX API Reference

> Complete API documentation for Metal X Decentralized Exchange on XPR Network

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

## Contract Mappings

### Order Types

| Value | Type | Description |
|-------|------|-------------|
| `0` | Orderbook | Order sitting in orderbook waiting to be matched (internal state, not user-placeable) |
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
| `transfer` | Order promoted to orderbook (eligible for execution based on last execution price) |
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

Cancels an order in the order queue, stop-loss table, or orderbook.

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

```javascript
const { JsonRpc, Api, JsSignatureProvider } = require('@proton/js');
const fetch = require('node-fetch');

const ENDPOINTS = ['https://rpc.api.mainnet.metalx.com'];
const SUBMIT_URL = 'https://dex.api.mainnet.metalx.com/dex/v1/orders/submit';
const PRIVATE_KEY = 'YOUR_PRIVATE_KEY';

const rpc = new JsonRpc(ENDPOINTS);
const api = new Api({
  rpc,
  signatureProvider: new JsSignatureProvider([PRIVATE_KEY])
});

const USERNAME = 'youraccount';
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
  const { serializedTransaction, signatures } = await api.transact(
    { actions },
    { blocksBehind: 300, expireSeconds: 3000, broadcast: false }
  );

  const response = await fetch(SUBMIT_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      serialized_tx_hex: Buffer.from(serializedTransaction).toString('hex'),
      signatures
    })
  });

  return response.json();
}
```

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

```python
import json
import requests
from pyeoskit import eosapi, wallet
from math import pow

wallet.import_key('mywallet', 'YOUR_PRIVATE_KEY')
eosapi.set_node('https://rpc.api.mainnet.metalx.com')

USERNAME = 'youraccount'
SUBMIT_URL = 'https://dex.api.mainnet.metalx.com/dex/v1/orders/submit'

# Order parameters
MARKET_ID = 1
ORDER_SIDE = 2  # Sell
ORDER_TYPE = 1  # Limit
FILL_TYPE = 0   # GTC
PRICE = 0.0021
AMOUNT = 700

BID_TOKEN = {'contract': 'eosio.token', 'symbol': 'XPR', 'precision': 4}
ASK_TOKEN = {'contract': 'xmd.token', 'symbol': 'XMD', 'precision': 6}

permission = {USERNAME: 'active'}

args1 = {
    'from': USERNAME,
    'to': 'dex',
    'quantity': f'{AMOUNT:.{BID_TOKEN["precision"]}f} {BID_TOKEN["symbol"]}',
    'memo': ''
}

args2 = {
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
    'trigger_price': 0
}

args3 = {'q_size': 20, 'show_error_msg': 0}

a1 = [BID_TOKEN['contract'], 'transfer', args1, permission]
a2 = ['dex', 'placeorder', args2, permission]
a3 = ['dex', 'process', args3, permission]

# Generate and submit transaction
info = eosapi.get_info()
final_tx = eosapi.generate_packed_transaction(
    [a1, a2, a3], 60,
    info['last_irreversible_block_id'],
    info['chain_id']
)
mtx = json.loads(final_tx)

response = requests.post(SUBMIT_URL, json={
    'serialized_tx_hex': mtx['packed_trx'],
    'signatures': mtx['signatures']
})
print(response.json())
```

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

  // Get orderbook depth
  async getOrderbook(marketId: number) {
    const res = await fetch(`${this.baseUrl}/dex/v1/orders/depth?market_id=${marketId}`);
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

  // Get recent trades
  async getRecentTrades(marketId: number) {
    const res = await fetch(`${this.baseUrl}/dex/v1/trades/recent?market_id=${marketId}`);
    return res.json();
  }

  // Get OHLCV data
  async getOHLCV(marketId: number, interval: string, from: number, to: number) {
    const res = await fetch(
      `${this.baseUrl}/dex/v1/chart/ohlcv?market_id=${marketId}&interval=${interval}&from=${from}&to=${to}`
    );
    return res.json();
  }
}
```

---

## Libraries & Dependencies

### JavaScript
```bash
npm install @proton/js node-fetch
```

### Python
```bash
pip install pyeoskit requests
```

**macOS setup for pyeoskit:**
```bash
brew install go cython
python3 -m pip install cmake
xcode-select --install
python3 -m pip install pyeoskit
```

---

## Additional Resources

- **API Docs:** https://api.dex.docs.metalx.com/
- **Developer Docs:** https://docs.metalx.com/
- **Metal X Exchange:** https://metalx.com/
- **WebAuth Wallet:** https://webauth.com/
- **DEX Bot:** https://github.com/XPRNetwork/dex-bot
- **Support:** https://help.xprnetwork.org/
