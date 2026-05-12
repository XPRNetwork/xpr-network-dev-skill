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
      // listAgents returns { items, hasMore, nextCursor } — verified against
      // @xpr-agents/sdk@0.2.6. Use .items, NOT the wrapper directly.
      const agents = new AgentRegistry(rpc);
      const result = await agents.listAgents({ limit: 5 });
      const names = result.items.map(a => a.account);
      console.log('  agents:  ', names.join(', ') || '(none)');
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
fi

# After a global install, the npm bin directory may not be on PATH yet —
# this is the #1 cause of "proton: command not found" in agent consoles.
# Resolve npm's prefix and prepend its bin to PATH for the rest of this
# script. Also print the export line so the operator can persist it.
if ! command -v proton >/dev/null 2>&1; then
  NPM_BIN="$(npm config get prefix 2>/dev/null)/bin"
  if [ -x "$NPM_BIN/proton" ]; then
    export PATH="$NPM_BIN:$PATH"
    warn "proton was not on PATH after install; prepended $NPM_BIN"
    warn "add this to the operator's shell profile to persist:"
    warn "    export PATH=\"$NPM_BIN:\$PATH\""
  fi
fi

command -v proton >/dev/null 2>&1 || die "proton CLI not callable even after PATH fixup"
ok "proton CLI callable ($(proton --version 2>/dev/null | head -1 || echo 'version unknown'))"

# Make sure the chain is set; this is non-interactive and idempotent.
proton chain:set "${PROTON_CHAIN:-proton}" >/dev/null 2>&1 || true

if [ -n "${XPR_PRIVATE_KEY:-}" ]; then
  say "Step 2 — Non-interactive keychain provisioning (XPR_PRIVATE_KEY is set)"
  warn "the key will be briefly visible in 'ps' while 'proton key:add' runs"
  warn "this script assumes a trusted single-tenant container (Pinata, dedicated VM)"
  warn "do NOT run this path on a shared host"

  # Pre-flight: catch the most common paste failure (whitespace/newlines
  # injected by chat interfaces) before handing the key to proton CLI,
  # whose error message is the unhelpful "invalid base-58 value".
  KEY_TRIMMED="$(printf '%s' "$XPR_PRIVATE_KEY" | tr -d '[:space:]')"
  if [ "$KEY_TRIMMED" != "$XPR_PRIVATE_KEY" ]; then
    warn "XPR_PRIVATE_KEY contained whitespace — stripped for the add call"
    warn "(chat interfaces often inject leading/trailing whitespace or newlines)"
    XPR_PRIVATE_KEY="$KEY_TRIMMED"
  fi
  case "$XPR_PRIVATE_KEY" in
    PVT_K1_*)
      # Length sanity: a PVT_K1 base58 key is ~55 chars total; flag if wildly off.
      KEY_LEN=${#XPR_PRIVATE_KEY}
      if [ "$KEY_LEN" -lt 50 ] || [ "$KEY_LEN" -gt 80 ]; then
        warn "XPR_PRIVATE_KEY length ($KEY_LEN) is outside the expected 50-80 char range"
        warn "proceeding anyway, but proton key:add will likely fail"
      fi
      ;;
    *)
      die "XPR_PRIVATE_KEY does not start with PVT_K1_ — likely wrong format or mangled in transit. Verify the key was pasted intact."
      ;;
  esac

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
    warn "common causes: (1) whitespace/newlines pasted with the key, (2) wrong key, (3) account already registered with this key"
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
