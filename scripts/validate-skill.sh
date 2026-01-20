#!/bin/bash
# XPR Network Developer Skill Validation Script
# Run this to check for common issues before publishing updates

set -e

SKILL_DIR="$(dirname "$0")/../skill"
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
fail() { echo -e "${RED}✗${NC} $1"; ((ERRORS++)); }
warn() { echo -e "${YELLOW}⚠${NC} $1"; ((WARNINGS++)); }

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
PACKAGES=("@proton/cli" "@proton/js" "@proton/web-sdk" "proton-tsc" "@proton/vert")
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
    HTTP_CODE=$(curl -sf -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
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
REAL_KEYS=$(grep -rE "PVT_K1_[1-9A-HJ-NP-Za-km-z]{40,}" "$SKILL_DIR" --include="*.md" | grep -v "xxxxx" | grep -v "PVT_K1_oldkey" || echo "")
if [ -z "$REAL_KEYS" ]; then
    pass "No real private keys found"
else
    fail "POSSIBLE PRIVATE KEY LEAK:"
    echo "$REAL_KEYS"
fi

# Legacy WIF format (5 + H/J/K + base58)
WIF_KEYS=$(grep -rE "5[HJK][1-9A-HJ-NP-Za-km-z]{49,50}" "$SKILL_DIR" --include="*.md" || echo "")
if [ -z "$WIF_KEYS" ]; then
    pass "No WIF private keys found"
else
    fail "POSSIBLE WIF PRIVATE KEY LEAK:"
    echo "$WIF_KEYS"
fi
echo ""

# 6. Check for personal account references
echo "6. Checking for personal account leaks..."
PERSONAL=$(grep -riE "paulgnz|paulgrey" "$SKILL_DIR" --include="*.md" || echo "")
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

# 9. List all skill files
echo "9. Skill files for manual review:"
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
