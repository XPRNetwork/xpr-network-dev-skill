# XPR Network Developer Skill for Claude Code

A comprehensive skill package that enhances Claude's capabilities for XPR Network blockchain development. This skill provides Claude with deep knowledge of smart contract development, CLI tools, frontend integration, and best practices specific to the XPR Network ecosystem.

## What is XPR Network?

XPR Network is a fast, gas-free blockchain with WebAuthn wallet support. Key features:

- **Zero gas fees** - Users don't pay transaction fees
- **WebAuthn wallets** - Login with Face ID, fingerprint, or security keys
- **4000+ TPS** - Fast block times (0.5s)
- **EOS-based** - Uses EOSIO technology with AssemblyScript smart contracts
- **Human-readable accounts** - 12 character account names instead of hex addresses

## Installation

### Method 1: Add to Claude Code settings

Add this skill to your Claude Code settings file (`~/.claude/settings.json`):

```json
{
  "skills": [
    {
      "name": "xpr-network-dev",
      "path": "/path/to/xpr-network-dev-skill/skill"
    }
  ]
}
```

### Method 2: Clone and reference

```bash
git clone https://github.com/XPRNetwork/xpr-network-dev-skill.git
cd xpr-network-dev-skill
```

Then add to your project's `CLAUDE.md`:

```markdown
For XPR Network development guidance, see: /path/to/xpr-network-dev-skill/skill/SKILL.md
```

### Method 3: Copy to project CLAUDE.md

Copy relevant sections from `skill/SKILL.md` directly into your project's `CLAUDE.md` file.

## Skill Modules

| Module | Description |
|--------|-------------|
| [SKILL.md](skill/SKILL.md) | Main entry point with overview and quick reference |
| [smart-contracts.md](skill/smart-contracts.md) | Contract development with @proton/ts-contracts |
| [cli-reference.md](skill/cli-reference.md) | Complete @proton/cli command reference |
| [web-sdk.md](skill/web-sdk.md) | Frontend integration with @proton/web-sdk |
| [backend-patterns.md](skill/backend-patterns.md) | Server-side signing, automated operations, bots |
| [rpc-queries.md](skill/rpc-queries.md) | Table reading and RPC patterns |
| [nfts-atomicassets.md](skill/nfts-atomicassets.md) | NFT development with AtomicAssets standard |
| [defi-trading.md](skill/defi-trading.md) | DEX integration, trading bots, perps architecture |
| [safety-guidelines.md](skill/safety-guidelines.md) | CRITICAL: Table modification rules, deployment safety |
| [examples.md](skill/examples.md) | Real-world patterns from production contracts |
| [resources.md](skill/resources.md) | Endpoints, links, community resources |

## Usage with Claude Code

Once installed, Claude will automatically use this knowledge when you ask about XPR Network development:

```
"How do I deploy a smart contract on XPR Network?"
"Query a table using proton CLI"
"Create a token transfer action"
"What's the safe way to add a field to a table?"
```

Claude will load specialized modules on demand based on your queries.

## Key Topics Covered

### Smart Contract Development
- AssemblyScript/TypeScript contracts with `@proton/ts-contracts`
- Table definitions (`@table`, `@primary`, singletons)
- Actions, authentication, inline actions
- Build and deploy workflow

### CLI Operations
- Network management (`chain:set`, `chain:get`)
- Key management (`key:add`, `key:list`)
- Contract deployment (`contract:set`)
- Table queries and action execution

### Frontend Integration
- `@proton/web-sdk` for wallet connection
- Session management and transaction signing
- RPC queries with `@proton/js`

### Backend Development
- Server-side transaction signing
- Automated bots and scheduled tasks
- Security best practices for key management

### NFT Development
- AtomicAssets standard (collections, schemas, templates, assets)
- Minting, transfers, and marketplace integration
- IPFS integration for media storage

### DeFi and Trading
- MetalX DEX integration (order book, trades)
- Trading bot patterns (grid bot, market maker)
- Perpetual futures architecture and building blocks

### Safety Guidelines
- **CRITICAL**: Never modify existing table structures with data
- Pre-deployment checklist
- Recovery procedures
- Multi-contract deployment safety

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Test your changes with Claude Code
4. Submit a pull request

### Areas for Contribution

- Additional code examples
- New patterns from production contracts
- Corrections and clarifications
- Translations

## Resources

- **Official Docs**: https://docs.xprnetwork.org
- **GitHub**: https://github.com/XPRNetwork
- **Block Explorer**: https://protonscan.io
- **Discord**: https://discord.gg/xprnetwork

## License

MIT License - see [LICENSE](LICENSE) for details.

---

Built for the XPR Network community by developers, for developers.
