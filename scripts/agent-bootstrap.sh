#!/usr/bin/env bash
# agent-bootstrap.sh — Idempotent provisioning for an XPR Network agent
#                      running on an OpenClaw-compatible runtime.
#
# Runs Steps 1, 3, and 4 of the bootstrap procedure in agent-bootstrap.md.
# Step 2 (proton CLI keychain) stays manual because it requires interactive
# key paste — the script prints the exact commands the operator must run.
#
# Safe to re-run: npm install and git pull/clone are both idempotent.

set -euo pipefail

# ─── Configuration ──────────────────────────────────────────────────────
SKILL_DIR="${SKILL_DIR:-./skills/xpr-network-dev}"
SKILL_REPO="${SKILL_REPO:-https://github.com/XPRNetwork/xpr-network-dev-skill}"
RPC_ENDPOINT="${RPC_ENDPOINT:-https://proton.eosusa.io}"

# ─── Helpers ────────────────────────────────────────────────────────────
say() { printf "\n\033[1;36m▶ %s\033[0m\n" "$*"; }
ok()  { printf "\033[1;32m  ✓ %s\033[0m\n" "$*"; }
warn(){ printf "\033[1;33m  ⚠ %s\033[0m\n" "$*"; }
die() { printf "\033[1;31m  ✗ %s\033[0m\n" "$*" >&2; exit 1; }

require() {
  command -v "$1" >/dev/null 2>&1 || die "missing dependency: $1"
}

# ─── Preflight ──────────────────────────────────────────────────────────
say "Preflight"
require node
require npm
require git
ok "node $(node --version), npm $(npm --version), git $(git --version | awk '{print $3}')"

# ─── Step 1 — Install runtime capabilities ──────────────────────────────
say "Step 1 — Install xpr-agents plugin + SDK + @proton/js"

if [ -f package.json ]; then
  npm install \
    @xpr-agents/openclaw \
    @xpr-agents/sdk \
    @proton/js
else
  warn "no package.json in cwd; initialising one"
  npm init -y >/dev/null
  npm install \
    @xpr-agents/openclaw \
    @xpr-agents/sdk \
    @proton/js
fi

INSTALLED_OPENCLAW=$(node -e "console.log(require('@xpr-agents/openclaw/package.json').version)")
INSTALLED_SDK=$(node -e "console.log(require('@xpr-agents/sdk/package.json').version)")
ok "openclaw $INSTALLED_OPENCLAW, sdk $INSTALLED_SDK"

# Quick smoke: confirm createCliSession is exported.
node -e "
  const oc = require('@xpr-agents/openclaw');
  if (typeof oc.createCliSession !== 'function') {
    process.exitCode = 1;
    console.error('createCliSession missing from @xpr-agents/openclaw exports');
  }
" || die "@xpr-agents/openclaw exports look wrong — check the installed version"
ok "createCliSession export present"

# ─── Step 3 — Install / refresh the dev knowledge ───────────────────────
say "Step 3 — Install xpr-network-dev-skill into $SKILL_DIR"

mkdir -p "$(dirname "$SKILL_DIR")"
if [ -d "$SKILL_DIR/.git" ]; then
  ( cd "$SKILL_DIR" && git pull --ff-only ) || die "git pull failed in $SKILL_DIR"
  ok "updated existing clone at $SKILL_DIR"
else
  if [ -e "$SKILL_DIR" ]; then
    die "$SKILL_DIR exists but is not a git checkout; refusing to overwrite"
  fi
  git clone --depth 1 "$SKILL_REPO" "$SKILL_DIR"
  ok "cloned $SKILL_REPO → $SKILL_DIR"
fi

if [ ! -f "$SKILL_DIR/skill/SKILL.md" ]; then
  die "$SKILL_DIR/skill/SKILL.md not found — repo layout changed?"
fi

# Print the skill index so the agent (or human reviewer) can grep it.
say "Skill index — $SKILL_DIR/skill/SKILL.md (first 40 lines)"
head -n 40 "$SKILL_DIR/skill/SKILL.md"

# ─── Step 4 — Read-only smoke test against mainnet ──────────────────────
say "Step 4 — Read-only smoke test against $RPC_ENDPOINT"

RPC_ENDPOINT="$RPC_ENDPOINT" node -e "
  const { JsonRpc } = require('@proton/js');
  const { AgentRegistry } = require('@xpr-agents/sdk');
  (async () => {
    const rpc = new JsonRpc(process.env.RPC_ENDPOINT);
    const info = await rpc.get_info();
    console.log('  chain_id:', info.chain_id);
    console.log('  head:    ', info.head_block_num);
    try {
      const agents = new AgentRegistry(rpc);
      const all = await agents.listAgents({ limit: 5 });
      console.log('  agents:  ', all.map(a => a.name).join(', ') || '(none)');
    } catch (e) {
      console.log('  agents:   (listAgents threw — registry may not be deployed on this RPC: ' + e.message + ')');
    }
  })().catch(e => { console.error(e); process.exit(1); });
"
ok "chain reachable, capabilities + knowledge wired"

# ─── Step 2 — Provision the proton CLI keychain ─────────────────────────
# Two paths: non-interactive if XPR_PRIVATE_KEY is set in env (managed
# consoles like Pinata Agents), interactive instructions printed otherwise
# (human at a terminal). See agent-bootstrap.md → Step 2 for the threat-
# model tradeoff between the two.

KEYCHAIN_STATUS="not provisioned (see manual steps printed above)"

if ! command -v proton >/dev/null 2>&1; then
  say "Step 2 — Installing @proton/cli"
  npm install -g @proton/cli
  ok "proton CLI installed ($(proton --version 2>/dev/null || echo 'version unknown'))"
fi

# Make sure the chain is set; this is non-interactive and idempotent.
proton chain:set "${PROTON_CHAIN:-proton}" >/dev/null 2>&1 || true

if [ -n "${XPR_PRIVATE_KEY:-}" ]; then
  say "Step 2 — Non-interactive keychain provisioning (XPR_PRIVATE_KEY is set)"
  warn "the key will be briefly visible in 'ps' while 'proton key:add' runs"
  warn "this script assumes a trusted single-tenant container (Pinata, dedicated VM)"
  warn "do NOT run this path on a shared host"

  # echo "no" answers the post-add "encrypt your stored keys?" prompt.
  # The key lands in the CLI's keychain on disk; we accept that tradeoff
  # because the alternative (key in agent process memory) is worse.
  if echo "no" | proton key:add "$XPR_PRIVATE_KEY" >/dev/null 2>&1; then
    ok "key added to proton CLI keychain"
    unset XPR_PRIVATE_KEY  # clear from this script's env asap
    KEYCHAIN_STATUS="provisioned via XPR_PRIVATE_KEY (env var cleared)"
    say "Step 2 verification — proton key:list"
    proton key:list
  else
    warn "proton key:add failed — falling through to interactive instructions"
  fi
fi

if [ "$KEYCHAIN_STATUS" = "not provisioned (see manual steps printed above)" ]; then
  say "Step 2 — Provision the proton CLI keychain (manual)"
  cat <<'EOF'
  XPR_PRIVATE_KEY is not set; the script will not write your key.
  Run the following yourself.

  Interactive (you're at a terminal):

      proton key:add                       # paste your key, answer encrypt prompt
      proton key:list                      # verify the account appears

  Non-interactive (managed console, no TTY):

      echo "no" | proton key:add PVT_K1_yourkey
      proton key:list

  See agent-bootstrap.md → Step 2 for the threat-model tradeoff and how
  to re-encrypt later with `proton key:lock <password>`.

EOF
fi

say "Bootstrap complete"
cat <<EOF
  Capabilities (xpr-agents plugin)  : installed
  Knowledge (xpr-network-dev-skill) : $SKILL_DIR
  RPC reachable                     : $RPC_ENDPOINT
  Keychain                          : $KEYCHAIN_STATUS

  Next: have the agent read $SKILL_DIR/skill/SKILL.md, summarize the
  reference docs available, and then proceed with its first task.
EOF
