# MetalX DEX Integration

MetalX is the primary decentralized exchange on XPR Network - a peer-to-peer marketplace for cryptocurrency trading with no gas fees.

## Documentation Links

- **API Reference**: https://api.dex.docs.metalx.com
- **User Documentation**: https://docs.metalx.com
- **DEX Bot**: https://github.com/XPRNetwork/dex-bot

## Overview

MetalX provides:
- **Order Book Trading** - Limit and market orders
- **Swap** - Instant token swaps via liquidity pools
- **Pools & Farms** - Yield farming and liquidity provision
- **Lending** - Via LOAN Protocol integration

Users maintain custody of their keys through WebAuth wallets.

---

## API Endpoints

### Base URLs

| Environment | RPC | DEX API |
|-------------|-----|---------|
| Mainnet | `https://rpc.api.mainnet.metalx.com` | `https://dex.api.mainnet.metalx.com/dex` |
| Testnet | `https://rpc.api.testnet.metalx.com` | `https://dex.api.testnet.metalx.com/dex` |

### Markets

```typescript
// Get all markets
GET /markets

// Response
{
  "success": true,
  "data": [
    {
      "market_id": "XPR_XUSDT",
      "base_token": {
        "symbol": "XPR",
        "contract": "eosio.token",
        "precision": 4
      },
      "quote_token": {
        "symbol": "XUSDT",
        "contract": "xtokens",
        "precision": 6
      },
      "min_order_size": "1.0000",
      "price_precision": 6,
      "status": "active"
    }
  ]
}
```

```typescript
async function getMarkets() {
  const response = await fetch('https://dex.api.mainnet.metalx.com/dex/markets');
  const { data } = await response.json();
  return data;
}
```

### Order Book

```typescript
// Get order book depth
GET /orderbook?market_id={market_id}&depth={depth}

// Response
{
  "success": true,
  "data": {
    "bids": [
      { "price": "0.001234", "quantity": "10000.0000", "total": "10000.0000" }
    ],
    "asks": [
      { "price": "0.001235", "quantity": "5000.0000", "total": "5000.0000" }
    ],
    "timestamp": 1705123456789
  }
}
```

```typescript
async function getOrderBook(marketId: string, depth: number = 50) {
  const response = await fetch(
    `https://dex.api.mainnet.metalx.com/dex/orderbook?market_id=${marketId}&depth=${depth}`
  );
  const { data } = await response.json();
  return data;
}
```

### Ticker / Price

```typescript
// Get ticker data
GET /ticker?market_id={market_id}

// Response
{
  "success": true,
  "data": {
    "market_id": "XPR_XUSDT",
    "last_price": "0.001234",
    "high_24h": "0.001300",
    "low_24h": "0.001200",
    "volume_24h": "1000000.0000",
    "change_24h": "2.5",
    "bid": "0.001233",
    "ask": "0.001235"
  }
}
```

### OHLCV / Candles

```typescript
// Get candlestick data
GET /ohlcv?market_id={market_id}&interval={interval}&limit={limit}

// Intervals: 1m, 5m, 15m, 30m, 1h, 4h, 1d, 1w
```

### Trades

```typescript
// Get recent trades
GET /trades?market_id={market_id}&limit={limit}

// Get trade history for account
GET /trades/history?account={account}&market_id={market_id}
```

### Account

```typescript
// Get balances
GET /balances?account={account}

// Get open orders
GET /orders?account={account}&status=open

// Get order history
GET /orders/history?account={account}&limit={limit}
```

### Daily Stats

```typescript
// Get 24h statistics
GET /stats/daily?market_id={market_id}
```

---

## Trading Transactions

### Place Limit Order

```typescript
async function placeLimitOrder(
  account: string,
  marketId: string,
  side: 'buy' | 'sell',
  price: string,
  quantity: string,
  session: any
) {
  const [baseSymbol, quoteSymbol] = marketId.split('_');

  const actions = [{
    account: 'dex',
    name: 'placeorder',
    authorization: [{ actor: account, permission: 'active' }],
    data: {
      account,
      market_id: marketId,
      side: side === 'buy' ? 1 : 2,
      type: 1,  // 1 = limit
      price,
      quantity,
      post_only: false,
      fill_or_kill: false,
      immediate_or_cancel: false,
      client_order_id: Date.now().toString()
    }
  }];

  return session.transact({ actions }, { broadcast: true });
}
```

### Place Market Order

```typescript
async function placeMarketOrder(
  account: string,
  marketId: string,
  side: 'buy' | 'sell',
  quantity: string,
  session: any
) {
  const actions = [{
    account: 'dex',
    name: 'placeorder',
    authorization: [{ actor: account, permission: 'active' }],
    data: {
      account,
      market_id: marketId,
      side: side === 'buy' ? 1 : 2,
      type: 2,  // 2 = market
      price: '0',
      quantity,
      post_only: false,
      fill_or_kill: false,
      immediate_or_cancel: true,
      client_order_id: Date.now().toString()
    }
  }];

  return session.transact({ actions }, { broadcast: true });
}
```

### Order Types

| Type | Value | Description |
|------|-------|-------------|
| Limit | 1 | Execute at specified price or better |
| Market | 2 | Execute immediately at best available |

### Order Flags

| Flag | Description |
|------|-------------|
| `post_only` | Only add to order book (maker), reject if would match |
| `fill_or_kill` | Execute entirely or cancel completely |
| `immediate_or_cancel` | Execute available, cancel remainder |

### Cancel Order

```typescript
async function cancelOrder(
  account: string,
  orderId: string,
  session: any
) {
  const actions = [{
    account: 'dex',
    name: 'cancelorder',
    authorization: [{ actor: account, permission: 'active' }],
    data: {
      account,
      order_id: orderId
    }
  }];

  return session.transact({ actions }, { broadcast: true });
}
```

### Cancel All Orders

```typescript
async function cancelAllOrders(
  account: string,
  marketId: string | null,
  session: any
) {
  const actions = [{
    account: 'dex',
    name: 'cancelall',
    authorization: [{ actor: account, permission: 'active' }],
    data: {
      account,
      market_id: marketId || ''  // Empty = all markets
    }
  }];

  return session.transact({ actions }, { broadcast: true });
}
```

---

## Deposits and Withdrawals

### Deposit to DEX

Tokens must be deposited to the DEX before trading:

```typescript
async function depositToDex(
  account: string,
  quantity: string,
  tokenContract: string,  // eosio.token for XPR, xtokens for XUSDT
  session: any
) {
  const actions = [{
    account: tokenContract,
    name: 'transfer',
    authorization: [{ actor: account, permission: 'active' }],
    data: {
      from: account,
      to: 'dex',
      quantity,
      memo: 'deposit'
    }
  }];

  return session.transact({ actions }, { broadcast: true });
}
```

### Withdraw from DEX

```typescript
async function withdrawFromDex(
  account: string,
  quantity: string,
  session: any
) {
  const actions = [{
    account: 'dex',
    name: 'withdraw',
    authorization: [{ actor: account, permission: 'active' }],
    data: {
      account,
      quantity
    }
  }];

  return session.transact({ actions }, { broadcast: true });
}
```

---

## Swap (AMM)

MetalX also provides Uniswap-style AMM swaps:

### Get Swap Quote

```typescript
async function getSwapQuote(
  inputToken: string,
  outputToken: string,
  amount: string
) {
  const response = await fetch(
    `https://dex.api.mainnet.metalx.com/swap/quote?` +
    `input_token=${inputToken}&output_token=${outputToken}&amount=${amount}`
  );
  const { data } = await response.json();
  return data;
}
```

### Execute Swap

```typescript
async function executeSwap(
  account: string,
  inputToken: { symbol: string; contract: string },
  outputToken: { symbol: string; contract: string },
  inputAmount: string,
  minOutput: string,  // Slippage protection
  session: any
) {
  const actions = [{
    account: inputToken.contract,
    name: 'transfer',
    authorization: [{ actor: account, permission: 'active' }],
    data: {
      from: account,
      to: 'swap.mtl',  // Swap contract
      quantity: inputAmount,
      memo: `swap:${outputToken.symbol}:${minOutput}`
    }
  }];

  return session.transact({ actions }, { broadcast: true });
}
```

---

## Liquidity Pools

### Add Liquidity

```typescript
async function addLiquidity(
  account: string,
  poolId: string,
  tokenA: { contract: string; quantity: string },
  tokenB: { contract: string; quantity: string },
  session: any
) {
  const actions = [
    // Transfer token A
    {
      account: tokenA.contract,
      name: 'transfer',
      authorization: [{ actor: account, permission: 'active' }],
      data: {
        from: account,
        to: 'swap.mtl',
        quantity: tokenA.quantity,
        memo: `addliq:${poolId}`
      }
    },
    // Transfer token B
    {
      account: tokenB.contract,
      name: 'transfer',
      authorization: [{ actor: account, permission: 'active' }],
      data: {
        from: account,
        to: 'swap.mtl',
        quantity: tokenB.quantity,
        memo: `addliq:${poolId}`
      }
    }
  ];

  return session.transact({ actions }, { broadcast: true });
}
```

### Remove Liquidity

```typescript
async function removeLiquidity(
  account: string,
  poolId: string,
  lpTokenAmount: string,
  session: any
) {
  const actions = [{
    account: 'swap.mtl',
    name: 'remliq',
    authorization: [{ actor: account, permission: 'active' }],
    data: {
      account,
      pool_id: poolId,
      lp_amount: lpTokenAmount
    }
  }];

  return session.transact({ actions }, { broadcast: true });
}
```

---

## Trading Bot Service Class

```typescript
import ProtonWebSDK from '@proton/web-sdk';

class MetalXTrader {
  private apiBase = 'https://dex.api.mainnet.metalx.com/dex';
  private session: any = null;
  private account: string = '';

  async connect() {
    const { session } = await ProtonWebSDK({
      linkOptions: {
        chainId: '384da888112027f0321850a169f737c33e53b388aad48b5adace4bab97f437e0',
        endpoints: ['https://rpc.api.mainnet.metalx.com']
      },
      selectorOptions: { appName: 'Trading Bot' }
    });

    this.session = session;
    this.account = session.auth.actor;
    return this.account;
  }

  // Market data
  async getMarkets() {
    const res = await fetch(`${this.apiBase}/markets`);
    return (await res.json()).data;
  }

  async getTicker(marketId: string) {
    const res = await fetch(`${this.apiBase}/ticker?market_id=${marketId}`);
    return (await res.json()).data;
  }

  async getOrderBook(marketId: string, depth = 50) {
    const res = await fetch(`${this.apiBase}/orderbook?market_id=${marketId}&depth=${depth}`);
    return (await res.json()).data;
  }

  // Account data
  async getBalances() {
    const res = await fetch(`${this.apiBase}/balances?account=${this.account}`);
    return (await res.json()).data;
  }

  async getOpenOrders(marketId?: string) {
    let url = `${this.apiBase}/orders?account=${this.account}&status=open`;
    if (marketId) url += `&market_id=${marketId}`;
    const res = await fetch(url);
    return (await res.json()).data;
  }

  // Trading
  async placeLimitOrder(marketId: string, side: 'buy' | 'sell', price: string, quantity: string) {
    return this.session.transact({
      actions: [{
        account: 'dex',
        name: 'placeorder',
        authorization: [{ actor: this.account, permission: 'active' }],
        data: {
          account: this.account,
          market_id: marketId,
          side: side === 'buy' ? 1 : 2,
          type: 1,
          price,
          quantity,
          post_only: false,
          fill_or_kill: false,
          immediate_or_cancel: false,
          client_order_id: Date.now().toString()
        }
      }]
    }, { broadcast: true });
  }

  async cancelOrder(orderId: string) {
    return this.session.transact({
      actions: [{
        account: 'dex',
        name: 'cancelorder',
        authorization: [{ actor: this.account, permission: 'active' }],
        data: { account: this.account, order_id: orderId }
      }]
    }, { broadcast: true });
  }

  async cancelAllOrders(marketId?: string) {
    return this.session.transact({
      actions: [{
        account: 'dex',
        name: 'cancelall',
        authorization: [{ actor: this.account, permission: 'active' }],
        data: { account: this.account, market_id: marketId || '' }
      }]
    }, { broadcast: true });
  }

  // Deposits/Withdrawals
  async deposit(quantity: string, tokenContract: string) {
    return this.session.transact({
      actions: [{
        account: tokenContract,
        name: 'transfer',
        authorization: [{ actor: this.account, permission: 'active' }],
        data: {
          from: this.account,
          to: 'dex',
          quantity,
          memo: 'deposit'
        }
      }]
    }, { broadcast: true });
  }

  async withdraw(quantity: string) {
    return this.session.transact({
      actions: [{
        account: 'dex',
        name: 'withdraw',
        authorization: [{ actor: this.account, permission: 'active' }],
        data: { account: this.account, quantity }
      }]
    }, { broadcast: true });
  }
}

export const trader = new MetalXTrader();
```

---

## WebSocket for Real-Time Data

MetalX may provide WebSocket feeds for real-time order book and trade updates:

```typescript
// Example WebSocket pattern (check docs for actual URL)
const ws = new WebSocket('wss://dex.api.mainnet.metalx.com/ws');

ws.onopen = () => {
  // Subscribe to order book updates
  ws.send(JSON.stringify({
    type: 'subscribe',
    channel: 'orderbook',
    market_id: 'XPR_XUSDT'
  }));

  // Subscribe to trades
  ws.send(JSON.stringify({
    type: 'subscribe',
    channel: 'trades',
    market_id: 'XPR_XUSDT'
  }));
};

ws.onmessage = (event) => {
  const data = JSON.parse(event.data);
  console.log('Update:', data);
};
```

---

## Smart Contracts

| Contract | Purpose |
|----------|---------|
| `dex` | Order book and matching engine |
| `swap.mtl` | AMM swap and liquidity pools |
| `farm.mtl` | Yield farming |
| `loan.mtl` | Lending protocol |

---

## Common Patterns

### Monitor Order Fills

```typescript
async function waitForFill(orderId: string, timeout = 60000): Promise<boolean> {
  const start = Date.now();

  while (Date.now() - start < timeout) {
    const orders = await trader.getOpenOrders();
    const order = orders.find((o: any) => o.order_id === orderId);

    if (!order) {
      return true;  // Order no longer open = filled or cancelled
    }

    await new Promise(r => setTimeout(r, 1000));
  }

  return false;  // Timeout
}
```

### Calculate Spread

```typescript
function calculateSpread(orderBook: { bids: any[]; asks: any[] }) {
  if (!orderBook.bids.length || !orderBook.asks.length) {
    return null;
  }

  const bestBid = parseFloat(orderBook.bids[0].price);
  const bestAsk = parseFloat(orderBook.asks[0].price);
  const spread = bestAsk - bestBid;
  const spreadPercent = (spread / bestBid) * 100;

  return {
    bestBid,
    bestAsk,
    spread,
    spreadPercent,
    midPrice: (bestBid + bestAsk) / 2
  };
}
```

### Simple Arbitrage Check

```typescript
async function checkArbitrageOpportunity(
  marketA: string,  // e.g., XPR_XUSDT
  marketB: string,  // e.g., XPR_XBTC
  marketC: string   // e.g., XBTC_XUSDT
) {
  const [tickerA, tickerB, tickerC] = await Promise.all([
    trader.getTicker(marketA),
    trader.getTicker(marketB),
    trader.getTicker(marketC)
  ]);

  // Calculate implied price through B and C
  const impliedPrice = parseFloat(tickerB.last_price) * parseFloat(tickerC.last_price);
  const directPrice = parseFloat(tickerA.last_price);

  const diff = ((impliedPrice - directPrice) / directPrice) * 100;

  return {
    directPrice,
    impliedPrice,
    differencePercent: diff,
    profitable: Math.abs(diff) > 0.5  // Account for fees
  };
}
```

---

## Resources

- **MetalX App**: https://metalx.com
- **API Docs**: https://api.dex.docs.metalx.com
- **User Docs**: https://docs.metalx.com
- **DEX Bot**: https://github.com/XPRNetwork/dex-bot
- **Support**: https://docs.metalx.com/support/getting-started
