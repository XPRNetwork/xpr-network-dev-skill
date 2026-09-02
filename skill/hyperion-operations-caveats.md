# XPR Network Hyperion — Operations & Caveats (hard-won)

Field notes from the protonnz full-history build (July 2026), including several multi-day incidents. Sections are numbered in the order discovered — §0 was found last and explains much of what §5.5 originally attributed to chain density. Everything here was hit in practice or confirmed by other XPR Network operators and the Hyperion maintainers. Read this before sizing hardware or debugging a stalled indexer. Setup steps live in [`hyperion-setup.md`](hyperion-setup.md).

Every CLI subcommand and config key named below was checked against the upstream `eosrio/hyperion-history-api` source (4.1.0, September 2026).

---

## 0. THE WORST ONE: never create composable ES templates for proton-* indices

**Hyperion v4 uses LEGACY index templates** (`_template` API via `indices.putTemplate`: `proton-action`, `proton-delta`, … with full mappings, 4 shards). **Composable templates (`_index_template`) silently take precedence over legacy templates** — so any composable template you add matching `proton-*` (even just to set a codec) **completely replaces Hyperion's template for newly created partition indices**: no mappings (dynamic mapping!), 1 shard, defaults.

What that does on XPR: DEX actions carry arbitrary keys in `act.data` (`"136|XMD/XPR/..."` arb-table entries). Dynamic mapping explodes toward ES's 1,000-field cap → every bulk triggers slow cluster-state mapping updates → writes crawl to ~2 docs/sec → at the cap, docs are **rejected → nack → redelivered forever**. The symptom set is a perfect mimic of the consumer-coma bug (§5.5): backlog frozen/growing, consumers holding prefetch unacked, ES "idle", master logging `syncs waiting for indexer`. We lost ~5 days to this, misattributing it to chain density and the known coma bug.

**Detection:** compare partitions: `GET proton-action-v1-0000NN/_mapping` — healthy ≈ 100-120 fields, poisoned ≈ 997+; healthy = 4 shards, poisoned = 1. Log will be full of `Limit of total fields [1000] exceeded`.

**Fix:** `DELETE _index_template/<yours>`; delete the malformed partition index; purge the poisoned action queues (safe ONLY because the range gets re-read from SHIP); re-run the range. With the legacy template back in charge we measured ~4,900 blocks/sec through the same "impossibly dense" era that crawled at ~2/sec.

**And the kicker: `best_compression` is already Hyperion's default** (`src/indexer/definitions/index-templates.ts`) — check `GET <index>/_settings` before "adding" it. To change replicas/codec on FUTURE indices, edit Hyperion's own legacy templates (`PUT _template/proton-action` with its full body modified), never a composable overlay.

---

## 1. Real storage footprint (do NOT over-size)

**Full XPR mainnet Hyperion history is ~2TB — not 5TB, not 15TB.** Confirmed by operators running it:

| Component | Full history (to ~block 393M, July 2026) |
|---|---|
| Actions | ~1.24 TB |
| Deltas (`index_all_deltas`) | ~0.67 TB |
| Blocks | ~0.12 TB |
| **Total (full, with deltas)** | **~2.03 TB** |
| **Action-only** (deltas off) | **~1.4 TB** |

- One operator runs full history with every index on a **7.68TB** drive — that's *years* of headroom, not a requirement — and considers 4TB no longer comfortable for a full node.
- **Replicas double storage.** Run `es_replicas: 0` (single node) — one operator halved their footprint the moment they removed replicas.

### The projection trap that cost us days
Do **NOT** measure the ES disk-fill rate during the **December 2023 Metal X DEX peak** and extrapolate it. That era runs ~27.6 GB/million blocks — roughly **10× the sustained rate** (dex `process`/`logorder`/`processltp` flood). Extrapolating the peak across the whole remaining chain over-projected action-only to **5.2TB** when the real figure is ~1.4TB. Trust whole-chain operator numbers (~2TB) over a short in-peak measurement.

**Implication:** a 2×1.92TB box (split ES/SHIP) **can hold action-only full history** on its 1.9TB ES drive. Full-with-deltas (~2TB) needs a drive >2TB (4TB or 7.68TB).

---

## 2. Redis temp-file bloat — the silent disk killer (reclaimed 425GB)

**Symptom:** `/var/lib/redis` is hundreds of GB, but `redis-cli INFO memory` shows only a couple GB `used_memory`. Disk mysteriously full.

**Cause:** Redis periodic RDB background-save (`save 3600 1 …`) writes a `temp-NNNNNN.rdb`, then renames to `dump.rdb`. If a save is **interrupted** (disk full, OOM, process churn, restarts), the temp file is **orphaned**. Under disk pressure + repeated restarts these **cascade** — we accumulated **35 files / 425GB** of junk in one bad afternoon (8.9G, 9.4G, 23G, 20G… each a failed save).

**This was a major contributor to our "disk full at block 230M" incident** — ES was only ~1TB there; 425GB of Redis garbage pushed the drive to 92%.

**Fix (safe — Redis doesn't use temp files):**
```bash
ls -lah /var/lib/redis/temp-*.rdb          # confirm they're stale (old dates)
rm -f /var/lib/redis/temp-*.rdb            # reclaim
redis-cli ping                             # confirm still healthy
```
**Part 2 of the Redis saga (it WILL escalate):** during high-speed indexing (~5k blocks/s) Hyperion's Redis usage balloons unbounded — ours hit **84GB RSS and got OOM-killed**, then entered a **systemd restart crashloop** (loading its 40GB dump exceeds the 90s start timeout → killed → retry, 45 attempts). With Redis down, indexer workers wedge with `ioredis ECONNREFUSED` — looks like yet another consumer stall. Operators had warned about exactly this: cap Redis memory, because unbounded Redis stops the queues.

**Permanent fix (Hyperion's Redis is rebuildable cache/coordination):**
```
# /etc/redis/redis.conf
maxmemory 12gb
maxmemory-policy allkeys-lru
save ""            # no RDB snapshots: kills both the temp-file bloat AND the crashloop-on-load
```
Wipe `dump.rdb` + `temp-*.rdb` when applying (frees the disk too).

**Prevent:** monitor `/var/lib/redis` size. Hyperion's Redis holds rebuildable cache/coordination data, so if this recurs you can safely disable RDB snapshots (`redis-cli CONFIG SET save ""`) or wipe Redis entirely between runs.

---

## 3. Disk-full → ES read-only → indexer stalls at a partition boundary

**This is the #1 misdiagnosis trap.** When the ES drive crosses ES's flood watermark (~90%), ES **blocks new shard allocation**. Hyperion partitions indices every `index_partition_size` blocks (default **10,000,000**), so when the indexer crosses a boundary (e.g. block **230,000,000**) it tries to create the next index (`proton-action-v1-0000NN`) — which **can't allocate** → goes **RED** → indexer can't write → **stalls at exactly that round block number.**

**Symptoms that look like something else but are actually disk:**
- Indexer master idle at **0% CPU** in `ep_poll` (not grinding).
- `"No blocks are being processed, please check your state-history node!"` (points at SHIP, but SHIP is fine).
- Reader runs *ahead* while `max_indexed_block` freezes.
- **No** deserialization error in `deserialization_errors.log`.
- Stall block is a **multiple of 10M**.

**ALWAYS check these FIRST when the indexer idles:**
```bash
df -h /                                                   # ES drive % — near 90%?
curl -s -u elastic:$P localhost:9200/_cluster/health      # status: red? unassigned_shards>0?
curl -s -u elastic:$P 'localhost:9200/_cat/indices/proton-action-*?v&s=index' | tail  # a RED partition?
```
We wasted hours chasing a "deserializer stall" that was purely disk. Experienced operators warn about this directly: once the ES data drive hits ~90% it flips read-only and causes a lot of pain.

**Recovery:** free space (see §2), delete the empty RED partition indices (`DELETE /proton-*-v1-0000NN` — safe if 0 docs) to get the cluster green, then resume.

---

## 4. NEVER purge queues / restart with docs in flight (silent data loss)

**Rule (every experienced operator repeats it):** don't restart the indexer with docs in the queues or you will be missing data. Purging RabbitMQ queues or restarting while the ds_pool/index queues hold documents **drops those actions/deltas** — leaving **silent gaps** that pass a "range completed" check but fail on `get_actions`.

We purged all `proton:*` queues and restarted repeatedly during the 230M disk incident → **small action gaps around block ~230M** (later confirmed and repaired, §11).

**Correct resume:** just `pm2 start proton-indexer` — the queued docs get *processed*, not lost. Only **purge** if you know the queues are empty.

**Important nuance — a *jam* recovery is NOT the same as a lossy restart.** If the `index_actions` (or other output) queues back up because the ES-write *consumers* stall (seen: 248k messages stuck, reader backpressured to R:0, ES green), the fix is a **normal `pm2 restart` with `purge_queues: false`** — the reconnected consumers drain the *durable* queue and write every doc (verified: 248k drained, none lost). The data-loss rule is specifically about **purging** or restarting in a way that **clears/skips** the queue. So: `purge_queues: false` + restart to revive stuck consumers = safe; `purge_queue` / wiping the queue = lost actions. Still verify the affected range afterward.

**Repair gaps:**
1. Find missing ranges in **Kibana** (or compare `get_actions` counts per block range against a reference node).
2. Set `live_reader: false`, `rewrite: true`, and `start_on`/`stop_on` to the affected range; disable streaming during the rescan.
3. Or use `./hyp-repair` on the targeted range (`scan-actions` / `fill-missing`, §11).
4. **Always verify completeness after any restart-under-load** — this is what separates a "looks done" index from a *provably complete* one (critical for tax/history use).

---

## 5. Compression, replicas and forcemerge (space reclaim)

- **`index.codec: best_compression` is Hyperion's default** (§0). It is ~30% smaller than the default codec and operators running full XPR history on enterprise NVMe report no measurable query-latency cost. Verify with `GET proton-action-v1-0000NN/_settings` rather than adding it.
- **Do not add a composable `_index_template` to set codec or replicas.** It replaces Hyperion's legacy template wholesale (§0) and, as a second-order effect, new partitions come up with ES's default of **1 replica** instead of Hyperion's `es_replicas: 0` — **yellow** on a single node with an unassigned replica. If you already did this: `DELETE _index_template/<yours>`, then fix existing indices with `PUT /proton-*/_settings {"index":{"number_of_replicas":0}}`.
- To change settings for future partitions, modify Hyperion's own legacy template body (`GET _template/proton-action`, edit, `PUT _template/proton-action`) so mappings and shard counts survive.
- **`forcemerge`** reclaims disk from documents marked for deletion, but it takes time and is I/O-heavy — run it when **not** actively indexing. Existing indices keep their codec until reindexed/force-merged.

---

## 5.5 THE big one: backfill in bounded 10M ranges, never open-ended

**Do not run the historical index as one open-ended pass (`start_on: 0, stop_on: 0`).** Every operator who has completed XPR full history runs explicit `start_on`/`stop_on` **ranges of ~10–15M blocks**: it is easier on the hardware and keeps the pipeline from jamming with data. Step through the ranges until you are current, then turn on the live reader.

Open-ended runs jam the RabbitMQ pipeline in dense eras: the `index_actions` consumers can **deadlock silently** — alive, holding their full prefetch unacked, ES idle and green, master logging `R:0 C:0 A:0 D:0 I:0 … syncs waiting for indexer` / `No blocks are being processed` (misleading — SHIP is fine). One operator hit an hours-long dead stall in the 200–250M era after growing ranges to 50M (`[04_deserializer] NACK ALL Cannot read properties of null (reading 'content')`); the fix was smaller ranges. The consumer wedge is a **known recurring Hyperion bug**: the indexer is running but not fully processing until manually restarted.

**Procedure (per range):** `live_reader: false`, `purge_queues: false`, **streaming disabled** during backfill, set `start_on`/`stop_on` (+10M), run; a range is done when the reader logs range-complete and **all queues are empty**; then `./stop <chain>-indexer` (graceful `hyp-control indexer stop`; `control_port` comes from `connections.json` → `chains.<chain>.control_port`, default 7002) and advance. Range overlap is safe — action docs are id-keyed by `global_sequence`, so re-indexing a boundary is idempotent. Automate it with a loop that polls ES max `block_num` + RabbitMQ queue depth, applies the stall remedy below, and alerts after ~6 consecutive stalls.

### The "consumer coma" bug — known for YEARS, and the correct revive
The silent consumer wedge (workers alive, prefetch held unacked, zero acks, ES idle) is a **long-standing Hyperion bug**, reported by operators running dozens of servers ("random workers go into a coma — the connection looks alive but nothing flows") and root-caused by the Hyperion maintainers: consumers get detached from the master and stop receiving its signals; the unacked messages were already in consumer memory, so RabbitMQ never gets the confirmation. The v4 (ESM) rewrite reduced it but v4.0.8 field reports still show it under heavy load.

**The revive that actually works (operator-proven):**
`pm2 stop` → **WAIT** until RabbitMQ shows the consumers truly detached (the unacked messages shift back to *ready* — can take minutes) → `pm2 start`.
A plain `pm2 restart` does NOT reliably work: RabbitMQ doesn't notice the old connections have stopped and the consumers don't properly reconnect — it needs a distinct stop, wait, start. If stalls persist on heavy ranges, a **full server reboot** clears it.

**After any stall episode, audit for gaps:** these wedges leave silent holes **in multiples of 500** (the index prefetch — see `prefetch` in `config.ref.json`). Kibana + `hyp-repair` scan the affected ranges. Do NOT raise the prefetch above 500.

**"No blocks are being processed, please check your state-history node!" is almost never SHIP.** Hyperion pauses reading when queues are over-limit, and the log line is a misleading side effect. `syncs waiting for indexer` means data has accumulated in index queues and not yet been pushed to ES. Resume is automatic once queues drain below `resume_trigger` — unless the consumers are comatose (above) or the master's RabbitMQ HTTP queue-size poll itself died (old `checkQueueSize` bug) — both only recover via stop/wait/start.

**Scripting gotcha — `./run` never returns:** Hyperion's `./run <chain>-indexer` helper ends by tailing `pm2 logs`, which blocks forever. Any automation that calls it must wrap it: `timeout 30 ./run <chain>-indexer || true` (pm2 start completes in seconds; killing the tail is harmless). Our range loop silently wedged for 43 hours on this — with the indexer comatose and nothing watching. Corollary: automation loops need a heartbeat log line so "alive but silent" is detectable.

**Config hygiene from the same incidents:** `routing_mode: round_robin` (heatmap deprecated); `amqp.frameMax: "0x10000"` in `connections.json`; invariant `auto_scale_trigger ≤ max_queue_limit`; disable `resource_limits`/`resource_usage`/`failed_trx` features you don't need (unsticking effect observed); cap Redis memory (§2 — unbounded Redis → swap → queue processing stops); don't over-ramp scaling ("sprinting to fill queues" runs slower).

**Alternative to grinding entirely:** one operator migrated by **restoring another operator's Elasticsearch snapshots** and indexing only the tail — full mainnet+testnet in ~2 days. If a friendly BP will share ES snapshots, that skips the dense-era grind.

**Bootstrap shortcut for the SHIP side:** full blocklog + state-history archives from a BP **plus a chain snapshot dated BEFORE the log head** → nodeos starts with `--snapshot`, rolls forward, "earliest available block = 1" within hours — no genesis replay at all. (Snapshot must be *older* than the end of the logs, never ahead; delete `blocks/reversible` when starting from a snapshot.)

## 6. Scaling / anti-jam config

**A jam-resistant baseline from an operator running dozens of Hyperion instances (XPR mainnet):** **`ds_threads: 4`, `ad_idx_queues: 2`, `max_autoscale: 9`**. Modest and jam-resistant — a good starting shape. (Our build ran `ds_threads: 8`; 4 + autoscale-to-9 is the operator-recommended shape.)

- Run a small fixed base with autoscaling headroom so the ds_pool doesn't jam on dense eras (the Dec-2023 DEX peak is the stress test).
- Watch RabbitMQ queue depth (`rabbitmqctl list_queues -p hyperion name messages`) — persistent backlog = a downstream (ES) bottleneck.
- Disable `live_reader` during the historical backfill (faster); re-enable it when caught up to follow the tip.
- **Don't change `ds_queues`/`ds_pool_size` while docs are queued** — the queue topology change can orphan them (same data-loss risk as §4). Let queues drain first.

---

## 7. Disk layout

- **ES and nodeos SHIP on separate physical drives** (they contend on I/O otherwise). Not RAID1 — a Hyperion node is fully rebuildable from chain, so mirroring wastes 50% capacity for little benefit. Protect the index with **off-box ES snapshots** instead (cheap object storage).
- The **ES drive must exceed the ES index size**: action-only (~1.4TB) fits a 1.9TB drive; full+deltas (~2TB) needs >2TB.

---

## 8. Hardware sourcing (Hetzner constraint + funding)

- **Hetzner standard dedicated models (AX/EX) cannot have drives added after ordering** — storage is fixed at order via the configurator (confirmed with Hetzner support). Size storage at purchase, or use the **Hetzner Server Auction** for storage-heavy boxes.
- **XPR governance funds public Hyperion hardware.** Precedent: a block producer's "Hyperion API Deployment" governance proposal (Jan 2024) requested **$2,400 for hardware** and passed **unanimously (1.09B XPR, 100%)**; the operator bears colocation/power/bandwidth. The network explicitly wants **≥5 healthy public Hyperion APIs**. A one-time hardware grant for a public node is a viable, precedented path.

---

## 9. The 10k limit is not a data limit

`get_actions` clamping at `total: 10000` is Elasticsearch's `max_result_window` (offset pagination cap), **not** a limit on retrievable history. **Cursor pagination** retrieves unlimited history — even on public nodes: page with `sort=desc&limit=1000`, then repeat with `before=<oldest @timestamp on the previous page>`, de-duplicating on `global_sequence` (several actions can share a timestamp). This means complete per-account exports are possible without a private node, though a private node gives you control and independence.

---

## 10. Users will report "missing history" that is actually `max_asc_window_days`

Hyperion v4's API defaults **`api.max_asc_window_days: 90`** (`src/interfaces/hyperionConfig.ts`) — `sort=asc` queries whose window reaches back more than 90 days return **empty** (guardrail against expensive deep ascending scans; 4.1.0 additionally rejects `sort=asc` with no `after`/`before` bound at all). Symptom pattern from real users: "the action index starts ~N days ago" with a bisected start date that is exactly `today - 90d`; descending queries and exports work fine over the same range, which proves the data is present. Internally inconsistent-looking bisects (`after=older` empty but `after=newer` returns hits) are the fingerprint.

For a full-history public node, set it explicitly:
```
./hyp-config set <chain> api.max_asc_window_days 3650   # then restart the API
```
Verify with `sort=asc&after=<genesis year>` returning the chain's first `eosio:onblock` actions.

---

## 11. Block-complete ≠ action-complete: the verification standard that actually matters

`hyp-repair quick-scan` and `/v2/health missing_blocks` validate the **block** index only. Action documents live in separate indices and can be silently absent while every block-level check passes green. Our node passed quick-scan ("no missing blocks") while holding a **1.25M-block action hole** (Feb 2024) plus **~53,000 missing actions scattered across ~29,000 micro-ranges** chain-wide — discovered only when a downstream consumer's ledger reconciliation failed.

**Where the holes came from:**
- The big one: after deleting a corrupted action partition, the re-index ran with **`rewrite: false`** — Hyperion then **skipped every block whose block-doc already existed**, never re-writing their actions. Rule: **any re-index over a range where block docs exist MUST use `rewrite: true`.**
- The scattered ones: restart/purge events during incident recovery (gaps in multiples of the 500-doc prefetch, exactly as operators predicted).

**The standard before claiming completeness (or publishing publicly):**
1. `./hyp-repair scan-actions <chain> -f 2 -l <head>` — action-level binary-search validation. (Run CLI tools under a pseudo-TTY: `script -qec "..." log` — they crash headless on `process.stdout.clearLine`.)
2. `fill-missing` what it finds; **re-scan to an explicit zero**: "No missing actions found."
3. Independent cross-check against a reference node: per-week `get_actions total.value` for the busiest contract (`dex`) since genesis — any week you return 0 and the reference doesn't is a hole. ~330 requests, minutes.
4. Keep a **daily canary** (last ~5 weeks of the same comparison) so future holes alert instead of corrupting downstream ledgers.

A downstream tax pipeline mis-classified ~12,000 payouts because of the Feb hole — completeness is a *correctness* property for anything financial, not a quality nicety.
