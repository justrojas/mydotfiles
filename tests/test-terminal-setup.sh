#!/bin/bash
# Assertions for terminal-setup.sh
# Run inside a container AFTER terminal-setup.sh has completed.
# Exits non-zero on the first failure and prints what went wrong.

set -euo pipefail

PASS=0
FAIL=0

pass() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); }

assert_symlink() {
    local link="$1" target="$2"
    if [[ ! -L "$link" ]]; then
        fail "$link is not a symlink"
    elif [[ "$(readlink "$link")" != "$target" ]]; then
        fail "$link points to '$(readlink "$link")' — expected '$target'"
    else
        pass "$link -> $target"
    fi
}

assert_dir() {
    local path="$1"
    [[ -d "$path" ]] && pass "directory exists: $path" || fail "directory missing: $path"
}

assert_file() {
    local path="$1"
    [[ -f "$path" ]] && pass "file exists: $path" || fail "file missing: $path"
}

assert_command() {
    local cmd="$1"
    command -v "$cmd" >/dev/null 2>&1 && pass "command available: $cmd" || fail "command not found: $cmd"
}

assert_executable() {
    local path="$1"
    [[ -x "$path" ]] && pass "executable: $path" || fail "not executable: $path"
}

DOTFILES="$HOME/my-dotfiles"

echo ""
echo "======================================"
echo "  terminal-setup.sh assertions"
echo "======================================"
echo ""

# ── tmux ──────────────────────────────────────────────────────────────────────
echo "tmux:"
assert_symlink "$HOME/.tmux.conf"    "$DOTFILES/config/tmux/tmux.conf"
assert_symlink "$HOME/.config/tmux"  "$DOTFILES/config/tmux"
assert_dir     "$HOME/.config/tmux/plugins/tpm"

# ── kitty ─────────────────────────────────────────────────────────────────────
echo "kitty:"
assert_symlink "$HOME/.config/kitty" "$DOTFILES/config/kitty"

# ── neovim / NvChad ───────────────────────────────────────────────────────────
echo "neovim:"
assert_dir  "$HOME/.config/nvim"
assert_file "$HOME/.config/nvim/init.lua"

# ── zsh ───────────────────────────────────────────────────────────────────────
echo "zsh:"
assert_symlink "$HOME/.zshrc" "$DOTFILES/config/zsh/.zshrc"
assert_dir     "$HOME/.oh-my-zsh"
assert_dir     "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
assert_dir     "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"

# ── oh-my-posh ────────────────────────────────────────────────────────────────
echo "oh-my-posh:"
assert_file      "$HOME/.local/bin/oh-my-posh"
assert_executable "$HOME/.local/bin/oh-my-posh"

# ── utility scripts ───────────────────────────────────────────────────────────
echo "utilities:"
assert_symlink "$HOME/.local/bin/kt" "$DOTFILES/scripts/utilities/kt"
assert_executable "$HOME/.local/bin/kt"

# ── summary ───────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
echo ""

[[ $FAIL -eq 0 ]] && echo "All assertions passed." || { echo "Some assertions FAILED."; exit 1; }
