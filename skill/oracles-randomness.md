# Oracles and Random Number Generation

This guide covers using price oracles and generating random numbers on XPR Network.

## Price Oracles

XPR Network provides on-chain price feeds through the `oracles` contract for DeFi applications, trading, and price-dependent logic.

### Available Price Feeds

| Index | Pair | Description |
|-------|------|-------------|
| 1 | XPR/USD | XPR Network token |
| 4 | BTC/USD | Bitcoin |
| 5 | ETH/USD | Ethereum |
| 6 | USDC/USD | USD Coin |
| 7 | USDT/USD | Tether |
| 13 | XPR/USD | XPR (alternate index) |

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
    d_double: string;
  };
  timestamp: string;
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
const ethPrice = await getOraclePrice(5);   // ETH/USD
const xprPrice = await getOraclePrice(1);   // XPR/USD
```

### Use Oracle in Smart Contract

```typescript
import { Contract, Name, TableStore, check } from 'proton-tsc';

// Oracle data structure
@table("data", noabigen)
class OracleData extends Table {
  constructor(
    public feed_index: u64 = 0,
    public aggregate: OracleAggregate = new OracleAggregate()
  ) { super(); }

  @primary
  get primary(): u64 { return this.feed_index; }
}

class OracleAggregate {
  d_double: f64 = 0;
}

@contract
class MyContract extends Contract {

  @action("checkprice")
  checkPrice(feedIndex: u64, minPrice: u64): void {
    // Query oracle table
    const oracleTable = new TableStore<OracleData>(
      Name.fromString("oracles"),
      Name.fromString("oracles").N
    );

    const data = oracleTable.requireGet(feedIndex, "Oracle feed not found");
    const price = <u64>(data.aggregate.d_double * 10000); // Convert to u64

    check(price >= minPrice, "Price below minimum");
  }
}
```

### Oracle Update Frequency

- Price feeds are updated by authorized oracle providers
- Typical update frequency: every few seconds to minutes
- Check `timestamp` field to verify data freshness

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
const xprPrice = await getOraclePrice(1);  // e.g., 0.00087
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

```typescript
import {
  Contract, Name, InlineAction, PermissionLevel,
  ActionData, check, requireAuth
} from 'proton-tsc';

@packer
class RequestRandParams extends ActionData {
  constructor(
    public assoc_id: u64 = 0,
    public signing_value: u64 = 0,
    public caller: Name = new Name()
  ) { super(); }
}

@contract
class MyGame extends Contract {

  @action("startgame")
  startGame(player: Name, gameId: u64): void {
    requireAuth(player);

    // Generate unique signing value (must be unique per request)
    const signingValue = this.generateSigningValue(gameId, player);

    // Request random number from oracle
    const requestAction = new InlineAction<RequestRandParams>("requestrand")
      .act(Name.fromString("rng"), new PermissionLevel(this.receiver))
      .send(new RequestRandParams(
        gameId,           // assoc_id - returned in callback
        signingValue,     // signing_value - must be unique
        this.receiver     // caller - your contract
      ));
  }

  private generateSigningValue(gameId: u64, player: Name): u64 {
    // Combine multiple values for uniqueness
    return gameId ^ player.N ^ currentTimeSec();
  }
}
```

#### 2. Receive Random Result

Implement the `receiverand` action in your contract:

```typescript
import { Name, Checksum256, check, requireAuth } from 'proton-tsc';

@contract
class MyGame extends Contract {

  // Called by RNG contract with the random result
  @action("receiverand")
  receiveRand(assoc_id: u64, random_value: Checksum256): void {
    // Only RNG contract can call this
    requireAuth(Name.fromString("rng"));

    // assoc_id is the gameId we passed in requestrand
    const gameId = assoc_id;

    // random_value is a SHA256 hash - use it for randomness
    const randomBytes = random_value.data;

    // Convert to usable random number
    const randomNumber = this.bytesToU64(randomBytes);

    // Use the random number in your game logic
    this.resolveGame(gameId, randomNumber);
  }

  private bytesToU64(bytes: u8[]): u64 {
    let result: u64 = 0;
    for (let i = 0; i < 8 && i < bytes.length; i++) {
      result = (result << 8) | <u64>bytes[i];
    }
    return result;
  }

  private resolveGame(gameId: u64, randomNumber: u64): void {
    // Your game resolution logic
    // e.g., pick winner, determine outcome, etc.
  }
}
```

#### 3. Enable Inline Actions

Your contract needs `eosio.code` permission to receive callbacks:

```bash
proton contract:enableinline mycontract
```

### Complete Example: Coin Flip Game

```typescript
import {
  Contract, Table, TableStore, Name, Asset,
  InlineAction, PermissionLevel, ActionData,
  check, requireAuth, currentTimeSec, Checksum256
} from 'proton-tsc';

// Game state
@table("games")
class Game extends Table {
  constructor(
    public id: u64 = 0,
    public player: Name = new Name(),
    public bet: u64 = 0,
    public choice: u8 = 0,  // 0 = heads, 1 = tails
    public status: u8 = 0,  // 0 = pending, 1 = resolved
    public won: boolean = false
  ) { super(); }

  @primary
  get primary(): u64 { return this.id; }
}

@packer
class RequestRandParams extends ActionData {
  constructor(
    public assoc_id: u64 = 0,
    public signing_value: u64 = 0,
    public caller: Name = new Name()
  ) { super(); }
}

@contract
class CoinFlip extends Contract {
  gamesTable: TableStore<Game> = new TableStore<Game>(this.receiver);

  @action("flip")
  flip(player: Name, choice: u8, bet: Asset): void {
    requireAuth(player);
    check(choice == 0 || choice == 1, "Choice must be 0 (heads) or 1 (tails)");
    check(bet.amount > 0, "Bet must be positive");

    // Create game
    const gameId = this.gamesTable.availablePrimaryKey;
    const game = new Game(gameId, player, bet.amount, choice, 0, false);
    this.gamesTable.store(game, player);

    // Transfer bet to contract
    // (would need inline action to eosio.token::transfer)

    // Request random number
    const signingValue = gameId ^ player.N ^ currentTimeSec();

    new InlineAction<RequestRandParams>("requestrand")
      .act(Name.fromString("rng"), new PermissionLevel(this.receiver))
      .send(new RequestRandParams(gameId, signingValue, this.receiver));
  }

  @action("receiverand")
  receiveRand(assoc_id: u64, random_value: Checksum256): void {
    requireAuth(Name.fromString("rng"));

    const game = this.gamesTable.requireGet(assoc_id, "Game not found");
    check(game.status == 0, "Game already resolved");

    // Determine outcome (0 or 1 based on random)
    const randomByte = random_value.data[0];
    const outcome: u8 = randomByte % 2 == 0 ? 0 : 1;

    // Check if player won
    const won = outcome == game.choice;

    // Update game
    game.status = 1;
    game.won = won;
    this.gamesTable.update(game, this.receiver);

    // Pay winner (2x bet minus fee)
    if (won) {
      const payout = game.bet * 2 * 95 / 100;  // 5% house edge
      // Send payout via inline action
    }
  }
}
```

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
import { currentBlock, currentTimeSec, taposBlockPrefix } from 'proton-tsc';

// WARNING: This is predictable by block producers!
// Only use for low-value, non-critical randomness

function pseudoRandom(seed: u64): u64 {
  const blockNum = currentBlock();
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
  const timestamp = new Date(data.timestamp).getTime();
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
