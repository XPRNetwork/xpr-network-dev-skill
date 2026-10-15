# v2.10.0: learnings from a full-size AtomicAssets drop and mainnet mint

## Summary

These are real-world learnings from building and launching a free-claim NFT drop on XPR Network. The setup:

- a `proton-tsc` claim contract using the `rng` oracle and `get_code_hash`
- 3,333 AtomicAssets NFTs pre-minted with the proton CLI
- a `@proton/web-sdk` 5.1.0 claim page

Everything was rehearsed at full size on testnet (2026-09-24/25), then minted on mainnet (2026-09-25: 167/167
batches, no duplicates). Each finding is placed in the module where a developer would look for it, not
appended as one list. Nothing in this PR is project-specific. Example account names are generic
(`myaccount`, `mycontract`), and it contains no keys.

It also **fixes a bug in the first draft** of the `get_code_hash` workaround (commit 9119338, never
published). That draft parsed a non-existent `account` field and a varuint `code_sequence`. The correct
packed layout is 43 bytes: `varuint32 struct_version | u64 code_sequence | checksum256 code_hash | u8 vm_type
| u8 vm_version`, with the hash at bytes 9..40.

Tool versions: `@proton/cli` 0.1.98 (source checked against 0.1.99), `proton-tsc` 0.3.58, `@proton/vert`
0.3.24, `@proton/web-sdk` / `@proton/link` 5.1.0.

## Changes by file

| File | Change |
|---|---|
| `smart-contracts.md` | Known SDK bug: `getCodeHash()` 3-param import vs the node's 4-param intrinsic breaks `setcode`. Adds a 4-param `@external` workaround and the exact packed-layout table. The helper fails safe: any unexpected length or version reads as "has code". Also: check `get_code_hash` after deploy (ABI-only half-deploys exit 0). |
| `cli-reference.md` | New section, *Scripting the CLI for bulk or high-value jobs*: errors exit 0, `expireSeconds: 3000`, supplied `expiration` / `ref_block_*` override the CLI's, how to tell pre-broadcast failures, node rejections and ambiguous results apart, resend only after irreversible time passes the expiration (reading state from the same endpoint), and the selected chain is global. Also: `contract:set` prompt and ABI-only deploys, `transaction:push` vs `proton action`, `create-funded`, and buying a `resources` plan from the CLI. |
| `nfts-atomicassets.md` | New *Bulk Minting Safely* pattern: `issued_supply` as the counter, journal before the push, the chain decides the outcome, the ambiguous-batch expiry gate, a lock, resource preflight, and a verify step. New *`template_mint` is back-filled* section (verify order by `asset_id`). The `createcol` example now shows collection `img` as `["string","Qm…"]`. `ipfs` variants serialize as `string` (CIDv0). Template keys must exist in the schema. Measured RAM, CPU and NET at full size, and NET exhaustion during bulk mints. |
| `oracles-randomness.md` | `rng` is live on testnet (callback ~1–3 s, a separate transaction). New best practices: a never-reused request id as `assoc_id` with stale-callback ignore, no `check()` on normal paths in `receiverand`, and don't auto-send to accounts with contract code (they could reject and stall or re-roll). Checklist updated. |
| `staking-governance.md` | `buyplan` pays from a deposit: transfer XPR to `resources` first (credited to the sender), then `buyplan`. Also when a bulk job needs a plan. |
| `rpc-queries.md` | `get_table_rows` can return fewer rows than `limit` (~1,000 observed). Always loop on `more` / `next_key`. |
| `troubleshooting.md` | New entries: *A push returned a `transaction_id`, but nothing changed on chain*; `transaction net usage is too high`; `get_table_rows` returns only part of a table; chain vs vert auth wording; `get_code_hash` setcode error; ABI-only "executed" no-ops; signing popup blocked after login (with the 5.1.0 `childWindow` detection). |
| `testing-debugging.md` | The vert test example used the chain's auth wording and would never match. It now uses vert's `missing required authority X`, and the error table lists both. Also: deploy to testnet early (vert 0.3.24 implements the same 3-param `get_code_hash`), `echo y |` plus a code-hash check in the deploy script, checklist items for oracle callbacks and contract-code accounts, and "rehearse at full size". |
| `web-sdk.md` | 5.1.0 is GA, with the 5.x options shape. Login and transact in separate clicks, with nothing async before `transact()`. A blocked popup leaves `link.childWindow` `null`, and the promise never settles (detection snippet). A hand-closed window also leaves it pending: treat it as unknown, not cancelled. `storagePrefix` key format, and scoping sessions per chain and contract. 5.1.0 login and cancel shapes (`{ error }` return, `E_CANCEL` / `E_WALLET_TYPE`, `'Closed'`). |
| `accounts-permissions.md` | `account:create-funded -k -o` for agent-driven rehearsals: no email step, and no private key printed. |
| `SKILL.md`, `safety-guidelines.md` | Safety reminder: a push response is not proof. Check `proton chain:get` before every signing step. Version bumped to 2.10.0. 5.x note on the login example. |
| `CHANGELOG.md`, `agent-bootstrap.md` | 2.10.0 entry and the bootstrap tag pin. |

## How each item was verified

| Item | Evidence |
|---|---|
| `get_code_hash` 3 vs 4 params | Testnet `setcode` failed with `wrong type for imported function get_code_hash` and passed with the 4-param import. `@proton/vert` 0.3.24's `get_code_hash` takes 3 args, which is why local tests passed. |
| 43-byte packed layout | Matches vert's `code_hash` struct (`varuint32, uint64, checksum256, uint8, uint8`). On testnet and mainnet, a plain WebAuth account read "no code" (NFT delivered), and an account with a contract read "has code" (NFT only reserved). |
| CLI exits 0 / 3000 s / header wins | `@proton/cli` source: each command's `catch()` only prints; `networks.ts` has `expireSeconds: 3000`; `@proton/js` `generateTapos` returns `{ ...header, ...transaction }`. On mainnet all 167 pushes carried a 600 s expiration set by the runner. On testnet a real push printed an error with no `transaction_id` and exited 0. |
| Ambiguous-push handling and bulk-mint pattern | Testnet: 3,333 editions with a deliberate interruption. A batch had landed but wasn't journaled; the supply check skipped it (no duplicate). A real ambiguous push was held until it expired. A `kill -9` right after a broadcast: the restart refused to resend until irreversible time passed the expiration. Mainnet: 167/167 batches at the first attempt, and verify showed one asset per edition, in order. |
| Phantom `transaction_id` | Testnet: a two-call transaction returned an id from one API endpoint and never landed. A config change pushed through another endpoint had already reached the producer, so the second call asserted there. |
| NET exhaustion and `resources` plan | Testnet: `transaction net usage is too high: 5533 > 4192` after ~80 batches of ~5.6 KB. Mainnet: `eosio.token::transfer` of 100 XPR to `resources`, then `resources::buyplan {plan_index:0}`. `planreceipt` and the `subscription` row were confirmed on chain. `resources` ABI checked: `buyplan {account, plan_index, plan_quantity}`. |
| `get_table_rows` short pages | Testnet: a monitor reading AtomicAssets `assets` in one call saw ~1,000 of 3,300 rows. It was fixed by looping on `more` / `next_key`. |
| `template_mint` back-fill | AtomicAssets API returned `template_mint` 0 for fresh testnet mints. Verification switched to `asset_id` order. |
| `createcol` / `ipfs` variant | Testnet: `["ipfs", …]` failed client-side with `type "ipfs" is not valid for variant`, and `["string","Qm…"]` worked. Used again on mainnet. |
| rng stale callbacks and the delivery split | Testnet: claim and cancel in one transaction, then a retry. The stale callback was ignored and exactly one NFT was delivered. A claimer with contract code got a reserved NFT, and a later `deliver` sent it. rng callbacks arrived in ~1–3 s. |
| Chain vs vert auth wording | Chain: `missing authority of <acct>` (testnet). vert 0.3.24 source: `missing required authority <acct>`. |
| web-sdk 5.1.0 behaviour | `@proton/web-sdk` 5.1.0 source: `window.open` before the first `await` in `transact()`; rejection only on the `close` message; `Storage` key `${storagePrefix}-${key}` with default `proton-storage`; `connect` returns `{ error }`. Popup blocking was reproduced in a testnet claim flow with login and transact in one click. |
| Full-size RAM / NET numbers | Testnet minter: 933,540 B for 3,333 assets (~280 B each); ~5.6 KB NET per 20-mint batch. |

`scripts/validate-skill.sh` passes. It checks npm packages, contract accounts, URLs, key leaks, personal references
and outdated domains.

## Not included / follow-ups

- An upstream issue for `proton-tsc` / `as-chain` about the `get_code_hash` signature is worth filing
  separately.
- `staking-governance.md` prices RAM at ~0.0004 XPR/byte (Bancor), while mainnet `eosio::globalram` shows
  `ram_price_per_byte: 0.0020 XPR` and `ram_fee_percent: 1000`. This PR leaves it unchanged. It needs a
  separate check of which price `buyram` actually charges.
