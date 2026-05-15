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
| Key storage | User's wallet | proton CLI's encrypted keychain |
| Signing | Wallet prompts user | proton CLI shells out from process |
| Use case | User-initiated actions | Automated/scheduled tasks |
| Security | Wallet handles keys | **Key NEVER enters process memory** |

> **Security update (v0.3.0+):** The traditional pattern of loading `XPR_PRIVATE_KEY` from `.env` into `JsSignatureProvider` is **no longer recommended** for long-running backends or AI agents. Keys in process memory are reachable from every tool call, every log line, every web fetch, every paste into an AI conversation — a single accidental leak compromises the whole account. The recommended pattern routes signing through the proton CLI's encrypted keychain so the key never enters the process. See the "Security: Key Isolation" section below for the rationale and migration path. (For serverless / CI / browser cases where this doesn't apply, route via the table at the top.)

---

## Setup (Recommended — proton CLI keychain)

### One-time operator setup

```bash
# Install the proton CLI
npm i -g @proton/cli

# Pick the network
proton chain:set proton              # or proton-test

# Add your blockchain key to the encrypted keychain
proton key:add                       # interactive — paste key once, stored encrypted

# Verify
proton key:list                      # shows public keys + accounts, NEVER prints private values
```

After this, the key lives in the CLI's encrypted keychain. Your `.env` does NOT need `XPR_PRIVATE_KEY`.

### Dependencies

```bash
npm install @xpr-agents/openclaw @proton/js
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
});

// `session.link.transact(...)` signs by shelling out to `proton transaction:push`.
// `rpc` is a standard JsonRpc instance for read operations.
```

What this gives you:

- **`session`** — a `ProtonSession`-shaped object. Same `transact()` interface as the legacy `Api`, but every signed transaction is signed by the CLI from the encrypted keychain. The key bytes never enter your Node.js process.
- **`rpc`** — a standard `JsonRpc` for read operations (`get_table_rows`, `get_info`, etc.). Reads still go via HTTP; only signing routes through the CLI.

### Legacy setup (`JsSignatureProvider`)

Only use this if you have a specific reason — testing, ephemeral keys you don't mind exposing, or wallets that can't go through the CLI:

<details>
<summary>Legacy: key in process memory (NOT recommended)</summary>

```typescript
import { JsonRpc, Api } from '@proton/js';
import { JsSignatureProvider } from 'eosjs/dist/eosjs-jssig';

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

The `@xpr-agents/openclaw` v0.3.0+ agent runner will **refuse to start** if `XPR_PRIVATE_KEY` is set in env, on the assumption that you intended to use the CLI keychain and forgot to migrate. If you genuinely want the legacy pattern, you're outside the agent runner's supported envelope and should build your own service.

</details>

---

## Transaction Signing

### Basic Transaction

These helpers take a `session` argument so they work with whatever signing path you set up in **Basic Configuration** — `createCliSession`'s `session` (recommended) drops in here. `blocksBehind` / `expireSeconds` are accepted by the CLI-backed `transact()` but ignored under the hood; `proton transaction:push` manages tx headers internally.

```typescript
import type { ProtonSession } from '@xpr-agents/sdk';

async function sendTransaction(session: ProtonSession, actions: any[]) {
  try {
    const result = await session.link.transact(
      { actions },
      { blocksBehind: 3, expireSeconds: 30 }
    );
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

  constructor(account: string, endpoint?: string) {
    this.account = account;
    // No privateKey parameter — the proton CLI handles signing from its keychain.
    // The CLI must already have a key registered for `account` via `proton key:add`.
    const { rpc, session } = createCliSession({
      account,
      permission: 'active',
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
        const result = await this.session.link.transact(
          { actions },
          { blocksBehind: 3, expireSeconds: 30 }
        );
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
      authorization: [{ actor: this.account, permission: 'active' }],
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
      authorization: [{ actor: this.account, permission: 'active' }],
      data
    }]);
  }
}

// Usage — note: no private key argument. The CLI handles it.
const xpr = new XPRBackendService('myaccount');

await xpr.transfer('recipient', '10.0000 XPR', 'Payment');
await xpr.callContract('mycontract', 'myaction', { param1: 'value' });
```

---

## Token Operations

### Deploy a Token

```typescript
async function deployToken(
  issuer: string,
  maxSupply: string  // e.g., "1000000.0000 MYTOKEN"
) {
  // Create token
  await sendTransaction([{
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
  issuer: string,
  to: string,
  quantity: string,
  memo: string = 'Token issuance'
) {
  await sendTransaction([{
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
  minter: string,
  collection: string,
  schema: string,
  templateId: number,
  recipient: string
) {
  return sendTransaction([{
    account: 'atomicassets',
    name: 'mintasset',
    authorization: [{ actor: minter, permission: 'active' }],
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
async function batchMintWithLimit(
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
      authorization: [{ actor: minter, permission: 'active' }],
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

    const result = await sendTransaction(actions);
    results.push(result);

    // Rate limit: wait between batches
    if (i + batchSize < recipients.length) {
      await new Promise(r => setTimeout(r, 1000));
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

async function resolveExpiredChallenges() {
  // Get active challenges that have ended
  const { rows } = await rpc.get_table_rows({
    code: 'pricebattle',
    scope: 'pricebattle',
    table: 'challenges',
    index_position: 'secondary',
    key_type: 'i64',
    lower_bound: 1,  // ACTIVE status
    upper_bound: 1,
    limit: 100
  });

  const now = Math.floor(Date.now() / 1000);

  for (const challenge of rows) {
    const endTime = challenge.started_at + challenge.duration;

    if (now >= endTime) {
      // Get current oracle price
      const price = await getOraclePrice(challenge.oracle_index);

      // Resolve the challenge
      await sendTransaction([{
        account: 'pricebattle',
        name: 'resolve',
        authorization: [{ actor: 'resolver', permission: 'active' }],
        data: {
          challenge_id: challenge.id,
          resolver: 'resolver',
          end_price: price
        }
      }]);

      console.log(`Resolved challenge ${challenge.id}`);
    }
  }
}

// Run every minute
cron.schedule('* * * * *', resolveExpiredChallenges);
```

### Cleanup Expired Entries

```typescript
async function cleanupExpired() {
  await sendTransaction([{
    account: 'mycontract',
    name: 'cleanup',
    authorization: [{ actor: 'myaccount', permission: 'active' }],
    data: { limit: 100 }
  }]);
}

// Run every hour
cron.schedule('0 * * * *', cleanupExpired);
```

---

## Security: Key Isolation

### The charliebot incident (April 2026)

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

**Make the unsafe thing impossible: the agent process must not have the chain key in memory.** All signing routes through the proton CLI's encrypted keychain.

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
proton key:add                # paste key once, stored encrypted in CLI keychain
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
}' myapp@owner

# Link permission to specific action
proton action eosio linkauth '{
  "account": "myapp",
  "code": "atomicassets",
  "type": "mintasset",
  "requirement": "minter"
}' myapp@owner
```

Now you can sign mintasset with the limited `minter` key.

### Rate Limiting

```typescript
class RateLimiter {
  private timestamps: number[] = [];
  private maxRequests: number;
  private windowMs: number;

  constructor(maxRequests: number, windowMs: number) {
    this.maxRequests = maxRequests;
    this.windowMs = windowMs;
  }

  async acquire(): Promise<void> {
    const now = Date.now();
    this.timestamps = this.timestamps.filter(t => now - t < this.windowMs);

    if (this.timestamps.length >= this.maxRequests) {
      const waitTime = this.timestamps[0] + this.windowMs - now;
      await new Promise(r => setTimeout(r, waitTime));
      return this.acquire();
    }

    this.timestamps.push(now);
  }
}

// Usage: Max 10 transactions per second
const limiter = new RateLimiter(10, 1000);

async function rateLimitedTransfer(to: string, amount: string) {
  await limiter.acquire();
  return transfer(to, amount);
}
```

---

## Error Handling

### Common Errors

| Error | Cause | Solution |
|-------|-------|----------|
| `missing authority` | Wrong key or permission | Check authorization matches key |
| `expired transaction` | Transaction took too long | Increase `expireSeconds` |
| `duplicate transaction` | Same tx submitted twice | Add unique data or wait |
| `cpu usage exceeded` | Not enough CPU staked | Stake more CPU or wait |
| `assertion failure` | Contract validation failed | Check action parameters |

### Robust Error Handling

```typescript
async function safeTransact(
  session: ProtonSession,
  actions: any[]
): Promise<TransactionResult> {
  try {
    const result = await session.link.transact(
      { actions },
      { blocksBehind: 3, expireSeconds: 30 }
    );
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
# encrypted keychain. If you set XPR_PRIVATE_KEY anyway, the agent runner
# refuses to start.
XPR_ACCOUNT=myaccount
XPR_RPC_ENDPOINT=https://proton.eosusa.io
XPR_CHAIN_ID=384da888112027f0321850a169f737c33e53b388aad48b5adace4bab97f437e0

# For testnet
# XPR_RPC_ENDPOINT=https://tn1.protonnz.com
# XPR_CHAIN_ID=71ee83bcf52142d61019d95f9cc5427ba6a0d7ff8accd9e2088ae2abeaf3d3dd

# Optional: separate signing key for A2A protocol (limited-blast-radius custom permission)
# A2A_SIGNING_KEY=PVT_K1_xxxxx

# Optional: AtomicAssets
ATOMIC_API=https://xpr.api.atomicassets.io

# Optional: Rate limiting
MAX_TPS=10
```

### Config Loader

```typescript
import { execSync } from 'child_process';

interface Config {
  account: string;
  rpcEndpoint: string;
  chainId: string;
  atomicApi: string;
  maxTps: number;
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

  // Verify the CLI has a key for this account before booting.
  try {
    execSync(`proton key:list`, { stdio: 'pipe' });
  } catch {
    throw new Error('proton CLI not found in PATH. Install with: npm i -g @proton/cli');
  }

  return {
    account: process.env.XPR_ACCOUNT!,
    rpcEndpoint: process.env.XPR_RPC_ENDPOINT || 'https://proton.eosusa.io',
    chainId: process.env.XPR_CHAIN_ID || '384da888112027f0321850a169f737c33e53b388aad48b5adace4bab97f437e0',
    atomicApi: process.env.ATOMIC_API || 'https://xpr.api.atomicassets.io',
    maxTps: parseInt(process.env.MAX_TPS || '10')
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
