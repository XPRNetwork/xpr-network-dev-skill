# XPR Network Resources

Comprehensive list of endpoints, tools, documentation, and community resources for XPR Network development.

---

## Chain Information

### Chain IDs

| Network | Chain ID |
|---------|----------|
| **Mainnet** | `384da888112027f0321850a169f737c33e53b388aad48b5adace4bab97f437e0` |
| **Testnet** | `71ee83bcf52142d61019d95f9cc5427ba6a0d7ff8accd9e2088ae2abeaf3d3dd` |

### Network Parameters

| Parameter | Value |
|-----------|-------|
| Block time | 0.5 seconds |
| Block producers | 21 active |
| Token symbol | XPR |
| Token precision | 4 decimals |
| Account names | 1-12 characters (a-z, 1-5) |

---

## RPC Endpoints

### Mainnet

| Endpoint | Provider | Notes |
|----------|----------|-------|
| `https://proton.eosusa.io` | EOSUSA | Primary, reliable |
| `https://proton.greymass.com` | Greymass | Good backup |
| `https://proton.cryptolions.io` | CryptoLions | Alternative |

### Testnet

| Endpoint | Provider |
|----------|----------|
| `https://proton-testnet.eosusa.io` | EOSUSA |

### Health Check

```bash
curl -s https://proton.eosusa.io/v1/chain/get_info | jq '.head_block_num'
```

---

## History API (Hyperion)

### Mainnet

| Endpoint |
|----------|
| `https://proton.eosusa.io/v2/history/get_actions` |
| `https://proton.eosusa.io/v2/history/get_transaction` |

### Common Queries

```bash
# Get account actions
curl "https://proton.eosusa.io/v2/history/get_actions?account=myaccount&limit=50"

# Get specific transaction
curl "https://proton.eosusa.io/v2/history/get_transaction?id=TX_ID"

# Filter by action
curl "https://proton.eosusa.io/v2/history/get_actions?account=myaccount&filter=eosio.token:transfer"
```

---

## Block Explorers

| Explorer | URL | Features |
|----------|-----|----------|
| **Proton Scan** | https://protonscan.io | Primary explorer |
| **XPR Network Explorer** | https://explorer.xprnetwork.org | Official explorer |

### Direct Links

```
# Account
https://protonscan.io/account/ACCOUNT_NAME

# Transaction
https://protonscan.io/tx/TRANSACTION_ID

# Contract
https://explorer.xprnetwork.org/account/CONTRACT_NAME
```

---

## Official Documentation

| Resource | URL |
|----------|-----|
| **Developer Docs** | https://docs.xprnetwork.org |
| **TypeScript Contracts** | https://docs.xprnetwork.org/contract-sdk/storage |
| **CLI Reference** | https://docs.xprnetwork.org/cli/usage |
| **Web SDK** | https://docs.xprnetwork.org/client-sdks/web |

---

## GitHub Repositories

### Official XPR Network

| Repository | Description |
|------------|-------------|
| [XPRNetwork/ts-smart-contracts](https://github.com/XPRNetwork/ts-smart-contracts) | Contract SDK (proton-tsc) |
| [XPRNetwork/proton-web-sdk](https://github.com/XPRNetwork/proton-web-sdk) | Frontend wallet integration |
| [XPRNetwork/proton-cli](https://github.com/XPRNetwork/proton-cli) | Command-line tools |
| [XPRNetwork/protonjs](https://github.com/XPRNetwork/protonjs) | JavaScript RPC library |

### Example Contracts

| Repository | Description |
|------------|-------------|
| [XPRNetwork/proton-ts-sc-examples](https://github.com/XPRNetwork/proton-ts-sc-examples) | Official example contracts |

---

## NPM Packages

| Package | Description | Install |
|---------|-------------|---------|
| `@proton/cli` | CLI tools | `npm i -g @proton/cli` |
| `proton-tsc` | Contract compiler | `npm i proton-tsc` |
| `@proton/web-sdk` | Frontend SDK | `npm i @proton/web-sdk` |
| `@proton/js` | RPC library | `npm i @proton/js` |
| `@proton/link` | Session management | `npm i @proton/link` |

---

## Useful Tools

### Resources Portal

https://resources.xprnetwork.org

- Buy/sell RAM
- View resource prices
- Manage account resources

### Faucets

| Network | Token | URL/Command |
|---------|-------|-------------|
| Testnet | XPR | `proton faucet:claim XPR myaccount` |
| Mainnet | FOOBAR | https://foobar.protonchain.com |

### Token Contracts

| Token | Contract | Decimals |
|-------|----------|----------|
| XPR | `eosio.token` | 4 |
| XUSDT | `xtokens` | 6 |
| XUSDC | `xtokens` | 6 |
| FOOBAR | `xtokens` | 6 |
| LOAN | `loan.token` | 4 |

---

## Wallets

| Wallet | Type | URL |
|--------|------|-----|
| **WebAuth** | Mobile (iOS/Android) | App stores |
| **webauth.com** | Web browser | https://webauth.com |
| **Anchor** | Desktop | https://greymass.com/anchor |

---

## System Contracts

| Contract | Account | Purpose |
|----------|---------|---------|
| Token | `eosio.token` | Native XPR transfers |
| System | `eosio` | Account creation, resources |
| User profiles | `eosio.proton` | KYC, user info |
| Oracles | `oracles` | Price feeds |
| Wrapped tokens | `xtokens` | XUSDT, XUSDC, etc. |

---

## Oracle Price Feeds

| Index | Pair | Description |
|-------|------|-------------|
| 4 | BTC/USD | Bitcoin price |
| 5 | ETH/USD | Ethereum price |
| 13 | XPR/USD | XPR price |

### Query Oracle

```bash
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
```

---

## Community

| Platform | Link |
|----------|------|
| **Discord** | https://discord.gg/xprnetwork |
| **Telegram** | https://t.me/proaborded |
| **Twitter/X** | https://twitter.com/XPRNetwork |

---

## Development Environment

### Recommended Setup

1. **Node.js**: v16+ (v18 LTS recommended)
2. **Editor**: VS Code with TypeScript extension
3. **CLI**: `@proton/cli` installed globally

### VS Code Extensions

- TypeScript (built-in)
- ESLint
- Prettier

### .vscode/settings.json

```json
{
  "typescript.tsdk": "node_modules/typescript/lib",
  "editor.formatOnSave": true
}
```

---

## Quick Start Commands

```bash
# Install CLI
npm i -g @proton/cli

# Set to testnet for development
proton chain:set proton-test

# Generate new key pair
proton key:generate

# Create boilerplate project
proton boilerplate myproject

# Build contract
cd myproject
npm run build

# Deploy to testnet
proton contract:set mycontract ./assembly/target

# Query contract table
proton table mycontract mytable
```

---

## Testnet vs Mainnet Checklist

| Step | Testnet | Mainnet |
|------|---------|---------|
| Set network | `proton chain:set proton-test` | `proton chain:set proton` |
| Get test tokens | `proton faucet:claim XPR account` | Purchase XPR |
| Deploy | Test thoroughly | After testnet verification |
| Test transactions | Use FOOBAR/test tokens | Real tokens |

---

## Support

- **Documentation issues**: https://github.com/XPRNetwork/ts-smart-contracts/issues
- **CLI issues**: https://github.com/XPRNetwork/proton-cli/issues
- **General questions**: Discord #developers channel

---

## License

Most XPR Network tools and SDKs are released under the MIT License.
