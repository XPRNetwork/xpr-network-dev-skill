# Oracles and Random Number Generation

This guide covers using price oracles and generating random numbers on XPR Network.

## Price Oracles

XPR Network provides on-chain price feeds through the `oracles` contract for DeFi applications, trading, and price-dependent logic.

### Available Price Feeds

**This is the canonical feed table for the skill** — `rpc-queries.md`, `resources.md`, and `loan-protocol.md` carry short excerpts and point here. Liveness verified 2026-09-01 against `oracles::feed` actions on Hyperion (the `data.points` array is per-provider and can look stale even for live feeds — check feed actions, not points).

| Index | Pair | Notes |
|-------|------|-------|
| 2 | XPR/BTC | 14-day average — updates infrequently by design |
| 3 | XPR/USD | 10-min average; the primary XPR price feed |
| 4 | BTC/USD | |
| 6 | MTL/USD | Priced from XMT (the XPR Network representation of MTL) |
| 7 | ETH/USD | |
| 8 | DOGE/USD | |
| 9 | USDT/USD | Live dollar reference |
| 13 | BUSD/USD | still updated |
| 14 | PAX/USD | |
| 15 | TUSD/USD | |
| 16 | LTC/USD | |
| 17 | PYUSD/USD | |
| 18 | XRP/USD | |
| 19 | SOL/USD | |
| 21 | HBAR/USD | |
| 22 | ADA/USD | |
| 23 | XLM/USD | |
| 24 | SNIPS/USD | |
| 25 | AVAX/USD | |

> **Dormant indices — do not use:** `5` (USDC/USD), `10`, `11`, `12` (XMD/USD), `20` exist in the `feeds` table but have received no updates for 1+ years. Index 12 is the trap: XMD is a live token but its oracle feed is dead — use `9` (USDT/USD) as the dollar reference instead. Query the live set yourself:
>
> ```bash
> curl -s -X POST https://proton.eosusa.io/v1/chain/get_table_rows \
>   -H 'Content-Type: application/json' \
>   -d '{"code":"oracles","scope":"oracles","table":"feeds","limit":100,"json":true}'
> ```

### Query Oracle Price

#### Via CLI

```bash
proton table oracles data -l 4 -u 4
```

#### Via Code

```typescript
interface OracleData {
  feed_index: number;
  aggregate: {
    d_double: string;   // aggregate is a variant: d_string | d_uint64_t | d_double
  };
  points: {             // one entry per provider submission (no top-level timestamp)
    provider: string;
    time: string;       // ISO time without 'Z' — append 'Z' before Date.parse
    data: { d_double?: string };
  }[];
}

async function getOraclePrice(feedIndex: number): Promise<number> {
  const { rows } = await rpc.get_table_rows({
    code: 'oracles',
    scope: 'oracles',
    table: 'data',
    lower_bound: feedIndex,
    upper_bound: feedIndex,
    limit: 1
  });

  if (rows.length === 0) {
    throw new Error(`Oracle feed ${feedIndex} not found`);
  }

  return parseFloat(rows[0].aggregate.d_double);
}

// Examples
const btcPrice = await getOraclePrice(4);   // BTC/USD
const ethPrice = await getOraclePrice(7);   // ETH/USD
const xprPrice = await getOraclePrice(3);   // XPR/USD
```

### Use Oracle in Smart Contract

```typescript
import { Contract, TableStore, check, currentTimeSec } from 'proton-tsc';
// proton-tsc ships the oracle table classes: Data { feed_index, aggregate: DataVariant, points: ProviderPoint[] }.
// `aggregate` is a variant (d_string | d_uint64_t | d_double) — a plain f64 field would mis-deserialize.
import { Data, ORACLES_CONTRACT } from 'proton-tsc/oracles';

const MAX_PRICE_AGE_SEC: u32 = 900;  // tune per feed; index 2 (XPR/BTC) is a 14-day average

@contract
class MyContract extends Contract {

  @action("checkprice")
  checkPrice(feedIndex: u64, minPrice: u64): void {
    // Query oracle table (code = scope = "oracles")
    const oracleTable = new TableStore<Data>(ORACLES_CONTRACT, ORACLES_CONTRACT);

    const data = oracleTable.requireGet(feedIndex, "Oracle feed not found");

    // WHY: a `data` row is never removed, so a dead feed still reads fine and
    // returns a year-old price. Freshness = newest provider submission;
    // the row has no top-level timestamp.
    let newest: u32 = 0;
    for (let i = 0; i < data.points.length; i++) {
      const t = data.points[i].time.secSinceEpoch();
      if (t > newest) newest = t;
    }
    check(newest > 0, "Oracle feed has no submissions");
    check(currentTimeSec() - newest <= MAX_PRICE_AGE_SEC, "Oracle price is stale");

    const price = <u64>(data.aggregate.f64Value * 10000); // f64Value asserts the variant holds a double

    check(price > 0, "Oracle price is zero");
    check(price >= minPrice, "Price below minimum");
  }
}
```

### Oracle Update Frequency

- Price feeds are updated by authorized oracle providers
- Typical update frequency: every few seconds to minutes
- Check freshness via `points[].time` (per-provider submission times) — the `data` row has no top-level timestamp

### Price Calculation Tips

```typescript
// Oracle prices have varying precision
// BTC might be 95322.71, XPR might be 0.00087

// Convert to consistent precision (e.g., 8 decimals)
function normalizePrice(price: number, decimals: number = 8): bigint {
  return BigInt(Math.round(price * Math.pow(10, decimals)));
}

// Calculate value
function calculateValue(amount: number, price: number): number {
  return amount * price;
}

// Example: Value of 1000 XPR
const xprPrice = await getOraclePrice(3);  // e.g., 0.00087
const xprValue = calculateValue(1000, xprPrice);  // $0.87
```

---

## Random Number Generation (RNG)

XPR Network provides verifiable random numbers through the `rng` contract. This is essential for:
- Games and gambling
- Lotteries and raffles
- Random NFT attributes
- Fair selection mechanisms

### How It Works

The RNG system uses an **oracle-based commit-reveal pattern**:

1. Your contract calls `rng::requestrand` with a unique signing value
2. Off-chain oracle generates random value using RSA signatures
3. Oracle calls `rng::setrand` with the cryptographic proof
4. RNG contract verifies the RSA-SHA256 signature
5. RNG contract calls your contract's `receiverand` action with the result

This ensures randomness cannot be predicted or manipulated.

### RNG Contract

| Contract | Account |
|----------|---------|
| RNG Oracle | `rng` |

**Repository:** https://github.com/XPRNetwork/proton-rng

### Integration Steps

#### 1. Request Random Number

Your contract calls `requestrand` on the `rng` contract:

Use the helper `proton-tsc` ships — don't hand-roll the `@packer`/`InlineAction` pair:

```typescript
import { Contract, Name, check, requireAuth, currentTimeSec } from 'proton-tsc';
import { sendRequestRandom } from 'proton-tsc/rng';

@contract
class MyGame extends Contract {

  @action("startgame")
  startGame(player: Name, gameId: u64): void {
    requireAuth(player);

    // signing_value must be unique per request — `rng` rejects a value it has seen
    const signingValue = this.generateSigningValue(gameId, player);

    // sendRequestRandom(contract, customerId, signingValue)
    // customerId comes back as `assoc_id` in the receiverand callback
    sendRequestRandom(this.receiver, gameId, signingValue);
  }

  private generateSigningValue(gameId: u64, player: Name): u64 {
    // Combine multiple values for uniqueness
    return gameId ^ player.N ^ <u64>currentTimeSec();
  }
}
```

#### 2. Receive Random Result

Implement the `receiverand` action in your contract:

```typescript
import { Name, Checksum256, check, requireAuth } from 'proton-tsc';
import { RNG_CONTRACT, rngChecksumToU64 } from 'proton-tsc/rng';

@contract
class MyGame extends Contract {

  // Called by RNG contract with the random result
  @action("receiverand")
  receiveRand(assoc_id: u64, random_value: Checksum256): void {
    // Only RNG contract can call this
    requireAuth(RNG_CONTRACT);

    // assoc_id is the customerId we passed to sendRequestRandom
    const gameId = assoc_id;

    // rngChecksumToU64(checksum, maxValue) folds the first 8 bytes and takes a modulus
    const roll = rngChecksumToU64(random_value, 100);  // 0..99

    // Use the random number in your game logic
    this.resolveGame(gameId, roll);
  }

  private resolveGame(gameId: u64, roll: u64): void {
    // Your game resolution logic
    // e.g., pick winner, determine outcome, etc.
  }
}
```

`random_value` is 32 bytes; `rngChecksumToU64` only consumes the first 8. For several
independent draws, slice different byte ranges yourself (see the slot machine below).

#### 3. Enable Inline Actions

`eosio.code` is what lets your contract **send** the `requestrand` inline action — it is
not needed to receive the callback (`rng` calls `receiverand` under its own authority).
You need it anyway, plus for any payout transfer you send:

```bash
proton contract:enableinline mycontract
```

### Complete Example: Coin Flip Game

The bet **is** the transfer. There is no `flip` action taking a `bet` argument — an
action argument is a claim, a transfer notification is a fact.

```typescript
import {
  Contract, Table, TableStore, Name, Asset, Symbol,
  check, requireAuth, currentTimeSec, Checksum256
} from 'proton-tsc';
import { sendTransferToken } from 'proton-tsc/token';
import { RNG_CONTRACT, sendRequestRandom } from 'proton-tsc/rng';

const TOKEN_CONTRACT = Name.fromString("eosio.token");
const XPR = new Symbol("XPR", 4);

// Pending flip
@table("games")
class Game extends Table {
  constructor(
    public id: u64 = 0,
    public player: Name = new Name(),
    public bet: u64 = 0,
    public choice: u8 = 0   // 0 = heads, 1 = tails
  ) { super(); }

  @primary
  get primary(): u64 { return this.id; }

  @secondary
  get byPlayer(): u64 { return this.player.N; }
}

@contract
class CoinFlip extends Contract {
  gamesTable: TableStore<Game> = new TableStore<Game>(this.receiver);

  @action("transfer", notify)
  onTransfer(from: Name, to: Name, quantity: Asset, memo: string): void {
    // WHY: any account can deploy a token contract that emits a transfer with
    // symbol `4,XPR`. Without firstReceiver the house pays real XPR for fake chips.
    if (this.firstReceiver != TOKEN_CONTRACT) return;
    if (to != this.receiver || from == this.receiver) return;
    if (memo != "heads" && memo != "tails") return;

    check(quantity.symbol == XPR, "Only XPR accepted");
    // Cap the stake so the house can always cover 2x
    check(quantity.amount >= 10000, "Minimum bet: 1 XPR");
    check(quantity.amount <= 10000000, "Maximum bet: 1000 XPR");

    // One pending flip per player — secondary index, not a table scan
    check(this.gamesTable.getBySecondaryU64(from.N, 0) == null, "Pending flip exists");

    const choice: u8 = memo == "heads" ? 0 : 1;
    const gameId = this.gamesTable.availablePrimaryKey;
    // Bet comes from `quantity`, never from a caller-supplied argument
    const game = new Game(gameId, from, <u64>quantity.amount, choice);
    this.gamesTable.store(game, this.receiver);  // contract pays RAM

    const signingValue = gameId ^ from.N ^ <u64>currentTimeSec();
    sendRequestRandom(this.receiver, gameId, signingValue);
  }

  @action("receiverand")
  receiveRand(assoc_id: u64, random_value: Checksum256): void {
    requireAuth(RNG_CONTRACT);

    const game = this.gamesTable.requireGet(assoc_id, "Game not found");

    const outcome: u8 = <u8>(random_value.data[0] % 2);
    const won = outcome == game.choice;

    // Remove first: settles the row and frees the player's pending slot
    this.gamesTable.remove(game);

    if (won) {
      const payout = game.bet * 2 * 95 / 100;  // 5% house edge
      sendTransferToken(TOKEN_CONTRACT, this.receiver, game.player,
        new Asset(<i64>payout, XPR), "Coin flip win");
    }
  }
}
```

A losing flip keeps the stake because it already arrived. Nothing needs collecting.

### Real-World Example: Slot Machine

This example demonstrates a more complex RNG use case with weighted symbol selection (based on the xpr-slots contract):

```typescript
import {
  Contract, Table, TableStore, Name, Asset,
  check, requireAuth, currentTimeSec, Checksum256, Symbol
} from 'proton-tsc';
import { sendTransferToken } from 'proton-tsc/token';
import { RNG_CONTRACT, sendRequestRandom } from 'proton-tsc/rng';

const TOKEN_CONTRACT = Name.fromString("eosio.token");
const XPR = new Symbol("XPR", 4);

// Pending game tracking
@table("games")
class Game extends Table {
  constructor(
    public id: u64 = 0,
    public player: Name = new Name(),
    public bet: u64 = 0,
    public timestamp: u64 = 0
  ) { super(); }

  @primary
  get primary(): u64 { return this.id; }

  @secondary
  get byPlayer(): u64 { return this.player.N; }
}

// Spin results (historical record)
@table("spinresults")
class SpinResult extends Table {
  constructor(
    public id: u64 = 0,
    public player: Name = new Name(),
    public reel1: u8 = 0,
    public reel2: u8 = 0,
    public reel3: u8 = 0,
    public betAmount: u64 = 0,
    public payout: u64 = 0,
    public jackpotWon: boolean = false,
    public timestamp: u64 = 0
  ) { super(); }

  @primary
  get primary(): u64 { return this.id; }
}

@contract
class SlotMachine extends Contract {
  gamesTable: TableStore<Game> = new TableStore<Game>(this.receiver);
  resultsTable: TableStore<SpinResult> = new TableStore<SpinResult>(this.receiver);

  // Symbol weights (higher = more common)
  // Total: 125 (for easy percentage calculation)
  static readonly WEIGHTS: u8[] = [40, 30, 25, 20, 10]; // Lemon, Cherry, Bell, Bar, Seven
  static readonly TOTAL_WEIGHT: u8 = 125;

  // Handle incoming transfer (player sends XPR to play)
  @action("transfer", notify)
  onTransfer(from: Name, to: Name, quantity: Asset, memo: string): void {
    // WHY: `notify` fires for ANY token contract that names us. Without this the
    // house pays real XPR out for a worthless token minted to look like `4,XPR`.
    if (this.firstReceiver != TOKEN_CONTRACT) return;
    if (to != this.receiver || from == this.receiver) return;
    if (memo != "spin") return;

    check(quantity.symbol == XPR, "Only XPR accepted");
    check(quantity.amount >= 10000, "Minimum bet: 1 XPR");
    check(quantity.amount <= 10000000, "Maximum bet: 1000 XPR");

    // Check no pending game for this player (prevents double-spin exploit).
    // WHY secondary index: a full scan is O(table) CPU per transfer — anyone can
    // grow the table and then every spin blows the CPU limit.
    check(this.gamesTable.getBySecondaryU64(from.N, 0) == null,
      "Pending spin exists - please wait");

    // Create pending game — stake comes from `quantity`, never from an argument
    const gameId = this.gamesTable.availablePrimaryKey;
    const game = new Game(gameId, from, <u64>quantity.amount, currentTimeSec());
    this.gamesTable.store(game, this.receiver);

    // Request random from oracle
    const signingValue = gameId ^ from.N ^ <u64>currentTimeSec();
    sendRequestRandom(this.receiver, gameId, signingValue);
  }

  @action("receiverand")
  receiveRand(assoc_id: u64, random_value: Checksum256): void {
    requireAuth(RNG_CONTRACT);

    const game = this.gamesTable.requireGet(assoc_id, "Game not found");

    // Extract 3 independent random values from the 32-byte hash
    // Using different portions ensures independence
    const rand1 = this.bytesToU64(random_value.data, 0);   // bytes 0-7
    const rand2 = this.bytesToU64(random_value.data, 8);   // bytes 8-15
    const rand3 = this.bytesToU64(random_value.data, 16);  // bytes 16-23

    // Convert to weighted symbols
    const reel1 = this.getWeightedSymbol(rand1);
    const reel2 = this.getWeightedSymbol(rand2);
    const reel3 = this.getWeightedSymbol(rand3);

    // Calculate payout
    const payout = this.calculatePayout(reel1, reel2, reel3, game.bet);
    const isJackpot = reel1 == 4 && reel2 == 4 && reel3 == 4; // Three 7s

    // Store result
    const result = new SpinResult(
      this.resultsTable.availablePrimaryKey,
      game.player, reel1, reel2, reel3,
      game.bet, payout, isJackpot, currentTimeSec()
    );
    this.resultsTable.store(result, this.receiver);

    // Remove pending game
    this.gamesTable.remove(game);

    // Pay winner
    if (payout > 0) {
      sendTransferToken(TOKEN_CONTRACT, this.receiver, game.player,
        new Asset(<i64>payout, XPR), "Slot win!");
    }
  }

  // Convert random u64 to weighted symbol index
  private getWeightedSymbol(random: u64): u8 {
    const value = <u8>(random % SlotMachine.TOTAL_WEIGHT);
    let cumulative: u8 = 0;

    for (let i = 0; i < SlotMachine.WEIGHTS.length; i++) {
      cumulative += SlotMachine.WEIGHTS[i];
      if (value < cumulative) {
        return <u8>i;
      }
    }
    return 0;
  }

  // Payout calculation based on symbol combination
  private calculatePayout(r1: u8, r2: u8, r3: u8, bet: u64): u64 {
    // Three of a kind
    if (r1 == r2 && r2 == r3) {
      if (r1 == 4) return this.getJackpotPayout(bet); // 7-7-7 Jackpot
      if (r1 == 1) return bet * 5;                   // Cherry 5x
      if (r1 == 3) return bet * 3;                   // Bar 3x
      if (r1 == 2) return bet * 2;                   // Bell 2x
      if (r1 == 0) return bet * 3 / 2;               // Lemon 1.5x
    }
    // Any two matching
    if (r1 == r2 || r2 == r3 || r1 == r3) {
      return bet / 2;                                // 0.5x
    }
    return 0;
  }

  private bytesToU64(bytes: u8[], offset: i32): u64 {
    let result: u64 = 0;
    for (let i = 0; i < 8; i++) {
      result = (result << 8) | <u64>bytes[offset + i];
    }
    return result;
  }

  private getJackpotPayout(bet: u64): u64 {
    // WHY a multiple of the wager, not a fixed pool: a flat 10,000 XPR jackpot on a
    // 1 XPR minimum bet is EV ~5.5x stake — min-bet spam drains the contract.
    // Every payout here is a multiple of `bet`, so the house edge holds at any stake.
    // Bound your bankroll accordingly: max bet 1000 XPR x 50 = 50,000 XPR exposure.
    return bet * 50;
  }
}
```

**Key patterns from this example:**

1. **Pending game tracking**: Prevent players from spamming spins while one is pending
2. **Multiple random values**: Extract independent values from different portions of the 32-byte hash
3. **Weighted randomness**: Use cumulative weights for non-uniform probability distributions
4. **Transfer notification**: Trigger game logic on incoming token transfer with memo — always gate on `this.firstReceiver` and the symbol before trusting `quantity`
5. **Historical records**: Store spin results for transparency/verification

---

### RNG Best Practices

1. **Unique Signing Values**
   ```typescript
   // Good - combine multiple sources
   const signingValue = gameId ^ player.N ^ currentTimeSec() ^ nonce;

   // Bad - predictable or reused
   const signingValue = gameId;  // Could be reused
   ```

2. **Validate Callback Source**
   ```typescript
   @action("receiverand")
   receiveRand(assoc_id: u64, random_value: Checksum256): void {
     // ALWAYS check caller is RNG contract
     requireAuth(Name.fromString("rng"));
     // ...
   }
   ```

3. **Handle Pending State**
   ```typescript
   // Track that game is waiting for random
   game.status = PENDING_RANDOM;

   // Prevent double-requests
   check(game.status != PENDING_RANDOM, "Already waiting for random");
   ```

4. **Use Full Entropy**
   ```typescript
   // Checksum256 has 32 bytes of entropy
   // Use different bytes for different purposes
   const result1 = random_value.data[0] % 6 + 1;  // Dice roll
   const result2 = random_value.data[4] % 52;     // Card draw
   ```

### Alternative: Block-Based Randomness

For lower-stakes applications, you can use block data for pseudo-randomness:

```typescript
import { currentBlockNum, currentTimeSec, taposBlockPrefix } from 'proton-tsc';

// WARNING: This is predictable by block producers!
// Only use for low-value, non-critical randomness

function pseudoRandom(seed: u64): u64 {
  const blockNum = currentBlockNum();
  const blockPrefix = taposBlockPrefix();
  const time = currentTimeSec();

  // Mix values
  return seed ^ blockNum ^ blockPrefix ^ time;
}
```

**When to use block-based:**
- Random cosmetic effects
- Non-valuable outcomes
- Development/testing

**When to use RNG oracle:**
- Games with real value
- Lotteries and raffles
- NFT rarity determination
- Any high-stakes randomness

---

## Multi-Oracle Patterns

### Price Aggregation

For critical applications, aggregate multiple sources:

```typescript
async function getAggregatedPrice(feedIndex: number): Promise<number> {
  // Query on-chain oracle
  const onChainPrice = await getOraclePrice(feedIndex);

  // Could also fetch from external APIs and compare
  // Reject if prices differ significantly

  return onChainPrice;
}
```

### Staleness Check

```typescript
async function getFreshPrice(feedIndex: number, maxAgeSeconds: number): Promise<number> {
  const { rows } = await rpc.get_table_rows({
    code: 'oracles',
    scope: 'oracles',
    table: 'data',
    lower_bound: feedIndex,
    upper_bound: feedIndex,
    limit: 1
  });

  if (rows.length === 0) {
    throw new Error('Oracle feed not found');
  }

  const data = rows[0];
  // Freshness = newest provider submission (rows carry no top-level timestamp)
  const timestamp = Math.max(...data.points.map((p: any) => Date.parse(p.time + 'Z')));
  const age = (Date.now() - timestamp) / 1000;

  if (age > maxAgeSeconds) {
    throw new Error(`Oracle data stale: ${age}s old (max ${maxAgeSeconds}s)`);
  }

  return parseFloat(data.aggregate.d_double);
}
```

---

## Quick Reference

### Oracle Queries

```bash
# Get BTC price
proton table oracles data -l 4 -u 4

# Get all oracle feeds
proton table oracles data
```

### RNG Contract

| Action | Description |
|--------|-------------|
| `requestrand` | Request random number |
| `setrand` | Oracle delivers random (internal) |
| `killjobs` | Cancel pending requests |
| `pause` | Pause contract (admin) |

### Key Tables

| Contract | Table | Description |
|----------|-------|-------------|
| `oracles` | `data` | Price feed data |
| `rng` | `jobs.a` | Pending random requests |
| `rng` | `signvals.a` | Used signing values |
| `rng` | `config.a` | RNG configuration |

### Integration Checklist

- [ ] Enable inline actions on your contract
- [ ] Implement `receiverand` action
- [ ] Validate `rng` is the caller in `receiverand`
- [ ] Generate unique signing values
- [ ] Handle pending game state
- [ ] Test on testnet first
