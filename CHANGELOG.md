# Changelog

All notable changes to this skill are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project loosely follows [Semantic Versioning](https://semver.org/) — MINOR bumps for new reference content or substantial corrections, PATCH bumps for typo / link fixes.

---

## [2.3.0] — 2026-05-16

This release closes the post-audit triage and ships the canonical reference tables, agent-ops hygiene, and a Hyperion etiquette section.

### Added

- **Agent bootstrap** — `agent-bootstrap.md` + `scripts/agent-bootstrap.sh` for deploying autonomous XPR Network agents on Pinata or any OpenClaw runtime. Pairs with `@xpr-agents/openclaw` for 55 MCP tools, uses the proton CLI keychain pattern, includes a non-interactive provisioning path for managed consoles. ([PR #20](https://github.com/XPRNetwork/xpr-network-dev-skill/pull/20))
- **Endpoint etiquette** — top-level *Endpoint Etiquette (RPC + Hyperion)* section in `rpc-queries.md` with an anti-pattern table, response-code reference (429 vs 403 vs 503), and a drop-in polite-fetch client that rotates endpoints, respects `Retry-After`, and aborts on 403. ([PR #24](https://github.com/XPRNetwork/xpr-network-dev-skill/pull/24), [PR #25](https://github.com/XPRNetwork/xpr-network-dev-skill/pull/25))
- **Canonical token registry** — verified token-contract / precision table in `resources.md` covering all native, wrapped, and project tokens on XPR Network, plus discovery RPC snippet. ([PR #26](https://github.com/XPRNetwork/xpr-network-dev-skill/pull/26))
- **Known DEX markets** — enumerated 18-market list for MetalX DEX (`dex` contract) with the XBTC_XMD 0% trading-fee callout. Alcor markets kept dynamic (~1,600 registered, filter at runtime). ([PR #26](https://github.com/XPRNetwork/xpr-network-dev-skill/pull/26))
- **Alcor hardening** — `cancelbuy` vs `cancelsell` decoder rule + malformed-memo failure-mode table. ([PR #26](https://github.com/XPRNetwork/xpr-network-dev-skill/pull/26))
- **AMM slippage math** — `slippageProtectedMin()` helper and slippage subsection in `defi-trading.md` for self-routed `proton.swaps` swaps. ([PR #27](https://github.com/XPRNetwork/xpr-network-dev-skill/pull/27))
- **Skill-wide AI-agent policy** — hoisted the *Policy for AI agents* block to the top of `SKILL.md` so every reference doc inherits it. ([PR #25](https://github.com/XPRNetwork/xpr-network-dev-skill/pull/25))

### Changed

- **Backend signing pattern** — replaced legacy `JsSignatureProvider` recommendation with the proton CLI keychain (`@xpr-agents/openclaw` `createCliSession`). Keys never enter agent process memory. Added a *When to use which pattern* decision table routing serverless / CI / browser readers to the right pattern. ([PR #15](https://github.com/XPRNetwork/xpr-network-dev-skill/pull/15), [PR #24](https://github.com/XPRNetwork/xpr-network-dev-skill/pull/24))
- **proton.swaps fee math** — corrected from `0.2%/0.05%` to canonical `0.3%` (0.2% LP + 0.1% XPR burns/grants), aligned with `docs.metalx.com`. `calculateSwapOutput` now reads both fee values from chain at runtime. ([PR #19](https://github.com/XPRNetwork/xpr-network-dev-skill/pull/19), [PR #22](https://github.com/XPRNetwork/xpr-network-dev-skill/pull/22))
- **MetalX swap tokens list** — filtered to actively-traded set; dormant tokens dropped, point to canonical FAQ for full historical list. ([PR #25](https://github.com/XPRNetwork/xpr-network-dev-skill/pull/25))
- **`@proton/cli` install line** — replaced personal-fork ref with official `@proton/cli` everywhere. ([PR #24](https://github.com/XPRNetwork/xpr-network-dev-skill/pull/24))
- **Community channels** — XPR Network community is on Telegram (`t.me/XPRNetwork`) and the official Help Desk (`help.xprnetwork.org`); Discord references stripped. ([PR #23](https://github.com/XPRNetwork/xpr-network-dev-skill/pull/23))
- **Alcor docs framing** — pool IDs and market IDs documented as session-derived and rotation-prone; readers warned not to cache across sessions. ([PR #25](https://github.com/XPRNetwork/xpr-network-dev-skill/pull/25), [PR #26](https://github.com/XPRNetwork/xpr-network-dev-skill/pull/26))
- **README** — comprehensive refresh: dual-audience framing (Claude Code skill + agent knowledge layer), OpenClaw section, updated Cursor/Copilot integration, validate-skill.sh checklist. ([PR #21](https://github.com/XPRNetwork/xpr-network-dev-skill/pull/21))

### Fixed

- **C1 / metalx-dex.md JS Submit Order** — destructured `{serializedTransaction, signatures}` from a method that returns `{transaction_id, processed}`; first run hit `TypeError`. Rewritten to use direct on-chain submission. ([PR #18](https://github.com/XPRNetwork/xpr-network-dev-skill/pull/18))
- **C3 / liquidityadd flow** — added the missing `depositprep` → empty-memo transfers → `liquidityadd` prerequisite sequence; calling cold was failing with `insufficient balance`. ([PR #19](https://github.com/XPRNetwork/xpr-network-dev-skill/pull/19))
- **C4 / token-creation `addliq:` memo path** — fictional, never existed in the contract. Replaced with the correct `liquidityadd` flow. ([PR #19](https://github.com/XPRNetwork/xpr-network-dev-skill/pull/19))
- **C5 / metalx-dex.md endpoints table** — Testnet row was orphaned by a wedged-in warning block. ([PR #19](https://github.com/XPRNetwork/xpr-network-dev-skill/pull/19))
- **C6 / backend-patterns.md** — `sendTransaction` / `safeTransact` referenced an undeclared `api` from a `<details>` "Legacy" block; would `ReferenceError` on first use. ([PR #18](https://github.com/XPRNetwork/xpr-network-dev-skill/pull/18))
- **`protocolfee1` doesn't exist on chain** — was cited as the on-chain destination of the swap protocol fee. Real destination verified as `fee.swaps`. ([PR #22](https://github.com/XPRNetwork/xpr-network-dev-skill/pull/22))
- **`@proton/ts-contracts` is not a real npm package** — cited in 4 places. Corrected to `proton-tsc` (the actual package). ([PR #22](https://github.com/XPRNetwork/xpr-network-dev-skill/pull/22))
- **MetalX DEX API param bugs** — `/orders/depth` and `/trades/recent` snippets used `?market_id=` (returns HTTP 400); the API requires `?symbol=` (and `&step=` for depth). `/trades/daily` returns *all* markets, not one — return shape corrected. ([PR #22](https://github.com/XPRNetwork/xpr-network-dev-skill/pull/22))
- **LOAN max supply** — claimed `100,000,000`; actual is unbounded with ~113B circulating. Off by ~1,133×. ([PR #22](https://github.com/XPRNetwork/xpr-network-dev-skill/pull/22))
- **LOAN underlying symbols** — `XRP`→`XXRP`, `XLM`→`XXLM`, etc. to match the on-chain double-X wrapped names in `lending.loan.markets`. ([PR #25](https://github.com/XPRNetwork/xpr-network-dev-skill/pull/25))
- **Dicebear** — third-party CDN avatar fallback replaced with a local initials-in-colored-circle pattern. ([PR #22](https://github.com/XPRNetwork/xpr-network-dev-skill/pull/22))
- **Snapshot mirror** — Cryptolions URL was dark; rewrote section to make the operator-mirror dynamic explicit, point to the Telegram validators group for currently-live mirrors. ([PR #22](https://github.com/XPRNetwork/xpr-network-dev-skill/pull/22))
- **"Fast finality" misuse** — corrected to *Fast inclusion (~2s first block; LIB ~3 minutes)*. ([PR #25](https://github.com/XPRNetwork/xpr-network-dev-skill/pull/25))
- **METAL / XMT classification** — flattened the `xtokens` registry into one wrapped-tokens table; clarified that METAL wraps Metal Blockchain (a separate Layer 0, not MetalX the DEX), and XMT is the XPR Network representation of MTL (Metal DAO governance, not MetalX governance). ([PR #26](https://github.com/XPRNetwork/xpr-network-dev-skill/pull/26))

### Triage state at release

23 of 24 audit items closed (C1–C6, H1–H6, M1–M7, L1–L5; L4 couldn't be reproduced and was dropped).

---

## [2.2.0] — 2026-05-12

Multi-PR accuracy + safety pass on top of v2.0.0. See [PR #21](https://github.com/XPRNetwork/xpr-network-dev-skill/pull/21) for the release pin. Highlights:

- Backend signing migrated to the proton CLI keychain pattern ([PR #15](https://github.com/XPRNetwork/xpr-network-dev-skill/pull/15))
- Alcor DEX full reference added ([PR #14](https://github.com/XPRNetwork/xpr-network-dev-skill/pull/14))
- MetalX accuracy passes + Python `proton action` subprocess pattern ([PR #16](https://github.com/XPRNetwork/xpr-network-dev-skill/pull/16), [PR #17](https://github.com/XPRNetwork/xpr-network-dev-skill/pull/17), [PR #18](https://github.com/XPRNetwork/xpr-network-dev-skill/pull/18))
- `proton.swaps` accuracy ([PR #19](https://github.com/XPRNetwork/xpr-network-dev-skill/pull/19))
- Server-side agent deployment ([PR #20](https://github.com/XPRNetwork/xpr-network-dev-skill/pull/20))
- SimpleDEX coverage added

---

## [2.0.0] — 2026-03-19

Major accuracy audit — 40+ verified fixes across 13 files. Contract actions, params, tables verified against live mainnet ABIs. Critical fixes for DEX deposits, LOAN protocol, oracle indices. See [PR #10](https://github.com/XPRNetwork/xpr-network-dev-skill/pull/10).
