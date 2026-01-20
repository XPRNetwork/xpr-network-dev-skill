# XPR Network Developer Skill

This skill provides comprehensive knowledge for developing on XPR Network, a fast, gas-free blockchain with WebAuthn wallet support.

## Skill Metadata

- **Name**: xpr-network-dev
- **Version**: 1.0.0
- **Author**: XPR Network Community
- **Repository**: https://github.com/XPRNetwork/xpr-network-dev-skill

## XPR Network Overview

XPR Network is an EOS-based blockchain optimized for payments and identity:

| Feature | Description |
|---------|-------------|
| **Speed** | 0.5 second block times, 4000+ TPS |
| **Fees** | Zero gas fees for end users |
| **Accounts** | Human-readable names (1-12 chars, a-z, 1-5) |
| **Wallets** | WebAuthn support (Face ID, fingerprint, security keys) |
| **Contracts** | AssemblyScript/TypeScript with @proton/ts-contracts |
| **Storage** | On-chain tables with RAM-based pricing |

### Chain IDs

| Network | Chain ID |
|---------|----------|
| Mainnet | `384da888112027f0321850a169f737c33e53b388aad48b5adace4bab97f437e0` |
| Testnet | `71ee83bcf52142d61019d95f9cc5427ba6a0d7ff8accd9e2088ae2abeaf3d3dd` |

## Progressive Disclosure

Load specialized modules based on your task:

### For Smart Contract Development
Read: `smart-contracts.md`
- Table definitions, actions, authentication
- Build and deploy workflow
- Testing patterns

### For CLI Operations
Read: `cli-reference.md`
- Network and key management
- Contract deployment
- Table queries and action execution

### For Frontend/dApp Development
Read: `web-sdk.md`
- Wallet connection with @proton/web-sdk
- Transaction signing
- Session management

### For Backend/Server-Side Development
Read: `backend-patterns.md`
- Programmatic transaction signing
- Automated operations and bots
- Security best practices

### For Reading Blockchain Data
Read: `rpc-queries.md`
- RPC endpoints
- Table query patterns
- Pagination and secondary indexes

### For NFT Development
Read: `nfts-atomicassets.md`
- AtomicAssets standard (collections, schemas, templates, assets)
- Minting and transfers
- Marketplace integration

### For MetalX DEX Trading
Read: `metalx-dex.md`
- Complete MetalX API reference
- Order book trading, swaps, liquidity pools
- Trading service class and patterns

### For DeFi/Trading Architecture
Read: `defi-trading.md`
- Trading bot patterns (grid, market maker)
- Building perpetual futures DEX
- Advanced DeFi building blocks

### CRITICAL: Before Modifying Contracts
Read: `safety-guidelines.md`
- **NEVER modify existing table structures with data**
- Pre-deployment checklist
- Recovery procedures

### For Real-World Examples
Read: `examples.md`
- PriceBattle: PvP prediction game
- ProtonWall: Social feed
- ProtonRating: Trust/reputation system

### For Endpoints and Resources
Read: `resources.md`
- RPC endpoints (mainnet/testnet)
- Official documentation links
- Community resources

---

## Quick Reference

### Common CLI Commands

```bash
# Install CLI
npm i -g @proton/cli

# Set network
proton chain:set proton          # Mainnet
proton chain:set proton-test     # Testnet

# Account info
proton account myaccount -t      # With token balances

# Query table
proton table CONTRACT TABLE

# Execute action
proton action CONTRACT ACTION 'JSON_DATA' AUTHORIZATION

# Deploy contract
proton contract:set ACCOUNT ./assembly/target
```

### Common RPC Query

```javascript
const { JsonRpc } = require('@proton/js');
const rpc = new JsonRpc('https://proton.eosusa.io');

const { rows } = await rpc.get_table_rows({
  code: 'CONTRACT',
  scope: 'CONTRACT',
  table: 'TABLE',
  limit: 100
});
```

### Basic Contract Structure

```typescript
import { Contract, Table, TableStore, Name } from 'proton-tsc';

@table("mydata")
class MyData extends Table {
  constructor(
    public id: u64 = 0,
    public owner: Name = new Name(),
    public value: string = ""
  ) { super(); }

  @primary
  get primary(): u64 { return this.id; }
}

@contract
class MyContract extends Contract {
  dataTable: TableStore<MyData> = new TableStore<MyData>(this.receiver);

  @action("store")
  store(owner: Name, value: string): void {
    requireAuth(owner);
    const row = new MyData(this.dataTable.availablePrimaryKey, owner, value);
    this.dataTable.store(row, this.receiver);
  }
}
```

### Basic Frontend Login

```typescript
import ProtonWebSDK from '@proton/web-sdk';

const { link, session } = await ProtonWebSDK({
  linkOptions: {
    chainId: '384da888112027f0321850a169f737c33e53b388aad48b5adace4bab97f437e0',
    endpoints: ['https://proton.eosusa.io']
  },
  selectorOptions: { appName: 'My App' }
});

// session.auth contains { actor, permission }
// Use session.transact() for transactions
```

---

## Key Packages

| Package | Purpose | Install |
|---------|---------|---------|
| `@proton/cli` | Command-line tools | `npm i -g @proton/cli` |
| `proton-tsc` | Contract development | `npm i proton-tsc` |
| `@proton/web-sdk` | Frontend wallet integration | `npm i @proton/web-sdk` |
| `@proton/js` | RPC queries | `npm i @proton/js` |

## Official Resources

- **Documentation**: https://docs.xprnetwork.org
- **GitHub**: https://github.com/XPRNetwork
- **Block Explorer**: https://protonscan.io
- **Resources Portal**: https://resources.xprnetwork.org (buy RAM, etc.)

---

## Safety Reminders

1. **NEVER modify existing table structures** once deployed with data - this breaks deserialization
2. **Always test on testnet** before mainnet deployment
3. **Verify the target account** before deploying - wrong account = overwrite existing contract
4. **Back up ABIs** before deploying changes
5. **Use new tables** for new features instead of modifying existing ones
