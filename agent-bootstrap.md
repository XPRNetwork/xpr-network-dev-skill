# Agent Bootstrap

How to stand up an autonomous XPR Network agent against this skill on any OpenClaw-compatible runtime.

## Who this is for

You're deploying a hosted agent (Pinata, your own OpenClaw container, future hosts) and want it to:

1. Have **runtime capabilities** on XPR Network — read/write the 4 contracts (identity, reputation, validation, escrow), use A2A, interact with the public indexer.
2. Have **domain knowledge** of XPR Network — fee math, memo gotchas, the dangerous-by-default patterns this skill exists to correct.

If you're an *individual developer* installing this skill into Claude Code on your own machine, see [README.md](./README.md) instead. This doc is for operators standing up server-side agents.

---

## How the pieces fit

| Layer | Source | What it gives the agent |
|---|---|---|
| **Capabilities** (do things) | [`@xpr-agents/openclaw`](https://github.com/XPRNetwork/xpr-agents) npm plugin | 55 MCP tools across the 4 contracts + A2A + indexer; 12 built-in skills |
| **Knowledge** (do them right) | This repo (`xpr-network-dev-skill`) | Fee math, deposit-first-or-die warnings, memo gotchas, action-name corrections — every fix this repo has shipped is a real failure mode somebody hit |

Without the plugin, the agent has knowledge but no way to act. Without the skill, the agent has tools but will copy-paste the dangerous patterns this repo spent months correcting. Use both.

---

## Bootstrap steps (runtime-agnostic)

These four steps work on any OpenClaw runtime. Pinata-specific notes are in the appendix at the bottom.

### Step 1 — Install runtime capabilities

Inside the agent's workspace:

```bash
npm install @xpr-agents/openclaw @xpr-agents/sdk @proton/js
```

Verify:

```bash
node -e "const oc = require('@xpr-agents/openclaw'); \
         console.log(Object.keys(oc).sort().join('\n'))"
```

You should see `createCliSession` and several registry/tool exports.

### Step 2 — Provision the proton CLI keychain

The agent process **must never hold the XPR private key directly at signing time**. All signing routes through the `proton` CLI's encrypted keychain. There are two ways to load the key into the keychain — pick the one that fits your environment:

#### 2a — Interactive (human at a terminal)

```bash
npm install -g @proton/cli
proton chain:set proton              # or proton-test for testnet
proton key:add                       # paste the key when prompted
proton key:list                      # verify the account is registered
```

`proton key:add` prompts twice: once for the key itself, once with *"Would you like to encrypt your stored keys with a password?"* Answer the second prompt how you like — a password gives you encryption-at-rest in exchange for needing `proton key:unlock` before signing.

#### 2b — Non-interactive (managed consoles, containers, scripts)

On Pinata Agents, Cloudflare gateways, CI containers, or anywhere without a real TTY, the interactive prompts will hang. Bypass them by passing the key as an argument and piping the encrypt-prompt answer:

```bash
npm install -g @proton/cli
proton chain:set proton
echo "no" | proton key:add PVT_K1_yourkey   # one-shot, no prompts
proton key:list
```

Notes:

- **There is no `--no-encrypt` / `--encrypt` flag.** Verified against `@proton/cli@0.1.98`. The `echo "no" | …` pipe is the supported way to auto-answer the prompt.
- **The key lands in the CLI's keychain as plaintext on disk.** Acceptable for a trusted single-tenant container (the agent host's threat model already assumes the host itself isn't compromised). Not acceptable on a shared box. Lock it later with `proton key:lock <password>` if you want encryption-at-rest; `proton key:unlock <password>` flips it back to plaintext.
- **The key is briefly visible in `ps` while `proton key:add` is running** (because it's a positional argument). On Pinata's per-agent containers `ps` is uid-scoped to the agent itself, so this is the same actor that already holds the key — no escalation. On a shared host, it's an exposure.
- After loading, signing is also non-interactive — `proton transaction:push '<json>'` and `proton action <contract> <action> '<args>' <account>@active` both return without prompts as long as the keystore is unlocked (or never locked).
- **Pre-existing locked keystores:** `key:add` skips the encryption prompt entirely when `isLocked === true` is already set, but any signing op still needs `proton key:unlock <password>` first.

#### Why the keychain at all

Every other approach (env-var private key passed to `JsSignatureProvider`, `.env` file, secrets-manager-then-zero) leaves the key reachable from the agent's **process memory at signing time** — every tool call, every log line, every paste into the model's context window is a potential leak surface. The CLI keychain pattern shells signing out to a separate `proton transaction:push` process, so the key bytes never enter the Node.js process the agent runs in.

The non-interactive path (2b) weakens this slightly at *provisioning* time — the key briefly passes through the script's env / pipe / argv — but the *runtime* property still holds: once provisioning is done, the agent process never sees the key again. That tradeoff is what makes managed-console deployment viable. See `skill/backend-patterns.md` → *Security: Key Isolation* for the full rationale.

### Step 3 — Install the dev knowledge

```bash
git clone https://github.com/XPRNetwork/xpr-network-dev-skill \
          ./skills/xpr-network-dev
```

Then point the agent at the entry file:

```bash
cat ./skills/xpr-network-dev/skill/SKILL.md
```

`SKILL.md` is the routing table — it lists every reference markdown file and what each covers. Treat it as a map: load individual reference files **on demand** when a task needs them, rather than dumping the whole repo into the system prompt.

**Always-read-before-acting docs (cheap, high-value grounding):**

| File | When to read |
|---|---|
| `skill/backend-patterns.md` → *Security: Key Isolation* | Once at startup; defines the signing pattern |
| `skill/metalx-dex.md` → *CRITICAL: DEX Token Deposits* | Before any transfer to the `dex` contract |
| `skill/defi-trading.md` → fee math + *Add Liquidity* | Before any swap quote or LP operation on `proton.swaps` |
| `skill/alcor-dex.md` → AI-agent policy block | Before any order action on `alcor` |

### Step 4 — Smoke test on chain (read-only, no signing)

```bash
node -e "
  const { JsonRpc } = require('@proton/js');
  const { AgentRegistry } = require('@xpr-agents/sdk');
  (async () => {
    const rpc = new JsonRpc('https://proton.eosusa.io');
    const info = await rpc.get_info();
    console.log('chain_id:', info.chain_id, 'head:', info.head_block_num);

    // listAgents returns { items, hasMore, nextCursor } — verified against
    // @xpr-agents/sdk@0.2.6 AgentRegistry.js line 123. The .items field is
    // an Agent[]; do NOT call .map directly on the wrapper.
    const agents = new AgentRegistry(rpc);
    const result = await agents.listAgents({ limit: 5 });
    console.log('first 5 agents:', result.items.map(a => a.account));
  })();
"
```

If this prints a chain ID and a non-empty agent list, both layers are wired. Time to register / accept jobs / etc.

### Step 5 — (Optional) Register the agent on the trustless registry

Only do this after Steps 1–4 pass. This is the first **signed** action — it uses the keychain from Step 2.

```bash
node -e "
  const { createCliSession } = require('@xpr-agents/openclaw');
  const { AgentRegistry } = require('@xpr-agents/sdk');
  (async () => {
    const { rpc, session } = createCliSession({
      account: process.env.XPR_ACCOUNT,
      permission: 'active',
      rpcEndpoint: 'https://proton.eosusa.io',
    });
    const agents = new AgentRegistry(rpc, session);
    const res = await agents.register({
      name: 'My Agent',
      description: '…',
      capabilities: [/* … */],
    });
    console.log('registered:', res.transaction_id);
  })();
"
```

Read `skill/` and the xpr-agents README before filling in the registration fields — they affect discoverability and trust score.

---

## Automation: `scripts/agent-bootstrap.sh`

Steps 1, 3, and 4 are idempotent and scriptable. Step 2 (`proton key:add`) stays manual. Run the script once at agent provisioning:

```bash
curl -fsSL https://raw.githubusercontent.com/XPRNetwork/xpr-network-dev-skill/main/scripts/agent-bootstrap.sh | bash
```

Or, if you've already cloned the repo:

```bash
./scripts/agent-bootstrap.sh
```

The script:

- Installs the `@xpr-agents/openclaw`, `@xpr-agents/sdk`, `@proton/js` packages
- Clones (or updates) `xpr-network-dev-skill` into `./skills/xpr-network-dev/`
- Runs the read-only smoke test
- **Stops before Step 2.** Prints the exact commands the operator needs to run manually for the keychain provisioning.

Re-running is safe — `npm install` and `git pull` are both idempotent.

---

## Appendix: Pinata Agents

[Pinata Agents](https://docs.pinata.cloud/agents/overview.md) are hosted OpenClaw instances. The four bootstrap steps above work as-is. A few host-specific notes:

**Where to run the commands.** Pinata agents have a persistent workspace with Node.js + Python and the ability to write/execute code in conversation. Paste the bootstrap chat prompt below into the agent's first session; the agent will execute each step and report back.

**Skill packaging — three options:**

1. **`git clone` into the workspace** (what Step 3 does). Simplest; works today; survives session restarts because the workspace persists.
2. **Pin this repo to IPFS, reference by CID.** Pinata is an IPFS company — their skill system natively supports CID references. Versioned by re-pin; no editorial dependency. Best when you want pinned-version skills with deterministic content addressing.
3. **Submit to ClawHub.** ClawHub is OpenClaw's skill marketplace (used by xpr-agents for 8 of its skills). Slower to land; gives you a stable slug for distribution. Best for long-term broad distribution.

**Secrets.** Provision in the Pinata Secrets section:

- `XPR_ACCOUNT` — the on-chain account the agent operates as
- `ANTHROPIC_API_KEY` (or other model provider) — for the LLM backing the agent
- `XPR_PRIVATE_KEY` — **only if** you're using the non-interactive provisioning path (Step 2b). Pinata's per-agent container is single-tenant, so the threat-model tradeoff in Step 2b is acceptable. The bootstrap script picks the key up from env, calls `proton key:add` once, then `unset`s the variable. After that the agent process never sees the key again — runtime signing still routes through the keychain via subprocess. If you'd rather paste the key once in chat instead of putting it in Secrets, leave this unset and the script will print the manual command.

**Bootstrap chat prompt.** Paste the following into the Pinata agent's first session — the agent runs the script, which either auto-provisions the key from `XPR_PRIVATE_KEY` or prints the manual command:

```
You are an XPR Network agent on a managed console (Pinata Agents).
Bootstrap yourself.

═══════════════════════════════════════════════════════════════
HARD RULES — read these before doing anything
═══════════════════════════════════════════════════════════════
1. NEVER run `proton key:add` without arguments. This console has
   no real TTY; the interactive prompt will hang or appear to work
   but mangle the input.
2. ALWAYS use the non-interactive form:
       echo "no" | proton key:add PVT_K1_<the-actual-key>
3. If you see "Error: invalid base-58 value" — the key was mangled
   in transit (whitespace, smart quotes, line breaks). STOP. Ask
   me to re-send it; do not retry. Do not echo the key back to me
   when asking.
4. After the key is loaded, NEVER store or repeat it. Confirm only
   with `proton key:list`, which redacts the private value.
═══════════════════════════════════════════════════════════════

Step 1 — Run the bootstrap script:

  curl -fsSL https://raw.githubusercontent.com/XPRNetwork/xpr-network-dev-skill/main/scripts/agent-bootstrap.sh | bash

Report the output. The script handles installs, PATH fixup, repo
clone, and a read-only smoke test. Stop and ask me if it fails.

Step 2 — Keychain provisioning:

  a) If the script said "key added to proton CLI keychain" because
     XPR_PRIVATE_KEY was set in Pinata Secrets: confirm with
     `proton key:list` and move on.

  b) Otherwise: ask me to provide the key. When I send it, run
     EXACTLY:

         echo "no" | proton key:add <key-you-received>

     Then run `proton key:list` to verify the account is registered.
     Apply the HARD RULES above.

Step 3 — Ground yourself:

  Read ./skills/xpr-network-dev/skill/SKILL.md and summarize the
  reference docs available to you (file name + one-line scope each).
  Then await my next instruction.
```

---

## Updating

Re-run `./scripts/agent-bootstrap.sh` whenever you want to pull skill updates. The script:

- `git pull` on `./skills/xpr-network-dev/` if it already exists
- `npm update` on the three xpr-agents packages

No reinstall, no re-keychain.

---

## Troubleshooting

**"`proton: command not found`" after `npm i -g @proton/cli`.** Global npm bin isn't on `PATH`. The bootstrap script auto-detects and prepends `$(npm config get prefix)/bin` for the rest of its run, but the *operator's* console may still need it. Add to `~/.bashrc` (or the runtime's persistence layer) to persist across sessions:

```bash
export PATH="$(npm config get prefix)/bin:$PATH"
```

**"`Error: invalid base-58 value`" from `proton key:add`.** The key was mangled in transit. Chat interfaces commonly inject:
- Leading/trailing whitespace or newlines
- Smart quotes (curly `'` `"` instead of straight `'` `"`)
- Word-wrap line breaks mid-key
- Surrounding backticks/code fences left in by the paster

The bootstrap script's `XPR_PRIVATE_KEY` path strips ASCII whitespace and verifies the `PVT_K1_` prefix before calling `proton key:add`, but it can't catch every form of corruption. If you hit this: re-send the key in a way that preserves it exactly (Pinata Secrets, file paste, or a separate plain-text channel) and retry. **Do not loop on retries** — three failed `proton key:add` attempts in 60 seconds with different mangled forms of the same key is a real footgun for accidental key disclosure.

**`proton key:add` hangs forever on a managed console.** No TTY. Use the non-interactive recipe instead:

```bash
echo "no" | proton key:add PVT_K1_yourkey
```

Never run bare `proton key:add` in a Pinata agent, a CI container, a thin web console, or anywhere `tty -s` returns false. See Step 2b.

**`TypeError: result.map is not a function` from the smoke test.** You're running an older version of `agent-bootstrap.md` against a current `@xpr-agents/sdk`. The SDK's `listAgents()` returns `{ items, hasMore, nextCursor }` — call `.items.map(a => a.account)` on the result. Pull the latest doc; this was a bug in the original publication.

**"`Buffer.from(undefined)` / `TypeError` on submit-order.** You're hitting an older copy of `metalx-dex.md`. Step 3's `git pull` fixes this — the snippet was corrected in PR #18 (May 2026).

**"`insufficient balance` on `liquidityadd`.** The deposit prerequisite isn't optional. Read `skill/defi-trading.md` → *Add Liquidity* — the 3-step `depositprep` → empty-memo transfer → `liquidityadd` flow is mandatory.

**"`api is not defined`" inside a copy-pasted `sendTransaction` / `safeTransact`.** Same fix: pull the latest skill. The helpers now take a `session` argument (PR #18).

**Agent runner refuses to start with `XPR_PRIVATE_KEY` set.** Working as designed. `@xpr-agents/openclaw` v0.3.0+ refuses if it sees a chain private key in env — that's the safety net for the keychain pattern. Either unset the variable or, if you genuinely need the legacy pattern, build your own service outside the agent runner's supported envelope.
