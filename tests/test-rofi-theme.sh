#!/usr/bin/env bash
# Validate config/rofi/config.rasi.
#
# Unlike the other suites this one runs on the host rather than in Docker:
# it only needs rofi's parser, not a provisioned system.
#
# WHY THIS EXISTS
# ---------------
# rofi fails a theme parse *silently*: it exits 0, prints nothing to stderr,
# and simply renders its stock theme (or pops an error dialog the caller never
# sees). The only reliable signal from the command line is that `-dump-theme`
# produces zero bytes. This suite asserts on the dump instead of the exit code.
#
# The specific regression it guards: a `configuration {}` block is only legal
# at the TOP of config.rasi. Placing it after a theme section — even the `*`
# defaults — fails with a parse error pointing at the closing brace of the
# preceding block, which sends you looking in the wrong place entirely.

set -uo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RASI="$DOTFILES_DIR/config/rofi/config.rasi"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
pass=0; fail=0

ok()   { echo -e "  ${GREEN}PASS${NC}  $*"; pass=$((pass + 1)); }
bad()  { echo -e "  ${RED}FAIL${NC}  $*"; fail=$((fail + 1)); }
skip() { echo -e "  ${YELLOW}SKIP${NC}  $*"; }

echo "rofi theme:"

if ! command -v rofi >/dev/null 2>&1; then
    skip "rofi not installed — cannot validate the theme"
    exit 0
fi

if [[ ! -f "$RASI" ]]; then
    bad "config/rofi/config.rasi is missing"
    exit 1
fi

# `configuration` must precede every theme block.
first_block="$(grep -nE '^[[:alnum:]*][^{]*\{' "$RASI" | head -1 | cut -d: -f2-)"
if [[ "$first_block" == configuration* ]]; then
    ok "configuration block comes first"
else
    bad "configuration must be the first block (found: ${first_block%%\{*})"
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/rofi"
cp "$RASI" "$TMP/rofi/config.rasi"

# Load it the way rofi will at runtime, via XDG_CONFIG_HOME. Loading with
# -theme instead would reject the configuration block and report a false error.
dump="$TMP/dump.txt"
XDG_CONFIG_HOME="$TMP" timeout 20 rofi -dump-theme >"$dump" 2>/dev/null

if [[ -s "$dump" ]]; then
    ok "theme parses ($(wc -c <"$dump") bytes resolved)"
else
    bad "theme did not parse (empty dump)"
    echo ""
    echo "Results: $pass passed, $fail failed"
    exit 1
fi

# Assert the palette actually survived resolution, not merely that something
# parsed. rofi normalises colours to 'rgba ( r, g, b, a % )', so grepping for
# the source hex would produce a false failure.
check_value() {
    local needle="$1" what="$2"
    if grep -qi -- "$needle" "$dump"; then
        ok "$what"
    else
        bad "$what (looked for '$needle')"
    fi
}

check_value "157, 124, 216" "accent #9d7cd8 resolved (matches bar + window border)"
check_value "30, 27, 46"    "background #1e1b2e resolved (matches bar)"
check_value "JetBrainsMono" "JetBrainsMono Nerd Font applied"

echo ""
echo "Results: $pass passed, $fail failed"
[[ "$fail" -eq 0 ]] || exit 1
echo "All assertions passed."
