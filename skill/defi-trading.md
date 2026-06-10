# DeFi and Trading on XPR Network

This guide covers DEX interaction, trading patterns, and building blocks for advanced DeFi applications including perpetual futures.

## MetalX DEX Overview

MetalX is the primary decentralized exchange on XPR Network — an **order book DEX** for spot trading, backed by the `dex` contract.

> **Two product surfaces under the MetalX brand.** This section covers the order-book DEX (the `dex` contract). MetalX also exposes a **Swap UI** for AMM-style liquidity pools, which is a separate contract on chain — **`proton.swaps`**. See [Proton Swaps (AMM Liquidity Pools)](#proton-swaps-amm-liquidity-pools) below for the swap/add-liquidity flow. The order-book and AMM surfaces are distinct: order-book trades route through `dex`, AMM swaps route through `proton.swaps`.

### Endpoints

| Network | RPC | DEX API |
|---------|-----|---------|
| Mainnet | `https://rpc.api.mainnet.metalx.com` | `https://dex.api.mainnet.metalx.com/dex` |

### Key Contracts

| Contract | Purpose |
|----------|---------|
| `dex` | Order book and matching engine |
| `eosio.token` | XPR and wrapped tokens |
| `xtokens` | Wrapped tokens (XUSDT, XBTC, etc.) |

---

## DEX API Queries

### Get All Markets

```typescript
async function getMarkets() {
  const response = await fetch('https://dex.api.mainnet.metalx.com/dex/v1/markets/all');
  const { data } = await response.json();
  return data;
}

// Response shape (verified live):
// - market_id, symbol (e.g. "XPR_XMD"), type
// - bid_token / ask_token — objects: { code, contract, precision, multiplier }
// - maker_fee, taker_fee
// - order_min        (NOT "min_order_size")
// - status_code      (NOT "status" — see Market Status Codes in metalx-dex.md)
```

### Get Order Book

The `/orders/depth` endpoint takes `symbol` (e.g. `XPR_XUSDC`) and `step` (price aggregation level), **not** `market_id`. Verified live against the API; passing `market_id` returns HTTP 400 `{"message":["symbol: Required","step: Expected number, received nan"]}`.

```typescript
async function getOrderBook(symbol: string, step: number = 0.0001) {
  const response = await fetch(
    `https://dex.api.mainnet.metalx.com/dex/v1/orders/depth?symbol=${symbol}&step=${step}`
  );
  const { data } = await response.json();
  return data;  // { bids: [{level, count, bid, ask}, ...], asks: [...] }
}

// Usage
const book = await getOrderBook('XPR_XUSDC');
```

### Get Latest Price

`/trades/daily` returns the **24h OHLCV for every market**, not a single market. Filter client-side by `market_id` or `symbol`.

```typescript
async function getDailyStats(symbol?: string) {
  const response = await fetch(
    `https://dex.api.mainnet.metalx.com/dex/v1/trades/daily`
  );
  const { data } = await response.json();
  // data is Array<{ market_id, symbol, volume_bid, volume_ask, open, close, high, low, change_percentage }>
  return symbol ? data.find((m: any) => m.symbol === symbol) : data;
}

// Usage
const xprUsdc = await getDailyStats('XPR_XUSDC');
console.log(xprUsdc.close, xprUsdc.high, xprUsdc.low, xprUsdc.volume_bid);
```

### Get Trade History

`/trades/recent` takes `symbol`, not `market_id`. Passing `market_id` returns HTTP 400.

```typescript
async function getTradeHistory(symbol: string, limit: number = 50) {
  const response = await fetch(
    `https://dex.api.mainnet.metalx.com/dex/v1/trades/recent?symbol=${symbol}&limit=${limit}`
  );
  const { data } = await response.json();
  return data;
}

// Usage
const trades = await getTradeHistory('XPR_XUSDC', 20);
```

### Get User's Open Orders

```typescript
async function getOpenOrders(account: string, marketId?: number) {
  // NOTE: the API ignores a market_id query param (verified live — it returns
  // all markets regardless). Filter client-side instead.
  const response = await fetch(
    `https://dex.api.mainnet.metalx.com/dex/v1/orders/open?account=${account}`
  );
  const { data } = await response.json();
  return marketId ? data.filter((o: any) => o.market_id === marketId) : data;
}
```

### Get User Balances

```typescript
async function getDexBalances(account: string) {
  const response = await fetch(
    `https://dex.api.mainnet.metalx.com/dex/v1/account/balances?account=${account}`
  );
  const { data } = await response.json();
  return data;
}
```

---

## DEX Trading Transactions

### Place Limit Order

```typescript
async function placeLimitOrder(
  account: string,
  marketId: number,
  orderSide: 'buy' | 'sell',
  price: string,
  quantity: string,
  bidSymbol: { sym: string; contract: string },
  askSymbol: { sym: string; contract: string },
  fillType: number = 0  // 0=GTC, 1=IOC, 2=POST_ONLY
) {
  const actions = [{
    account: 'dex',
    name: 'placeorder',
    authorization: [{ actor: account, permission: 'active' }],
    data: {
      market_id: marketId,
      account,
      order_type: 1,       // 1 = limit (only valid type; use trigger_price for stop loss / take profit)
      order_side: orderSide === 'buy' ? 1 : 2,  // 1=buy, 2=sell
      quantity,
      price,
      bid_symbol: bidSymbol,   // extended_symbol e.g. {"sym":"4,XPR","contract":"eosio.token"}
      ask_symbol: askSymbol,   // extended_symbol e.g. {"sym":"6,XUSDC","contract":"xtokens"}
      trigger_price: 0,        // optional: set non-zero for stop-loss / take-profit orders
      fill_type: fillType,     // 0=GTC, 1=IOC, 2=POST_ONLY
      referrer: ''             // optional: referrer account name
    }
  }];

  return session.transact({ actions }, { broadcast: true });
}
```

### Simulate Market Order

> **Note:** There is no market order type on the DEX. `order_type` only supports `1` (limit).
> To simulate a market order, place a limit order with `fill_type: 1` (IOC — Immediate or Cancel)
> at an aggressive price that will match immediately. Any unfilled remainder is cancelled.

```typescript
async function placeMarketOrder(
  account: string,
  marketId: number,
  orderSide: 'buy' | 'sell',
  quantity: string,
  bidSymbol: { sym: string; contract: string },
  askSymbol: { sym: string; contract: string }
) {
  // Use a very high price for buys or very low price for sells to ensure fill
  const aggressivePrice = orderSide === 'buy' ? '999999999' : '1';

  const actions = [{
    account: 'dex',
    name: 'placeorder',
    authorization: [{ actor: account, permission: 'active' }],
    data: {
      market_id: marketId,
      account,
      order_type: 1,       // 1 = limit (the only valid order type)
      order_side: orderSide === 'buy' ? 1 : 2,
      quantity,
      price: aggressivePrice,
      bid_symbol: bidSymbol,
      ask_symbol: askSymbol,
      trigger_price: 0,
      fill_type: 1,        // 1 = IOC (Immediate or Cancel) — unfilled portion is cancelled
      referrer: ''
    }
  }];

  return session.transact({ actions }, { broadcast: true });
}
```

### Cancel Order

```typescript
async function cancelOrder(account: string, orderId: string) {
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

### Cancel Multiple Orders

> **Note:** There is no `cancelall` action on the DEX contract. You must cancel orders
> individually using `cancelorder(account, order_id)`. To cancel all open orders, fetch
> them first via the API and then cancel each one.

```typescript
async function cancelAllOrders(account: string, marketId?: string) {
  // 1. Fetch all open orders for this account
  const openOrders = await getOpenOrders(account, marketId);

  // 2. Cancel each order individually
  const actions = openOrders.map((order: any) => ({
    account: 'dex',
    name: 'cancelorder',
    authorization: [{ actor: account, permission: 'active' }],
    data: {
      account,
      order_id: order.order_id
    }
  }));

  if (actions.length === 0) return;

  return session.transact({ actions }, { broadcast: true });
}
```

### Deposit to DEX

```typescript
async function depositToDex(account: string, quantity: string, tokenContract: string) {
  const actions = [{
    account: tokenContract,
    name: 'transfer',
    authorization: [{ actor: account, permission: 'active' }],
    data: {
      from: account,
      to: 'dex',
      quantity,
      // WARNING: memo MUST be empty string. Using 'deposit' or other non-empty
      // memo will cause the transfer to be treated as a regular transfer, not a DEX deposit.
      memo: ''
    }
  }];

  return session.transact({ actions }, { broadcast: true });
}
```

### Withdraw from DEX

There are two withdraw options:

- **`withdrawall(account)`** — withdraws all balances at once.
- **`withdraw(account, balance)`** — withdraws a specific amount, where `balance` is an `extended_asset`.

```typescript
// Withdraw all DEX balances
async function withdrawAllFromDex(account: string) {
  const actions = [{
    account: 'dex',
    name: 'withdrawall',
    authorization: [{ actor: account, permission: 'active' }],
    data: {
      account
    }
  }];

  return session.transact({ actions }, { broadcast: true });
}

// Withdraw a specific amount (balance is an extended_asset)
async function withdrawFromDex(
  account: string,
  quantity: string,       // e.g. "100.0000 XPR"
  tokenContract: string   // e.g. "eosio.token"
) {
  const actions = [{
    account: 'dex',
    name: 'withdraw',
    authorization: [{ actor: account, permission: 'active' }],
    data: {
      account,
      balance: {
        quantity,
        contract: tokenContract
      }
    }
  }];

  return session.transact({ actions }, { broadcast: true });
}
```

---

## Trading Bot Patterns

### Grid Bot Strategy

```typescript
interface GridConfig {
  marketId: string;
  lowerPrice: number;
  upperPrice: number;
  gridLevels: number;
  quantityPerGrid: string;
}

class GridBot {
  private config: GridConfig;
  private gridPrices: number[] = [];

  constructor(config: GridConfig) {
    this.config = config;
    this.calculateGridPrices();
  }

  private calculateGridPrices() {
    const { lowerPrice, upperPrice, gridLevels } = this.config;
    const step = (upperPrice - lowerPrice) / (gridLevels - 1);

    for (let i = 0; i < gridLevels; i++) {
      this.gridPrices.push(lowerPrice + step * i);
    }
  }

  async placeInitialOrders(currentPrice: number) {
    const orders: Promise<any>[] = [];

    for (const gridPrice of this.gridPrices) {
      if (gridPrice < currentPrice) {
        // Place buy order below current price
        orders.push(this.placeBuyOrder(gridPrice));
      } else if (gridPrice > currentPrice) {
        // Place sell order above current price
        orders.push(this.placeSellOrder(gridPrice));
      }
    }

    return Promise.all(orders);
  }

  private async placeBuyOrder(price: number) {
    return placeLimitOrder(
      this.account,
      this.config.marketId,
      'buy',
      price.toFixed(4),
      this.config.quantityPerGrid
    );
  }

  private async placeSellOrder(price: number) {
    return placeLimitOrder(
      this.account,
      this.config.marketId,
      'sell',
      price.toFixed(4),
      this.config.quantityPerGrid
    );
  }

  // Called when an order fills
  async onOrderFilled(filledOrder: Order) {
    const gridIndex = this.findGridIndex(parseFloat(filledOrder.price));

    if (filledOrder.side === 'buy') {
      // Buy filled - place sell at next grid up
      const sellPrice = this.gridPrices[gridIndex + 1];
      if (sellPrice) {
        await this.placeSellOrder(sellPrice);
      }
    } else {
      // Sell filled - place buy at next grid down
      const buyPrice = this.gridPrices[gridIndex - 1];
      if (buyPrice) {
        await this.placeBuyOrder(buyPrice);
      }
    }
  }
}
```

### Market Maker Strategy

```typescript
interface MarketMakerConfig {
  marketId: string;
  spread: number;      // e.g., 0.002 for 0.2%
  levels: number;      // Orders per side
  levelSpacing: number; // e.g., 0.001 for 0.1%
  quantityPerLevel: string;
}

class MarketMaker {
  private config: MarketMakerConfig;

  async updateQuotes(midPrice: number) {
    // Cancel existing orders
    await cancelAllOrders(this.account, this.config.marketId);

    const orders: Promise<any>[] = [];

    for (let i = 0; i < this.config.levels; i++) {
      const offset = this.config.spread / 2 + i * this.config.levelSpacing;

      // Bid (buy)
      const bidPrice = midPrice * (1 - offset);
      orders.push(placeLimitOrder(
        this.account,
        this.config.marketId,
        'buy',
        bidPrice.toFixed(4),
        this.config.quantityPerLevel
      ));

      // Ask (sell)
      const askPrice = midPrice * (1 + offset);
      orders.push(placeLimitOrder(
        this.account,
        this.config.marketId,
        'sell',
        askPrice.toFixed(4),
        this.config.quantityPerLevel
      ));
    }

    return Promise.all(orders);
  }
}
```

---

## Building a Perpetual Futures DEX

A perps DEX on XPR Network would require these components:

### 1. Core Tables

```typescript
// Positions table
@table("positions")
class Position extends Table {
  constructor(
    public id: u64 = 0,
    public trader: Name = new Name(),
    public market: string = "",         // e.g., "BTC-PERP"
    public side: u8 = 0,                // 1=long, 2=short
    public size: u64 = 0,               // Position size (base units)
    public entry_price: u64 = 0,        // Average entry (8 decimals)
    public leverage: u8 = 1,            // 1-100x
    public collateral: u64 = 0,         // Margin deposited
    public unrealized_pnl: i64 = 0,     // Current PnL
    public last_funding_time: u64 = 0,  // Last funding payment
    public liquidation_price: u64 = 0   // Auto-liquidation price
  ) { super(); }

  @primary
  get primary(): u64 { return this.id; }

  @secondary
  get byTrader(): u64 { return this.trader.N; }
}

// Markets configuration
@table("markets")
class Market extends Table {
  constructor(
    public market_id: string = "",
    public oracle_index: u8 = 0,         // Oracle feed index
    public max_leverage: u8 = 20,        // Max allowed leverage
    public maintenance_margin: u16 = 500, // 5% in basis points
    public initial_margin: u16 = 1000,    // 10% in basis points
    public funding_interval: u32 = 3600,  // 1 hour
    public maker_fee: u16 = 10,           // 0.1% in basis points
    public taker_fee: u16 = 50,           // 0.5% in basis points
    public open_interest_long: u64 = 0,
    public open_interest_short: u64 = 0
  ) { super(); }

  @primary
  get primary(): string { return this.market_id; }
}

// Funding rate history
@table("funding")
class FundingRate extends Table {
  constructor(
    public id: u64 = 0,
    public market_id: string = "",
    public timestamp: u64 = 0,
    public funding_rate: i64 = 0,  // Can be negative
    public mark_price: u64 = 0,
    public index_price: u64 = 0
  ) { super(); }

  @primary
  get primary(): u64 { return this.id; }
}

// Insurance fund
@table("insurance", singleton)
class InsuranceFund extends Table {
  constructor(
    public balance: u64 = 0,
    public last_contribution: u64 = 0
  ) { super(); }
}
```

### 2. Oracle Integration for Mark Price

```typescript
// Mark price = TWAP of oracle + funding premium
async function getMarkPrice(marketId: string): Promise<u64> {
  const market = await getMarket(marketId);

  // Get index price from oracle
  const indexPrice = await getOraclePrice(market.oracle_index);

  // Get order book mid price from DEX
  const orderBook = await getOrderBook(marketId);
  const midPrice = calculateMidPrice(orderBook);

  // Calculate funding premium
  const premium = calculatePremium(midPrice, indexPrice);

  // Mark price includes premium
  return indexPrice + premium;
}

function calculatePremium(midPrice: u64, indexPrice: u64): i64 {
  // Premium = (Mid Price - Index Price) / Index Price
  // Dampened over time
  return ((midPrice - indexPrice) * 10000) / indexPrice;
}
```

### 3. Margin and Leverage

```typescript
@action("openposition")
openPosition(
  trader: Name,
  market: string,
  side: u8,          // 1=long, 2=short
  size: u64,         // Position size
  leverage: u8,      // 1-100
  collateral: Asset  // Margin to deposit
): void {
  requireAuth(trader);

  const marketConfig = this.marketsTable.requireGet(market, "Market not found");

  // Validate leverage
  check(leverage >= 1 && leverage <= marketConfig.max_leverage, "Invalid leverage");

  // Calculate required margin
  const markPrice = this.getMarkPrice(market);
  const notionalValue = (size * markPrice) / PRICE_PRECISION;
  const requiredMargin = (notionalValue * marketConfig.initial_margin) / 10000;

  check(collateral.amount >= requiredMargin, "Insufficient margin");

  // Calculate liquidation price
  const liquidationPrice = this.calculateLiquidationPrice(
    side,
    markPrice,
    leverage,
    marketConfig.maintenance_margin
  );

  // Create position
  const position = new Position(
    this.getNextPositionId(),
    trader,
    market,
    side,
    size,
    markPrice,
    leverage,
    collateral.amount,
    0,  // unrealized PnL starts at 0
    currentTimeSec(),
    liquidationPrice
  );

  this.positionsTable.store(position, trader);

  // Update open interest
  if (side == 1) {
    marketConfig.open_interest_long += size;
  } else {
    marketConfig.open_interest_short += size;
  }
  this.marketsTable.update(marketConfig, this.receiver);
}

function calculateLiquidationPrice(
  side: u8,
  entryPrice: u64,
  leverage: u8,
  maintenanceMargin: u16
): u64 {
  // For longs: Liq Price = Entry * (1 - 1/leverage + maintenance_margin)
  // For shorts: Liq Price = Entry * (1 + 1/leverage - maintenance_margin)

  const leverageFactor = PRECISION / leverage;
  const marginFactor = (maintenanceMargin * PRECISION) / 10000;

  if (side == 1) {  // Long
    return (entryPrice * (PRECISION - leverageFactor + marginFactor)) / PRECISION;
  } else {  // Short
    return (entryPrice * (PRECISION + leverageFactor - marginFactor)) / PRECISION;
  }
}
```

### 4. Funding Rate Mechanism

```typescript
@action("applyfunding")
applyFunding(market: string): void {
  const marketConfig = this.marketsTable.requireGet(market, "Market not found");
  const now = currentTimeSec();

  // Check if funding interval has passed
  check(
    now >= this.lastFundingTime(market) + marketConfig.funding_interval,
    "Funding not due yet"
  );

  // Calculate funding rate
  const markPrice = this.getMarkPrice(market);
  const indexPrice = this.getOraclePrice(marketConfig.oracle_index);

  // Funding Rate = (Mark Price - Index Price) / Index Price * 0.01
  // Clamped to max ±0.1% per interval
  let fundingRate = ((markPrice - indexPrice) * 100) / indexPrice;
  fundingRate = clamp(fundingRate, -1000, 1000);  // ±0.1%

  // Apply to all positions
  let cursor = this.positionsTable.lowerBound(market);
  while (cursor && cursor.market == market) {
    const payment = this.calculateFundingPayment(cursor, fundingRate);

    if (cursor.side == 1) {
      // Longs pay when funding > 0
      cursor.collateral -= payment;
    } else {
      // Shorts receive when funding > 0
      cursor.collateral += payment;
    }

    cursor.last_funding_time = now;
    this.positionsTable.update(cursor, this.receiver);

    cursor = this.positionsTable.next(cursor);
  }

  // Record funding rate
  this.recordFunding(market, fundingRate, markPrice, indexPrice);
}
```

### 5. Liquidation System

```typescript
@action("liquidate")
liquidate(positionId: u64, liquidator: Name): void {
  requireAuth(liquidator);

  const position = this.positionsTable.requireGet(positionId, "Position not found");
  const markPrice = this.getMarkPrice(position.market);

  // Check if position is liquidatable
  const isLiquidatable = this.checkLiquidation(position, markPrice);
  check(isLiquidatable, "Position not liquidatable");

  // Calculate liquidation penalty
  const market = this.marketsTable.get(position.market);
  const penalty = (position.collateral * LIQUIDATION_PENALTY) / 10000;

  // Pay liquidator reward (portion of penalty)
  const liquidatorReward = (penalty * LIQUIDATOR_SHARE) / 100;
  this.transferReward(liquidator, liquidatorReward);

  // Send remainder to insurance fund
  const insuranceContribution = penalty - liquidatorReward;
  this.addToInsurance(insuranceContribution);

  // Close position
  this.closePosition(position, markPrice, true);  // true = liquidation
}

function checkLiquidation(position: Position, markPrice: u64): boolean {
  // Calculate unrealized PnL
  let pnl: i64;
  if (position.side == 1) {  // Long
    pnl = ((markPrice - position.entry_price) * position.size) / PRICE_PRECISION;
  } else {  // Short
    pnl = ((position.entry_price - markPrice) * position.size) / PRICE_PRECISION;
  }

  // Calculate margin ratio
  const equity = position.collateral + pnl;
  const notional = (position.size * markPrice) / PRICE_PRECISION;
  const marginRatio = (equity * 10000) / notional;

  // Liquidate if below maintenance margin
  const market = this.marketsTable.get(position.market);
  return marginRatio < market.maintenance_margin;
}
```

### 6. Order Matching (Limit Orders)

```typescript
@table("orders")
class Order extends Table {
  constructor(
    public id: u64 = 0,
    public trader: Name = new Name(),
    public market: string = "",
    public side: u8 = 0,        // 1=long, 2=short
    public price: u64 = 0,
    public size: u64 = 0,
    public filled: u64 = 0,
    public reduce_only: bool = false,
    public post_only: bool = false,
    public timestamp: u64 = 0
  ) { super(); }

  @primary
  get primary(): u64 { return this.id; }

  @secondary  // For order book sorting
  get byPrice(): u64 { return this.price; }
}

@action("placeorder")
placeOrder(
  trader: Name,
  market: string,
  side: u8,
  price: u64,
  size: u64,
  reduceOnly: bool,
  postOnly: bool
): void {
  requireAuth(trader);

  // Validate order
  // ...

  // Check for matching orders
  const matchingOrders = this.findMatchingOrders(market, side, price);

  for (const match of matchingOrders) {
    if (postOnly) {
      check(false, "Order would cross - post-only rejected");
    }

    // Execute match
    this.executeMatch(trader, match, size);
  }

  // Place remainder on book
  if (size > 0) {
    const order = new Order(
      this.getNextOrderId(),
      trader,
      market,
      side,
      price,
      size,
      0,
      reduceOnly,
      postOnly,
      currentTimeSec()
    );
    this.ordersTable.store(order, trader);
  }
}
```

---

## Required Infrastructure

To build a production perps DEX:

### Smart Contracts

| Contract | Purpose |
|----------|---------|
| `perps.core` | Positions, orders, matching |
| `perps.oracle` | Mark price calculation, TWAP |
| `perps.liquidation` | Liquidation bot rewards |
| `perps.insurance` | Insurance fund management |

### Backend Services

| Service | Purpose |
|---------|---------|
| Liquidation Bot | Monitor positions, trigger liquidations |
| Funding Bot | Apply funding rates on schedule |
| Oracle Aggregator | Fetch prices, calculate TWAP |
| Order Indexer | Fast order book queries |

### Frontend

- Real-time position tracking
- P&L calculations
- Order book visualization
- Leverage slider with liquidation price preview

---

## Security Considerations

### For Perps DEX

1. **Oracle Manipulation** - Use TWAP, multiple sources
2. **Flash Loan Attacks** - Require position to be held for min time
3. **Cascading Liquidations** - Insurance fund, position limits
4. **Front-Running** - Time-weighted execution, commit-reveal
5. **Smart Contract Risk** - Audits, bug bounties, gradual rollout

### Rate Limiting

```typescript
// Prevent spam orders
const MAX_ORDERS_PER_BLOCK = 10;

@action("placeorder")
placeOrder(...): void {
  const userOrdersThisBlock = this.countRecentOrders(trader);
  check(userOrdersThisBlock < MAX_ORDERS_PER_BLOCK, "Rate limit exceeded");
  // ...
}
```

---

## Proton Swaps (AMM Liquidity Pools)

`proton.swaps` provides automated market maker (AMM) swap pools — an alternative to the DEX order book for instant trades.

> **This is what the MetalX "Swap" tab runs on.** MetalX does not deploy a separate swap contract on XPR Network; its swap UI is a front-end on top of `proton.swaps`. So the pools, liquidity, and on-chain math documented here are the same ones a MetalX user is interacting with — they're not two separate venues.

### Key Contract

| Contract | Purpose |
|----------|---------|
| `proton.swaps` | AMM swap pools, liquidity provision |

### Query All Pools

```bash
curl -s -X POST https://proton.eosusa.io/v1/chain/get_table_rows \
  -H 'Content-Type: application/json' \
  -d '{"code":"proton.swaps","scope":"proton.swaps","table":"pools","limit":100,"json":true}'
```

Pool row structure:

| Field | Description |
|-------|-------------|
| `lt_symbol` | LP token symbol (e.g., `XPRUSDC`) |
| `creator` | Pool creator account |
| `memo` | Pool identifier string |
| `pool1` | Reserve of token A (extended_asset) |
| `pool2` | Reserve of token B (extended_asset) |
| `hash` | Pool hash |
| `fee` | Exchange fee object |

### Exchange Fees

**Product spec (canonical):** [docs.metalx.com → Swap fees and discounts](https://docs.metalx.com/swap-pools-and-farms/what-is-metal-x-swap/swap-fees-and-discounts) — the per-trade fee on MetalX Swap is **0.3%**, split as **0.2% to LPs** + **0.1% to XPR burns or XPR Grants** (quarterly disposition).

**On-chain mechanism** (for programmatic integrators talking to `proton.swaps` without going through the MetalX UI):

- LP slice = `pools[i].fee.exchange_fee` — 20 bps on pools exposed in the MetalX UI.
- Burns/Grants slice = `globall.exchange_fee_for_protocol` — 10 bps, flat. Sent on-chain to the `fee.swaps` account (verified via `get_account` and outbound transfer history); governance-mutable via the contract's `globalfee` action. From there, MetalX disposes of accumulated XPR by burning or routing to XPR Grants quarterly (per [docs.metalx.com](https://docs.metalx.com/swap-pools-and-farms/what-is-metal-x-swap/swap-fees-and-discounts)).

The two slices compound (protocol fee comes off the input first, then the AMM math applies the LP fee) — the difference vs adding is negligible at these magnitudes.

Other pools may exist in the `pools` table with different `fee.exchange_fee` values, but only the MetalX-exposed set is documented and product-supported. For anything not in the MetalX docs, read `pools[i].fee` and `globall.exchange_fee_for_protocol` live from chain and don't assume a total; that pool may not be routable through the MetalX UI at all.

### Active Pools

The `pools` table lists every pool the contract knows about. **Pool set rotates** — query `get_table_rows code=proton.swaps scope=proton.swaps table=pools` for the current set rather than hard-coding a list.

For the canonical list of swap routes a MetalX user can actually take, see [docs.metalx.com](https://docs.metalx.com/) → *Swap pools and farms*.

### Execute a Swap

Swaps are done via token transfer to `proton.swaps` with a memo specifying the output token:

```bash
# Swap 1000 XPR → XUSDC (minimum 1 XUSDC out)
proton action eosio.token transfer \
  '{"from":"myaccount","to":"proton.swaps","quantity":"1000.0000 XPR","memo":"XPRUSDC,1"}' \
  myaccount

# Swap 10 XUSDC → XPR (minimum 1 XPR out)
proton action xtokens transfer \
  '{"from":"myaccount","to":"proton.swaps","quantity":"10.000000 XUSDC","memo":"XPRUSDC,1"}' \
  myaccount
```

**Memo format:** `<POOL_LT_SYMBOL>,<MIN_OUTPUT>`

- `POOL_LT_SYMBOL`: The LP token symbol (e.g., `XPRUSDC`)
- `MIN_OUTPUT`: Minimum amount to receive (slippage protection, use `1` for no minimum)

The contract automatically determines direction based on which token you send.

### Calculate Expected Output

For a constant-product AMM (x × y = k):

```
output = (input_amount × (10000 - exchange_fee) × output_reserve) / (input_reserve × 10000 + input_amount × (10000 - exchange_fee))
```

The pure AMM formula applies the **LP fee** to the input. To match on-chain output, deduct the **burns/grants fee first**, then run the formula with the LP fee — the contract does these in that order. Read both fee values from chain at runtime; the burns/grants slice is governance-mutable.

```typescript
function calculateSwapOutput(
  inputAmount: number,
  inputReserve: number,
  outputReserve: number,
  exchangeFee: number,    // pool LP fee in bps — read pools[i].fee.exchange_fee
  protocolFee: number     // burns/grants slice — read globall.exchange_fee_for_protocol
): number {
  // 1) Burns/Grants slice comes off the input first.
  const inputAfterProtocol = inputAmount * (10000 - protocolFee) / 10000;
  // 2) Then the AMM swap math applies the LP fee.
  const inputWithFee = inputAfterProtocol * (10000 - exchangeFee);
  return (inputWithFee * outputReserve) / (inputReserve * 10000 + inputWithFee);
}
```

### Slippage Protection

When calling `proton.swaps` directly (no MetalX UI to compute slippage for you), the **memo** carries the minimum-acceptable output as an integer (`<LT_SYMBOL>,<MIN_OUTPUT_RAW>`). If actual on-chain output falls below `<MIN_OUTPUT_RAW>` the contract reverts the swap and returns your input.

Compute `MIN_OUTPUT_RAW` from your expected output and a tolerance:

```typescript
function slippageProtectedMin(
  expectedOutput: number,        // from calculateSwapOutput, in human units
  outputPrecision: number,       // e.g. 6 for XUSDC, 4 for XPR, 8 for XBTC
  slippageBps: number = 50       // 50 = 0.5%; common defaults: 30 (0.3%), 50 (0.5%), 100 (1%)
): string {
  const minHuman = expectedOutput * (10_000 - slippageBps) / 10_000;
  // Convert to the raw-integer form the contract expects:
  const minRaw = Math.floor(minHuman * Math.pow(10, outputPrecision));
  return minRaw.toString();
}

// Example: swap 1000 XPR → XUSDC, expect 2.20 XUSDC, accept up to 0.5% slippage
const minOut = slippageProtectedMin(2.20, 6, 50);  // → "2189000"
const memo = `XPRUSDC,${minOut}`;
// "XPRUSDC,2189000" — contract will revert if final XUSDC out is below 2.189 XUSDC
```

**Rules of thumb:**

- **Stablecoin → stablecoin** swaps: 0.1–0.3% slippage is usually fine.
- **Volatile pair** with thin liquidity: 0.5–1% to absorb intra-block price drift.
- **Multi-hop via `proton.swaps`**: prefer the official routing API; manual multi-hop slippage compounds across legs and you'll need to widen tolerance per hop.
- **Don't use `MIN_OUTPUT = 1`** in production — that disables slippage protection entirely. The doc snippet earlier uses `1` for clarity, not as a recommendation.

`maxSent` / `maxIn` works the same way for `EXACT_OUTPUT`-style swaps if/when the AMM exposes that mode; the current `proton.swaps` transfer-memo path is `EXACT_INPUT` only.

### Add Liquidity

`liquidityadd` consumes tokens from your **deposit balance** on `proton.swaps` — it does **not** pull from your wallet directly. Calling `liquidityadd` against an empty deposit balance fails with `insufficient balance`. The end-to-end flow is three steps:

1. **`depositprep`** — reserve rows in the `deposits` table for the two token symbols.
2. **`transfer` each token to `proton.swaps` with `memo: ""`** — credits the deposit balance.
3. **`liquidityadd`** — moves the deposited amounts into the pool and mints LP tokens.

> ⚠️ **Empty memo when depositing for liquidity.** `proton.swaps`'s transfer handler routes by memo:
> - `memo: ""` → credited to your deposit balance (this is what you want for `liquidityadd`)
> - `memo: "<LT_SYMBOL>,<MIN_OUT>"` → executes a swap (see "Execute a Swap" above)
> - Any other non-empty memo → contract assertion failure or, worse, attempts a swap against a missing pool and reverts the transfer (verify on testnet first).
>
> When prepping for `liquidityadd`, use `memo: ""`. Do **not** pass `"addliq:..."` or anything similar — there is no add-liquidity memo path.

#### `liquidityadd` parameters

| Param | Type | Description |
|-------|------|-------------|
| `owner` | name | Your account |
| `lt_symbol` | symbol | LP token symbol, e.g. `"8,XPRUSDC"` |
| `add_token1` | extended_asset | Amount of token A to consume from deposit balance |
| `add_token2` | extended_asset | Amount of token B to consume from deposit balance |
| `add_token1_min` | extended_asset | Minimum token A (slippage protection) |
| `add_token2_min` | extended_asset | Minimum token B (slippage protection) |

#### End-to-end CLI flow

```bash
# 1) Reserve deposit slots for both symbols.
proton action proton.swaps depositprep \
  '{"owner":"myaccount","symbols":[{"sym":"4,XPR","contract":"eosio.token"},{"sym":"6,XUSDC","contract":"xtokens"}]}' \
  myaccount

# 2) Transfer each token to proton.swaps with EMPTY memo to credit the deposit balance.
proton action eosio.token transfer \
  '{"from":"myaccount","to":"proton.swaps","quantity":"1000.0000 XPR","memo":""}' \
  myaccount
proton action xtokens transfer \
  '{"from":"myaccount","to":"proton.swaps","quantity":"2.200000 XUSDC","memo":""}' \
  myaccount

# 3) Add liquidity — must add both sides proportionally; mins protect against rebalance during the tx.
proton action proton.swaps liquidityadd \
  '{"owner":"myaccount","lt_symbol":"8,XPRUSDC","add_token1":{"quantity":"1000.0000 XPR","contract":"eosio.token"},"add_token2":{"quantity":"2.200000 XUSDC","contract":"xtokens"},"add_token1_min":{"quantity":"990.0000 XPR","contract":"eosio.token"},"add_token2_min":{"quantity":"2.178000 XUSDC","contract":"xtokens"}}' \
  myaccount
```

If `liquidityadd` reverts (e.g. price moved past your `_min` slippage bounds), the funds **remain in your deposit balance** — they're not lost. Call `withdrawall` to pull them back to your wallet, or retry with adjusted parameters.

### Remove Liquidity

```bash
# Remove liquidity — params are {owner, lt} where lt is an asset (the LP tokens to redeem)
proton action proton.swaps liquidityrmv \
  '{"owner":"myaccount","lt":"1000.00000000 XPRUSDC"}' \
  myaccount

# Withdraw returned tokens
proton action proton.swaps withdrawall '{"owner":"myaccount"}' myaccount
```

> ⚠️ Always call `withdrawall` after removing liquidity to receive your tokens back.

### Multi-Hop Swaps

For tokens without a direct pool (e.g., METAL → XUSDC), you need multiple swaps:

```
METAL → XPR (via METAL/XPR pool) → XUSDC (via XPR/XUSDC pool)
```

Each hop incurs the pool's exchange fee, making multi-hop trades more expensive.

### Arbitrage Considerations

- **Fees eat spread:** With ~0.3% total per hop (0.2% LP + 0.1% burns/grants — see *Exchange Fees* above), a round-trip (buy + sell) costs ~0.6%. Arbitrage only works if price discrepancy exceeds this.
- **Triangular routes:** 3-hop routes cost ~0.9% minimum in fees. In practice, pools on XPR Network are efficient enough that profitable cycles are rare.
- **Pool imbalances:** Large swaps can temporarily move pool prices. Watch for whale trades creating imbalances that revert over time.
- **DEX vs Swap divergence:** The order book (MetalX DEX) and AMM pools can diverge in price. Check both before trading.

---

## Resources

- **MetalX DEX**: https://metalx.com
- **XPR DEX Bot**: https://github.com/XPRNetwork/dex-bot
- **Oracle Feeds**: `oracles` contract on XPR Network
- **Proton Swaps**: AMM pools at `proton.swaps` contract
- **SimpleDEX**: Token launch + AMM at `simpledex` / `simplelaunch` — see `simpledex.md`
- **RPC Endpoints**: `proton.eosusa.io` (primary), `proton.protonuk.io`, `proton.cryptolions.io` (fallbacks)
