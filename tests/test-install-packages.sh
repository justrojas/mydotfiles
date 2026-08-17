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
DOTFILES="${DOTFILES:-$HOME/my-dotfiles}"

# The environment under test is what an INTERACTIVE shell gets, not what a bare
# `bash script.sh` inherits. config/shell/env.sh is the single definition of
# that PATH (~/.local/bin, ~/.fzf/bin, ...), so source it before asserting.
#
# Without this, every tool installed to ~/.local/bin — zoxide, nvim, kitty —
# reports "command not found" despite having installed perfectly. Only tools
# landing in /usr/bin (eza, glow) passed.
# shellcheck source=/dev/null
[ -f "$DOTFILES/config/shell/env.sh" ] && . "$DOTFILES/config/shell/env.sh"

# Accept any one of several binary names — package name != binary name is the
# norm on Debian (bat -> batcat, fd-find -> fdfind, imagemagick -> convert).
assert_any_command() {
    local label="$1"; shift
    local c
    for c in "$@"; do
        if command -v "$c" >/dev/null 2>&1; then
            pass "command available: $label ($(command -v "$c"))"
            return
        fi
    done
    fail "command not found: $label (tried: $*)"
}

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
assert_any_command "bat" batcat bat
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

# ── kitty ─────────────────────────────────────────────────────────────────────
# Installed by lib/installers.sh into ~/.local/bin; previously unasserted, so a
# broken kitty install would have gone unnoticed by this suite.
echo "kitty:"
assert_command kitty

# ── neovim ────────────────────────────────────────────────────────────────────
echo "neovim:"
assert_command nvim

# ── summary ───────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
echo ""

[[ $FAIL -eq 0 ]] && echo "All assertions passed." || { echo "Some assertions FAILED."; exit 1; }
