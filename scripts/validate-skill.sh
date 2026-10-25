#!/bin/bash
# XPR Network Developer Skill Validation Script
# Run this to check for common issues before publishing updates

set -e

SKILL_DIR="$(dirname "$0")/../skill"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# Everything an agent or operator might read or run; node_modules and .git are never scanned.
REPO_SCAN=("$REPO_DIR/skill" "$REPO_DIR/README.md" "$REPO_DIR/agent-bootstrap.md" "$REPO_DIR/SECURITY.md" "$REPO_DIR/scripts" "$REPO_DIR/install.sh")
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "XPR Network Developer Skill Validator"
echo "=========================================="
echo ""

ERRORS=0
WARNINGS=0

# Helper functions
pass() { echo -e "${GREEN}✓${NC} $1"; }
fail() { echo -e "${RED}✗${NC} $1"; ERRORS=$((ERRORS+1)); }
warn() { echo -e "${YELLOW}⚠${NC} $1"; WARNINGS=$((WARNINGS+1)); }

# 1. Check YAML frontmatter
echo "1. Checking SKILL.md frontmatter..."
if head -1 "$SKILL_DIR/SKILL.md" | grep -q "^---$"; then
    pass "SKILL.md has YAML frontmatter"
else
    fail "SKILL.md missing YAML frontmatter (must start with ---)"
fi
echo ""

# 2. Check npm packages exist
echo "2. Verifying npm packages..."
PACKAGES=("@proton/cli" "@proton/js" "@proton/web-sdk" "proton-tsc" "@proton/vert" "@xpr-agents/openclaw" "@xpr-agents/sdk")
for pkg in "${PACKAGES[@]}"; do
    if npm view "$pkg" version &>/dev/null; then
        VERSION=$(npm view "$pkg" version 2>/dev/null)
        pass "$pkg ($VERSION)"
    else
        fail "$pkg NOT FOUND on npm"
    fi
done
echo ""

# 3. Check contract accounts exist on mainnet
echo "3. Verifying contract accounts on mainnet..."
CONTRACTS=("eosio.token" "eosio.proton" "xtokens" "oracles" "rng" "dex" "loan.token" "atomicassets")
for contract in "${CONTRACTS[@]}"; do
    RESULT=$(curl -sf "https://proton.eosusa.io/v1/chain/get_account" -d "{\"account_name\":\"$contract\"}" 2>/dev/null | grep -o '"account_name"' || echo "")
    if [ -n "$RESULT" ]; then
        pass "$contract"
    else
        fail "$contract NOT FOUND on mainnet"
    fi
done
echo ""

# 4. Check key URLs are reachable
echo "4. Checking key URLs..."
URLS=(
    "https://docs.xprnetwork.org"
    "https://explorer.xprnetwork.org"
    "https://resources.xprnetwork.org"
    "https://proton.eosusa.io/v1/chain/get_info"
    "https://api.protonnz.com/v1/chain/get_info"
    "https://tn1.protonnz.com/v1/chain/get_info"
    "https://lightapi.eosamsterdam.net/api/account/proton/eosio"
    "https://dex.api.mainnet.metalx.com/dex/v1/markets/all"
)
for url in "${URLS[@]}"; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null) || HTTP_CODE="000"
    if [ "$HTTP_CODE" = "200" ]; then
        pass "$url"
    else
        fail "$url (HTTP $HTTP_CODE)"
    fi
done
echo ""

# 5. Check for leaked private keys
echo "5. Checking for leaked private keys..."
# Real private keys (PVT_K1_ followed by valid base58)
REAL_KEYS=$(grep -rE "PVT_K1_[1-9A-HJ-NP-Za-km-z]{40,}" "${REPO_SCAN[@]}" --include="*.md" --include="*.sh" 2>/dev/null | grep -v "xxxxx" | grep -v "PVT_K1_oldkey" || echo "")
if [ -z "$REAL_KEYS" ]; then
    pass "No real private keys found"
else
    fail "POSSIBLE PRIVATE KEY LEAK:"
    echo "$REAL_KEYS"
fi

# Legacy WIF format (5 + H/J/K + base58)
WIF_KEYS=$(grep -rE "5[HJK][1-9A-HJ-NP-Za-km-z]{49,50}" "${REPO_SCAN[@]}" --include="*.md" --include="*.sh" 2>/dev/null || echo "")
if [ -z "$WIF_KEYS" ]; then
    pass "No WIF private keys found"
else
    fail "POSSIBLE WIF PRIVATE KEY LEAK:"
    echo "$WIF_KEYS"
fi
echo ""

# 6. Check for personal account references
echo "6. Checking for personal account leaks..."
PERSONAL=$(grep -riE "paulgnz|paulgrey" "${REPO_SCAN[@]}" --include="*.md" --include="*.sh" 2>/dev/null | grep -v 'scripts/validate-skill.sh:' || echo "")
if [ -z "$PERSONAL" ]; then
    pass "No personal account references"
else
    warn "Personal account references found:"
    echo "$PERSONAL"
fi
echo ""

# 7. Check for outdated references (exclude "formerly" historical context)
echo "7. Checking for outdated references..."
PROTONSCAN=$(grep -ri "protonscan.io" "$SKILL_DIR" --include="*.md" | grep -v "formerly" || echo "")
if [ -z "$PROTONSCAN" ]; then
    pass "No active protonscan.io references"
else
    fail "Found protonscan.io references (should be explorer.xprnetwork.org):"
    echo "$PROTONSCAN"
fi

BLOKS=$(grep -ri "proton.bloks.io" "$SKILL_DIR" --include="*.md" | grep -v "formerly" || echo "")
if [ -z "$BLOKS" ]; then
    pass "No active proton.bloks.io references"
else
    fail "Found proton.bloks.io references (should be explorer.xprnetwork.org):"
    echo "$BLOKS"
fi
echo ""

# 8. Check MetalX API endpoints have /v1/
echo "8. Checking MetalX API endpoints..."
BAD_METALX=$(grep -rE "metalx.com/dex/(markets|balances|orders|trades|orderbook|ticker)" "$SKILL_DIR" --include="*.md" || echo "")
if [ -z "$BAD_METALX" ]; then
    pass "All MetalX endpoints use /dex/v1/ prefix"
else
    fail "MetalX endpoints missing /v1/ prefix:"
    echo "$BAD_METALX"
fi
echo ""

# 9. Liquidation how-to must stay out (policy since 2.11.0 — see safety-guidelines.md → Network Etiquette)
echo "9. Checking for liquidation how-to content..."
LIQ=$(grep -rnE 'memo":"liquidate|getLiquidatableBorrows|@action\("liquidate"\)|scanliq' "$SKILL_DIR" --include="*.md" || echo "")
if [ -z "$LIQ" ]; then
    pass "No liquidation how-to content"
else
    fail "Liquidation how-to content found (deliberately out of scope):"
    echo "$LIQ"
fi
echo ""

# 10. Policy blocks must stay in the entry file (an agent reads SKILL.md first)
echo "10. Checking skill-wide policy blocks..."
POLICY_COUNT=$(grep -c 'applies skill-wide' "$SKILL_DIR/SKILL.md" || true)
if [ "$POLICY_COUNT" -ge 2 ] && grep -q 'AI-generated contract code' "$SKILL_DIR/SKILL.md" \
   && grep -q '^## Network Etiquette: Do Not Spam the Chain' "$SKILL_DIR/safety-guidelines.md" \
   && grep -q 'must decline' "$SKILL_DIR/safety-guidelines.md"; then
    pass "SKILL.md policy blocks and Network Etiquette section present"
else
    fail "A skill-wide policy block (keychain / AI-generated code / Network Etiquette) is missing or weakened"
fi
echo ""

# 11. Reporting goes through GitHub issues only; no email anywhere (the old address was spammed)
echo "11. Checking for email or non-issue reporting channels..."
EMAILS=$(grep -rnE 'mailto:|[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+\.(com|org|io|net|dev|nz|co|xyz)\b' "${REPO_SCAN[@]}" --include="*.md" --include="*.sh" 2>/dev/null \
    | grep -v 'scripts/validate-skill.sh:' \
    | grep -vE '@proton/|@xpr-agents/|@eosrio/|@types/|@wharfkit/|@shellbook/|@greymass/|@openclaw/' || echo "")
if [ -z "$EMAILS" ]; then
    pass "No email addresses or mailto links"
else
    fail "Email or mailto found (reporting is GitHub issues only):"
    echo "$EMAILS"
fi
echo ""

# 12. Spam-shaped sample code (see safety-guidelines.md → Network Etiquette rules 2, 3, 7, 11)
echo "12. Checking for spam-shaped sample code..."
SPAM=$(grep -rnE 'nonce["'"'"']?[[:space:]]*:[[:space:]]*(Date\.now|Math\.random)|setInterval\([^)]*(transact|push|sendTransaction|\.action)|RateLimiter\([0-9]+,[[:space:]]*(1000|500|250|100)\)|Add unique data|NOT rate-limited|not rate-limited on-chain|use memo-based swap|MAX_TPS=' "$SKILL_DIR" --include="*.md" || echo "")
if [ -z "$SPAM" ]; then
    pass "No nonce de-duplication, sub-second limiters, timer-driven signing, or cooldown-bypass wording"
else
    fail "Spam-shaped sample code or advice found:"
    echo "$SPAM"
fi
echo ""

# 13. Key and bind hygiene across the repo
echo "13. Checking key handling and network binds..."
HYGIENE=$(grep -rnE 'curl[^|]*\|[[:space:]]*(sudo[[:space:]]+)?(ba)?sh\b|key:(add|remove)[[:space:]]+PVT_K1_|keychain is encrypted|encrypted by default|encrypted keychain|(http-server-address|state-history-endpoint)[[:space:]]*=[[:space:]]*0\.0\.0\.0' "${REPO_SCAN[@]}" --include="*.md" --include="*.sh" 2>/dev/null \
    | grep -v 'scripts/validate-skill.sh:' \
    | grep -viE 'never|do not|don.t|\bNOT\b|instead of|avoid|wrong|hygiene' || echo "")
if [ -z "$HYGIENE" ]; then
    pass "No curl|bash, no key on a key:add command line, no 'encrypted keychain' claim, no 0.0.0.0 API/SHIP bind"
else
    fail "Key-handling or bind hygiene problem:"
    echo "$HYGIENE"
fi
echo ""

# 14. Warning-level sweeps: liquidation wording outside the files allowed to carry the stub, account/faucet loops
echo "14. Sweeping for liquidation wording and account-farming loops..."
LIQ_WIDE=$(grep -rniE '\bliquidat(e|ion|ions|or|ors|able)\b' "$SKILL_DIR" --include="*.md" \
    | grep -vE 'loan-protocol\.md|defi-trading\.md|safety-guidelines\.md|SKILL\.md|metalx-dex\.md|xpr-agents\.md' || echo "")
if [ -z "$LIQ_WIDE" ]; then
    pass "No liquidation wording outside the allowed files"
else
    warn "Liquidation wording outside the allowed files (check it is a refusal, not a how-to):"
    echo "$LIQ_WIDE"
fi
FARM=$(grep -rnE '(for |while |xargs|seq |forEach|\.map\().{0,80}(create-funded|faucet:claim|newaccount)|(create-funded|faucet:claim|newaccount).{0,80}(for |while |xargs|seq |forEach|\.map\()' "$SKILL_DIR" --include="*.md" || echo "")
if [ -z "$FARM" ]; then
    pass "No loops around account creation or faucet claims"
else
    warn "Loop around account creation or faucet claims (rule 8):"
    echo "$FARM"
fi
echo ""

# 15. List all skill files
echo "15. Skill files for manual review:"
echo "-----------------------------------"
find "$SKILL_DIR" -name "*.md" -type f | sort | while read -r file; do
    LINES=$(wc -l < "$file")
    echo "  $(basename "$file") ($LINES lines)"
done
echo ""

# Summary
echo "=========================================="
echo "VALIDATION SUMMARY"
echo "=========================================="
if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}All checks passed!${NC}"
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}Passed with $WARNINGS warning(s)${NC}"
else
    echo -e "${RED}Failed with $ERRORS error(s) and $WARNINGS warning(s)${NC}"
fi
echo ""

exit $ERRORS
