# RPC Queries and Table Reading

This guide covers reading blockchain data from XPR Network using RPC calls and the `@proton/js` library.

## RPC Endpoints

### Mainnet

| Endpoint | Provider |
|----------|----------|
| `https://proton.eosusa.io` | EOSUSA |
| `https://proton.greymass.com` | Greymass |
| `https://proton.cryptolions.io` | CryptoLions |

### Testnet

| Endpoint | Provider |
|----------|----------|
| `https://proton-testnet.eosusa.io` | EOSUSA |

### Hyperion (History API)

| Network | Endpoint |
|---------|----------|
| Mainnet | `https://proton.eosusa.io/v2/history/get_actions` |

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
  code: 'protonrating',      // Contract account
  scope: 'protonrating',     // Table scope (usually same as code)
  table: 'ratings',          // Table name
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

### Exact Match Query

```typescript
// Get specific account rating
const { rows } = await rpc.get_table_rows({
  code: 'protonrating',
  scope: 'protonrating',
  table: 'ratings',
  lower_bound: 'someuser',
  upper_bound: 'someuser',
  limit: 1
});

const rating = rows.length > 0 ? rows[0] : null;
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

| Index | Pair |
|-------|------|
| 4 | BTC/USD |
| 5 | ETH/USD |
| 13 | XPR/USD |

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

  // Account rating
  async getAccountRating(account: string): Promise<number> {
    const rows = await this.getTable('protonrating', 'ratings', {
      lowerBound: account,
      upperBound: account,
      limit: 1
    });
    return rows[0]?.level ?? 3;  // Default level 3 (unknown)
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

For transaction history, use Hyperion:

### Get Account Actions

```typescript
async function getAccountActions(account: string, limit: number = 100) {
  const response = await fetch(
    `https://proton.eosusa.io/v2/history/get_actions?account=${account}&limit=${limit}`
  );
  return response.json();
}
```

### Filter by Action

```typescript
// Get only transfer actions
const url = new URL('https://proton.eosusa.io/v2/history/get_actions');
url.searchParams.set('account', 'alice');
url.searchParams.set('filter', 'eosio.token:transfer');
url.searchParams.set('limit', '50');

const response = await fetch(url);
const { actions } = await response.json();
```

### Get Transaction

```typescript
async function getTransaction(txId: string) {
  const response = await fetch(
    `https://proton.eosusa.io/v2/history/get_transaction?id=${txId}`
  );
  return response.json();
}
```

---

## cURL Examples

```bash
# Basic table query
curl -s -X POST https://proton.eosusa.io/v1/chain/get_table_rows \
  -H "Content-Type: application/json" \
  -d '{
    "code": "protonrating",
    "scope": "protonrating",
    "table": "ratings",
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
  'https://proton.greymass.com'
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
