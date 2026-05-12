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

### Step 2 — Provision the proton CLI keychain (interactive)

The agent process **must never hold the XPR private key directly**. All signing routes through the `proton` CLI's encrypted keychain.

```bash
npm install -g @proton/cli
proton chain:set proton              # or proton-test for testnet
proton key:add                       # interactive — paste the key once
proton key:list                      # verify the account is registered
```

This is the **only step that cannot be scripted** because `proton key:add` requires interactive paste. Do it once per agent at provisioning time; the encrypted keychain persists across sessions.

> **Why this matters.** Every other approach (env-var private key, `.env` file, secrets-manager-then-zero) leaves the key reachable from the agent's process memory at least briefly. The CLI keychain pattern means the key bytes never enter the Node.js process the agent runs in. A malicious or hallucinating agent later in the session has no key to leak. See `skill/backend-patterns.md` → *Security: Key Isolation* for the full rationale.

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

    const agents = new AgentRegistry(rpc);
    const all = await agents.listAgents({ limit: 5 });
    console.log('first 5 agents:', all.map(a => a.name));
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
- The chain private key does **not** go in Secrets. It goes into the proton CLI keychain via Step 2.

**Bootstrap chat prompt.** Paste the following into the Pinata agent's first session — the agent will execute each step and stop where manual input is needed:

```
You are an XPR Network agent. Bootstrap yourself by running:

  curl -fsSL https://raw.githubusercontent.com/XPRNetwork/xpr-network-dev-skill/main/scripts/agent-bootstrap.sh | bash

Report the output of each step. When the script stops at the keychain
provisioning, prompt me for the private key — do not log or echo it.
After `proton key:add` returns and `proton key:list` shows my account,
read ./skills/xpr-network-dev/skill/SKILL.md and summarize the
reference docs available to you. Then await my next instruction.
```

---

## Updating

Re-run `./scripts/agent-bootstrap.sh` whenever you want to pull skill updates. The script:

- `git pull` on `./skills/xpr-network-dev/` if it already exists
- `npm update` on the three xpr-agents packages

No reinstall, no re-keychain.

---

## Troubleshooting

**"`proton: command not found`" after `npm i -g @proton/cli`.** Add your global npm bin to `PATH`. Run `npm config get prefix` and add `<that-path>/bin` to `PATH`. On Pinata's workspace, this usually means adding to `~/.bashrc` so it persists.

**"`Buffer.from(undefined)` / `TypeError` on submit-order.** You're hitting an older copy of `metalx-dex.md`. Step 3's `git pull` fixes this — the snippet was corrected in PR #18 (May 2026).

**"`insufficient balance` on `liquidityadd`.** The deposit prerequisite isn't optional. Read `skill/defi-trading.md` → *Add Liquidity* — the 3-step `depositprep` → empty-memo transfer → `liquidityadd` flow is mandatory.

**"`api is not defined`" inside a copy-pasted `sendTransaction` / `safeTransact`.** Same fix: pull the latest skill. The helpers now take a `session` argument (PR #18).

**Agent runner refuses to start with `XPR_PRIVATE_KEY` set.** Working as designed. `@xpr-agents/openclaw` v0.3.0+ refuses if it sees a chain private key in env — that's the safety net for the keychain pattern. Either unset the variable or, if you genuinely need the legacy pattern, build your own service outside the agent runner's supported envelope.
