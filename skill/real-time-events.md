# Real-Time Events and Notifications

This guide covers listening for blockchain events, streaming data, and building notification systems on XPR Network.

## Overview

XPR Network provides several ways to get real-time updates:

| Method | Use Case | Latency |
|--------|----------|---------|
| **Hyperion Streaming** | Action/delta streams | ~1-2 seconds |
| **Polling** | Simple integrations | 1-30 seconds |
| **State History Plugin** | Full node operators | Real-time |

---

## Hyperion Streaming API

Hyperion streams actions and table deltas over **socket.io** (not a raw WebSocket). Most public XPR Network Hyperions advertise it (`/v2/health` → `"streaming":{"enable":true,"traces":true,"deltas":true}`; bloxprod reports `traces:false`), but as of **2026-09-01** the reality on the public endpoints is:

| Endpoint | Connect via socket.io `path: '/stream'` | Live/replay data delivered in tests |
|---|---|---|
| `https://proton.eosusa.io` | ✅ connects; receives `handshake` + `lib_update`; `streamActions` requests accepted (`status: OK`) | ❌ none in 60–90 s windows (live tail or historical replay) |
| `https://api-xprnetwork-main.saltant.io` | ❌ 404 — proxy doesn't expose the socket mount | — |
| `https://proton.protonuk.io` | ❌ 403 | — |

> **Treat public streaming as best-effort, not a dependency.** The connection layer below is verified; delivery on the shared endpoints is not. For production, either poll politely (next section, and the etiquette rules in `rpc-queries.md`) or run your own Hyperion and stream from that. If you do get the public stream working, please open an issue with the recipe.

### Why the obvious approaches fail

The socket.io server is mounted at **`/stream`** on the HTTPS origin. So:

```
wss://proton.eosusa.io/stream                       ❌ raw WebSocket — no socket.io handshake, fails
https://proton.eosusa.io/socket.io/?EIO=4           ❌ default socket.io path — 404
https://proton.eosusa.io/stream/socket.io/?EIO=4    ❌ doubled path — 404
io('https://proton.eosusa.io', { path: '/stream' })  ✅ correct
```

You also need `socket.io-client` (v4) — a plain `ws` client cannot speak the protocol.

### Recommended: the official client

`@eosrio/hyperion-stream-client` handles the path, transports, reconnection, and the request/ack protocol:

```bash
npm install @eosrio/hyperion-stream-client
```

```typescript
import { HyperionStreamClient } from '@eosrio/hyperion-stream-client';

// Pass the HTTPS API origin — the client appends /stream itself.
const client = new HyperionStreamClient({ endpoint: 'https://proton.eosusa.io' });

client.on('error', (e) => console.error('stream error:', e));
await client.connect();

// Hyperion rejects unscoped requests (ack `{ status: 'FAIL', reason: 'invalid request' }`) —
// narrow by `account` (the notified account) or otherwise be specific.
const transfers = await client.streamActions({
  contract: 'eosio.token',
  action: 'transfer',
  account: 'dex',          // e.g. every transfer touching the dex contract
  start_from: 0,           // 0 = live tail; a block number = replay from there
  read_until: 0,           // 0 = keep streaming
  filters: [],             // optional field filters, e.g. [{ field: 'data.to', value: 'dex' }]
});

// Stream objects emit 'message' (plus 'start' / 'error'); 'data' is a client-level event
transfers.on('message', (msg) => {
  const { act, block_num } = msg.content;
  console.log(block_num, act.data);   // { from, to, quantity, memo }
});

// Table deltas work the same way
const deltas = await client.streamDeltas({
  code: 'oracles', table: 'data', scope: 'oracles', payer: '',
  start_from: 0, read_until: 0,
});
deltas.on('message', (msg) => console.log('oracle update', msg.content));
```

### Raw `socket.io-client` (if you can't use the official client)

Connection recipe that is verified to reach `handshake` / `lib_update` on eosusa:

```typescript
import { io } from 'socket.io-client';

const socket = io('https://proton.eosusa.io', {
  path: '/stream',              // the mount point — NOT the default /socket.io
  transports: ['websocket'],
  reconnection: true,
});

socket.on('connect',       () => console.log('connected', socket.id));
// Hyperion 3.x servers (e.g. eosusa) deliver the handshake as a 'message' with event:'handshake';
// 4.x servers emit a dedicated 'handshake' event with { chain, chain_id } — listen for both
socket.on('message',       (m) => m.event === 'handshake' && console.log('handshake', m));
socket.on('handshake',     (m) => console.log('handshake', m));
socket.on('lib_update',    (m) => console.log('LIB', m.block_num));
socket.on('fork_event',    (m) => console.warn('fork', m));
socket.on('message',       (m) => console.log('stream message', m));
socket.on('connect_error', (e) => console.error(e.message));
```

Stream requests are sent as socket.io events with acknowledgements (`action_stream_request`, `delta_stream_request`, `cancel_stream_request`) and each carries a server-assigned `reqUUID`; replies arrive on `message`. The exact payloads are an implementation detail of the client library — use it rather than hand-rolling unless you have a reason.

### Thin adapter used by the examples in this doc

The notification-service, database-sync, and webhook examples further down use this small callback-style wrapper over the official client, so they read the same way regardless of transport details. Note that `account` is **required** for action streams — Hyperion acks unscoped requests with `status: FAIL, reason: invalid request`.

```typescript
import { HyperionStreamClient } from '@eosrio/hyperion-stream-client';

export class HyperionStream {
  private client: HyperionStreamClient;

  constructor(endpoint = 'https://proton.eosusa.io') {
    this.client = new HyperionStreamClient({ endpoint });
    this.client.on('error', (e) => console.error('hyperion stream error:', e));
  }

  connect(): Promise<void> { return this.client.connect(); }
  disconnect(): void { this.client.disconnect(); }

  /** Stream `contract::action` traces where `account` is notified. Callback gets the action with trx_id/block_num/@timestamp attached. */
  async subscribeActions(contract: string, action: string, account: string, cb: (action: any) => void) {
    const stream = await this.client.streamActions({ contract, action, account, start_from: 0, read_until: 0, filters: [] });
    stream.on('message', (msg: any) => {
      const c = msg.content;
      cb({ ...c.act, trx_id: c.trx_id, block_num: c.block_num, '@timestamp': c['@timestamp'] });
    });
    return stream;
  }

  /** Stream table deltas for `code::table` (scope defaults to the contract). Callback gets { present, data, primary_key, ... }. */
  async subscribeDeltas(code: string, table: string, cb: (delta: any) => void, scope: string = code) {
    const stream = await this.client.streamDeltas({ code, table, scope, payer: '', start_from: 0, read_until: 0 });
    stream.on('message', (msg: any) => cb(msg.content));
    return stream;
  }
}
```

### Self-hosting note

If you run your own Hyperion, the socket.io server listens on a separate stream port that must be proxied to `/stream` with WebSocket upgrade headers (`Upgrade` / `Connection: upgrade`, long `proxy_read_timeout`). Cloudflare's orange-cloud proxy interferes with long-lived stream sockets — use DNS-only for the Hyperion hostname.

---

## Polling Pattern

For simpler integrations, poll the Hyperion API:

### Poll for New Actions

```typescript
class ActionPoller {
  private lastTimestamp: string = '';
  private pollInterval: number;
  private running: boolean = false;

  constructor(
    private account: string,
    private filter: string | undefined,
    intervalMs: number = 5000
  ) {
    this.pollInterval = intervalMs;
    this.lastTimestamp = new Date().toISOString();
  }

  start(callback: (actions: any[]) => void): void {
    this.running = true;
    this.poll(callback);
  }

  stop(): void {
    this.running = false;
  }

  private async poll(callback: (actions: any[]) => void): Promise<void> {
    while (this.running) {
      try {
        const url = new URL('https://proton.eosusa.io/v2/history/get_actions');
        url.searchParams.set('account', this.account);
        url.searchParams.set('after', this.lastTimestamp);
        url.searchParams.set('sort', 'asc');
        url.searchParams.set('limit', '100');

        if (this.filter) {
          url.searchParams.set('filter', this.filter);
        }

        const response = await fetch(url);
        const data = await response.json();

        if (data.actions && data.actions.length > 0) {
          callback(data.actions);

          // Update timestamp to latest action
          const lastAction = data.actions[data.actions.length - 1];
          this.lastTimestamp = lastAction['@timestamp'];
        }
      } catch (error) {
        console.error('Polling error:', error);
      }

      await this.sleep(this.pollInterval);
    }
  }

  private sleep(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }
}

// Usage: Poll for incoming transfers
const poller = new ActionPoller('myaccount', 'eosio.token:transfer', 3000);

poller.start((actions) => {
  for (const action of actions) {
    if (action.act.data.to === 'myaccount') {
      console.log('Received payment:', action.act.data);
      // Handle incoming payment
    }
  }
});
```

### Poll for Table Changes

```typescript
class TablePoller<T> {
  private lastData: Map<string, T> = new Map();

  constructor(
    private contract: string,
    private table: string,
    private scope: string = contract,
    private pollInterval: number = 5000
  ) {}

  async start(
    onAdd: (row: T) => void,
    onUpdate: (oldRow: T, newRow: T) => void,
    onRemove: (row: T) => void,
    getKey: (row: T) => string
  ): Promise<void> {
    while (true) {
      try {
        const { rows } = await rpc.get_table_rows({
          code: this.contract,
          scope: this.scope,
          table: this.table,
          limit: 1000
        });

        const currentKeys = new Set<string>();

        for (const row of rows) {
          const key = getKey(row);
          currentKeys.add(key);

          const existing = this.lastData.get(key);
          if (!existing) {
            onAdd(row);
          } else if (JSON.stringify(existing) !== JSON.stringify(row)) {
            onUpdate(existing, row);
          }

          this.lastData.set(key, row);
        }

        // Check for removed rows
        for (const [key, row] of this.lastData) {
          if (!currentKeys.has(key)) {
            onRemove(row);
            this.lastData.delete(key);
          }
        }
      } catch (error) {
        console.error('Table poll error:', error);
      }

      await new Promise(r => setTimeout(r, this.pollInterval));
    }
  }
}

// Usage: Watch challenges table
const challengePoller = new TablePoller('pricebattle', 'challenges');

challengePoller.start(
  (challenge) => console.log('New challenge:', challenge),
  (old, updated) => console.log('Challenge updated:', old.id, '->', updated),
  (challenge) => console.log('Challenge removed:', challenge.id),
  (row) => String(row.id)
);
```

---

## Notification Service Architecture

### Backend Service

Build a notification service that watches the chain and notifies users:

```typescript
import { Server } from 'socket.io';
// HyperionStream = the thin adapter defined in the streaming section above

interface Subscription {
  userId: string;
  account: string;
  filters: string[];
}

class NotificationService {
  private hyperion: HyperionStream;
  private io: Server;
  private subscriptions: Map<string, Subscription[]> = new Map();

  constructor(ioServer: Server) {
    this.io = ioServer;
    this.hyperion = new HyperionStream();
  }

  async start(): Promise<void> {
    await this.hyperion.connect();
    // Streams are opened per watched account in subscribeUser() — Hyperion
    // requires an `account` on action streams, and per-account is the right
    // granularity for notifications anyway.
  }

  private watched = new Set<string>();

  private watchAccount(account: string): void {
    if (this.watched.has(account)) return;
    this.watched.add(account);
    this.watchTransfers(account);
    this.watchNFTs(account);
  }

  private watchTransfers(account: string): void {
    this.hyperion.subscribeActions('eosio.token', 'transfer', account, (action) => {
      const { from, to, quantity, memo } = action.data;

      // Notify recipient
      this.notifyAccount(to, {
        type: 'transfer_received',
        from,
        quantity,
        memo,
        txId: action.trx_id
      });

      // Notify sender
      this.notifyAccount(from, {
        type: 'transfer_sent',
        to,
        quantity,
        memo,
        txId: action.trx_id
      });
    });
  }

  private watchNFTs(account: string): void {
    this.hyperion.subscribeActions('atomicassets', 'transfer', account, (action) => {
      const { from, to, asset_ids } = action.data;

      this.notifyAccount(to, {
        type: 'nft_received',
        from,
        assetIds: asset_ids,
        txId: action.trx_id
      });
    });
  }

  private notifyAccount(account: string, notification: any): void {
    // Emit to all connected clients watching this account
    this.io.to(`account:${account}`).emit('notification', notification);

    // Could also store in database, send push notification, etc.
  }

  // Called when user connects
  subscribeUser(socketId: string, account: string): void {
    this.io.sockets.sockets.get(socketId)?.join(`account:${account}`);
    this.watchAccount(account);
  }
}

// Express + Socket.io setup
import express from 'express';
import { createServer } from 'http';
import { Server } from 'socket.io';

const app = express();
const httpServer = createServer(app);
const io = new Server(httpServer, { cors: { origin: '*' } });

const notificationService = new NotificationService(io);

io.on('connection', (socket) => {
  console.log('Client connected:', socket.id);

  socket.on('subscribe', (account: string) => {
    notificationService.subscribeUser(socket.id, account);
    console.log(`${socket.id} subscribed to ${account}`);
  });
});

notificationService.start();
httpServer.listen(3001);
```

### Frontend Client

```typescript
import { io, Socket } from 'socket.io-client';

class NotificationClient {
  private socket: Socket;
  private handlers: Map<string, ((data: any) => void)[]> = new Map();

  constructor(serverUrl: string) {
    this.socket = io(serverUrl);

    this.socket.on('notification', (notification) => {
      const handlers = this.handlers.get(notification.type) || [];
      handlers.forEach(handler => handler(notification));

      // Also call 'all' handlers
      const allHandlers = this.handlers.get('all') || [];
      allHandlers.forEach(handler => handler(notification));
    });
  }

  subscribe(account: string): void {
    this.socket.emit('subscribe', account);
  }

  on(type: string, handler: (data: any) => void): void {
    const handlers = this.handlers.get(type) || [];
    handlers.push(handler);
    this.handlers.set(type, handlers);
  }
}

// React hook
import { useEffect, useState } from 'react';

export function useNotifications(account: string) {
  const [notifications, setNotifications] = useState<any[]>([]);
  const [client] = useState(() => new NotificationClient('http://localhost:3001'));

  useEffect(() => {
    if (!account) return;

    client.subscribe(account);

    client.on('all', (notification) => {
      setNotifications(prev => [notification, ...prev].slice(0, 50));
    });
  }, [account]);

  return notifications;
}

// Usage in component
function NotificationBell({ account }) {
  const notifications = useNotifications(account);

  return (
    <div>
      {notifications.map((n, i) => (
        <div key={i}>
          {n.type === 'transfer_received' && (
            <span>Received {n.quantity} from {n.from}</span>
          )}
          {n.type === 'nft_received' && (
            <span>Received NFT from {n.from}</span>
          )}
        </div>
      ))}
    </div>
  );
}
```

---

## Transaction Confirmation

Wait for transaction confirmation:

```typescript
interface TxResult {
  transaction_id: string;
  processed: {
    block_num: number;
    block_time: string;
  };
}

async function waitForConfirmation(
  txId: string,
  confirmations: number = 1,
  timeoutMs: number = 30000
): Promise<boolean> {
  const startTime = Date.now();

  while (Date.now() - startTime < timeoutMs) {
    try {
      const response = await fetch(
        `https://proton.eosusa.io/v2/history/get_transaction?id=${txId}`
      );
      const data = await response.json();

      if (data.trx_id) {
        // Transaction found
        const info = await rpc.get_info();
        const txBlockNum = data.actions[0]?.block_num;
        const currentBlock = info.head_block_num;
        const confirmedBlocks = currentBlock - txBlockNum;

        if (confirmedBlocks >= confirmations) {
          return true;
        }
      }
    } catch (error) {
      // Transaction not yet indexed, continue waiting
    }

    await new Promise(r => setTimeout(r, 1000));
  }

  return false;
}

// Usage
const result = await session.transact({ actions }, { broadcast: true });
const confirmed = await waitForConfirmation(result.transaction_id, 3);

if (confirmed) {
  console.log('Transaction confirmed!');
} else {
  console.log('Confirmation timeout');
}
```

---

## Event-Driven Architecture

### Database Sync Pattern

Sync blockchain data to a database for fast queries:

```typescript
import { Pool } from 'pg';

class BlockchainSync {
  private pool: Pool;
  private stream: HyperionStream;

  // `watchAccount`: transfers touching this account (Hyperion requires a scope;
  // to index *all* transfers, run your own Hyperion and stream from it)
  constructor(dbConfig: any, private watchAccount: string) {
    this.pool = new Pool(dbConfig);
    this.stream = new HyperionStream();
  }

  async start(): Promise<void> {
    await this.stream.connect();

    // Sync transfers
    this.stream.subscribeActions('eosio.token', 'transfer', this.watchAccount, async (action) => {
      await this.pool.query(
        `INSERT INTO transfers (tx_id, from_account, to_account, quantity, memo, timestamp)
         VALUES ($1, $2, $3, $4, $5, $6)
         ON CONFLICT (tx_id) DO NOTHING`,
        [
          action.trx_id,
          action.data.from,
          action.data.to,
          action.data.quantity,
          action.data.memo,
          action['@timestamp']
        ]
      );
    });

    // Sync challenges
    this.stream.subscribeDeltas('pricebattle', 'challenges', async (delta) => {
      if (delta.present) {
        await this.pool.query(
          `INSERT INTO challenges (id, creator, opponent, amount, status, created_at)
           VALUES ($1, $2, $3, $4, $5, NOW())
           ON CONFLICT (id) DO UPDATE SET
             opponent = $2, status = $4`,
          [delta.data.id, delta.data.creator, delta.data.opponent, delta.data.amount, delta.data.status]
        );
      } else {
        await this.pool.query('DELETE FROM challenges WHERE id = $1', [delta.primary_key]);
      }
    });
  }
}
```

### Webhook Pattern

Send webhooks when events occur:

```typescript
import axios from 'axios';

interface WebhookConfig {
  url: string;
  account: string;
  events: string[];
  secret: string;
}

class WebhookDispatcher {
  private webhooks: WebhookConfig[] = [];

  register(config: WebhookConfig): void {
    this.webhooks.push(config);
  }

  async dispatch(event: string, account: string, payload: any): Promise<void> {
    const matching = this.webhooks.filter(
      w => w.account === account && w.events.includes(event)
    );

    for (const webhook of matching) {
      try {
        const signature = this.sign(payload, webhook.secret);

        await axios.post(webhook.url, {
          event,
          payload,
          timestamp: Date.now()
        }, {
          headers: {
            'X-Webhook-Signature': signature,
            'Content-Type': 'application/json'
          }
        });
      } catch (error) {
        console.error(`Webhook failed: ${webhook.url}`, error);
      }
    }
  }

  private sign(payload: any, secret: string): string {
    const crypto = require('crypto');
    return crypto
      .createHmac('sha256', secret)
      .update(JSON.stringify(payload))
      .digest('hex');
  }
}

// Usage
const dispatcher = new WebhookDispatcher();

dispatcher.register({
  url: 'https://myapp.com/webhooks/payments',
  account: 'merchant',
  events: ['transfer_received'],
  secret: 'my-webhook-secret'
});

// In your stream handler (one stream per merchant account):
stream.subscribeActions('eosio.token', 'transfer', 'merchant', (action) => {
  dispatcher.dispatch('transfer_received', action.data.to, action.data);
});
```

---

## Quick Reference

### Hyperion Stream Requests (via `@eosrio/hyperion-stream-client`)

```typescript
// Action stream — `account` is required in practice (server acks unscoped requests with status FAIL)
client.streamActions({ contract: 'eosio.token', action: 'transfer', account: 'dex', start_from: 0, read_until: 0, filters: [] });

// Delta stream
client.streamDeltas({ code: 'pricebattle', table: 'challenges', scope: 'pricebattle', payer: '', start_from: 0, read_until: 0 });
```

Connection: `io('https://<hyperion>', { path: '/stream', transports: ['websocket'] })` — socket.io, not raw WebSocket. Public-endpoint delivery is unverified; see the streaming section.

### Common Filters

| Filter | Description |
|--------|-------------|
| `eosio.token:transfer` | All token transfers |
| `atomicassets:*` | All NFT actions |
| `pricebattle:*` | All PriceBattle actions |
| `eosio:newaccount` | New account creation |

### Polling Intervals

| Use Case | Recommended Interval |
|----------|---------------------|
| Real-time UI | 1-3 seconds |
| Background sync | 5-10 seconds |
| Analytics | 30-60 seconds |

### Performance Tips

1. **Prefer streaming over polling** where it actually delivers — on the public endpoints today that's unverified, so default to polite polling (see `rpc-queries.md` → Endpoint Etiquette) and stream from your own Hyperion when you need it
2. **Filter server-side** - don't fetch everything and filter client-side
3. **Implement reconnection logic** for socket.io connections (the official client does this for you)
4. **Use database indexes** for synced blockchain data
5. **Batch notifications** to avoid overwhelming users

---

## Libraries

### block-stream

TypeScript library for real-time XPR Network streaming via State History Plugin.

**Repository:** https://github.com/SuperstrongBE/block-stream

**Features:**
- WebSocket streaming with automatic ABI decoding
- Microservice architecture with chainable processors
- Contract whitelisting and granular filtering
- Winston logging with configurable levels

**Installation:** not published to npm (the repo's package name `@rockerone/block-stream-client` is unpublished too) — clone and import from the checkout:
```bash
git clone https://github.com/SuperstrongBE/block-stream
cd block-stream && bun install
```

**Example:**
```typescript
import { BlockStreamClient } from './index';   // from the cloned repo

const client = new BlockStreamClient({
  socketAddress: 'ws://proton-ship.eosusa.io:8080',
  contracts: {
    'eosio.token': {
      tables: ['accounts'],
      actions: ['transfer']
    },
    'pricebattle': {
      tables: ['*'],      // All tables
      actions: ['*']      // All actions
    }
  }
});

client
  .pipe(async (ctx) => {
    if (ctx.$action) {
      console.log('Action:', ctx.$action.name, ctx.$action.data);
    }
    if (ctx.$delta) {
      console.log('Delta:', ctx.$table, ctx.$delta);
    }
  })
  .start();
```

**Best for:** Production indexers, analytics pipelines, real-time dashboards requiring direct State History access.
