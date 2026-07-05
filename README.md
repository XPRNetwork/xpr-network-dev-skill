# XPR Network Developer Skill

A comprehensive, ABI-verified knowledge layer for XPR Network development. Use it two ways:

- **In Claude Code** (and any AI assistant that reads markdown) — install once, the assistant loads the right module on demand when you ask about smart contracts, DEX trading, NFTs, lending, agents, or infrastructure. See [Installation](#installation).
- **As the brain for a server-side autonomous agent** — paired with the [`@xpr-agents/openclaw`](https://github.com/XPRNetwork/xpr-agents) plugin, this skill gives a Pinata-hosted (or self-hosted) OpenClaw agent the knowledge to use its tools correctly: which memo means "deposit" vs "swap" vs "stranded funds", what the real swap fees are, when `liquidityadd` will silently fail. See [`agent-bootstrap.md`](./agent-bootstrap.md).

Every fact in this skill is verified against live mainnet ABIs, contract source, and Hyperion traces — not pattern-matched from training data.

## What is XPR Network?

XPR Network is a fast, gas-free blockchain with WebAuthn wallet support. Key features:

- **Zero gas fees** - Users don't pay transaction fees
- **WebAuthn wallets** - Login with Face ID, fingerprint, or security keys
- **4000+ TPS** - Fast block times (0.5s)
- **EOS-based** - Uses EOSIO technology with AssemblyScript smart contracts
- **Human-readable accounts** - 12 character account names instead of hex addresses

## Installation

### The easy way:

```bash
git clone https://github.com/XPRNetwork/xpr-network-dev-skill.git
cd xpr-network-dev-skill
./install.sh
```

> **Deploying a server-side agent?** This README covers installing the skill into Claude Code on your own machine. If you're standing up an autonomous XPR Network agent on Pinata or another OpenClaw runtime, see [agent-bootstrap.md](./agent-bootstrap.md) instead.

## Updating

**Claude Code install (`./install.sh`):** the symlink points at your local checkout, so `git pull` is all you need.

```bash
cd xpr-network-dev-skill
git pull
```

Your assistant will see the new content on its next conversation. No reinstall.

**Server-side agent (`agent-bootstrap.sh`):** re-run the bootstrap script. It's idempotent — `git pull` on the skill checkout, `npm update` on the xpr-agents packages, no re-provisioning of the keychain.

```bash
./scripts/agent-bootstrap.sh
```

> **Current release: v2.3.2 (July 2026).** Full release notes and version history in [`CHANGELOG.md`](./CHANGELOG.md).

### Method 1: Manual symlink (personal skill)

Personal skills are available across all your projects:

```bash
git clone https://github.com/XPRNetwork/xpr-network-dev-skill.git
mkdir -p ~/.claude/skills
ln -s /path/to/xpr-network-dev-skill/skill ~/.claude/skills/xpr-network-dev
```

### Method 2: Project-level skill

To make the skill available only in a specific project:

```bash
mkdir -p .claude/skills
ln -s /path/to/xpr-network-dev-skill/skill .claude/skills/xpr-network-dev
```

Commit `.claude/skills/xpr-network-dev` to version control so teammates get the skill automatically.

### Method 3: Copy to project CLAUDE.md

Copy relevant sections from `skill/SKILL.md` directly into your project's `CLAUDE.md` file. This is the simplest approach but the content always loads into context rather than on-demand.

## Usage with Other AI Tools

This skill is just structured markdown - it works with any AI coding assistant, not just Claude Code.

### Cursor

Modern Cursor uses `.cursor/rules/*.mdc` files; the legacy `.cursorrules` flat file still works but isn't where new projects should land.

**Modern** — drop a project rule pointing at the skill:

```bash
mkdir -p .cursor/rules
cat > .cursor/rules/xpr-network.mdc <<'EOF'
---
description: XPR Network development reference
globs: ["**/*"]
alwaysApply: false
---
When working on XPR Network code, consult the modules under `skill/`. Start
at skill/SKILL.md for the routing table; load individual reference docs on
demand (e.g. skill/defi-trading.md for swap/AMM, skill/metalx-dex.md for
the order book).
EOF
```

**In-prompt reference** (any Cursor version):

```
@skill/smart-contracts.md How do I create a singleton table?
```

**Indexed** — add the `skill/` folder to your workspace and Cursor will index it for retrieval-augmented answers without an explicit rule.

### GitHub Copilot

Drop a `.github/copilot-instructions.md` pointing Copilot at the skill, then reference specific modules in commit-message and PR-description prompts:

```bash
mkdir -p .github && cat > .github/copilot-instructions.md <<'EOF'
This project targets XPR Network. Reference docs are in `skill/`. Start at
skill/SKILL.md (routing table); load `skill/<topic>.md` on demand.
EOF
```

### Other AI tools

The skill is plain markdown — paste relevant module content into any tool's context window, or point its file-indexing feature at the `skill/` folder. Knowledge is tool-agnostic.

### OpenClaw / Pinata Agents

For autonomous server-side agents (Pinata, self-hosted OpenClaw, future hosts), this skill is the **knowledge layer** that pairs with [`@xpr-agents/openclaw`](https://github.com/XPRNetwork/xpr-agents) as the **capabilities layer**. The bootstrap procedure — install the openclaw plugin, provision the proton CLI keychain, clone this skill into the agent workspace, smoke test — is documented in [`agent-bootstrap.md`](./agent-bootstrap.md). One-command provisioning script in [`scripts/agent-bootstrap.sh`](./scripts/agent-bootstrap.sh).

### Direct Reference

For any AI tool, you can paste sections directly:

```
"I'm building on XPR Network. Here's the relevant documentation: [paste from skill/smart-contracts.md]"
```

## Skill Modules

### Core Development

| Module                                                   | Description                                        |
| -------------------------------------------------------- | -------------------------------------------------- |
| [SKILL.md](skill/SKILL.md)                               | Main entry point with overview and quick reference |
| [smart-contracts.md](skill/smart-contracts.md)           | Contract development with `proton-tsc`             |
| [cli-reference.md](skill/cli-reference.md)               | Complete @proton/cli command reference             |
| [web-sdk.md](skill/web-sdk.md)                           | Frontend integration with @proton/web-sdk          |
| [backend-patterns.md](skill/backend-patterns.md)         | Server-side signing, automated operations, bots    |
| [rpc-queries.md](skill/rpc-queries.md)                   | Table reading, Hyperion API, Light API             |
| [testing-debugging.md](skill/testing-debugging.md)       | Unit testing, testnet workflows, debugging         |
| [accounts-permissions.md](skill/accounts-permissions.md) | Account creation, permissions, multisig            |
| [staking-governance.md](skill/staking-governance.md)     | XPR staking, Block Producers, DPoS, resource model |

### Tokens & Identity

| Module                                             | Description                                   |
| -------------------------------------------------- | --------------------------------------------- |
| [token-creation.md](skill/token-creation.md)       | Creating fungible tokens, issuance, vesting   |
| [webauth-identity.md](skill/webauth-identity.md)   | WebAuth wallets, KYC, profiles, trust ratings |
| [nfts-atomicassets.md](skill/nfts-atomicassets.md) | NFT development with AtomicAssets standard    |

### DeFi & Trading

| Module                                               | Description                                     |
| ---------------------------------------------------- | ----------------------------------------------- |
| [metalx-dex.md](skill/metalx-dex.md)                 | Complete MetalX DEX API reference                        |
| [alcor-dex.md](skill/alcor-dex.md)                   | Alcor order book + v3 AMM + OTC reference                |
| [simpledex.md](skill/simpledex.md)                   | SimpleDEX token launch + bonding curves + AMM graduation |
| [defi-trading.md](skill/defi-trading.md)             | Trading bots, perps architecture, DeFi patterns          |
| [loan-protocol.md](skill/loan-protocol.md)           | LOAN lending protocol integration                        |
| [oracles-randomness.md](skill/oracles-randomness.md) | Price oracles, verifiable random numbers                 |

### Integration Patterns

| Module                                           | Description                                   |
| ------------------------------------------------ | --------------------------------------------- |
| [real-time-events.md](skill/real-time-events.md) | Hyperion streaming, WebSockets, notifications |
| [payment-patterns.md](skill/payment-patterns.md) | Payment links, invoicing, POS, subscriptions  |

### Infrastructure

| Module                                       | Description                                        |
| -------------------------------------------- | -------------------------------------------------- |
| [node-operation.md](skill/node-operation.md) | API nodes, Block Producers, validators, Leap setup |

### Safety & Reference

| Module                                             | Description                                           |
| -------------------------------------------------- | ----------------------------------------------------- |
| [safety-guidelines.md](skill/safety-guidelines.md) | CRITICAL: Table modification rules, deployment safety |
| [troubleshooting.md](skill/troubleshooting.md)     | Common errors, solutions, diagnostics                 |
| [examples.md](skill/examples.md)                   | Community example contracts (PriceBattle, ProtonWall, ProtonRating) — educational |
| [resources.md](skill/resources.md)                 | Endpoints, links, community resources                 |

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

- AssemblyScript/TypeScript contracts with `proton-tsc`
- Table definitions (`@table`, `@primary`, singletons)
- Actions, authentication, inline actions
- Build and deploy workflow
- Unit testing with `@proton/vert`

### CLI Operations

- Network management (`chain:set`, `chain:get`)
- Key management (`key:add`, `key:list`)
- Contract deployment (`contract:set`)
- Table queries and action execution
- Account creation and permissions

### Frontend Integration

- `@proton/web-sdk` for wallet connection
- Session management and transaction signing
- RPC queries with `@proton/js`
- WebAuth and KYC verification

### Backend Development

- **proton CLI keychain pattern** — keys never enter agent process memory; signing shells out to `proton transaction:push`
- `@xpr-agents/openclaw` `createCliSession` as the keychain-backed `ProtonSession`
- Automated bots and scheduled tasks
- `@xpr-agents/sdk` registries (Agent, Escrow, Validation, Feedback) for read + write
- Hyperion and Light API integration
- Legacy `JsSignatureProvider` pattern (documented as the discouraged fallback, not the default)

### Token & Identity

- Fungible token creation and management
- Token vesting and airdrops
- WebAuth wallet integration
- User profiles and KYC status
- Trust rating system

### NFT Development

- AtomicAssets standard (collections, schemas, templates, assets)
- Minting, transfers, and marketplace integration
- IPFS integration for media storage

### DeFi and Trading

- **MetalX** order-book DEX (the `dex` contract) — orders, deposits, lifecycle
- **MetalX Swap** AMM (the `proton.swaps` contract) — verified 0.30% total swap fee (0.20% LP + 0.10% protocol), three-step `depositprep` → empty-memo transfer → `liquidityadd` flow
- **Alcor DEX** — order book + v3 AMM + OTC, base/quote inversion gotcha
- **SimpleDEX** — token launch with bonding curves + AMM graduation
- Trading bot patterns (grid bot, market maker)
- Perpetual futures architecture and building blocks
- **LOAN protocol** — supply, borrow, liquidations

### Server-Side Agents

- Deploying an autonomous XPR Network agent on Pinata (hosted OpenClaw) or self-hosted runtimes — see [`agent-bootstrap.md`](./agent-bootstrap.md)
- Capabilities layer: 72 MCP tools across identity, reputation, validation, escrow, A2A via `@xpr-agents/openclaw`
- Knowledge layer: this skill, loaded into the agent workspace as on-demand reference docs
- Idempotent provisioning script ([`scripts/agent-bootstrap.sh`](./scripts/agent-bootstrap.sh)) with PATH fixup, key-format validation, read-only smoke test
- Non-interactive `proton key:add` for managed consoles (no TTY)

### Safety & Troubleshooting

- **CRITICAL**: Never modify existing table structures with data
- **CRITICAL**: Token transfers to the `dex` contract MUST use empty memo (otherwise funds are stranded with no recovery)
- **CRITICAL**: `liquidityadd` on `proton.swaps` requires `depositprep` + empty-memo transfers first — calling it cold fails with `insufficient balance`
- Pre-deployment checklist
- Recovery procedures
- Multi-contract deployment safety
- Common errors and solutions

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Test your changes with Claude Code
4. Submit a pull request

### Areas for Contribution

- **Verified corrections** — when you hit a doc that doesn't match on-chain reality, open a PR with the curl/source citation; this skill prioritizes verified-against-mainnet over pattern-matched-against-training-data
- **New patterns from production** — agent operator patterns, novel contract integrations, real failure modes you've debugged
- **Coverage gaps** — token contract + precision registry, market-id lists for the DEXes, additional safety callouts
- **Additional code examples** — kept ABI-current; include the curl/RPC call that verified the example
- Translations

Run `./scripts/validate-skill.sh` before opening a PR. It checks:

1. `SKILL.md` YAML frontmatter present
2. npm packages still resolve (`@proton/cli`, `@proton/js`, `@proton/web-sdk`, `proton-tsc`, `@proton/vert`)
3. Referenced mainnet contract accounts still exist (`eosio.token`, `dex`, `atomicassets`, etc.)
4. Key URLs return HTTP 200 (docs, explorer, RPC endpoints, MetalX API)
5. No leaked private keys (PVT_K1_ or legacy WIF format)
6. No personal account references
7. No active links to retired explorers (`protonscan.io`, `proton.bloks.io`)
8. MetalX endpoints use the correct `/dex/v1/` prefix
9. Inventory of skill files with line counts (for manual review)

If you're touching a reference module, also include the curl / RPC call you used to verify the change in the PR description — the skill prioritizes verified-against-mainnet over pattern-matched-against-training-data.

## Resources

**XPR Network**

- **Official Docs**: https://docs.xprnetwork.org
- **GitHub**: https://github.com/XPRNetwork
- **Block Explorer**: https://explorer.xprnetwork.org
- **Telegram**: https://t.me/XPRNetwork
- **Help Desk**: https://help.xprnetwork.org — official support
- **Governance DAO**: https://gov.xprnetwork.org — token-listing votes happen at [community #7](https://gov.xprnetwork.org/communities/7)

**Agent infrastructure**

- **xpr-agents repo**: https://github.com/XPRNetwork/xpr-agents — `@xpr-agents/openclaw` plugin, `@xpr-agents/sdk`, agent-runner starter kit
- **Agent registry (live)**: https://agents.protonnz.com
- **Pinata Agents** (hosted OpenClaw): https://docs.pinata.cloud/agents/overview.md

## License

MIT License - see [LICENSE](LICENSE) for details.

---

Built for the XPR Network community by developers, for developers.
