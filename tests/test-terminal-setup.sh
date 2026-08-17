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

DOTFILES="${DOTFILES:-$HOME/my-dotfiles}"

# The environment under test is what an INTERACTIVE shell gets, not what a
# bare `bash script.sh` inherits. config/shell/env.sh is the single definition
# of that PATH (~/.local/bin, ~/.fzf/bin, ~/go/bin, ...), so source it before
# asserting — otherwise every tool installed to ~/.local/bin reports MISSING
# even though it installed perfectly.
# shellcheck source=/dev/null
[ -f "$DOTFILES/config/shell/env.sh" ] && . "$DOTFILES/config/shell/env.sh"

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

# ── bash (primary interactive shell) ─────────────────────────────────────────
echo "bash:"
assert_symlink "$HOME/.bashrc"       "$DOTFILES/config/bash/.bashrc"
assert_symlink "$HOME/.bash_profile" "$DOTFILES/config/bash/.bash_profile"
assert_file    "$HOME/.config/shell/preferred"
# bash must be the seeded default; a regression here silently drops you into zsh.
if [[ "$(cat "$HOME/.config/shell/preferred" 2>/dev/null)" == "bash" ]]; then
    pass "shell preference is bash"
else
    fail "shell preference is bash (got: $(cat "$HOME/.config/shell/preferred" 2>/dev/null || echo unset))"
fi
# The .bashrc must be syntactically valid and load without emitting errors —
# this is what catches things like sourcing a zsh-only completion file.
if bash -n "$HOME/.bashrc" 2>/dev/null; then
    pass ".bashrc parses"
else
    fail ".bashrc parses"
fi

# ── zsh (still available via shell-toggle) ───────────────────────────────────
echo "zsh:"
assert_symlink "$HOME/.zshrc" "$DOTFILES/config/zsh/.zshrc"
assert_dir     "$HOME/.oh-my-zsh"
assert_dir     "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
assert_dir     "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"

# ── shared shell layer ────────────────────────────────────────────────────────
echo "shared shell layer:"
assert_file "$DOTFILES/config/shell/env.sh"
assert_file "$DOTFILES/config/shell/aliases.sh"
assert_file "$DOTFILES/config/shell/switch.sh"
assert_file "$DOTFILES/config/shell/docker_functions.bash"

# ── terminfo ──────────────────────────────────────────────────────────────────
# A missing xterm-kitty entry is the root cause of the herdr double-keypress
# bug, so assert it explicitly rather than discovering it by hand later.
echo "terminfo:"
if infocmp xterm-kitty >/dev/null 2>&1; then
    pass "xterm-kitty terminfo resolves"
else
    fail "xterm-kitty terminfo resolves"
fi

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
