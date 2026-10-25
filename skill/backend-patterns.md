# Backend Development Patterns

This guide covers server-side integration with XPR Network - signing transactions programmatically, automated operations, and production patterns.

## When to use which pattern

Not every workload fits the same signing model. Route yourself before going deeper:

| Your runtime | Recommended pattern | Where to read |
|--------------|---------------------|---------------|
| **Browser / dApp frontend** | `@proton/web-sdk` (ProtonWebSDK) — user's wallet holds the key | [`web-sdk.md`](./web-sdk.md) |
| **Long-running backend on a VPS / VM / Mac mini / dedicated host** | **proton CLI keychain** (this doc) | continue below |
| **Autonomous AI agent** (Claude-driven, agent runner, etc.) | **proton CLI keychain** (this doc) — non-negotiable for agents after the charliebot incident | continue below |
| **Smart contract dev workflows** (deploy, action invocation) | proton CLI (already standard) | [`cli-reference.md`](./cli-reference.md) |
| **Serverless** (Vercel/Lambda/Cloudflare Workers) | KMS-backed signing OR ephemeral fetch from a secrets manager scoped to a custom permission | "Constrained environments" section below |
| **CI/CD pipeline** (GitHub Actions deploying a contract, etc.) | Short-lived deploy permission via `linkauth`; key in CI secret only for the pipeline duration | "Constrained environments" section below |
| **Multi-tenant SaaS** (each tenant has their own key) | KMS with per-tenant key isolation, or relay user-wallet-signed transactions | not yet documented — open an issue |

The rest of this guide focuses on the proton CLI keychain pattern (long-running backend + agents). Other paths are linked above.

## Overview

For server-side integration where you have a persistent filesystem:

| Aspect | Frontend (web-sdk) | Backend (this guide) |
|--------|-------------------|---------|
| Key storage | User's wallet | proton CLI keychain (`proton-cli.json`, locked with `proton key:lock`) |
| Signing | Wallet prompts user | proton CLI shells out from process |
| Use case | User-initiated actions | Automated/scheduled tasks |
| Security | Wallet handles keys | **Key NEVER enters process memory** |

> **Security update (v0.3.0+):** The traditional pattern of loading `XPR_PRIVATE_KEY` from `.env` into `JsSignatureProvider` is **no longer recommended** for long-running backends or AI agents. Keys in process memory are reachable from every tool call, every log line, every web fetch, every paste into an AI conversation — a single accidental leak compromises the whole account. The recommended pattern routes signing through the proton CLI's keychain so the key never enters the process. See the "Security: Key Isolation" section below for the rationale and migration path. (For serverless / CI / browser cases where this doesn't apply, route via the table at the top.)

---

## Setup (Recommended — proton CLI keychain)

### One-time operator setup

```bash
# Install the proton CLI
npm i -g @proton/cli

# Pick the network
proton chain:set proton              # or proton-test

# Add your blockchain key to the CLI keychain
proton key:add                       # interactive — paste key once

# Required on any long-lived host: encrypt the keystore at rest
proton key:lock <password>           # without this, the key sits plaintext in proton-cli.json

# Verify
proton key:list                      # public keys + accounts only; private values print only with --reveal-private
```

After this, the key lives in the CLI's keychain — `proton-cli.json` in the CLI config dir, **plaintext on disk until `proton key:lock <password>` runs**, so treat the lock as part of setup. Your `.env` does NOT need `XPR_PRIVATE_KEY`.

**Unattended hosts.** `proton transaction:push` signs from that keystore, so against a *locked* store it cannot sign on its own — expect it to fail or prompt for the password (verify the exact behaviour on your CLI version; this skill does not script around it). The expected daemon flow is: a human runs `proton key:unlock` at boot, under supervision, and the service signs for the rest of its uptime; the unlock password lives in the supervisor's secret store or the service's memory only — never in `.env`, a shell script, or a cron line. Do not leave a plaintext (unlocked) `proton-cli.json` sitting on a host reachable from the network just so a daemon can sign unattended; if the host is lost, the key is lost. Whatever the flow, the key in the keychain should belong to a linked, scoped permission (see **Permission Linking** below), so a compromise is bounded.

### Dependencies

```bash
npm install @xpr-agents/openclaw @xpr-agents/sdk @proton/js   # your own Node process
# Inside an OpenClaw harness use `openclaw plugins install @xpr-agents/openclaw` instead —
# a plain npm install leaves the plugin undiscoverable there (see xpr-agents.md → Tooling).
```

### Basic Configuration

```typescript
import { createCliSession } from '@xpr-agents/openclaw';

// No private key in .env. The CLI handles signing from its keychain.
const XPR_ACCOUNT = process.env.XPR_ACCOUNT!;
const RPC_ENDPOINT = process.env.XPR_RPC_ENDPOINT || 'https://proton.eosusa.io';

const { rpc, session } = createCliSession({
  account: XPR_ACCOUNT,
  permission: 'active',
  rpcEndpoint: RPC_ENDPOINT,
  // Optional cap on every XPR transfer/stake/fee this session signs, in raw
  // units. Falls back to MAX_TRANSFER_AMOUNT, then 10000000 (1,000 XPR).
  maxTransferAmount: 10000000,
});

// `session.link.transact(...)` signs by shelling out to `proton transaction:push`.
// Each push signs from the CLI keystore: on a locked store it cannot sign
// unattended (see "Unattended hosts" above).
// `rpc` is a standard JsonRpc instance for read operations.
```

What this gives you:

- **`session`** — a `ProtonSession`-shaped object. Same `transact()` interface as the legacy `Api`, but every signed transaction is signed by the CLI from its keychain. The key bytes never enter your Node.js process.
- **`rpc`** — a standard `JsonRpc` for read operations (`get_table_rows`, `get_info`, etc.). Reads still go via HTTP; only signing routes through the CLI.

### Legacy setup (`JsSignatureProvider`)

Only use this if you have a specific reason — testing, ephemeral keys you don't mind exposing, or wallets that can't go through the CLI:

<details>
<summary>Legacy: key in process memory (NOT recommended)</summary>

```typescript
import { JsonRpc, Api, JsSignatureProvider } from '@proton/js';

// ⚠️  Key sits in process memory. Reachable from every tool, log, prompt.
const PRIVATE_KEY = process.env.XPR_PRIVATE_KEY;
const rpc = new JsonRpc(process.env.XPR_RPC_ENDPOINT || 'https://proton.eosusa.io');
const signatureProvider = new JsSignatureProvider([PRIVATE_KEY]);

const api = new Api({
  rpc,
  signatureProvider,
  textDecoder: new TextDecoder(),
  textEncoder: new TextEncoder()
});
```

The `create-xpr-agent` starter (the agent-runner scaffold that wraps `@xpr-agents/openclaw`) **refuses to start** if `XPR_PRIVATE_KEY` is set in env — the check lives in the scaffold's `start.sh`, not in the openclaw package, and `createCliSession` itself does not check. The assumption is that you intended to use the CLI keychain and forgot to migrate. If you genuinely want the legacy pattern, you're outside the starter's supported envelope and should build your own service.

</details>

---

## Transaction Signing

### Basic Transaction

These helpers take a `session` argument so they work with whatever signing path you set up in **Basic Configuration** — `createCliSession`'s `session` (recommended) drops in here. `session.link.transact()` takes a single `{ actions }` argument — there is no options parameter, and `proton transaction:push` manages tx headers (`blocksBehind` / `expireSeconds`) internally. (The two-argument `transact(tx, options)` shape exists only on `createCliApi().api`, where the options are accepted and ignored.)

```typescript
import type { ProtonSession } from '@xpr-agents/sdk';

async function sendTransaction(session: ProtonSession, actions: any[]) {
  try {
    const result = await session.link.transact({ actions });
    return { success: true, transaction_id: result.transaction_id };
  } catch (error: any) {
    return { success: false, error: error.message };
  }
}
```

### Token Transfer

```typescript
async function transferTokens(
  session: ProtonSession,
  from: string,
  to: string,
  quantity: string,
  memo: string = ''
) {
  const actions = [{
    account: 'eosio.token',
    name: 'transfer',
    authorization: [{ actor: from, permission: 'active' }],
    data: { from, to, quantity, memo }
  }];

  return sendTransaction(session, actions);
}

// Usage — `session` comes from createCliSession() in Basic Configuration
await transferTokens(session, 'myaccount', 'recipient', '10.0000 XPR', 'Payment');
```

### Multiple Actions in One Transaction

```typescript
async function batchTransfer(
  session: ProtonSession,
  from: string,
  transfers: Array<{ to: string; quantity: string; memo: string }>
) {
  const actions = transfers.map(t => ({
    account: 'eosio.token',
    name: 'transfer',
    authorization: [{ actor: from, permission: 'active' }],
    data: {
      from,
      to: t.to,
      quantity: t.quantity,
      memo: t.memo
    }
  }));

  return sendTransaction(session, actions);
}
```

---

## Service Class Pattern

```typescript
import { JsonRpc } from '@proton/js';
import { createCliSession } from '@xpr-agents/openclaw';
import type { ProtonSession } from '@xpr-agents/sdk';

interface TransactionResult {
  success: boolean;
  transaction_id?: string;
  error?: string;
}

class XPRBackendService {
  private rpc: JsonRpc;
  private session: ProtonSession;
  private account: string;
  private permission: string;

  // `permission` is a custom permission linked to exactly the actions this
  // service calls (see "Permission Linking" below) — not `active`. Every action
  // the service signs must be linked to it, or run one instance per permission.
  constructor(account: string, permission: string, endpoint?: string) {
    this.account = account;
    this.permission = permission;
    // No privateKey parameter — the proton CLI handles signing from its keychain.
    // The CLI must already hold the key for `account@permission` via `proton key:add`.
    const { rpc, session } = createCliSession({
      account,
      permission,
      rpcEndpoint: endpoint || 'https://proton.eosusa.io',
    });
    this.rpc = rpc;
    this.session = session;
  }

  // Execute transaction with retry logic
  async transact(actions: any[], retries: number = 3): Promise<TransactionResult> {
    for (let attempt = 1; attempt <= retries; attempt++) {
      try {
        // session.link.transact shells out to `proton transaction:push`.
        // Same interface as eosjs Api.transact, just CLI-backed signing.
        const result = await this.session.link.transact({ actions });
        return { success: true, transaction_id: result.transaction_id };
      } catch (error: any) {
        const isRetryable = this.isRetryableError(error);

        if (attempt === retries || !isRetryable) {
          return { success: false, error: error.message };
        }

        // Wait before retry (exponential backoff)
        await this.sleep(Math.pow(2, attempt) * 1000);
      }
    }
    return { success: false, error: 'Max retries exceeded' };
  }

  private isRetryableError(error: any): boolean {
    const message = error.message || '';
    // Retry on network errors, not on validation errors
    return message.includes('ECONNREFUSED') ||
           message.includes('timeout') ||
           message.includes('Too Many Requests');
  }

  private sleep(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  // Query table data
  async getTable<T>(
    code: string,
    table: string,
    options: {
      scope?: string;
      lowerBound?: string | number;
      upperBound?: string | number;
      limit?: number;
    } = {}
  ): Promise<T[]> {
    const { rows } = await this.rpc.get_table_rows({
      code,
      scope: options.scope || code,
      table,
      lower_bound: options.lowerBound,
      upper_bound: options.upperBound,
      limit: options.limit || 100,
      json: true
    });
    return rows as T[];
  }

  // Token operations
  async transfer(to: string, quantity: string, memo: string = ''): Promise<TransactionResult> {
    return this.transact([{
      account: 'eosio.token',
      name: 'transfer',
      authorization: [{ actor: this.account, permission: this.permission }],
      data: {
        from: this.account,
        to,
        quantity,
        memo
      }
    }]);
  }

  async getBalance(account: string, symbol: string = 'XPR'): Promise<string> {
    const rows = await this.getTable<{ balance: string }>('eosio.token', 'accounts', {
      scope: account
    });
    const balance = rows.find(r => r.balance.includes(symbol));
    return balance?.balance || `0.0000 ${symbol}`;
  }

  // Custom contract action
  async callContract(
    contract: string,
    action: string,
    data: Record<string, any>
  ): Promise<TransactionResult> {
    return this.transact([{
      account: contract,
      name: action,
      authorization: [{ actor: this.account, permission: this.permission }],
      data
    }]);
  }
}

// Usage — note: no private key argument. The CLI handles it.
// `pay` is a custom permission on myaccount linked to eosio.token::transfer and
// mycontract::myaction (Permission Linking below). The keychain holds its key, not active's.
const xpr = new XPRBackendService('myaccount', 'pay');

await xpr.transfer('recipient', '10.0000 XPR', 'Payment');
await xpr.callContract('mycontract', 'myaction', { param1: 'value' });
```

---

## Token Operations

### Deploy a Token

```typescript
async function deployToken(
  session: ProtonSession,
  issuer: string,
  maxSupply: string  // e.g., "1000000.0000 MYTOKEN"
) {
  // Create token
  await sendTransaction(session, [{
    account: 'eosio.token',
    name: 'create',
    authorization: [{ actor: issuer, permission: 'active' }],
    data: {
      issuer,
      maximum_supply: maxSupply
    }
  }]);
}
```

### Issue Tokens

```typescript
async function issueTokens(
  session: ProtonSession,
  issuer: string,
  to: string,
  quantity: string,
  memo: string = 'Token issuance'
) {
  await sendTransaction(session, [{
    account: 'eosio.token',
    name: 'issue',
    authorization: [{ actor: issuer, permission: 'active' }],
    data: {
      to,
      quantity,
      memo
    }
  }]);
}
```

### Check Balance

```typescript
async function getTokenBalance(account: string, tokenContract: string = 'eosio.token') {
  const { rows } = await rpc.get_table_rows({
    code: tokenContract,
    scope: account,
    table: 'accounts',
    json: true
  });
  return rows;
}
```

---

## NFT Operations (Backend)

### Mint NFT from Backend

```typescript
async function mintNFT(
  session: ProtonSession,
  minter: string,
  collection: string,
  schema: string,
  templateId: number,
  recipient: string
) {
  return sendTransaction(session, [{
    account: 'atomicassets',
    name: 'mintasset',
    // `minter` is a custom permission linked to atomicassets::mintasset only
    // (Permission Linking below) — a leaked mint key cannot move funds.
    authorization: [{ actor: minter, permission: 'minter' }],
    data: {
      authorized_minter: minter,
      collection_name: collection,
      schema_name: schema,
      template_id: templateId,
      new_asset_owner: recipient,
      immutable_data: [],
      mutable_data: [],
      tokens_to_back: []
    }
  }]);
}
```

### Batch Mint with Rate Limiting

```typescript
// One transaction of up to 50 mints every 10 s = 6 tx/min, the rule 3 budget
// (300 NFTs/min). A drop that needs more than 6 tx/min is a rule 3 case: your
// own API node or paid resource plan, a human-written limit in config with the
// reason, and the hard ceiling of 60 writes/min per operator. Not a bigger loop.
async function batchMintWithLimit(
  session: ProtonSession,
  minter: string,
  collection: string,
  schema: string,
  templateId: number,
  recipients: string[],
  batchSize: number = 50
) {
  const results: TransactionResult[] = [];

  for (let i = 0; i < recipients.length; i += batchSize) {
    const batch = recipients.slice(i, i + batchSize);

    const actions = batch.map(recipient => ({
      account: 'atomicassets',
      name: 'mintasset',
      authorization: [{ actor: minter, permission: 'minter' }],   // linked permission, see mintNFT
      data: {
        authorized_minter: minter,
        collection_name: collection,
        schema_name: schema,
        template_id: templateId,
        new_asset_owner: recipient,
        immutable_data: [],
        mutable_data: [],
        tokens_to_back: []
      }
    }));

    const result = await sendTransaction(session, actions);
    results.push(result);

    // Pace: 10 s between batches (or route sendTransaction through the
    // RateLimiter below — same budget either way)
    if (i + batchSize < recipients.length) {
      await new Promise(r => setTimeout(r, 10_000));
    }
  }

  return results;
}
```

---

## Scheduled/Automated Tasks

### Resolve Expired Game Challenges

```typescript
import cron from 'node-cron';

// Writes go through the 6/min limiter (RateLimiter, "Rate Limiting" below). A run
// that finds more than 6 due rows resolves 6 now and the rest on later ticks; if
// that is too slow for your game, the answer is the rule 3 conditions, not a
// bigger loop. See safety-guidelines.md → Network Etiquette, rules 1-4.
const resolveLimiter = new RateLimiter(6, 60_000);
let resolving = false;                                   // in-process mutex: ticks must not overlap
const failedChallenges = new Map<number, number>();      // id -> failure count

async function resolveExpiredChallenges(session: ProtonSession) {
  if (resolving) return;   // previous tick still running (it may be waiting on the limiter)
  resolving = true;
  try {
    const now = Math.floor(Date.now() / 1000);

    // Read first: active challenges only, small page
    const { rows } = await rpc.get_table_rows({
      code: 'pricebattle',
      scope: 'pricebattle',
      table: 'challenges',
      index_position: 'secondary',
      key_type: 'i64',
      lower_bound: 1,  // ACTIVE status
      upper_bound: 1,
      limit: 25
    });

    // Forget failures for rows that are gone (resolved by someone else, or deleted)
    for (const id of failedChallenges.keys()) {
      if (!rows.some(r => r.id === id)) failedChallenges.delete(id);
    }

    // Push only for rows the read confirms are due, and never for a row that has
    // already asserted — re-pushing a permanently failing row every minute is spam.
    const due = rows.filter(c =>
      now >= c.started_at + c.duration && !failedChallenges.has(c.id)
    );

    for (const challenge of due) {
      // Resolve the challenge — the contract reads the oracle price itself;
      // resolve(challenge_id: uint64, resolver: name) takes no price argument.
      const result = await resolveLimiter.run(() => sendTransaction(session, [{
        account: 'pricebattle',
        name: 'resolve',
        authorization: [{ actor: 'resolver', permission: 'resolve' }],   // linked to pricebattle::resolve, not active
        data: {
          challenge_id: challenge.id,
          resolver: 'resolver'
        }
      }]));

      if (result.success) {
        console.log(`Resolved challenge ${challenge.id}`);
      } else {
        // Skip it from now on; a human looks at why it asserts
        failedChallenges.set(challenge.id, (failedChallenges.get(challenge.id) ?? 0) + 1);
        console.error(`Challenge ${challenge.id} failed, skipping on later runs:`, result.error);
      }
    }
  } finally {
    resolving = false;
  }
}

// Run every minute; the mutex and the limiter make overlapping ticks harmless
cron.schedule('* * * * *', () => resolveExpiredChallenges(session));
```

### Cleanup Expired Entries

```typescript
async function cleanupExpired(session: ProtonSession) {
  await sendTransaction(session, [{
    account: 'mycontract',
    name: 'cleanup',
    authorization: [{ actor: 'myaccount', permission: 'active' }],
    data: { limit: 100 }
  }]);
}

// Run every hour
cron.schedule('0 * * * *', () => cleanupExpired(session));
```

---

## Security: Key Isolation

### The charliebot incident (2026-04-24)

An autonomous agent (charliebot) was compromised when an AI assistant working in the codebase pasted a hardcoded `PVT_K1_…` value into a script. The script was committed, pushed to a public repo, and within hours an attacker had drained the wallet — sold the memecoins, sold the XPR, moved everything out through HitBTC.

The root cause was not the leaked key. It was the **deployment pattern** — the agent loaded `XPR_PRIVATE_KEY` from `.env` into process memory via `JsSignatureProvider`. Once in memory, the key was reachable from:

- Every tool call the agent made
- Every skill the agent loaded
- Every prompt the LLM saw
- Every log line the agent wrote
- Every web fetch the agent issued
- Every JS execution context the agent spawned

That model required perfect prompt-injection resistance, perfect log-redaction discipline, and perfect committer attention — forever. Not a defensible posture.

### Key Management — the new pattern

**Make the unsafe thing impossible: the agent process must not have the chain key in memory.** All signing routes through the proton CLI's keychain.

```typescript
// ❌ NEVER do this (legacy pattern that caused the charliebot leak)
const PRIVATE_KEY = process.env.XPR_PRIVATE_KEY;
const signatureProvider = new JsSignatureProvider([PRIVATE_KEY]);

// ✅ DO this (proton CLI keychain pattern, v0.3.0+)
import { createCliSession } from '@xpr-agents/openclaw';

const { rpc, session } = createCliSession({
  account: process.env.XPR_ACCOUNT!,
  permission: 'active',
});

// session.link.transact() shells out to `proton transaction:push`.
// The key never enters this Node.js process.
```

Operator setup happens once, outside the agent:

```bash
npm i -g @proton/cli
proton chain:set proton
proton key:add                # paste key once, stored in the CLI keychain
proton key:lock <password>    # required — proton-cli.json is plaintext until you do this
```

### What this doesn't fix (honest list)

- **The proton CLI itself can be attacked.** You trust whatever guarantees the CLI provides for its keychain — that's out of scope for the agent project.
- **A2A still uses an EOSIO key in process.** Agent-to-agent signing needs to sign arbitrary messages, which the proton CLI doesn't expose. Use a separate `A2A_SIGNING_KEY` registered on a custom permission with no on-chain powers — limited blast radius (reputation only, not funds).
- **OS-level isolation isn't perfect.** Root on the agent host can read the keychain. This refactor solves the application-level attack surface, not the host-level one.

### Constrained environments (serverless, CI, ephemeral containers)

If your runtime has no persistent filesystem (serverless functions, CI pipelines, fresh containers per request), you can't use the proton CLI keychain — the keychain doesn't survive between invocations. You have three viable fallbacks, in order of preference:

**1. KMS-backed signing.** Generate a key in AWS KMS / GCP KMS / Azure Key Vault. The KMS holds the private key; you call its sign API at transaction time. The private key bytes never leave the KMS service. Requires writing a custom signature provider that wraps the KMS sign call — out of scope for this guide.

**2. Scoped permission + secrets manager.** Create a custom permission on your account (e.g. `@deploy`) with `linkauth` restricted to only the specific actions your runtime needs (e.g. `atomicassets::mintasset` for a mint serverless function). Store that key in a secrets manager. Even if leaked, the attacker can only invoke the linked actions — they cannot move funds or change permissions. See the "Permission Linking" section below for the `linkauth` mechanics.

**3. Ephemeral fetch at signing time.** Last resort — fetch the key from a secrets manager, sign immediately, drop the reference. The key still touches process memory between fetch and sign, but the window is narrow. Always combine with scoped permissions (option 2) so a leak is bounded.

#### Option 3 example (ephemeral fetch + JsSignatureProvider)

If you genuinely cannot use a scoped KMS sign path, fetch the key from a secrets manager at signing time and zero it immediately:

```typescript
// Last resort. The key still touches process memory between fetch and sign —
// you've narrowed the window but not eliminated it.
import { SecretsManager } from '@aws-sdk/client-secrets-manager';

async function signWithEphemeralKey(actions: any[]) {
  const client = new SecretsManager({ region: 'us-east-1' });
  const response = await client.getSecretValue({ SecretId: 'xpr/private-key' });
  let privateKey: string | null = response.SecretString!;

  try {
    const signatureProvider = new JsSignatureProvider([privateKey]);
    const api = new Api({ rpc, signatureProvider, /* ... */ });
    return await api.transact({ actions }, { blocksBehind: 3, expireSeconds: 30 });
  } finally {
    privateKey = null;  // help the GC; not a real guarantee
  }
}
```

This is strictly worse than the CLI keychain. Use only if the CLI is not an option.

### Use Dedicated Accounts

Create separate accounts for different purposes:

| Account | Purpose | Permissions |
|---------|---------|-------------|
| `myapp.ops` | Automated operations | Limited to specific actions |
| `myapp.mint` | NFT minting only | Only atomicassets::mintasset |
| `myapp.pay` | Payments only | Only eosio.token::transfer |

### Permission Linking

Link custom permissions to specific actions:

```bash
# Create custom permission
proton action eosio updateauth '{
  "account": "myapp",
  "permission": "minter",
  "parent": "active",
  "auth": {
    "threshold": 1,
    "keys": [{"key": "PUB_K1_xxx", "weight": 1}],
    "accounts": [],
    "waits": []
  }
}' myapp@active     # a child of active is created and linked with active; owner is not needed

# Link permission to specific action
proton action eosio linkauth '{
  "account": "myapp",
  "code": "atomicassets",
  "type": "mintasset",
  "requirement": "minter"
}' myapp@active
```

Now you can sign mintasset with the limited `minter` key. Keep the owner key offline; it is only for recovering `active`. The same shape gives `XPRBackendService` its `pay` permission (link `eosio.token::transfer`) and the challenge resolver its `resolve` permission (link `pricebattle::resolve`).

### Rate Limiting

Use this for API calls **and** for chain writes. The default chain write budget for an autonomous process is 6 transactions per minute per account, one in flight; see [`safety-guidelines.md` → Network Etiquette](safety-guidelines.md#network-etiquette-do-not-spam-the-chain).

```typescript
class RateLimiter {
  private timestamps: number[] = [];
  private inFlight = false;
  private waiters: Array<() => void> = [];

  // Rule 3 defaults: 6 writes per 60 s, one in flight. These are the numbers to
  // put in the code, not a default to tune up (see loadConfig for the override gate).
  constructor(private maxRequests = 6, private windowMs = 60_000) {}

  async acquire(): Promise<void> {
    // Semaphore of one: never more than a single transaction in flight
    while (this.inFlight) {
      await new Promise<void>(r => this.waiters.push(r));
    }
    this.inFlight = true;

    // Sliding window
    for (;;) {
      const now = Date.now();
      this.timestamps = this.timestamps.filter(t => now - t < this.windowMs);
      if (this.timestamps.length < this.maxRequests) break;
      await new Promise(r => setTimeout(r, this.timestamps[0] + this.windowMs - now));
    }
    this.timestamps.push(Date.now());
  }

  release(): void {
    this.inFlight = false;
    this.waiters.shift()?.();
  }

  // acquire → run → always release
  async run<T>(fn: () => Promise<T>): Promise<T> {
    await this.acquire();
    try {
      return await fn();
    } finally {
      this.release();
    }
  }
}

// Usage: 6 transactions per minute, one in flight (safety-guidelines.md rule 3)
const limiter = new RateLimiter(6, 60_000);

async function rateLimitedTransfer(to: string, amount: string) {
  return limiter.run(() => transfer(to, amount));
}
```

---

## Error Handling

### Common Errors

| Error | Cause | Solution |
|-------|-------|----------|
| `missing authority` | Wrong key or permission | Check authorization matches key |
| `expired transaction` | Transaction took too long to reach a block (slow endpoint, or the push waited behind other work) | Wait, then retry with backoff (rule 4). `proton transaction:push` sets `expireSeconds` itself — `session.link.transact()` has no option to raise it. If it keeps happening, look at the RPC endpoint, not the loop. |
| `duplicate transaction` | Same tx submitted twice | Do not resubmit: the first push was accepted or is in flight. Look it up by `trx_id`. Never add a nonce or dummy field to make a transaction unique (rule 2). |
| `cpu usage exceeded` | Not enough CPU staked | Stake more CPU or wait |
| `assertion failure` | Contract validation failed | Check action parameters |

### Robust Error Handling

```typescript
async function safeTransact(
  session: ProtonSession,
  actions: any[]
): Promise<TransactionResult> {
  try {
    const result = await session.link.transact({ actions });
    return { success: true, transaction_id: result.transaction_id };

  } catch (error: any) {
    const message = error.message || String(error);

    // Parse assertion failures
    if (message.includes('assertion failure')) {
      const match = message.match(/assertion failure with message: (.+)/);
      return {
        success: false,
        error: match ? match[1] : 'Contract assertion failed'
      };
    }

    // Resource errors
    if (message.includes('cpu usage exceeded')) {
      return { success: false, error: 'Insufficient CPU resources' };
    }

    if (message.includes('ram usage exceeded')) {
      return { success: false, error: 'Insufficient RAM' };
    }

    // Auth errors
    if (message.includes('missing authority')) {
      return { success: false, error: 'Authorization failed - check key permissions' };
    }

    return { success: false, error: message };
  }
}
```

---

## Monitoring and Logging

### Transaction Logging

```typescript
interface TransactionLog {
  timestamp: Date;
  action: string;
  data: any;
  result: TransactionResult;
}

class LoggedXPRService extends XPRBackendService {
  private logs: TransactionLog[] = [];

  async transact(actions: any[]): Promise<TransactionResult> {
    const result = await super.transact(actions);

    for (const action of actions) {
      this.logs.push({
        timestamp: new Date(),
        action: `${action.account}::${action.name}`,
        data: action.data,
        result
      });
    }

    // Also log to external service
    await this.sendToLoggingService(actions, result);

    return result;
  }

  private async sendToLoggingService(actions: any[], result: TransactionResult) {
    // Send to your logging service (Datadog, CloudWatch, etc.)
    console.log(JSON.stringify({
      service: 'xpr-backend',
      actions: actions.map(a => `${a.account}::${a.name}`),
      success: result.success,
      tx_id: result.transaction_id,
      error: result.error
    }));
  }
}
```

### Health Check Endpoint

```typescript
import express from 'express';

const app = express();

app.get('/health', async (req, res) => {
  try {
    // Check RPC connection
    const info = await rpc.get_info();

    // Check account balance
    const balance = await xpr.getBalance(xpr.account);

    res.json({
      status: 'healthy',
      chain: {
        head_block: info.head_block_num,
        chain_id: info.chain_id
      },
      account: {
        name: xpr.account,
        balance
      }
    });
  } catch (error: any) {
    res.status(500).json({
      status: 'unhealthy',
      error: error.message
    });
  }
});
```

---

## Environment Configuration

### .env Template

```bash
# XPR Network Configuration
# Note: NO XPR_PRIVATE_KEY here. The proton CLI handles signing from its
# keychain. If you set XPR_PRIVATE_KEY anyway, the create-xpr-agent
# starter's start.sh refuses to start.
XPR_ACCOUNT=myaccount
XPR_RPC_ENDPOINT=https://proton.eosusa.io
XPR_CHAIN_ID=384da888112027f0321850a169f737c33e53b388aad48b5adace4bab97f437e0

# For testnet
# XPR_RPC_ENDPOINT=https://tn1.protonnz.com
# XPR_CHAIN_ID=71ee83bcf52142d61019d95f9cc5427ba6a0d7ff8accd9e2088ae2abeaf3d3dd

# Optional: @xpr-agents/openclaw plugin settings (defaults shown)
# XPR_NETWORK=mainnet                 # mainnet | testnet
# XPR_PERMISSION=active
# MAX_TRANSFER_AMOUNT=10000000        # raw units = 1,000 XPR; caps every signed XPR transfer/stake/fee
# INDEXER_URL=https://indexer.xpragents.com
# TRUSTED_ARBITRATORS=protonnz        # comma-separated; the runner declines jobs naming any other arbitrator
# SHELLBOOK_API_KEY=                  # only if the agent posts on shellbook.io

# Optional: AtomicAssets
ATOMIC_API=https://xpr.api.atomicassets.io

# Chain write budget (safety-guidelines.md → Network Etiquette, rule 3).
# 6/min is the ceiling for an unattended process; loadConfig refuses more
# unless RATE_OVERRIDE_REASON is set, and never accepts more than 60.
MAX_TX_PER_MINUTE=6
# RATE_OVERRIDE_REASON=      # human-written reason; needs your own API node too
```

Add `.env` to `.gitignore` **before** writing any key into it — a committed key is a leaked key.

`A2A_SIGNING_KEY` — the one key the A2A protocol needs in process — is deliberately **not** in this template. It belongs in a secrets manager or the supervisor's secret store, injected into the environment at start, and it must be the key of a dedicated `a2a` permission with no token-transfer or funds authority, so a leak costs reputation only (see "What this doesn't fix" above). No `PVT_K1_` string belongs in any file an agent might copy.

### Config Loader

```typescript
import { execSync } from 'child_process';

interface Config {
  account: string;
  rpcEndpoint: string;
  chainId: string;
  atomicApi: string;
  maxTxPerMinute: number;
}

function loadConfig(): Config {
  const required = ['XPR_ACCOUNT'];

  for (const key of required) {
    if (!process.env[key]) {
      throw new Error(`Missing required environment variable: ${key}`);
    }
  }

  // Refuse legacy XPR_PRIVATE_KEY env var — keys belong in the CLI keychain.
  if (process.env.XPR_PRIVATE_KEY) {
    throw new Error(
      'XPR_PRIVATE_KEY is set but is no longer supported.\n' +
      '  1. Install proton CLI: npm i -g @proton/cli\n' +
      '  2. Add your key:        proton key:add\n' +
      '  3. Remove XPR_PRIVATE_KEY from your .env'
    );
  }

  // Verify the CLI actually holds a key for this account before booting.
  let keyList: string;
  try {
    keyList = execSync('proton key:list', { stdio: 'pipe' }).toString();
  } catch {
    throw new Error('proton CLI not found in PATH. Install with: npm i -g @proton/cli');
  }
  if (!keyList.includes(process.env.XPR_ACCOUNT!)) {
    throw new Error(`No key in the proton CLI keychain for ${process.env.XPR_ACCOUNT}. Run: proton key:add`);
  }

  // Chain write budget — rule 3. Above 6/min only with your own API node and a
  // human-written reason in the config. Even with the reason set, rule 3's hard
  // ceiling still applies: 60 writes/min per operator across ALL accounts.
  const maxTxPerMinute = parseInt(process.env.MAX_TX_PER_MINUTE || '6', 10);
  if (!Number.isInteger(maxTxPerMinute) || maxTxPerMinute < 1) {
    throw new Error('MAX_TX_PER_MINUTE must be a positive integer (default 6)');
  }
  if (maxTxPerMinute > 6 && !process.env.RATE_OVERRIDE_REASON) {
    throw new Error(
      `MAX_TX_PER_MINUTE=${maxTxPerMinute} is above the 6/min default. Lower it, or set ` +
      'RATE_OVERRIDE_REASON with the reason and run your own API node ' +
      '(safety-guidelines.md → Network Etiquette, rule 3).'
    );
  }
  if (maxTxPerMinute > 60) {
    throw new Error('MAX_TX_PER_MINUTE above 60 is never allowed (rule 3 hard ceiling, per operator).');
  }

  return {
    account: process.env.XPR_ACCOUNT!,
    rpcEndpoint: process.env.XPR_RPC_ENDPOINT || 'https://proton.eosusa.io',
    chainId: process.env.XPR_CHAIN_ID || '384da888112027f0321850a169f737c33e53b388aad48b5adace4bab97f437e0',
    atomicApi: process.env.ATOMIC_API || 'https://xpr.api.atomicassets.io',
    maxTxPerMinute
  };
}
```

---

## Testing

### Test with Testnet

```typescript
// Use testnet for development
const TESTNET_CONFIG = {
  endpoint: 'https://tn1.protonnz.com',
  chainId: '71ee83bcf52142d61019d95f9cc5427ba6a0d7ff8accd9e2088ae2abeaf3d3dd'
};

// Get testnet tokens
// proton faucet:claim XPR myaccount
```

### Mock Transactions for Unit Tests

```typescript
import { jest } from '@jest/globals';

const mockApi = {
  transact: jest.fn().mockResolvedValue({
    transaction_id: 'mock_tx_id_123'
  })
};

// In tests
test('transfer succeeds', async () => {
  const result = await service.transfer('recipient', '10.0000 XPR');
  expect(result.success).toBe(true);
  expect(mockApi.transact).toHaveBeenCalled();
});
```
