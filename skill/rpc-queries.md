# RPC Queries and Table Reading

This guide covers reading blockchain data from XPR Network using RPC calls and the `@proton/js` library.

## RPC Endpoints

Canonical, capability-annotated endpoint list lives in [`resources.md → RPC Endpoints`](./resources.md#rpc-endpoints) — verified per provider for both `/v1/chain/*` (RPC) and `/v2/history/*` (Hyperion). Quick reference:

### Mainnet

| Endpoint | Provider | RPC | Hyperion |
|----------|----------|-----|----------|
| `https://proton.eosusa.io` | EOSUSA | ✓ | ✓ |
| `https://proton.protonuk.io` | ProtonUK | ✓ | ✓ |
| `https://proton-api.eosiomadrid.io` | EOS Madrid | ✓ | ✓ |
| `https://api-xprnetwork-main.saltant.io` | Saltant | ✓ | ✓ |
| `https://xpr-mainnet-api.bloxprod.io` | BloxProd | ✓ | ✓ |
| `https://proton-hyperion.luminaryvisn.com` | Luminary Vision | ✓ | ✓ |
| `https://api.protonnz.com` | ProtonNZ | ✓ | — |
| `https://proton.cryptolions.io` | CryptoLions | ✓ | — |

### Testnet

| Endpoint | Provider |
|----------|----------|
| `https://tn1.protonnz.com` | ProtonNZ |
| `https://api-xprnetwork-test.saltant.io` | Saltant |

Hyperion base path: `/v2/history/` or `/v2/state/`

### Light API

| Network | Endpoint |
|---------|----------|
| Mainnet | `https://lightapi.eosamsterdam.net/api` |

Fast, lightweight API for common queries like token balances.

### Block Explorers

| Explorer | URL |
|----------|-----|
| XPR Network Explorer | `https://explorer.xprnetwork.org` |

---

## Endpoint Etiquette (RPC + Hyperion) — read before deploying an agent

**Public RPC and Hyperion endpoints are run by community operators.** Free at the point of use, not free to operate. Bad citizenship gets you rate-limited *or* added to a manual ban list. **Operator feedback (XPR Network BPs):** the worst offenders aren't using Hyperion at all — they're hammering standard RPC. Most-cited abuse patterns:

| Anti-pattern | Why it's bad | Fix |
|---|---|---|
| Tight `push_trx` retry loops on failing transactions | Every retry is a full broadcast across the cluster — failed tx still consumes operator CPU. Agents commonly retry on assertion failures expecting transient errors. | Distinguish retryable (`cpu usage exceeded`, expired) from permanent (assertion failure, missing authority). Exponential backoff. Don't retry assertion failures — they'll keep failing. |
| `get_table_rows` polled in a tight loop | RAM-stored tables are expensive to read. Looping every 100ms because "you need fresh data" is the #1 RPC abuse. | Poll at 10s+ for most state. Cache the last response. Use Hyperion deltas (`/v2/history/get_deltas`) to react to *changes* rather than re-reading the whole row set. |
| Constant `get_transactions` / `get_actions` (several/sec) | Hyperion-side bandwidth and indexer load. | Poll at a sane interval with `after=` cursors, or stream — but note public-endpoint streaming is currently best-effort (see `real-time-events.md`); self-hosted Hyperion streams reliably. |
| Unbounded `get_history` page-scroll | Walking 10,000 actions one page at a time hits the operator with hundreds of queries for one user task. | Cap the page-scroll. Cache historical pages (they don't change). If you genuinely need full history, run your own indexer. |

### Response codes — what they actually mean

| Code | Meaning | Recovery |
|---|---|---|
| `429 Too Many Requests` | **Hyperion's internal rate limit** — you've crossed the per-IP threshold momentarily. Not a ban; just slow down. | Back off exponentially (2s → 4s → 8s, cap ~60s), switch endpoint, retry. Honor `Retry-After` if set. |
| `403 Forbidden` | **You've been added to the operator's manual ban list** — a human watched your traffic and decided you were abusing the endpoint. | Much harder to recover from. Fix the abuse pattern, message the operator, ask to be unbanned. Don't keep retrying — that confirms you're a bot. |
| `503 Service Unavailable` | Operator overloaded (often by someone else's abuse) or in maintenance. | Treat like 429: back off, switch endpoint. |

### Defaults that won't get you banned

- **Don't poll faster than you need.** Live state (head_block_num, freshest trades) at 1–2 seconds is fine. Most state (balances, table rows, account info) changes infrequently — **10 seconds or more is plenty**. Never sub-second.
- **Cache aggressively.** `get_info.chain_id` never changes — cache forever. ABIs change only on contract deploy — cache for hours. Account info, table schemas — minutes to hours, not seconds.
- **Stream instead of polling when you can.** Hyperion's socket.io stream (mounted at `/stream`) costs the operator one connection where one-second polling costs 86,400 requests/day per agent. Caveat: on the public XPR endpoints the connection handshake works but data delivery is unverified as of 2026-09 (`real-time-events.md` has the details) — so default to polite polling and stream from your own Hyperion when you need real-time.
- **Rotate between endpoints.** Round-robin or randomize across the operator pool to spread load.
- **Identify yourself.** Set a meaningful `User-Agent` header (e.g. `XPRAgent/myagent 1.0`). Operators triage bad behavior much more aggressively when traffic is anonymous.
- **High-volume? Run your own.** If your agent monitors every swap, indexes every NFT trade, or otherwise needs thousands of requests per minute, **don't rely on public endpoints** — run your own indexer node or rent dedicated capacity.

### Hyperion endpoints

Not every RPC provider runs Hyperion (it's a heavier indexer some operators choose not to host). Verified Hyperion-serving endpoints on mainnet (May 2026):

```
https://proton.eosusa.io
https://proton.protonuk.io
https://proton-api.eosiomadrid.io
https://api-xprnetwork-main.saltant.io
https://xpr-mainnet-api.bloxprod.io
https://proton-hyperion.luminaryvisn.com
```

RPC-only providers (404 on `/v2/history/*`): `api.protonnz.com`, `proton.cryptolions.io`.

### Polite client (drop-in)

A small fetch wrapper that rotates endpoints, respects `Retry-After`, backs off exponentially, and aborts on `403` (since a ban won't fix itself):

```typescript
const HYPERION_ENDPOINTS = [
  'https://proton.eosusa.io',
  'https://proton.protonuk.io',
  'https://proton-api.eosiomadrid.io',
  'https://api-xprnetwork-main.saltant.io',
  'https://xpr-mainnet-api.bloxprod.io',
  'https://proton-hyperion.luminaryvisn.com',
];

const USER_AGENT = 'XPRAgent/your-agent-name 1.0';  // change this!

async function politeFetch(
  path: string,
  options: RequestInit = {},
  attempt = 0
): Promise<Response> {
  const endpoint = HYPERION_ENDPOINTS[attempt % HYPERION_ENDPOINTS.length];
  const url = `${endpoint}${path}`;

  const res = await fetch(url, {
    ...options,
    headers: {
      'User-Agent': USER_AGENT,
      ...(options.headers || {}),
    },
  });

  // 403 = manual ban list — retrying just confirms you're a bot. Surface the error.
  if (res.status === 403) {
    throw new Error(`Endpoint ${endpoint} returned 403 — likely banned. Fix your traffic pattern and contact the operator.`);
  }

  // 429 / 503 = rate-limited / overloaded; back off and try the next endpoint.
  if (res.status === 429 || res.status === 503) {
    if (attempt >= 5) {
      throw new Error(`All endpoints rate-limiting after ${attempt + 1} attempts`);
    }
    const retryAfter = parseInt(res.headers.get('Retry-After') || '0', 10);
    const backoffMs = retryAfter > 0
      ? retryAfter * 1000
      : Math.min(60_000, 2_000 * Math.pow(2, attempt));
    await new Promise(r => setTimeout(r, backoffMs));
    return politeFetch(path, options, attempt + 1);
  }

  return res;
}
```

---

## Setup

### Using @proton/js

```bash
npm install @proton/js
```

```typescript
import { JsonRpc } from '@proton/js';

const rpc = new JsonRpc('https://proton.eosusa.io');
```

### Using fetch directly

```typescript
async function queryTable(code: string, table: string, scope?: string) {
  const response = await fetch('https://proton.eosusa.io/v1/chain/get_table_rows', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      code,
      scope: scope ?? code,
      table,
      json: true,
      limit: 100
    })
  });
  return response.json();
}
```

---

## get_table_rows

The primary method for reading table data.

### Basic Query

```typescript
const { rows } = await rpc.get_table_rows({
  code: 'eosio.proton',      // Contract account
  scope: 'eosio.proton',     // Table scope (usually same as code)
  table: 'usersinfo',        // Table name
  json: true,                // Return JSON (not binary)
  limit: 100                 // Max rows to return
});
```

### Query Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `code` | string | Contract account name |
| `scope` | string | Table scope (often same as code) |
| `table` | string | Table name |
| `json` | boolean | Return JSON instead of binary (usually true) |
| `limit` | number | Max rows to return (default 10) |
| `lower_bound` | string/number | Start at this key |
| `upper_bound` | string/number | End at this key |
| `index_position` | string | Index to use: `primary`, `secondary`, `tertiary`, etc. |
| `key_type` | string | Key type: `i64`, `i128`, `name`, `float64`, etc. |
| `reverse` | boolean | Reverse order |

### CRITICAL: All-Numeric Account Names (e.g. `333555`, `111111`)

XPR Network allows account names using only digits 1-5 (e.g. `333555`, `111111`, `12345`). These cause a **silent data loss bug** in `get_table_rows` because the RPC interprets all-numeric strings as raw `u64` integer values instead of EOSIO name-encoded values.

**The problem:** EOSIO names are base32-encoded into u64 using charset `.12345abcdefghijklmnopqrstuvwxyz`. The name `"333555"` encodes to u64 `1785205097907617792`, but the RPC sees `"333555"` and treats it as the raw integer `333555` — a completely different value. Queries return empty results with no error.

**Fix depends on which parameter is numeric:**

| Parameter | Fix | Example |
|-----------|-----|---------|
| `scope` | Convert name to u64 encoding | `scope: "1785205097907617792"` |
| `lower_bound` / `upper_bound` | Convert name to u64 encoding, **or** pass `key_type: "name"` (primary index) so the string is parsed as a name | `lower_bound: "1785205097907617792"` or `lower_bound: "333555", key_type: "name"` |

**Do not append `"."` to force name parsing** — `"333555."` throws `chain_type_exception` on current nodeos (verified September 2026 on v5.0.x), for bounds as well as scope. Always pass the u64 name encoding.

#### Name-to-u64 Encoding Function

```typescript
/**
 * Convert an EOSIO account name to its u64 string representation.
 * Required for all-numeric names used as scope in get_table_rows.
 */
function nameToU64(name: string): string {
  const charset = '.12345abcdefghijklmnopqrstuvwxyz';
  let value = BigInt(0);
  const len = Math.min(name.length, 12);
  for (let i = 0; i < len; i++) {
    const idx = charset.indexOf(name[i]);
    if (idx < 0) return name; // not a valid EOSIO name char
    value |= BigInt(idx) << BigInt(64 - 5 * (i + 1));
  }
  if (name.length === 13) {
    const idx = charset.indexOf(name[12]);
    if (idx >= 0) value |= BigInt(idx & 0xf);
  }
  return value.toString();
}

/** Fix scope, lower_bound and upper_bound for all-numeric account names */
function safeName(name: string): string {
  if (/^\d+$/.test(name)) return nameToU64(name);
  return name;
}
const safeScopeName = safeName;   // same rule applies to scope and bounds
```

#### Example: Querying a Scoped Table for Account `333555`

```typescript
// BAD — returns empty rows (scope interpreted as raw integer 333555)
const { rows } = await rpc.get_table_rows({
  code: 'eosio.token',
  scope: '333555',        // ← WRONG: interpreted as u64 333555
  table: 'accounts',
  json: true, limit: 100
});
// rows = []  ← silent failure!

// BAD — throws chain_type_exception
const { rows } = await rpc.get_table_rows({
  code: 'eosio.token',
  scope: '333555.',       // ← WRONG: "." trick doesn't work for scope
  table: 'accounts',
  json: true, limit: 100
});
// Error: Could not convert scope string '333555.'

// GOOD — use u64 name encoding
const { rows } = await rpc.get_table_rows({
  code: 'eosio.token',
  scope: safeScopeName('333555'),  // → "1785205097907617792"
  table: 'accounts',
  json: true, limit: 100
});
// rows = [{ balance: "1000.0000 XPR" }]  ← correct!
```

#### Example: Querying by Account Name in Bounds

```typescript
// BAD — returns wrong row (lower_bound interpreted as integer 333555)
const { rows } = await rpc.get_table_rows({
  code: 'eosio.proton',
  scope: 'eosio.proton',
  table: 'usersinfo',
  lower_bound: '333555',   // ← interpreted as row index, not name
  upper_bound: '333555',
  limit: 1
});

// GOOD — pass the u64 name encoding (same helper as for scope)
const { rows } = await rpc.get_table_rows({
  code: 'eosio.proton',
  scope: 'eosio.proton',
  table: 'usersinfo',
  lower_bound: nameToU64('333555'),  // → "1785205097907617792"
  upper_bound: nameToU64('333555'),
  limit: 1
});
// (Appending "." — "333555." — throws chain_type_exception on current nodeos.)
```

#### Alternative: Use `get_currency_balance` for Token Balances

For token balances specifically, `get_currency_balance` handles numeric names correctly without any workaround:

```typescript
// Works correctly for all account names including numeric ones
const balances = await fetch(endpoint + '/v1/chain/get_currency_balance', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ code: 'eosio.token', account: '333555' })
}).then(r => r.json());
// ["1000.0000 XPR"]
```

#### Which APIs Are Affected?

| API | Affected? | Notes |
|-----|-----------|-------|
| `get_table_rows` scope | YES | Must use u64 encoding |
| `get_table_rows` lower/upper_bound | YES | Must use u64 encoding |
| `get_table_by_scope` lower/upper_bound | YES | Same integer-first parsing — pass the u64 encoding |
| `get_currency_balance` | NO | Handles names correctly |
| Hyperion APIs | NO | Use string account names |
| Light API | NO | Use string account names |

#### `get_table_by_scope` Has the Same Bug

`get_table_by_scope` with `lower_bound: "333555"` parses the bound as the integer 333555 and returns unrelated scopes (verified: `["....xpr"]`); `lower_bound: "1785205097907617792"` returns `["333555", ...]`. Apply `safeName()` to its bounds too. The scope strings it *returns* are proper names, but passing a numeric one back as `scope` in `get_table_rows` re-triggers the bug — always apply `safeScopeName()`.

---

### Exact Match Query

```typescript
// Get specific user profile
const { rows } = await rpc.get_table_rows({
  code: 'eosio.proton',
  scope: 'eosio.proton',
  table: 'usersinfo',
  lower_bound: 'alice',
  upper_bound: 'alice',
  limit: 1
});

const userProfile = rows.length > 0 ? rows[0] : null;
```

### Range Query

```typescript
// Get challenges with ID 10-50
const { rows } = await rpc.get_table_rows({
  code: 'pricebattle',
  scope: 'pricebattle',
  table: 'challenges',
  lower_bound: 10,
  upper_bound: 50,
  limit: 100
});
```

### Secondary Index Query

```typescript
// Query by secondary index (e.g., by author)
const { rows } = await rpc.get_table_rows({
  code: 'protonwall',
  scope: 'protonwall',
  table: 'posts',
  index_position: 'secondary',  // or '2'
  key_type: 'name',
  lower_bound: 'alice',
  upper_bound: 'alice',
  limit: 100
});
```

### Pagination

```typescript
async function getAllRows(code: string, table: string) {
  const allRows: any[] = [];
  let more = true;
  let nextKey = '';

  while (more) {
    const { rows, more: hasMore, next_key } = await rpc.get_table_rows({
      code,
      scope: code,
      table,
      limit: 100,
      lower_bound: nextKey || undefined
    });

    allRows.push(...rows);
    more = hasMore;
    nextKey = next_key;
  }

  return allRows;
}
```

### Reverse Order

```typescript
// Get latest entries first
const { rows } = await rpc.get_table_rows({
  code: 'protonwall',
  scope: 'protonwall',
  table: 'posts',
  reverse: true,
  limit: 10
});
```

---

## Common Tables

### User Profile (eosio.proton)

```typescript
// Get user profile info
const { rows } = await rpc.get_table_rows({
  code: 'eosio.proton',
  scope: 'eosio.proton',
  table: 'usersinfo',
  lower_bound: 'alice',
  upper_bound: 'alice',
  limit: 1
});

// Response includes:
// - acc: account name
// - name: display name
// - avatar: avatar URL or base64
// - verified: boolean
// - verifiedon: timestamp
// - kyc: array of KYC providers
```

### Token Balances

```typescript
// Get XPR balance
const { rows } = await rpc.get_table_rows({
  code: 'eosio.token',
  scope: 'alice',          // User's account as scope!
  table: 'accounts',
  limit: 100
});

// Returns array of balances: [{ balance: "123.0000 XPR" }, ...]
```

### Oracle Prices

```typescript
// Get BTC/USD price (index 4)
const { rows } = await rpc.get_table_rows({
  code: 'oracles',
  scope: 'oracles',
  table: 'data',
  lower_bound: 4,
  upper_bound: 4,
  limit: 1
});

// Response:
// {
//   feed_index: 4,
//   aggregate: { d_double: "95322.71000000000640284" }
// }
const btcPrice = parseFloat(rows[0].aggregate.d_double);
```

### Oracle Feed Indexes

Common feeds (excerpt — the **canonical full table** with liveness notes is in [`oracles-randomness.md`](./oracles-randomness.md#available-price-feeds)):

| Index | Pair |
|-------|------|
| 3 | XPR/USD |
| 4 | BTC/USD |
| 7 | ETH/USD |
| 9 | USDT/USD |

> Index 5 (USDC/USD) has not updated since 2023 — don't use it; index 9 (USDT/USD) is the live dollar reference.

### Singleton Tables

For singleton tables, there's only one row with no primary key:

```typescript
// Get contract config
const { rows } = await rpc.get_table_rows({
  code: 'pricebattle',
  scope: 'pricebattle',
  table: 'config',
  limit: 1
});

const config = rows[0];  // Single row
```

---

## RPC Service Class

```typescript
import { JsonRpc } from '@proton/js';

class ProtonRPC {
  private rpc: JsonRpc;

  constructor(endpoint: string = 'https://proton.eosusa.io') {
    this.rpc = new JsonRpc(endpoint);
  }

  // Generic table query
  async getTable<T>(
    code: string,
    table: string,
    options: Partial<{
      scope: string;
      limit: number;
      lowerBound: string | number;
      upperBound: string | number;
      indexPosition: string;
      keyType: string;
      reverse: boolean;
    }> = {}
  ): Promise<T[]> {
    const { rows } = await this.rpc.get_table_rows({
      code,
      scope: options.scope ?? code,
      table,
      json: true,
      limit: options.limit ?? 100,
      lower_bound: options.lowerBound,
      upper_bound: options.upperBound,
      index_position: options.indexPosition,
      key_type: options.keyType,
      reverse: options.reverse
    });
    return rows as T[];
  }

  // User profile
  async getUserInfo(account: string) {
    const rows = await this.getTable('eosio.proton', 'usersinfo', {
      lowerBound: account,
      upperBound: account,
      limit: 1
    });
    return rows[0] ?? null;
  }

  // Token balance
  async getBalance(account: string, symbol: string = 'XPR'): Promise<string> {
    const rows = await this.getTable('eosio.token', 'accounts', {
      scope: account
    });
    const balance = rows.find((r: any) => r.balance.includes(symbol));
    return balance?.balance ?? `0.0000 ${symbol}`;
  }

  // Oracle price
  async getOraclePrice(feedIndex: number): Promise<number> {
    const rows = await this.getTable('oracles', 'data', {
      lowerBound: feedIndex,
      upperBound: feedIndex,
      limit: 1
    });
    return parseFloat(rows[0]?.aggregate?.d_double ?? '0');
  }

  // Open challenges
  async getOpenChallenges() {
    return this.getTable('pricebattle', 'challenges', {
      indexPosition: 'secondary',  // status index
      keyType: 'i64',
      lowerBound: 0,  // OPEN status
      upperBound: 0,
      limit: 100
    });
  }
}

export const protonRPC = new ProtonRPC();
```

---

## Hyperion History API

Hyperion provides full history and state APIs. Base URL: `https://proton.eosusa.io`

> **Etiquette + the polite-fetch client live at the top of this doc** — see [Endpoint Etiquette (RPC + Hyperion)](#endpoint-etiquette-rpc--hyperion--read-before-deploying-an-agent). The advice applies to every Hyperion call below.

### History Endpoints

| Endpoint | Description |
|----------|-------------|
| `/v2/history/get_actions` | Query action history |
| `/v2/history/get_transaction` | Get transaction by ID |
| `/v2/history/get_deltas` | Table delta history |
| `/v2/history/get_abi_snapshot` | Historical ABI |
| `/v2/history/get_created_accounts` | Accounts created by account |
| `/v2/history/get_creator` | Get account creator |
| ~~`/v2/history/get_transfers`~~ | **Not deployed on XPR Network Hyperion endpoints — returns 404** (verified eosusa + protonuk, 2026-09). Use `get_actions` with `filter=eosio.token:transfer` (below). |

### State Endpoints

| Endpoint | Description |
|----------|-------------|
| `/v2/state/get_account` | Account info with resources |
| `/v2/state/get_key_accounts` | Accounts by public key |
| `/v2/state/get_tokens` | All token balances for account |
| `/v2/state/get_voters` | Voter information |
| `/v2/state/get_proposals` | Multisig proposals |

### Get Account Actions

```typescript
interface HyperionAction {
  '@timestamp': string;
  trx_id: string;
  act: {
    account: string;
    name: string;
    authorization: Array<{ actor: string; permission: string }>;
    data: Record<string, any>;
  };
  block_num: number;
  producer: string;
}

async function getAccountActions(
  account: string,
  options: {
    limit?: number;
    skip?: number;
    filter?: string;
    sort?: 'asc' | 'desc';
    after?: string;
    before?: string;
  } = {}
): Promise<{ actions: HyperionAction[]; total: number }> {
  const url = new URL('https://proton.eosusa.io/v2/history/get_actions');
  url.searchParams.set('account', account);
  url.searchParams.set('limit', String(options.limit ?? 100));

  if (options.skip) url.searchParams.set('skip', String(options.skip));
  if (options.filter) url.searchParams.set('filter', options.filter);
  if (options.sort) url.searchParams.set('sort', options.sort);
  if (options.after) url.searchParams.set('after', options.after);
  if (options.before) url.searchParams.set('before', options.before);

  const response = await fetch(url);
  return response.json();
}

// Examples:
// Get all actions
await getAccountActions('alice');

// Get only transfer actions
await getAccountActions('alice', { filter: 'eosio.token:transfer' });

// Get actions from last 24 hours
await getAccountActions('alice', {
  after: new Date(Date.now() - 86400000).toISOString()
});

// Paginate through all actions
await getAccountActions('alice', { skip: 100, limit: 100 });
```

### Filter by Contract and Action

```typescript
// Filter format: "contract:action" or "contract:*" for all actions
const filters = {
  allTransfers: 'eosio.token:transfer',
  allFromContract: 'pricebattle:*',
  specificAction: 'atomicassets:mintasset',
  multipleFilters: 'eosio.token:transfer,atomicassets:transfer'  // comma-separated
};

// Get only battle-related actions
const { actions } = await getAccountActions('alice', {
  filter: 'pricebattle:*',
  limit: 50
});
```

### Get Token Transfers

```typescript
interface Transfer {
  from: string;
  to: string;
  quantity: string;
  memo: string;
  block_num: number;
  '@timestamp': string;
  trx_id: string;
}

// NOTE: there is no /v2/history/get_transfers route in Hyperion at all (absent from
// upstream 4.1.0's route list; only a vestigial config key remains), so public XPR
// endpoints return HTTP 404. Do not treat that 404 as "no transfers".
// Use get_actions with the transfer filter instead; it carries the same data.
async function getTransfers(
  account: string,
  opts: { symbol?: string; direction?: 'in' | 'out'; contract?: string; limit?: number } = {}
): Promise<Transfer[]> {
  const { symbol, direction, contract = 'eosio.token', limit = 100 } = opts;
  const url = new URL('https://proton.eosusa.io/v2/history/get_actions');
  url.searchParams.set('account', account);
  url.searchParams.set('filter', `${contract}:transfer`);
  url.searchParams.set('limit', String(limit));
  url.searchParams.set('sort', 'desc');
  // Optional server-side narrowing — Hyperion indexes transfer fields as @transfer.*
  if (direction === 'in')  url.searchParams.set('@transfer.to', account);
  if (direction === 'out') url.searchParams.set('@transfer.from', account);
  if (symbol) url.searchParams.set('@transfer.symbol', symbol);

  const { actions } = await (await fetch(url)).json();
  return actions.map((a: any) => ({
    from: a.act.data.from,
    to: a.act.data.to,
    quantity: a.act.data.quantity,
    memo: a.act.data.memo ?? '',
    block_num: a.block_num,
    '@timestamp': a['@timestamp'],
    trx_id: a.trx_id,
  }));
}

// Inbound XPR transfers only
const transfers = await getTransfers('alice', { symbol: 'XPR', direction: 'in' });
```

### Get Transaction by ID

```typescript
interface HyperionTransaction {
  trx_id: string;
  lib: number;
  cached_lib: boolean;
  executed: boolean;
  actions: HyperionAction[];   // block_num / @timestamp live on each action
  last_indexed_block: number;
  last_indexed_block_time: string;
  query_time_ms: number;
}
// Irreversible when actions[0].block_num <= lib

async function getTransaction(txId: string): Promise<HyperionTransaction> {
  const response = await fetch(
    `https://proton.eosusa.io/v2/history/get_transaction?id=${txId}`
  );
  return response.json();
}
```

### Get Account State

```typescript
interface AccountState {
  account: {                    // the nodeos get_account object, nested
    account_name: string;
    total_resources: {
      net_weight: string;
      cpu_weight: string;
      ram_bytes: number;
    };
    [key: string]: unknown;
  };
  actions: HyperionAction[];    // most recent actions
  links: unknown[];             // linkauth entries
  tokens: Array<{
    symbol: string;
    amount: number;
    contract: string;
    precision: number;
  }>;
  total_actions: number;
}

async function getAccountState(account: string): Promise<AccountState> {
  const response = await fetch(
    `https://proton.eosusa.io/v2/state/get_account?account=${account}`
  );
  return response.json();
}
```

### Get All Token Balances

```typescript
interface TokenBalance {
  symbol: string;
  amount: number;     // numeric, not a string
  contract: string;
  precision: number;
}

async function getAllBalances(account: string): Promise<TokenBalance[]> {
  const response = await fetch(
    `https://proton.eosusa.io/v2/state/get_tokens?account=${account}`
  );
  const data = await response.json();
  return data.tokens;
}

// Returns all tokens the account holds
const balances = await getAllBalances('alice');
// [{ symbol: 'XPR', amount: 1000, contract: 'eosio.token', precision: 4 }, ...]
```

### Get Accounts by Public Key

```typescript
async function getKeyAccounts(publicKey: string): Promise<string[]> {
  const response = await fetch(
    `https://proton.eosusa.io/v2/state/get_key_accounts?public_key=${publicKey}`
  );
  const data = await response.json();
  return data.account_names;
}

// Find all accounts controlled by a key
const accounts = await getKeyAccounts('PUB_K1_6MRy...');
```

### Get Table Deltas (Change History)

```typescript
async function getTableDeltas(
  code: string,
  table: string,
  scope?: string
): Promise<any[]> {
  const url = new URL('https://proton.eosusa.io/v2/history/get_deltas');
  url.searchParams.set('code', code);
  url.searchParams.set('table', table);
  if (scope) url.searchParams.set('scope', scope);
  url.searchParams.set('limit', '100');

  const response = await fetch(url);
  const data = await response.json();
  return data.deltas;
}

// Track changes to a specific table
const deltas = await getTableDeltas('pricebattle', 'challenges');
```

---

## Light API

Light API provides fast, lightweight queries optimized for common operations.

Base URL: `https://lightapi.eosamsterdam.net`

### Endpoints

| Endpoint | Description |
|----------|-------------|
| `/api/account/proton/{account}` | Account info |
| `/api/balances/proton/{account}` | All token balances |
| `/api/tokenbalance/proton/{account}/{contract}/{symbol}` | Specific token balance |
| `/api/key/proton/{public_key}` | Accounts by key |
| `/api/topholders/proton/{contract}/{symbol}/{limit}` | Top token holders — `limit` must be 10–1000; returns an array of `[account, amount]` pairs |
| `/api/accinfo/proton/{account}` | Detailed account info |
| `/api/usercount/proton` | Total registered users |

### Get Account Balances

```typescript
interface LightAPIBalance {
  contract: string;
  currency: string;
  amount: string;
  decimals: string;   // e.g. "4" — a string, parseInt when needed
}

async function getLightAPIBalances(account: string): Promise<LightAPIBalance[]> {
  const response = await fetch(
    `https://lightapi.eosamsterdam.net/api/balances/proton/${account}`
  );
  const data = await response.json();
  return data.balances;
}

// Fast way to get all balances
const balances = await getLightAPIBalances('alice');
```

### Get Specific Token Balance

```typescript
async function getTokenBalance(
  account: string,
  contract: string,
  symbol: string
): Promise<string> {
  const response = await fetch(
    `https://lightapi.eosamsterdam.net/api/tokenbalance/proton/${account}/${contract}/${symbol}`
  );
  // Returns a bare number as text/plain (e.g. "0.0003"), not JSON
  return (await response.text()).trim();
}

// Get XPR balance
const xprBalance = await getTokenBalance('alice', 'eosio.token', 'XPR');

// Get XUSDC balance
const usdcBalance = await getTokenBalance('alice', 'xtokens', 'XUSDC');
```

### Get Accounts by Public Key

```typescript
async function getAccountsByKey(publicKey: string): Promise<string[]> {
  const response = await fetch(
    `https://lightapi.eosamsterdam.net/api/key/${publicKey}`   // no network segment; legacy EOS... key format
  );
  // Response is keyed by network: { proton: { accounts: { <name>: [{perm, threshold, auth}] } }, ... }
  const data = await response.json();
  return Object.keys(data.proton?.accounts ?? {});
}
```

### Get Top Token Holders

```typescript
interface TokenHolder {
  account: string;
  amount: string;
}

async function getTopHolders(
  contract: string,
  symbol: string,
  limit: number = 100   // must be 10–1000 (outside that range → 400 Invalid count)
): Promise<TokenHolder[]> {
  const response = await fetch(
    `https://lightapi.eosamsterdam.net/api/topholders/proton/${contract}/${symbol}/${limit}`
  );
  // Response is a JSON array of [account, amount] pairs
  const data: [string, string][] = await response.json();
  return data.map(([account, amount]) => ({ account, amount }));
}

// Get top 100 XPR holders
const topHolders = await getTopHolders('eosio.token', 'XPR', 100);
```

### Get Total User Count

```typescript
async function getTotalUsers(): Promise<number> {
  const response = await fetch(
    'https://lightapi.eosamsterdam.net/api/usercount/proton'
  );
  // Returns a bare integer as text/plain
  return parseInt(await response.text(), 10);
}
```

---

## Block Explorer APIs

### XPR Network Explorer

The official XPR Network Explorer provides a web interface for viewing accounts, transactions, and contracts.

```typescript
// Link to transaction
const txLink = `https://explorer.xprnetwork.org/transaction/${txId}`;

// Link to account
const accountLink = `https://explorer.xprnetwork.org/account/${account}`;

// Link to contract
const contractLink = `https://explorer.xprnetwork.org/account/${contract}?tab=contract`;
```

---

## Combined Query Service

```typescript
import { JsonRpc } from '@proton/js';

class XPRQueryService {
  private rpc: JsonRpc;
  private hyperionBase = 'https://proton.eosusa.io';
  private lightApiBase = 'https://lightapi.eosamsterdam.net';

  constructor(endpoint: string = 'https://proton.eosusa.io') {
    this.rpc = new JsonRpc(endpoint);
  }

  // === Table Queries (via RPC) ===

  async getTableRows<T>(
    code: string,
    table: string,
    options: {
      scope?: string;
      limit?: number;
      lowerBound?: string | number;
      upperBound?: string | number;
      indexPosition?: string;
      keyType?: string;
      reverse?: boolean;
    } = {}
  ): Promise<T[]> {
    const { rows } = await this.rpc.get_table_rows({
      code,
      scope: options.scope ?? code,
      table,
      json: true,
      limit: options.limit ?? 100,
      lower_bound: options.lowerBound,
      upper_bound: options.upperBound,
      index_position: options.indexPosition,
      key_type: options.keyType,
      reverse: options.reverse
    });
    return rows as T[];
  }

  // === Hyperion History ===

  async getActions(account: string, filter?: string, limit = 100) {
    const url = new URL(`${this.hyperionBase}/v2/history/get_actions`);
    url.searchParams.set('account', account);
    url.searchParams.set('limit', String(limit));
    if (filter) url.searchParams.set('filter', filter);

    const response = await fetch(url);
    return response.json();
  }

  async getTransaction(txId: string) {
    const response = await fetch(
      `${this.hyperionBase}/v2/history/get_transaction?id=${txId}`
    );
    return response.json();
  }

  // /v2/history/get_transfers does not exist in Hyperion (public endpoints 404) —
  // use get_actions with the transfer filter and map act.data.
  async getTransfers(account: string, symbol?: string, limit = 100) {
    const url = new URL(`${this.hyperionBase}/v2/history/get_actions`);
    url.searchParams.set('account', account);
    url.searchParams.set('filter', 'eosio.token:transfer');
    url.searchParams.set('limit', String(limit));
    if (symbol) url.searchParams.set('@transfer.symbol', symbol);

    const { actions } = await (await fetch(url)).json();
    return actions.map((a: any) => ({ ...a.act.data, block_num: a.block_num, timestamp: a['@timestamp'], trx_id: a.trx_id }));
  }

  // === Light API (fast queries) ===

  async getAllBalances(account: string) {
    const response = await fetch(
      `${this.lightApiBase}/api/balances/proton/${account}`
    );
    return response.json();
  }

  async getTokenBalance(account: string, contract: string, symbol: string) {
    const response = await fetch(
      `${this.lightApiBase}/api/tokenbalance/proton/${account}/${contract}/${symbol}`
    );
    return response.json();
  }

  // === Common Queries ===

  async getUserProfile(account: string) {
    const rows = await this.getTableRows('eosio.proton', 'usersinfo', {
      lowerBound: account,
      upperBound: account,
      limit: 1
    });
    return rows[0] ?? null;
  }

  async getOraclePrice(feedIndex: number): Promise<number> {
    const rows = await this.getTableRows('oracles', 'data', {
      lowerBound: feedIndex,
      upperBound: feedIndex,
      limit: 1
    });
    return parseFloat(rows[0]?.aggregate?.d_double ?? '0');
  }

}

export const xprQuery = new XPRQueryService();
```

---

## cURL Examples

```bash
# Basic table query - get user profiles
curl -s -X POST https://proton.eosusa.io/v1/chain/get_table_rows \
  -H "Content-Type: application/json" \
  -d '{
    "code": "eosio.proton",
    "scope": "eosio.proton",
    "table": "usersinfo",
    "json": true,
    "limit": 10
  }'

# Specific account
curl -s -X POST https://proton.eosusa.io/v1/chain/get_table_rows \
  -H "Content-Type: application/json" \
  -d '{
    "code": "eosio.proton",
    "scope": "eosio.proton",
    "table": "usersinfo",
    "lower_bound": "alice",
    "upper_bound": "alice",
    "limit": 1
  }'

# Oracle price
curl -s -X POST https://proton.eosusa.io/v1/chain/get_table_rows \
  -H "Content-Type: application/json" \
  -d '{
    "code": "oracles",
    "scope": "oracles",
    "table": "data",
    "lower_bound": 4,
    "upper_bound": 4,
    "limit": 1
  }'

# Account actions (Hyperion)
curl -s "https://proton.eosusa.io/v2/history/get_actions?account=alice&limit=10"
```

---

## Error Handling

```typescript
async function safeQuery<T>(queryFn: () => Promise<T>, defaultValue: T): Promise<T> {
  try {
    return await queryFn();
  } catch (error: any) {
    if (error.message?.includes('table not found')) {
      // Table doesn't exist or has no data
      return defaultValue;
    }
    if (error.message?.includes('ECONNREFUSED')) {
      // Endpoint down - try backup
      console.error('Primary endpoint down');
    }
    throw error;
  }
}

// Usage
const rating = await safeQuery(
  () => protonRPC.getAccountRating('alice'),
  3  // Default rating
);
```

---

## Performance Tips

1. **Use specific bounds** - Don't query entire tables when you need specific rows
2. **Paginate large results** - Use `limit` and `next_key` for large tables
3. **Cache when possible** - Oracle prices, user profiles don't change frequently
4. **Use secondary indexes** - Query by indexed fields when primary key isn't suitable
5. **Multiple endpoints** - Implement fallback endpoints for reliability

```typescript
const ENDPOINTS = [
  'https://proton.eosusa.io',
  'https://proton.protonuk.io'
];

async function queryWithFallback(query: (rpc: JsonRpc) => Promise<any>) {
  for (const endpoint of ENDPOINTS) {
    try {
      const rpc = new JsonRpc(endpoint);
      return await query(rpc);
    } catch (error) {
      console.error(`Endpoint ${endpoint} failed:`, error);
      continue;
    }
  }
  throw new Error('All endpoints failed');
}
```
