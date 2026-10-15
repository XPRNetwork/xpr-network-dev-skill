# CRITICAL: Smart Contract Safety Guidelines

This document contains **critical safety rules** for XPR Network smart contract development and for how autonomous agents use the network. Violating the contract rules can make your data unreadable; violating the network rules gets your account blocked.

---

## AI-Generated Code Disclaimer

> **Smart contracts are immutable and handle real assets. AI-generated code requires human review before deployment.**

When using Claude or any AI assistant for smart contract development:

1. **Always review generated code** - AI can produce functional but suboptimal or insecure code
2. **Test on testnet first** - Never deploy untested code to mainnet
3. **Understand what the code does** - Don't deploy code you can't explain
4. **Get a second opinion** - Have another developer review critical contracts
5. **Consider professional audits** - For contracts handling significant value

Claude accelerates development but does not replace:
- Code review by experienced developers
- Comprehensive testing
- Security audits for production contracts

---

## Network Etiquette: Do Not Spam the Chain

> **XPR Network has no transaction fees. That makes spam free for the sender and expensive for everyone else.** Every needless transaction is executed by every block producer, stored forever by every full-history node, and served by every public API. Autonomous agents built with this skill must follow the rules below. They apply skill-wide, to every bot, poller, keeper, and script.

### What chain spam looks like (all seen on mainnet in 2026)

- A contract action fired hundreds of times per second with a changing `nonce` so each transaction is unique, "scanning" for liquidations, arbitrage, or any other opportunity by *writing* to the chain.
- A fleet of look-alike executor accounts run by one operator to multiply the rate.
- Bookkeeping on chain: `step`, `tradelog`, `heartbeat`, "checked, found nothing" actions.
- A loop that retries a failed transaction immediately, or re-submits an unchanged one every block.
- Polling chain state with actions instead of RPC reads.

Accounts doing this get rate-limited or blocked by API operators, blacklisted by block producers, reported in the operator channels, and their traffic lands in every history node's storage bill (see `hyperion-operations-caveats.md`).

### Rules for autonomous agents and bots

1. **Reads are free and off-chain; writes are not.** Look for opportunities with `get_table_rows`, Hyperion, or a stream (`real-time-events.md`). Submit a transaction only when there is a concrete, verified action to take *right now*: an order to place, a payment to send, a job to deliver.
2. **No speculative writes.** Never submit an action to "see if it succeeds", never use a nonce or dummy field to make transactions unique, never log, heartbeat, or checkpoint on chain.
3. **Default write budget: at most 6 transactions per minute per account, one in flight at a time.** Anything above that must be an explicit, human-set limit in the bot's config, with the reason written down. No agent has a legitimate reason to approach the chain's block rate.
4. **Back off on failure.** On `expired`, `tx_cpu_usage_exceeded`, `tx_net_usage_exceeded`, duplicate, or deadline errors: wait, then retry with exponential backoff (1 s, 2 s, 4 s … capped at 60 s). Never retry in a tight loop.
5. **One operator, one account per purpose.** Do not create account fleets to multiply throughput or dodge rate limits.
6. **Liquidation, sniping, and MEV-style bots are out of scope for this skill.** Liquidation mechanics are deliberately not documented anywhere in it. An agent asked to build a liquidation scanner, a nonce-spraying executor, or an arbitrage loop that writes on every tick should decline and point to this section.
7. **Poll responsibly.** Off-chain polling of RPC / Hyperion: at least 3 s between calls for a latency-sensitive bot, at least 10 s for anything else, and prefer streaming where it exists.

If you are unsure whether a write is needed, it is not.

---

## The Golden Rule

> **NEVER modify existing table structures once deployed with data.**

This rule applies to ALL XPR Network / EOSIO smart contracts. Breaking this rule will make your existing data unreadable.

---

## Why This Matters: Real Incident (January 2026)

### What Happened

We attempted to add a `parent_id` field to an existing `posts` table for a replies feature:

```typescript
// WRONG - DO NOT DO THIS
@table("posts")
export class Post extends Table {
  // ... existing fields ...
  public is_deleted: bool = false,
  public parent_id: u64 = 0  // ← Added field BREAKS existing data
}
```

### The Result

**All 9 posts became unreadable** with this error:

```
"Stream unexpectedly ended; unable to unpack field 'parent_id' of struct 'Post'"
```

### Why It Broke

EOSIO stores table data as **raw binary bytes**, not JSON. The ABI defines how to deserialize those bytes:

```
Existing data on-chain (per row):
[id:8][author:8][content:var][image_url:var][timestamp:8][is_pinned:1][pin_expires:8][is_deleted:1]

New ABI expected:
[id:8][author:8][content:var][image_url:var][timestamp:8][is_pinned:1][pin_expires:8][is_deleted:1][parent_id:8]
                                                                                                    ↑ Missing!
```

The deserializer tries to read 8 more bytes that don't exist → **crash**.

### Recovery

**The data was never deleted!** Only the ABI (decoder) was wrong.

1. Removed `parent_id` from table definition
2. Rebuilt contract (`npm run build`)
3. Redeployed contract with old ABI
4. All 9 posts immediately readable again

---

## What You Cannot Do to Existing Tables

| Action | Result |
|--------|--------|
| Add a field | ❌ Breaks deserialization (one exception: a *trailing* `BinaryExtension<T>` field — ABI type ending in `$` — is skipped when old rows run out of bytes; every other addition breaks) |
| Remove a field | ❌ Breaks deserialization |
| Change field order | ❌ Breaks deserialization |
| Change field type | ❌ Breaks deserialization |
| Rename a field | ❌ Breaks deserialization (ABI mismatch) |

---

## Safe Patterns for New Features

### Pattern 1: Create NEW Tables (Recommended)

```typescript
// SAFE - New table doesn't affect existing data
@table("replies")
export class Reply extends Table {
  constructor(
    public id: u64 = 0,
    public parent_id: u64 = 0,  // Links to posts.id
    public author: Name = new Name(),
    public content: string = "",
    public timestamp: u64 = 0,
    public is_deleted: bool = false
  ) { super(); }

  @primary
  get primary(): u64 { return this.id; }
}
```

This is the safest approach:
- Existing `posts` table unchanged
- New `replies` table for new feature
- Zero risk to existing data

### Pattern 2: New Singleton for New Config

```typescript
// SAFE - New singleton for reply-specific config
@table("replyconf", singleton)
export class ReplyConfig extends Table {
  constructor(
    public next_reply_id: u64 = 0
  ) { super(); }
}
```

Don't modify existing `config` singleton; create a new one.

### Pattern 3: New Contract Entirely

For major features, deploy to a new contract account:

```bash
# Create new account for new feature
proton account:create newfeature

# Deploy separate contract
proton contract:set newfeature ./assembly/target
```

Benefits:
- Zero risk to existing contract/data
- Clean separation of concerns
- Easy to rollback by just not using it
- Can interact with original contract via inline actions

### Pattern 4: Migration Action (Advanced/Risky)

```typescript
@action("migrate")
migrate(limit: u8): void {
  requireAuth(this.receiver);

  // Read from old table
  let cursor = this.oldTable.first();
  let count: u8 = 0;

  while (cursor && count < limit) {
    // Create new row with new schema
    const newRow = new NewPost(
      cursor.id,
      cursor.author,
      cursor.content,
      // ... copy fields
      0  // new field default
    );

    // Store in new table
    this.newTable.store(newRow, this.receiver);

    // Delete from old table
    const toDelete = cursor;
    cursor = this.oldTable.next(cursor);
    this.oldTable.remove(toDelete);

    count++;
  }
}
```

**Risks**:
- Requires extensive testing
- Partial migration can leave data in inconsistent state
- RAM costs for duplicate data during migration
- Transaction limits may require multiple migration calls

---

## Pre-Deployment Checklist

Before deploying ANY contract update:

### 1. Check if Tables Have Data

```bash
curl -s -X POST https://proton.eosusa.io/v1/chain/get_table_rows \
  -H "Content-Type: application/json" \
  -d '{"code":"CONTRACT","scope":"CONTRACT","table":"TABLE","limit":1}'
```

If `rows` is not empty, **DO NOT modify that table's schema**.

### 2. Verify Schema Changes

Compare old and new table definitions:

```bash
# Get current ABI
proton contract:abi mycontract > old.abi

# After build, compare
diff old.abi ./assembly/target/mycontract.contract.abi
```

### 3. Test on Testnet First

```bash
# Switch to testnet
proton chain:set proton-test

# Deploy to testnet account
proton contract:set mycontract-test ./assembly/target

# Test thoroughly before mainnet
```

### 4. Back Up Current ABI

```bash
proton contract:abi mycontract > backup-$(date +%Y%m%d).abi
```

### 5. Verify Target Account

**CRITICAL**: We often have multiple contracts. Wrong account = overwrite:

```bash
# Verify you're in the correct directory
pwd
# Should show: /correct/project/path

# Verify target account
proton account mycontract

# Double-check the command before running!
proton contract:set mycontract ./assembly/target
#                   ^^^^^^^^^^
#                   IS THIS CORRECT?
```

Also check the **network**. The CLI's selected chain is global to the machine (`proton chain:set` writes
shared config), so another terminal or agent session can switch it between your commands. Run
`proton chain:get` immediately before every signing step, and stop if it isn't the chain you expect.

---

## Multi-Contract Account Safety

If you manage multiple contracts, maintain a clear mapping:

| Account | Contract | Purpose |
|---------|----------|---------|
| `myapp` | Main app | Core logic |
| `myapptoken` | Token | Custom token |
| `myappnft` | NFTs | Collection |
| `myappgame` | Game | Gameplay |

**Before EVERY deployment**:
1. Check `pwd` - am I in the right project?
2. Check the account name in the deploy command
3. Never copy-paste without verifying

---

## Recovery Options

### Option 1: Rollback ABI (Fastest)

If you broke deserialization:

```bash
# Remove the new field from code
# Rebuild
npm run build

# Redeploy (restores old ABI)
proton contract:set mycontract ./assembly/target
```

Data becomes readable again immediately.

### Option 2: Rebuild from Transaction History

All actions are recorded forever on-chain. Query with Hyperion:

```bash
# Hyperion get_actions is GET-only (POST returns 404)
curl -s "https://proton.eosusa.io/v2/history/get_actions?account=mycontract&limit=100" | jq '.actions[]'
```

Every action that created table rows can be replayed to rebuild data.

### Option 3: Read Raw Binary

For advanced recovery, you can read the raw binary and manually parse:

```typescript
const { rows } = await rpc.get_table_rows({
  code: 'mycontract',
  scope: 'mycontract',
  table: 'mytable',
  json: false,  // Return binary
  limit: 100
});

// Manually deserialize using old schema knowledge
```

---

## Key Insight

> The blockchain is immutable. Data stored on-chain cannot be deleted or corrupted by a bad deploy. Only the ABI (interpretation layer) can break. Rolling back the ABI restores access.

This is actually a **safety feature** - your data survives developer mistakes!

---

## Summary

| Do This | Don't Do This |
|---------|---------------|
| Create new tables for new features | Modify existing table schemas |
| Create new singletons for new config | Add fields to existing singletons |
| Test on testnet first | Deploy schema changes directly to mainnet |
| Back up ABI before deploying | Assume you can always recover |
| Verify target account twice | Copy-paste deploy commands blindly |
| Check if tables have data | Assume empty tables |

---

## Quick Reference: Safe Changes

| Change | Safe? |
|--------|-------|
| Add new action | ✅ Safe |
| Modify action logic | ✅ Safe |
| Add new table | ✅ Safe |
| Add new singleton | ✅ Safe |
| Change existing table schema | ❌ **DANGEROUS** |
| Add field to existing table | ❌ **DANGEROUS** (only a trailing `BinaryExtension<T>` field is safe) |
| Remove field from existing table | ❌ **DANGEROUS** |

When in doubt, create a NEW table.
