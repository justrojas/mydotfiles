#!/bin/bash
# Assertions for install-packages.sh
# Run inside a container AFTER install-packages.sh has completed.
# Exits non-zero on the first failure and prints what went wrong.

set -euo pipefail

PASS=0
FAIL=0

pass() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); }

assert_command() {
    local cmd="$1"
    command -v "$cmd" >/dev/null 2>&1 && pass "command available: $cmd" || fail "command not found: $cmd"
}

echo ""
echo "======================================"
echo "  install-packages.sh assertions"
echo "======================================"
echo ""

# ── core apt packages ─────────────────────────────────────────────────────────
echo "core packages:"
assert_command git
assert_command curl
assert_command wget
assert_command zsh
assert_command tmux
assert_command fzf
assert_command bat
assert_command btop
assert_command vim
assert_command python3
assert_command node
assert_command npm
assert_command gpg

# ── third-party packages ──────────────────────────────────────────────────────
echo "third-party packages:"
assert_command eza
assert_command glow
assert_command zoxide

# ── neovim ────────────────────────────────────────────────────────────────────
echo "neovim:"
assert_command nvim

# ── summary ───────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
echo ""

[[ $FAIL -eq 0 ]] && echo "All assertions passed." || { echo "Some assertions FAILED."; exit 1; }
