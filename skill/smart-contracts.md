# Smart Contract Development on XPR Network

This guide covers AssemblyScript/TypeScript smart contract development using [`proton-tsc`](https://www.npmjs.com/package/proton-tsc) — the npm package that ships the SDK decorators and types. Build is via `proton-asc` (AssemblyScript compiler). Note: `@proton/ts-contracts` is **not** a real npm package; earlier docs cited that name in error.

> **Before deploying to mainnet**: Always review AI-generated code, test thoroughly on testnet, and consider having experienced developers review critical contracts. See `safety-guidelines.md` for essential deployment safety rules.

## Overview

XPR Network smart contracts are written in AssemblyScript (a TypeScript-like language that compiles to WebAssembly). The SDK provides decorators and utilities for defining tables, actions, and interacting with the blockchain.

## Project Setup

### Create New Contract

```bash
# Using CLI boilerplate
proton boilerplate myproject

# Or manually
mkdir mycontract && cd mycontract
npm init -y
npm install proton-tsc
```

### Project Structure

```
mycontract/
├── assembly/
│   ├── mycontract.contract.ts   # Main contract file (.contract.ts by convention)
│   └── target/                   # Build output (WASM + ABI)
├── package.json
└── tsconfig.json
```

By convention contract files are named `*.contract.ts` (the boilerplate and proton-tsc examples use it). The compiler locates the contract through the `@contract` decorator, not the filename; the build output is named after the source file (`mycontract.contract.wasm` / `.abi`).

### package.json Scripts

```json
{
  "scripts": {
    "build": "npx proton-asc ./assembly/mycontract.contract.ts"
  }
}
```

**Note**: The build command is `proton-asc` (AssemblyScript compiler), not `proton-tsc`. The `proton-tsc` package provides the TypeScript types and decorators, while `proton-asc` handles compilation.

---

## Tables (Storage)

Tables are like database tables - define columns (fields) and rows are stored with a primary key.

### Basic Table

```typescript
import { Table, Name } from 'proton-tsc';

@table("users")
export class User extends Table {
  constructor(
    public id: u64 = 0,
    public account: Name = new Name(),
    public balance: u64 = 0,
    public created_at: u64 = 0
  ) {
    super();
  }

  @primary
  get primary(): u64 {
    return this.id;
  }
}
```

### Table Naming Rules

- 1-12 characters
- Lowercase a-z and digits 1-5 only
- No dots, dashes, or uppercase

### Singleton Table (Single Row)

Singletons store a single configuration/state row without needing a primary key.

```typescript
import { Singleton } from 'proton-tsc';

@table("config", singleton)
export class Config extends Table {
  constructor(
    public owner: Name = new Name(),
    public paused: boolean = false,
    public fee_percent: u8 = 5
  ) {
    super();
  }
}

@contract
class MyContract extends Contract {
  // Initialize singleton with contract receiver
  configSingleton: Singleton<Config> = new Singleton<Config>(this.receiver);

  @action("init")
  init(owner: Name): void {
    // Without this the first caller of an undeployed-but-live contract wins ownership
    requireAuth(this.receiver);

    // Check if already initialized — get() never returns null (it returns a
    // default-constructed Config), so use getOrNull() for existence checks
    check(this.configSingleton.getOrNull() === null, "Already initialized");

    // Set initial config
    const config = new Config(owner, false, 5);
    this.configSingleton.set(config, this.receiver);
  }

  @action("setpaused")
  setPaused(paused: boolean): void {
    const config = this.configSingleton.getOrNull();
    check(config !== null, "Not initialized");
    requireAuth(config!.owner);

    config!.paused = paused;
    this.configSingleton.set(config!, this.receiver);
  }

  @action("myaction")
  myAction(): void {
    const config = this.configSingleton.getOrNull();
    check(config !== null, "Not initialized");
    check(!config!.paused, "Contract is paused");
    // ... action logic
  }
}
```

**Singleton Methods:**
- `get()` - Returns the stored value, or a default-constructed instance if nothing is stored (never `null`)
- `getOrNull()` - Returns the stored value or `null` if not set — use this for existence checks
- `set(value, payer)` - Sets or updates the singleton value
- `remove()` - Removes the singleton value

### Secondary Indexes

```typescript
@table("posts")
export class Post extends Table {
  constructor(
    public id: u64 = 0,
    public author: Name = new Name(),
    public content: string = "",
    public timestamp: u64 = 0
  ) {
    super();
  }

  @primary
  get primary(): u64 { return this.id; }

  @secondary
  get byAuthor(): u64 { return this.author.N; }

  @secondary
  get byTimestamp(): u64 { return this.timestamp; }
}
```

---

## TableStore Operations

The contract account pays RAM for every row it writes, so each state-changing
action below carries `requireAuth`. Reads need no auth.

### Initialize TableStore

```typescript
import { Contract, TableStore } from 'proton-tsc';

@contract
class MyContract extends Contract {
  userTable: TableStore<User> = new TableStore<User>(this.receiver);
}
```

### Store (Insert New Row)

```typescript
@action("adduser")
addUser(account: Name): void {
  requireAuth(this.receiver);
  const user = new User(
    this.userTable.availablePrimaryKey,  // Auto-increment ID
    account,
    0,
    currentTimeSec()
  );
  this.userTable.store(user, this.receiver);  // Throws if exists
}
```

### Set (Upsert)

```typescript
@action("setuser")
setUser(id: u64, account: Name, balance: u64): void {
  requireAuth(this.receiver);
  const user = new User(id, account, balance, currentTimeSec());
  this.userTable.set(user, this.receiver);  // Insert or update
}
```

### Get (Read)

```typescript
@action("getuser")
getUser(id: u64): void {
  const user = this.userTable.get(id);
  if (!user) {
    check(false, "User not found");
    return;
  }
  print(`User: ${user.account}`);
}
```

### Update

```typescript
@action("updatebal")
updateBalance(id: u64, newBalance: u64): void {
  requireAuth(this.receiver);  // writes an arbitrary balance — never leave open
  const user = this.userTable.requireGet(id, "User not found");
  user.balance = newBalance;
  this.userTable.update(user, this.receiver);  // Throws if not exists
}
```

### Delete

```typescript
@action("deluser")
deleteUser(id: u64): void {
  requireAuth(this.receiver);
  const user = this.userTable.requireGet(id, "User not found");
  this.userTable.remove(user);
}
```

### Check Existence

```typescript
if (this.userTable.exists(id)) {
  // Row exists
}
```

### Iteration

```typescript
// There is no getAll(); iterate with the cursor API
let cursor = this.userTable.first();
while (cursor) {
  print(`User: ${cursor.account}`);
  cursor = this.userTable.next(cursor);
}
```

---

## Actions

### Basic Action

```typescript
@action("transfer")
transfer(from: Name, to: Name, amount: u64, memo: string): void {
  requireAuth(from);  // Require signature from 'from' account

  check(amount > 0, "Amount must be positive");

  // ... transfer logic
}
```

### Action with Authorization

```typescript
@action("adminonly")
adminAction(admin: Name): void {
  requireAuth(admin);
  requireAuth(this.receiver);  // Also require contract's auth
}
```

### Notify Handler (for incoming transfers)

Notify handlers let your contract react to actions on other contracts (e.g., token transfers).

```typescript
@action("transfer", notify)
onTransfer(from: Name, to: Name, quantity: Asset, memo: string): void {
  // Only process transfers TO this contract (not from)
  if (to != this.receiver) return;

  // Only accept transfers from eosio.token
  if (this.firstReceiver != Name.fromString("eosio.token")) return;

  // Only accept the symbol you price in — one contract can host many tokens
  if (quantity.symbol != new Symbol("XPR", 4)) return;

  // Parse memo and process payment
  if (memo.startsWith("deposit:")) {
    // Handle deposit
  }
}
```

**Important Contract Properties:**
- `this.receiver` - The contract that contains this code (your contract)
- `this.firstReceiver` - The contract where the action originated (e.g., `eosio.token` for transfers)

**Security Note**: Always check `this.firstReceiver` **and** `quantity.symbol` in notify handlers. `firstReceiver` stops a malicious contract from spoofing a transfer notification; the symbol check stops a worthless token issued under the same symbol string on the real token contract from being credited as the one you price in.

```typescript
// SECURE: Check the token contract
if (this.firstReceiver != Name.fromString("eosio.token")) return;

// INSECURE: Anyone could call your contract with fake transfer data
// @action("transfer", notify)  // Without firstReceiver check = vulnerable
```

---

## Data Types

### Primitive Types

| Type | Description | Range |
|------|-------------|-------|
| `u8` | Unsigned 8-bit | 0 to 255 |
| `u16` | Unsigned 16-bit | 0 to 65,535 |
| `u32` | Unsigned 32-bit | 0 to 4,294,967,295 |
| `u64` | Unsigned 64-bit | 0 to 18,446,744,073,709,551,615 |
| `i8`, `i16`, `i32`, `i64` | Signed integers | |
| `f32`, `f64` | Floating point | Avoid in financial calculations |
| `bool` | Boolean | true/false |
| `string` | UTF-8 string | Variable length |

### XPR Network Types

```typescript
import { Name, Asset, Symbol, ExtendedAsset } from 'proton-tsc';

// Name (account names)
const account = Name.fromString("alice");
const accountU64 = account.N;  // u64 representation

// Symbol (token symbols)
const xprSymbol = new Symbol("XPR", 4);  // 4 decimals

// Asset (amount + symbol)
const amount = new Asset(10000, xprSymbol);  // 1.0000 XPR
const amountStr = amount.toString();  // "1.0000 XPR"

// Parse from string
const parsed = Asset.fromString("100.0000 XPR");
```

### Price Storage (Fixed Point)

For financial data, use u64 with fixed decimal places:

```typescript
// Store $95,322.71 as u64 with 8 decimals
const price: u64 = 9532271000000;  // 95322.71 * 10^8

// Convert back
const priceFloat = <f64>price / 100000000.0;
```

---

## Authentication

### requireAuth

```typescript
import { requireAuth, hasAuth, isAccount } from 'proton-tsc';

@action("myaction")
myAction(user: Name): void {
  requireAuth(user);  // Throws if user didn't sign

  if (hasAuth(user)) {
    // User signed (non-throwing check)
  }

  if (isAccount(user)) {
    // Account exists on chain
  }
}
```

### Contract Self-Auth

```typescript
// Check if action is called by the contract itself
if (hasAuth(this.receiver)) {
  // Called internally
}
```

---

## Inline Actions

Call other contracts from within your contract:

```typescript
import { InlineAction, PermissionLevel, ActionData, Name, Asset, requireAuth, check } from 'proton-tsc';

@action("paywinner")
payWinner(winner: Name, amount: Asset): void {
  requireAuth(this.receiver);        // spends contract funds — never leave open
  check(amount.amount > 0, "Amount must be positive");

  // Transfer tokens using inline action
  // InlineAction takes the action name; .act(contract, permission) binds the
  // target contract and authorization; .send(data) dispatches it.
  const transfer = new InlineAction<TransferArgs>("transfer");
  transfer
    .act(Name.fromString("eosio.token"), new PermissionLevel(this.receiver, Name.fromString("active")))
    .send(new TransferArgs(this.receiver, winner, amount, "Prize payout"));
}

// Define the action arguments class. It MUST extend ActionData (the SDK's
// Packer base) and call super() — `InlineAction<T>` requires `T extends Packer`.
@packer
class TransferArgs extends ActionData {
  constructor(
    public from: Name = new Name(),
    public to: Name = new Name(),
    public quantity: Asset = new Asset(),
    public memo: string = ""
  ) { super(); }
}
```

For eosio.token transfers specifically you do not need to hand-roll this: the
SDK ships `sendTransferToken(tokenContract, from, to, quantity, memo)` in
`proton-tsc/token`, which is exactly the inline action above.

### Enable Inline Actions

Before using inline actions, enable them on the contract account:

```bash
proton contract:enableinline mycontract
```

---

## Time Functions

```typescript
import { currentTimeSec, currentTimeMs, currentTimePoint } from 'proton-tsc';

@action("checktime")
checkTime(): void {
  const nowSec = currentTimeSec();      // Unix timestamp in seconds
  const nowMs = currentTimeMs();        // Unix timestamp in milliseconds
  const timePoint = currentTimePoint(); // TimePoint object

  // Calculate expiry (1 hour from now)
  const expiresAt = nowSec + 3600;
}
```

---

## Assertions

```typescript
import { check } from 'proton-tsc';

@action("validate")
validate(amount: u64, recipient: Name): void {
  check(amount > 0, "Amount must be positive");
  check(amount <= 1000000, "Amount exceeds maximum");
  check(isAccount(recipient), "Recipient account does not exist");
}
```

---

## Build and Deploy

### Build

```bash
npm run build
# Output: assembly/target/mycontract.contract.wasm and mycontract.contract.abi
# (named after the source file, minus .ts)
```

### Deploy

```bash
# Set network
proton chain:set proton

# Add key (do NOT store in files)
proton key:add

# Deploy WASM + ABI
proton contract:set mycontract ./assembly/target

# Initialize contract
proton action mycontract init '{"owner":"mycontract"}' mycontract
```

---

## AssemblyScript Gotchas

### No `any` or `undefined`

```typescript
// Wrong
function foo(a?) {}
function foo(a: any) {}

// Correct
function foo(a: u64 = 0): void {}
```

### No Union Types (except nullable)

```typescript
// Wrong
function foo(a: u32 | string): void {}

// Correct - use generics or separate functions
function foo<T>(a: T): void {}
```

### Objects Must Be Typed

```typescript
// Wrong
const a = {};
a.prop = "value";

// Correct - use Map or class
const a = new Map<string, string>();
a.set("prop", "value");
```

### String Comparison

```typescript
// Use == for string content comparison
const a = "abc";
const b = "abc";
check(a == b, "strings match");  // Correct

// === checks reference equality (usually not what you want)
```

### No try/catch

Throwing aborts the entire transaction. Use `check()` for validation.

### No Closures

Arrow functions exist, but they cannot capture the enclosing scope — that includes
`this`, so a callback can never touch contract state or tables.

```typescript
// Wrong - captures `threshold` and `this` from the enclosing scope
const threshold: u64 = 5;
const filtered = items.filter(x => x > threshold);
const pay = (to: Name): void => this.transferTo(to);

// Correct - use for loops and private methods
const filtered: u64[] = [];
for (let i = 0; i < items.length; i++) {
  if (items[i] > 5) filtered.push(items[i]);
}
```

---

## Complete Example

```typescript
import {
  Contract, Table, TableStore, Singleton, Name, Asset, Symbol,
  check, requireAuth, currentTimeSec, print
} from 'proton-tsc';

@table("balances")
export class Balance extends Table {
  constructor(
    public account: Name = new Name(),
    public amount: u64 = 0,
    public lastUpdate: u64 = 0
  ) { super(); }

  @primary
  get primary(): u64 { return this.account.N; }
}

@table("config", singleton)
export class Config extends Table {
  constructor(
    public owner: Name = new Name(),
    public paused: boolean = false
  ) { super(); }
}

@contract
export class MyToken extends Contract {
  balanceTable: TableStore<Balance> = new TableStore<Balance>(this.receiver);
  configSingleton: Singleton<Config> = new Singleton<Config>(this.receiver);

  @action("init")
  init(owner: Name): void {
    requireAuth(this.receiver);
    const config = new Config(owner, false);
    this.configSingleton.set(config, this.receiver);
  }

  @action("deposit")
  deposit(account: Name, amount: u64): void {
    requireAuth(account);

    const config = this.configSingleton.get();
    check(!config.paused, "Contract is paused");
    check(amount > 0, "Amount must be positive");

    let balance = this.balanceTable.get(account.N);
    if (!balance) {
      balance = new Balance(account, 0, 0);
    }

    balance.amount += amount;
    balance.lastUpdate = currentTimeSec();
    this.balanceTable.set(balance, this.receiver);
  }

  @action("withdraw")
  withdraw(account: Name, amount: u64): void {
    requireAuth(account);

    const balance = this.balanceTable.requireGet(
      account.N,
      "No balance found"
    );

    check(balance.amount >= amount, "Insufficient balance");

    balance.amount -= amount;
    balance.lastUpdate = currentTimeSec();

    if (balance.amount == 0) {
      this.balanceTable.remove(balance);
    } else {
      this.balanceTable.update(balance, this.receiver);
    }
  }
}
```

---

## Next Steps

- Read `safety-guidelines.md` before deploying (CRITICAL)
- See `examples.md` for production contract patterns
- Use `cli-reference.md` for deployment commands


---

## Things that are irreversible, and one that looks safe but is not

### A table's layout is frozen the moment it holds a row — appending counts

A row is packed bytes with no field names. Change the struct — including **adding a field at the end**, because
rows written earlier do not contain it — and every existing row decodes wrongly or aborts.

The failure is worse than it sounds, because a contract that cannot decode its own rows usually cannot repair
them either: every helper that reads a row deserializes it first. A real sequence:

1. v1 wrote a `config` singleton row.
2. v2 added two fields to that struct and was deployed.
3. `setconfig` aborted with `invalid symbol` — while reading the row it was about to **replace**.
4. The settings were unreachable. There was no action that could fix it, and the account was abandoned.

**How to survive it:**

- **Reserve spares up front** on every table (`spare1: u64`, and a `string`/`name` if you might need those
  shapes — a `u64` cannot stand in for a string).
- **Pin the layout in CI.** Store each published table's fields in a file and fail the build when they change,
  so the change is a deliberate diff rather than a surprise.
- **`Singleton.remove()` never deserializes** — it is `find` + `remove`. A `resetconfig` action that calls it is
  the one escape hatch that works on a row nobody can read. Guard it (contract auth, and refuse while anything
  depends on the settings), and add it *before* you need it.
- For a table with many rows, the same trick works with raw iterators: `lowerBound`/`next`/`remove` are cursor
  operations and never decode. `getValue()` is the only thing that decodes. A throwaway "wipe" contract with
  matching table **names** (the struct is irrelevant — nothing reads it) can clear a stuck account.

### `availablePrimaryKey` is "last row + 1", not "never used before"

It reads the last row's key and adds one; on an empty table it is 0. So **if you ever delete rows, ids are
recycled**, and anything derived from an id (an account name, an external reference, a file on disk) collides
with the old one.

If rows can be deleted, keep your own counter in a singleton and never derive the next id from the table.

### Aborting inside a `transfer` notification aborts the SENDER's transaction

A `@action("transfer", notify)` handler that calls `check()` and fails does not "reject the payment" — it fails
the whole transaction that sent it. The practical consequences:

- A contract that throws in its handler **cannot be sent any token at all**, including the tokens it needs to
  operate, and including a transfer that merely leads one of your own transactions for CPU.
- A deployed-but-unconfigured contract that does `check(configured)` in its handler is bricked: you cannot even
  fund it or configure it if your configuration transaction carries a transfer.
- When the contract runs out of RAM, `store()` throws here too — so every payment starts being rejected at chain
  level, with nothing in your logs.

**Rule:** in a notification handler, every path is a `return`, never a `check`. Validate, and if it is not for
you or not valid, either return or send the money back inline.

### ABI action fields use the contract's PARAMETER names

`proton-asc` takes field names straight from the action's TypeScript parameters, so `create(orderId: u64)` is
`{"orderId": 0}` in the transaction, not `order_id`. Table fields, by contrast, are the class property names and
usually snake_case. Read `target/<name>.contract.abi` rather than guessing; the error is
`missing <action>.<field> (type=...)`.


### Deleting the rows does NOT un-stick a table whose layout changed

The worst version of the layout problem is the one that looks fixed. After deleting every row:

```
get_table_rows  ->  {"rows": []}     for the table AND for every secondary index
next insert     ->  could not insert object, most likely a uniqueness constraint was violated
```

The cause is **orphaned secondary index entries**. Removing a row cleans up only the indexes the *current*
struct declares; entries written under an index that an earlier version declared stay behind. They are
invisible, because a query on a secondary index resolves each entry to its primary row, finds none, and returns
an empty list. And they are fatal, because the next row with that primary key tries to write an index entry
that already exists.

So a table that has ever had a secondary index added, removed or reordered can leave an account that accepts
nothing and shows no reason.

Clearing them needs a tool that declares **every secondary index the table has ever had, in the original
order**, and walks each one with raw cursors (`IDX64.lowerBound` / `next` / `remove` — none of which decode).

The detail that makes or breaks it: **get the index through `TableStore`, never through a `MultiIndex` you
construct yourself.** The compiler wires secondary indexes into the store's MultiIndex; a hand-built one has an
EMPTY index list, so the sweep deletes nothing and reports "no such index" while appearing to run.

```ts
const store = new TableStore<AnyRow>(this.receiver)   // indexes wired by the compiler
const idx = <IDX64>store.mi.idxdbs[i]
let it = idx.lowerBound(0)
while (it.i >= 0) { const next = idx.next(it); idx.remove(it); it = next }
```

This works — an account cleared this way takes writes again normally. But it needs the account's full index
history, which you only have if you broke it yourself. **On a development chain, prefer a fresh account.** An account costs a few XPR of
RAM; hours of forensics cost more, and the recovered account is never provably clean. The practical rule is
that **a contract account which has held rows under a different layout is disposable, not repairable** — so
decide the tables before the first deployment anybody transacts with, and if they must change afterwards, move
to a new account on every chain at once so the names stay in step.
