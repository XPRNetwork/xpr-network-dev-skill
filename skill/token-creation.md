# Token Creation on XPR Network

This guide covers creating and managing fungible tokens on XPR Network.

## Token Basics

### Token Structure

Tokens on XPR Network consist of:
- **Symbol**: 1-7 uppercase letters (e.g., `XPR`, `MYTOKEN`)
- **Precision**: Decimal places (0-18, typically 4-8)
- **Contract**: Account that hosts the token (e.g., `eosio.token`)
- **Supply**: Maximum and current circulating supply

### Common Token Contracts

| Token | Contract | Precision |
|-------|----------|-----------|
| XPR | `eosio.token` | 4 |
| XUSDT | `xtokens` | 6 |
| XUSDC | `xtokens` | 6 |
| XBTC | `xtokens` | 8 |
| LOAN | `loan.token` | 4 |

---

## Creating a Token

To create a custom token, you need to deploy your own token contract. The `xtokens` contract listed above is a system contract for official wrapped tokens (XUSDT, XUSDC, XBTC) and is not available for public use.

### Deploy Your Own Token Contract

#### 1. Create Token Contract

```typescript
// assembly/token.ts
import {
  Contract, Table, TableStore, Name, Asset, Symbol,
  check, requireAuth, isAccount, hasAuth, requireRecipient
} from 'proton-tsc';

// Currency stats table
@table("stat")
class CurrencyStats extends Table {
  constructor(
    public supply: Asset = new Asset(),
    public max_supply: Asset = new Asset(),
    public issuer: Name = new Name()
  ) { super(); }

  @primary
  get primary(): u64 { return this.supply.symbol.code(); }
}

// Account balances table
@table("accounts")
class Account extends Table {
  constructor(
    public balance: Asset = new Asset()
  ) { super(); }

  @primary
  get primary(): u64 { return this.balance.symbol.code(); }
}

@contract
class Token extends Contract {
  // Create a new token
  @action("create")
  create(issuer: Name, maximum_supply: Asset): void {
    requireAuth(this.receiver);

    const sym = maximum_supply.symbol;
    check(sym.isValid(), "Invalid symbol");
    check(maximum_supply.isValid(), "Invalid supply");
    check(maximum_supply.amount > 0, "Max supply must be positive");

    // TableStore's second argument is the SCOPE and its type is Name, not u64:
    // wrap the symbol code (`new Name(sym.code())`) and pass accounts by `owner`,
    // not `owner.N`.
    const statsTable = new TableStore<CurrencyStats>(this.receiver, new Name(sym.code()));
    check(!statsTable.exists(sym.code()), "Token already exists");

    const stats = new CurrencyStats(
      new Asset(0, sym),
      maximum_supply,
      issuer
    );
    statsTable.store(stats, this.receiver);
  }

  // Issue tokens to account
  @action("issue")
  issue(to: Name, quantity: Asset, memo: string): void {
    const sym = quantity.symbol;
    check(sym.isValid(), "Invalid symbol");
    check(memo.length <= 256, "Memo too long");

    const statsTable = new TableStore<CurrencyStats>(this.receiver, new Name(sym.code()));
    const stats = statsTable.requireGet(sym.code(), "Token does not exist");

    requireAuth(stats.issuer);

    check(quantity.isValid(), "Invalid quantity");
    check(quantity.amount > 0, "Must issue positive quantity");
    check(quantity.symbol == stats.max_supply.symbol, "Symbol mismatch");
    check(quantity.amount <= stats.max_supply.amount - stats.supply.amount, "Exceeds max supply");

    stats.supply.amount += quantity.amount;
    statsTable.update(stats, stats.issuer);

    this.addBalance(to, quantity, stats.issuer);
  }

  // Retire (burn) tokens
  @action("retire")
  retire(quantity: Asset, memo: string): void {
    const sym = quantity.symbol;
    check(sym.isValid(), "Invalid symbol");
    check(memo.length <= 256, "Memo too long");

    const statsTable = new TableStore<CurrencyStats>(this.receiver, new Name(sym.code()));
    const stats = statsTable.requireGet(sym.code(), "Token does not exist");

    requireAuth(stats.issuer);

    check(quantity.isValid(), "Invalid quantity");
    check(quantity.amount > 0, "Must retire positive quantity");
    check(quantity.symbol == stats.supply.symbol, "Symbol mismatch");

    stats.supply.amount -= quantity.amount;
    statsTable.update(stats, stats.issuer);

    this.subBalance(stats.issuer, quantity);
  }

  // Transfer tokens
  @action("transfer")
  transfer(from: Name, to: Name, quantity: Asset, memo: string): void {
    check(from != to, "Cannot transfer to self");
    requireAuth(from);
    check(isAccount(to), "Recipient does not exist");

    const sym = quantity.symbol;
    const statsTable = new TableStore<CurrencyStats>(this.receiver, new Name(sym.code()));
    const stats = statsTable.requireGet(sym.code(), "Token does not exist");

    // Notify sender and receiver
    requireRecipient(from);   // free function, not a Contract method
    requireRecipient(to);

    check(quantity.isValid(), "Invalid quantity");
    check(quantity.amount > 0, "Must transfer positive quantity");
    check(quantity.symbol == stats.supply.symbol, "Symbol mismatch");
    check(memo.length <= 256, "Memo too long");

    const payer = hasAuth(to) ? to : from;

    this.subBalance(from, quantity);
    this.addBalance(to, quantity, payer);
  }

  // Open balance (allows receiving without sender paying RAM)
  @action("open")
  open(owner: Name, symbol: Symbol, ram_payer: Name): void {
    requireAuth(ram_payer);

    const statsTable = new TableStore<CurrencyStats>(this.receiver, new Name(symbol.code()));
    check(statsTable.exists(symbol.code()), "Token does not exist");

    const accountsTable = new TableStore<Account>(this.receiver, owner);
    if (!accountsTable.exists(symbol.code())) {
      const account = new Account(new Asset(0, symbol));
      accountsTable.store(account, ram_payer);
    }
  }

  // Close zero balance
  @action("close")
  close(owner: Name, symbol: Symbol): void {
    requireAuth(owner);

    const accountsTable = new TableStore<Account>(this.receiver, owner);
    const account = accountsTable.requireGet(symbol.code(), "Balance not found");
    check(account.balance.amount == 0, "Cannot close non-zero balance");
    accountsTable.remove(account);
  }

  // Helper: subtract from balance
  private subBalance(owner: Name, value: Asset): void {
    // Asset.amount is i64 and isValid() accepts negatives: a negative subtract
    // would MINT tokens. Gate every balance mutation on a positive amount.
    check(value.amount > 0, "Amount must be positive");

    const accountsTable = new TableStore<Account>(this.receiver, owner);
    const from = accountsTable.requireGet(value.symbol.code(), "No balance");
    check(from.balance.amount >= value.amount, "Insufficient balance");

    from.balance.amount -= value.amount;
    accountsTable.update(from, owner);
  }

  // Helper: add to balance
  private addBalance(owner: Name, value: Asset, ram_payer: Name): void {
    check(value.amount > 0, "Amount must be positive");

    const accountsTable = new TableStore<Account>(this.receiver, owner);
    let to = accountsTable.get(value.symbol.code());

    if (!to) {
      to = new Account(value);
      accountsTable.store(to, ram_payer);
    } else {
      to.balance.amount += value.amount;
      accountsTable.update(to, ram_payer);
    }
  }
}
```

#### 2. Build and Deploy

```bash
# Build
npm run build

# Deploy
proton contract:set mytokencontract ./assembly/target

# Create token (1 billion max supply, 4 decimals)
proton action mytokencontract create \
  '{"issuer":"mytokencontract","maximum_supply":"1000000000.0000 MYTKN"}' \
  mytokencontract
```

#### 3. Issue Tokens

```bash
# Issue to yourself
proton action mytokencontract issue \
  '{"to":"mytokencontract","quantity":"1000000.0000 MYTKN","memo":"Initial issuance"}' \
  mytokencontract

# Transfer to users
proton action mytokencontract transfer \
  '{"from":"mytokencontract","to":"alice","quantity":"1000.0000 MYTKN","memo":"Airdrop"}' \
  mytokencontract
```

---

## Token Operations

### Check Token Supply

```bash
proton table mytokencontract stat
```

### Check Balance

```bash
proton table mytokencontract accounts alice
```

### Transfer Tokens (Frontend)

```typescript
async function transferToken(
  session: any,
  tokenContract: string,
  to: string,
  quantity: string,
  memo: string = ''
) {
  return session.transact({
    actions: [{
      account: tokenContract,
      name: 'transfer',
      authorization: [session.auth],
      data: {
        from: session.auth.actor,
        to,
        quantity,
        memo
      }
    }]
  }, { broadcast: true });
}

// Usage
await transferToken(session, 'mytokencontract', 'bob', '100.0000 MYTKN', 'Payment');
```

### Query Balance (Frontend)

```typescript
async function getTokenBalance(
  account: string,
  tokenContract: string,
  symbol: string
): Promise<string> {
  const { rows } = await rpc.get_table_rows({
    code: tokenContract,
    scope: account,
    table: 'accounts',
    limit: 100
  });

  const balance = rows.find((r: any) => r.balance.includes(symbol));
  return balance?.balance ?? `0.0000 ${symbol}`;
}
```

---

## Token with Extended Features

### Pausable Token

```typescript
@table("config", singleton)
class Config extends Table {
  constructor(
    public paused: boolean = false,
    public owner: Name = new Name()
  ) { super(); }
}

@action("transfer")
transfer(from: Name, to: Name, quantity: Asset, memo: string): void {
  const config = this.configSingleton.get();
  check(!config.paused, "Token transfers are paused");

  // The pause check is an ADDITION, not a replacement — every standard transfer
  // check still has to run, in full:
  check(from != to, "Cannot transfer to self");
  requireAuth(from);
  check(isAccount(to), "Recipient does not exist");
  check(quantity.isValid(), "Invalid quantity");
  check(quantity.amount > 0, "Must transfer positive quantity");
  check(memo.length <= 256, "Memo too long");

  requireRecipient(from);
  requireRecipient(to);

  this.subBalance(from, quantity);
  this.addBalance(to, quantity, hasAuth(to) ? to : from);
}

@action("pause")
pause(paused: boolean): void {
  const config = this.configSingleton.get();
  requireAuth(config.owner);
  config.paused = paused;
  this.configSingleton.set(config, this.receiver);
}
```

### Mintable Token (with cap)

```typescript
@action("mint")
mint(to: Name, quantity: Asset): void {
  const config = this.configSingleton.get();
  requireAuth(config.owner);

  check(quantity.isValid(), "Invalid quantity");
  // A negative amount would pass the cap check below and still credit `to`
  check(quantity.amount > 0, "Must mint positive quantity");

  // Check against max supply
  const statsTable = new TableStore<CurrencyStats>(this.receiver, new Name(quantity.symbol.code()));
  const stats = statsTable.requireGet(quantity.symbol.code(), "Token not found");

  check(quantity.symbol == stats.max_supply.symbol, "Symbol mismatch");
  check(
    stats.supply.amount + quantity.amount <= stats.max_supply.amount,
    "Would exceed max supply"
  );

  stats.supply.amount += quantity.amount;
  statsTable.update(stats, this.receiver);

  this.addBalance(to, quantity, this.receiver);
}
```

### Burnable Token

```typescript
@action("burn")
burn(from: Name, quantity: Asset, memo: string): void {
  requireAuth(from);
  check(memo.length <= 256, "Memo too long");

  const statsTable = new TableStore<CurrencyStats>(this.receiver, new Name(quantity.symbol.code()));
  const stats = statsTable.requireGet(quantity.symbol.code(), "Token not found");

  check(quantity.isValid(), "Invalid quantity");
  // Asset.amount is i64: a negative burn mints supply and credits `from`
  check(quantity.amount > 0, "Must burn positive quantity");
  check(quantity.symbol == stats.supply.symbol, "Symbol mismatch");

  this.subBalance(from, quantity);

  stats.supply.amount -= quantity.amount;
  statsTable.update(stats, from);
}
```

### Transfer Fee Token

```typescript
@table("config", singleton)
class Config extends Table {
  constructor(
    public fee_percent: u16 = 100,  // 1% = 100 basis points
    public fee_receiver: Name = new Name()
  ) { super(); }
}

@action("transfer")
transfer(from: Name, to: Name, quantity: Asset, memo: string): void {
  check(from != to, "Cannot transfer to self");
  requireAuth(from);
  check(isAccount(to), "Recipient does not exist");
  check(quantity.isValid(), "Invalid quantity");
  // Negative amount inverts the fee maths and credits `to` out of thin air
  check(quantity.amount > 0, "Must transfer positive quantity");
  check(memo.length <= 256, "Memo too long");

  // A token contract must notify both sides, or every notify-based dApp
  // integrating this token silently misses the transfer.
  requireRecipient(from);
  requireRecipient(to);

  const config = this.configSingleton.get();

  // Calculate fee
  const feeAmount = (quantity.amount * config.fee_percent) / 10000;
  const netAmount = quantity.amount - feeAmount;
  check(netAmount > 0, "Amount too small after fee");

  // Transfer net amount to recipient
  this.subBalance(from, quantity);
  this.addBalance(to, new Asset(netAmount, quantity.symbol), from);

  // Transfer fee to fee receiver
  if (feeAmount > 0) {
    this.addBalance(config.fee_receiver, new Asset(feeAmount, quantity.symbol), from);
  }
}
```

---

## Wrapped Tokens

Wrapped tokens represent assets from other chains:

### Wrap Pattern

```typescript
import { Table, TableStore, Name, Asset, Symbol, Utils, sha256,
         check, requireAuth } from 'proton-tsc';

@table("usedhashes")
class UsedHash extends Table {
  constructor(
    public key: u64 = 0,          // first 8 bytes of sha256(txHash)
    public tx_hash: string = ""   // full hash kept so a key collision is visible
  ) { super(); }

  @primary
  get primary(): u64 { return this.key; }
}

// Table primary keys are u64, so a hex tx hash has to be folded down to one.
private hashKey(txHash: string): u64 {
  const digest = sha256(Utils.stringToU8Array(txHash)).data;
  let key: u64 = 0;
  for (let i = 0; i < 8; i++) {
    key = (key << 8) | <u64>digest[i];
  }
  return key;
}

@action("wrap")
wrap(account: Name, amount: u64, txHash: string): void {
  // Only bridge contract can wrap
  requireAuth(this.receiver);

  check(amount > 0, "Amount must be positive");
  check(txHash.length > 0, "Tx hash required");

  // Verify tx hash hasn't been used — exists() takes a u64 primary key
  const key = this.hashKey(txHash);
  check(!this.usedHashes.exists(key), "Already wrapped");

  // Record hash
  this.usedHashes.store(new UsedHash(key, txHash), this.receiver);

  // Mint wrapped tokens
  const quantity = new Asset(amount, WRAPPED_SYMBOL);
  this.addBalance(account, quantity, this.receiver);
}

@action("unwrap")
unwrap(account: Name, quantity: Asset, destinationAddress: string): void {
  requireAuth(account);

  check(quantity.isValid(), "Invalid quantity");
  // Negative amount would turn this burn into a mint
  check(quantity.amount > 0, "Must unwrap positive quantity");
  check(quantity.symbol == WRAPPED_SYMBOL, "Wrong token");
  check(destinationAddress.length > 0, "Destination address required");

  // Burn wrapped tokens
  this.subBalance(account, quantity);

  // Emit event for bridge to process
  // (Bridge monitors this and releases original tokens)
}
```

---

## Listing a Token on MetalX

**Listing isn't self-serve.** Pool creation on `proton.swaps` (the contract behind MetalX's Swap UI) is gated — there's no action a token issuer can call to spin up a pool on their own. New tokens are admitted through the XPR Network governance DAO:

- **Governance community:** <https://gov.xprnetwork.org/communities/7>

Submit your listing request there; voters decide. Once a pool exists for your token, the technical seed-liquidity flow (`depositprep` → empty-memo transfers → `liquidityadd`) is documented in `defi-trading.md` → *Proton Swaps (AMM Liquidity Pools)* → *Add Liquidity*. This file stays focused on what a token issuer can do unilaterally (deploy, issue, airdrop).

---

## Airdrop Tokens

### Batch Transfer Script

```typescript
async function airdrop(
  recipients: Array<{ account: string; amount: string }>,
  tokenContract: string,
  batchSize: number = 50
) {
  for (let i = 0; i < recipients.length; i += batchSize) {
    const batch = recipients.slice(i, i + batchSize);

    const actions = batch.map(r => ({
      account: tokenContract,
      name: 'transfer',
      authorization: [{ actor: issuer, permission: 'active' }],
      data: {
        from: issuer,
        to: r.account,
        quantity: r.amount,
        memo: 'Airdrop'
      }
    }));

    // Sign via proton CLI keychain — see backend-patterns.md for createCliSession setup
    await session.link.transact({ actions }, { blocksBehind: 3, expireSeconds: 30 });

    // Rate limit
    await new Promise(r => setTimeout(r, 500));
  }
}
```

---

## Token Vesting

```typescript
import { Contract, Table, TableStore, Name, Asset, Symbol, U128,
         check, requireAuth, currentTimeSec } from 'proton-tsc';
import { sendTransferToken } from 'proton-tsc/token';

const TOKEN_CONTRACT = Name.fromString("mytokencontract");
const VEST_SYMBOL = new Symbol("MYTKN", 4);

@table("vesting")
class VestingSchedule extends Table {
  constructor(
    public id: u64 = 0,
    public beneficiary: Name = new Name(),
    public total_amount: u64 = 0,
    public claimed_amount: u64 = 0,
    public start_time: u64 = 0,
    public cliff_duration: u64 = 0,
    public vesting_duration: u64 = 0
  ) { super(); }

  @primary
  get primary(): u64 { return this.id; }

  @secondary
  get byBeneficiary(): u64 { return this.beneficiary.N; }
}

@action("createvest")
createVesting(
  beneficiary: Name,
  amount: Asset,
  cliffDays: u32,
  vestingDays: u32
): void {
  requireAuth(this.receiver);

  check(amount.amount > 0, "Amount must be positive");
  check(vestingDays > 0, "Vesting duration must be positive");
  check(vestingDays >= cliffDays, "Cliff longer than vesting period");

  const schedule = new VestingSchedule(
    this.vestingTable.availablePrimaryKey,
    beneficiary,
    amount.amount,
    0,
    currentTimeSec(),
    // Cast BEFORE multiplying: `cliffDays * 86400` is u32 arithmetic and wraps
    // above ~49,710 days.
    <u64>cliffDays * 86400,
    <u64>vestingDays * 86400
  );

  this.vestingTable.store(schedule, this.receiver);
}

@action("claim")
claim(vestingId: u64): void {
  const schedule = this.vestingTable.requireGet(vestingId, "Vesting not found");
  requireAuth(schedule.beneficiary);

  const now = currentTimeSec();
  const elapsed = now - schedule.start_time;

  // Check cliff
  check(elapsed >= schedule.cliff_duration, "Still in cliff period");

  // Calculate vested amount
  let vestedAmount: u64;
  if (elapsed >= schedule.vesting_duration) {
    vestedAmount = schedule.total_amount;
  } else {
    // total_amount * elapsed overflows u64 for large grants over long schedules
    // (e.g. 1e14 units * 1e8 seconds), so do the multiply in u128.
    vestedAmount = (U128.from(schedule.total_amount) * U128.from(elapsed)
                    / U128.from(schedule.vesting_duration)).toU64();
  }

  const claimable = vestedAmount - schedule.claimed_amount;
  check(claimable > 0, "Nothing to claim");

  // Update claimed
  schedule.claimed_amount += claimable;
  this.vestingTable.update(schedule, this.receiver);

  // Transfer tokens — sendTransferToken from 'proton-tsc/token' is the SDK's
  // inline eosio.token::transfer; there is no `transferTokens` helper.
  sendTransferToken(
    TOKEN_CONTRACT,
    this.receiver,
    schedule.beneficiary,
    new Asset(claimable, VEST_SYMBOL),
    `Vesting claim #${schedule.id}`
  );
}
```

---

## Quick Reference

### Token Creation Commands

```bash
# Create token (via CLI)
proton action TOKEN_CONTRACT create '{"issuer":"ISSUER","maximum_supply":"AMOUNT SYMBOL"}' TOKEN_CONTRACT

# Issue tokens
proton action TOKEN_CONTRACT issue '{"to":"RECIPIENT","quantity":"AMOUNT SYMBOL","memo":""}' ISSUER

# Transfer
proton action TOKEN_CONTRACT transfer '{"from":"FROM","to":"TO","quantity":"AMOUNT SYMBOL","memo":""}' FROM

# Check supply
proton table TOKEN_CONTRACT stat

# Check balance
proton table TOKEN_CONTRACT accounts ACCOUNT
```

### Symbol Format

```
"1000.0000 XPR"    # 4 decimals
"1.000000 XUSDT"   # 6 decimals
"0.00000001 XBTC"  # 8 decimals
```

Always match the precision defined when token was created.
