# Changelog

All notable changes to this skill are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project loosely follows [Semantic Versioning](https://semver.org/) — MINOR bumps for new reference content or substantial corrections, PATCH bumps for typo / link fixes.

---

## [2.6.0] — 2026-09-03

Full-skill accuracy pass. Every module was re-verified against live mainnet ABIs and tables, the current npm packages (`@proton/cli` 0.1.99, `@proton/web-sdk` 5.1.0-rc-4 / 4.4.2, `@proton/js` 30.1.0, `proton-tsc` 0.3.58, `@proton/vert` 0.3.24, `@xpr-agents/openclaw` 0.5.4, `@xpr-agents/sdk` 0.2.7, `@eosrio/hyperion-stream-client` 4.0.0-rc.3), upstream sources (Hyperion 4.1.0, Leap 5.0.3, proton.contracts, alcor-ui, alcor-v2-sdk), docs.metalx.com and xpragents.com/llms.txt, and ~200 URLs. About 75 confirmed inaccuracies fixed across 24 files; nothing unverified was changed. MINOR bump: substantial corrections.

### Fixed — proton-tsc / contracts (`smart-contracts.md`, `testing-debugging.md`, `examples.md`, `safety-guidelines.md`, `troubleshooting.md`, `token-creation.md`, `oracles-randomness.md`)

- `Singleton.get()` never returns `null` (returns a default instance); existence checks now use `getOrNull()`.
- `TableStore` has no `getAll()` / `getBySecondaryIndex()`; secondary lookups use `getBySecondaryU64(value, index)` (single row or null).
- `InlineAction` takes only the action name; sending is `.act(contract, permission).send(data)`. Fixed in three places.
- No `sendInline`, `formatAsset`, `getCaller`, `transfer`, `currentBlock`, `printI`/`printU`, `getRamUsage`, or `Contract.requireRecipient` — replaced with `sendTransferToken` (`proton-tsc/token`), `Asset`, `hasAuth`-based admin lookup, `currentBlockNum`, `printi`/`printui`, and the free `requireRecipient`.
- Oracle table in contracts: use `Data`/`DataVariant` from `proton-tsc/oracles` (`aggregate.f64Value`); a plain `f64` field mis-deserializes the variant. Off-chain `data` rows have no `timestamp` — freshness comes from `points[].time`.
- Build outputs are named after the source file (`mycontract.contract.wasm` / `.abi`); the `.contract.ts` name is a convention, not a compiler requirement.
- `@proton/vert`: `blockchain.createContract(name, folder)` (no `loadContract`); `addTime` takes a `TimePointSec`; bundled `eosio.token` lives in `proton-tsc/external/eosio.token`.
- `proton action` has no `--verbose`; `stakexpr` params are `from, receiver, stake_xpr_quantity`.
- Real nodeos error texts for expired / CPU / RAM failures, with exception names; `unable to find key` is C++ CDT text, not proton-tsc.
- `pricebattle`: `resolve(challenge_id, resolver)` takes no price; `Challenge` has `expires_at`; the deployed contract exposes no secondary index (frontend query now scans and filters); `protonrating` admin pattern rewritten without a caller API.
- Hyperion `get_actions` is GET-only (safety checklist curl fixed). `localStorage` cleanup clears every `proton-storage-*` key.
- Appending a trailing `BinaryExtension<T>` field is the one supported additive table change; documented as the exception to the golden rule.

### Fixed — CLI / SDK / backend (`cli-reference.md`, `web-sdk.md`, `backend-patterns.md`, `accounts-permissions.md`)

- CLI store is one `proton-cli.json` under the OS config dir (`~/Library/Preferences/@proton/cli-nodejs/` on macOS, `~/.config/@proton/cli-nodejs/` on Linux); `~/.proton-cli` does not exist.
- `proton account:create` is the free Metal-identity flow with no flags; paid creation is `account:create-funded -c -k -r`.
- `proton transaction:push` takes **unsigned** `{actions}` JSON and signs from the keychain; bare `proton transaction '<json>'` does not parse its argument (still broken in 0.1.99).
- `msig:propose` takes a JSON **array** of actions; msig example expiration is now computed (the old literal date had passed).
- `key:list` hides private keys by default but `--reveal-private` prints them.
- The `XPR_PRIVATE_KEY` refusal lives in the `create-xpr-agent` starter's `start.sh`, not in `@xpr-agents/openclaw` (fixed in three files).
- `session.link.transact({ actions })` takes one argument; the two-arg form belongs to `createCliApi().api`.
- `JsSignatureProvider` is exported by `@proton/js` (no `eosjs` import).
- `@proton/web-sdk`: the documented options are the **4.x** shape; `latest` is 5.1.0-rc-4 with `uiOptions.appInfo` / `uiOptions.theme` and a two-field `selectorOptions`. Installs now pin `@4`, `@proton/link` must match web-sdk's major (not `3.2.3-x`), `chainId` is fetched from `get_info` when omitted, `backButton` does not exist (`requestStatus` does), `removeSession` takes `(identifier, auth, chainId)`, and "Unknown Requestor" means `requestAccount` is unset.

### Fixed — RPC / Hyperion / Light API / streaming (`rpc-queries.md`, `real-time-events.md`, `resources.md`, `node-operation.md`, `hyperion-setup.md`, `hyperion-operations-caveats.md`)

- All-numeric account names: appending `"."` to `lower_bound`/`upper_bound` is rejected (`chain_type_exception`) on current nodeos — use the u64 encoding or `key_type: "name"`. `get_table_by_scope` bounds have the same integer-first bug. Helper unified as `safeName()`.
- `/v2/history/get_transfers` does not exist in Hyperion at all (not merely undeployed).
- `get_transaction` response shape (`trx_id, lib, cached_lib, executed, actions[]…`), `get_account` state shape (nested `account`), and `get_tokens` `amount: number` corrected.
- Light API: `tokenbalance` and `usercount` return text/plain numbers; `key` lookup is `/api/key/{key}` keyed by network; `topholders` returns `[account, amount]` pairs with `limit` 10–1000; `decimals` is a string.
- Streaming: stream objects emit `message`, not `data` (the doc's handlers never fired); unscoped requests are acked `status: FAIL, reason: invalid request`; Hyperion 3.x servers deliver the handshake as a `message`, 4.x as a `handshake` event; bloxprod advertises `traces:false`. `block-stream` is not on npm (clone the repo).
- `control_port` is read from `connections.json`, not the chain config. Snapshot mirror cited as `https`. Stream client 4.0.0-rc.3 is published under the `latest` tag.
- Dropped two closed neftyblocks P2P peers; nodeos version guidance now says Leap 5.0.3 (final Leap) or Spring 1.2.x, matching mainnet's v5.0.0–v5.0.3. Anchor URL is `anchorwallet.io`.

### Fixed — DeFi / DEX (`metalx-dex.md`, `defi-trading.md`, `alcor-dex.md`, `simpledex.md`, `loan-protocol.md`, `staking-governance.md`)

- MetalX DEX `order_type` is 1 limit / 2 stop-loss / 3 take-profit (per docs.metalx.com); `show_error_msg` is `bool?`; leaderboard takes repeated `market_ids=` (bracketed form is a 400).
- Alcor: mainnet market-creation fee is 2,000 XPR (×2 if base ≠ XPR; 50,000 XPR is testnet), paid by transfer with a `new_market|…` memo; the API's `base_currency`/`target_currency` are swapped relative to the on-chain table; `account` table is an order index, not balances; no `/account/{name}/orders` endpoint; route endpoint is `/swapRouter/getRoute`; SDK has no `computePoolAddress`.
- SimpleDEX: `dex.protonnz.com` already 308-redirects; 6-decimal quote tokens (XMD, XUSDC) scale ×1,000,000; `sell` field is `minXpr`; moderation authority is `simplesetup@active` or the 2-of-4 owner msig.
- LOAN: liquidation memo is `liquidate,<borrower>,<LTOKEN>`; one global 10% `liquidation_incentive` (no per-collateral table); `borrows` rows have no `health_factor` (compute it); the whitelist gates contract callers by code hash, not users; supply refreshed (~114.2B).
- Staking: staker rewards are claimed with `eosio::voterclaim` (`voterclaimst` to restake) — `claimrewards` is the BP pay claim; vote for exactly 4 BPs (fewer is accepted but disqualifies rewards); RAM ≈0.0004 XPR/byte with a live-lookup pointer.

### Fixed — identity / payments / agents (`webauth-identity.md`, `payment-patterns.md`, `xpr-agents.md`, `agent-bootstrap.md`, `README.md`)

- `usersinfo.aacts` / `ac` are arrays of `{field_0, field_1}` tuples; KYC claim table gains `metal.kyc:nationalidnumber` and legacy `trulioo:*` sets (7–8 claims, order varies); contract snippet imports fixed.
- XPR/USD is oracle feed **3** (payment example used a non-existent feed 1).
- xpragents: an unset name reads as `""` (not 13 dots); the indexer's CORS is allow-listed to xpragents.com/localhost; funding an open job before `selectbid` is now rejected by the contract (wedge behaviour was pre-Sept-2026).
- `@xpr-agents/openclaw` ships **75** MCP tools (four places); `proton key:lock` takes no argument; the openclaw package exports CLI helpers, not registry classes; bootstrap script re-runs `npm install`, not `npm update`; Pinata docs link points at the HTML page; version pins refreshed to `@proton/cli` 0.1.99 and `@xpr-agents/sdk` 0.2.7.

### Verified unchanged (for the record)

All 18 MetalX markets, the 19-live / 5-dormant oracle split, every LOAN collateral factor and feed index, SimpleDEX fees/thresholds, the four xpragents contract ABIs and every arity in `xpr-agents.md`, all resources.md token precisions and issuers, all Hyperion ops config keys and CLI subcommands against upstream 4.1.0, all 24 Leap `config.ini` keys, and the empty-memo DEX deposit behaviour (no refund action exists in the `dex` ABI).

---

## [2.5.1] — 2026-09-03

Prompt audit of the skill's model-facing text (SKILL.md, the agent bootstrap chat prompt, module rule lines) against current Claude models. No rule was dropped; every change removes duplication, shouting register, or archaeology while keeping each constraint and its reason.

### Changed

- **`SKILL.md` frontmatter description** now names the legacy brand and package namespace (Proton, proton-tsc, `@proton/*`) and the product areas the modules cover, so the skill triggers on questions that never say "XPR Network".
- **`SKILL.md` AI-generated-code disclaimer** collapsed from a bullet wall to one reasoned paragraph pointing at the full checklist in `safety-guidelines.md`.
- **`SKILL.md`** mid-file "CRITICAL: Before Modifying Contracts" block removed — the same rule already routes in the module table and is recapped in Safety Reminders.
- **`agent-bootstrap.md` bootstrap chat prompt**: the four key-handling rules (non-interactive `key:add` only, base-58 error means stop and re-send, never echo or store the key, confirm via `key:list`) restated at normal volume with their reasons, replacing the boxed HARD RULES block.
- **`agent-bootstrap.md` troubleshooting**: PR numbers and "original publication" history removed from three symptom→fix entries.
- **`cli-reference.md`** key-management rule now states its reason and points at the key-isolation section instead of an exclamation.

---

## [2.5.0] — 2026-09-02

### Added

- **`hyperion-setup.md`** — standing up a Hyperion v4 full-history node on XPR mainnet, written from the protonnz full-history build (4.0.8, indexed to head). Version matrix, hardware sizing (~2TB full history), Hetzner RAID1 split, OS limits, Elasticsearch 9 / RabbitMQ 4 / MongoDB 8 install traps, SHIP `config.ini`, the two honest full-history paths (blocks.log replay vs p2p from genesis), `hyp-config` quirks (no-TTY crash, missing `experimental` key, chains-new needs a serving node), the replay-before-index ordering rule, nginx with a `/stream/` socket.io proxy, bp.json feature flags.
- **`hyperion-operations-caveats.md`** — field notes from several multi-day incidents, in discovery order: composable `_index_template` silently replacing Hyperion's legacy templates (dynamic-mapping explosion, 1,000-field cap, writes at ~2 docs/s); real storage footprint and the DEX-peak projection trap; orphaned Redis `temp-*.rdb` files (425GB reclaimed) and unbounded Redis RSS; disk-full → ES read-only → stall at a 10M partition boundary; never purge queues with docs in flight; backfill in bounded 10M ranges; the "consumer coma" wedge and the stop/wait/start revive; jam-resistant scaling; Hetzner storage constraint and the governance-funding precedent; the 10k `max_result_window` vs cursor pagination; `max_asc_window_days` masquerading as missing history; block-complete ≠ action-complete and the `scan-actions`/`fill-missing`/cross-check standard.
- README Infrastructure table and Backend Development topic list; SKILL.md routing rows for both modules.

Every CLI subcommand and config key in both modules was checked against upstream `eosrio/hyperion-history-api` source (4.1.0). Operator sources are paraphrased and unattributed by design.

MINOR bump per this changelog's convention (new reference content).

---

## [2.4.0] — 2026-09-02

### Added

- **`xpr-agents.md`** — new reference module for the xpragents.com trustless agent registry / job board ([PR #34](https://github.com/XPRNetwork/xpr-network-dev-skill/pull/34)). Covers the four mainnet contracts (`agentcore`, `agentfeed`, `agentvalid`, `agentescrow`), the indexer API, the exact job lifecycle with `proton action` calls — including the rule that a client must `selectbid` **before** funding an open job — multi-file delivery via a JSON manifest in `evidence_uri`, and one-liners for reviews, validation and arbitration. Canonical always-current source: https://xpragents.com/llms.txt. Review before release verified all four contracts exist, all 14 cited actions match their live ABIs field-for-field, every URL resolves, and every number/rule agrees with `llms.txt`.
- README: module-table row and a Server-Side Agents pointer for the new module.

MINOR bump per this changelog's convention (new reference content).

---

## [2.3.3] — 2026-09-02

Community audit response — every finding in [issue #32](https://github.com/XPRNetwork/xpr-network-dev-skill/issues/32) independently re-verified against mainnet before fixing. Thanks to the reporter: all six were real.

### Fixed

- **DEX wrong-memo outcome — the two docs contradicted each other** (`metalx-dex.md` said "permanently stuck", `defi-trading.md` said "treated as a regular transfer"). Settled empirically from 17 real wrong-memo deposits by 8 accounts (2025-10 → 2026-04): the transfer **succeeds** (contract doesn't reject), is **not credited** to `balances`, and there is **no contract path to recover it** (`withdraw`/`withdrawall` read only `balances`; ABI has no admin refund). One large case was manually refunded by the operators after ~10 days (memo `refund`); several others never were. Both docs and the `SKILL.md` safety rule now say the same thing: treat as lost, contact MetalX support immediately, recovery is discretionary. `metalx-dex.md`, `defi-trading.md`, `SKILL.md`
- **"XPR accounts cannot contain dots" was false** — `eosio.token`, `xmd.token`, `xmd.treasury`, `lending.loan` etc. all exist (and appear in the skill's own tables). Rule corrected: the Antelope charset is `a-z 1-5 .`; dotted names are system/premium accounts, *user-registered* names are dot-free. Added a validator gotcha so agents stop flagging canonical contracts as malformed. `accounts-permissions.md`, `resources.md`, `SKILL.md`, `README.md`
- **`getKYCLevel()` returned `NaN` on mainnet** — `kyc_level` is a comma-separated *claim list* (`metal.kyc:address,metal.kyc:selfie,…`), not a number, so `parseInt` → `NaN` and every `>= n` gate silently failed. Replaced with `getKYCClaims()` / `hasKYCClaim()` / an explicitly-derived `getKYCTier()`; the fake "levels 0–3" table replaced with the real claim list; example response corrected; documented that `verified` is an opt-in display flag independent of KYC (fully KYC'd accounts routinely have `verified: false`). `webauth-identity.md`
- **`/v2/history/get_transfers` is not deployed on XPR Hyperion endpoints (404)** — was documented with a worked example, and the 404 read as "no transfers found". Replaced both implementations with `get_actions?filter=eosio.token:transfer` plus the `@transfer.to/from/symbol` narrowing params (live-verified). `rpc-queries.md`
- **Streaming section documented a raw `wss://…/stream` WebSocket that cannot connect** — Hyperion streaming is **socket.io mounted at `path: '/stream'`** on the HTTPS origin. Rewrote the section around `@eosrio/hyperion-stream-client` (and a raw `socket.io-client` recipe), with the negative controls that fail and why. **Honest status included:** connection + request handshake verified on eosusa, but no live or replay data was delivered in 60–90 s tests, and saltant (404) / protonuk (403) don't expose the mount — so public streaming is documented as best-effort with polling as the default. `real-time-events.md`, `rpc-queries.md`
- **Oracle feed tables disagreed across four modules** (5 / 5 / 13 / 15 rows). `oracles-randomness.md` is now the canonical table (19 live feeds, verified via `oracles::feed` actions), the other three are labeled excerpts that link to it. Added liveness notes: indices 5, 10, 11, 12, 20 are dormant (1+ years without updates) — **index 12 (XMD/USD) is a trap**: live token, dead feed; use 9 (USDT/USD) as the dollar reference. `oracles-randomness.md`, `loan-protocol.md`, `rpc-queries.md`, `resources.md`

---

## [2.3.2] — 2026-07-06

Monthly drift audit. Full re-verification against live mainnet came back clean — all 28 cited accounts, all 18 MetalX DEX markets, all fee values, all 6 Hyperion endpoints, and all canonical MetalX docs claims held. Fixes below are the only drift found.

### Fixed

- **`@xpr-agents/openclaw` tool/skill counts** — docs said "55 MCP tools + 12 built-in skills"; the package registers **72 tools** and bundles **13 skills** (verified by counting `registerTool` calls in `dist/tools/` and the `openclaw.plugin.json` skills manifest at v0.5.2 — the count was inherited from a stale upstream README and was wrong even at original verification). `agent-bootstrap.md`, `README.md`
- **LOAN circulating supply** — refreshed ~113.3B (May 2026) → ~113.7B (July 2026).
- **Agent registry URL** — `agents.protonnz.com` → `xpragents.com` (old domain now 301-redirects there; cite the terminal destination). `README.md`

### Verified, deliberately NOT changed

- **Identity-verification URL stays `identity.metallicus.com`** — the MetalX FAQ links `identity.metalx.com`, but that URL 301-redirects to `identity.metallicus.com`; the skill already cited the terminal destination. Recorded here so future audits don't "align" it to the redirect.

### Added

- **`openclaw plugins install @xpr-agents/openclaw`** documented as the primary install path in `agent-bootstrap.md` Step 1 (skills ship pre-built in the tarball since v0.4.0); npm-direct remains supported.
- **`npx xpr-agents-setup-security`** — new optional-hardening subsection in `agent-bootstrap.md` Step 2: the v0.5.x script that delegates the agent account's `owner` permission to a human-controlled account, so a compromised `active` key can't take over the account.

### Re-verified unchanged (openclaw 0.3.0 → 0.5.2)

`createCliSession` signature and `{transaction_id, processed}` return shape • no `broadcast:false` path • signing shells out to `proton transaction:push` • `XPR_PRIVATE_KEY` refuse-to-start guard • export surface • `@xpr-agents/sdk@0.2.6` `listAgents` shape.

---

## [2.3.1] — 2026-06-10

Post-release consistency patch. Every fix sandbox-tested against the live API before landing; snippets were re-extracted from the edited docs and re-run as the final gate. ([PR #28](https://github.com/XPRNetwork/xpr-network-dev-skill/pull/28))

### Fixed

- **`getOHLCV` + *Get OHLCV Chart*** — still passed `market_id` (HTTP 400). Verified contract: `symbol=` + `interval ∈ {1D, 240, 60, 15, 5}` + **ISO-date** `from`/`to` (epoch timestamps return HTTP 500). `metalx-dex.md`
- **Stale arbitrage fee math** — "0.2%/hop, ~0.4% round-trip" contradicted the canonical 0.3% earlier in the same file. Now ~0.6% round-trip / ~0.9% triangular. `defi-trading.md`
- **`/markets/all` response shape** — comment described non-existent fields; corrected to the live keys (`bid_token`/`ask_token` objects, `order_min`, `status_code`, `maker_fee`, `taker_fee`). `defi-trading.md`
- **`getOpenOrders`** — implied server-side `market_id` filtering; the API ignores the param (verified live). Rewritten to filter client-side. `defi-trading.md`
- **`rpc-queries.md` header endpoint tables** — listed 2 RPC providers / 1 Hyperion endpoint, contradicting the etiquette section in the same file. Now the full 8-row capability table.
- **`XMT (METAL)` conflation** — two `loan-protocol.md` rows now read `XMT (MTL — Metal DAO)`.
- Two broken heading anchors (etiquette slug in `resources.md`; `#token-contracts` → `#token-contract-registry` in `alcor-dex.md`); `jq` snippet `status` → `status_code`; CHANGELOG triage arithmetic; "Metal X" → "MetalX" and "orderbook" → "order book" spellings; self-contained `RAW_MEMO` example in `alcor-dex.md`.

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
