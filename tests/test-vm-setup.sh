#!/bin/bash
# Assertions for vm-setup.sh (the headless / --minimal profile).
# Run inside a container AFTER vm-setup.sh has completed.
#
# This suite asserts two distinct things:
#   1. the shell + editor + multiplexer environment IS present
#   2. the GUI-only components were correctly SKIPPED
# (2) matters as much as (1) — a VM profile that quietly drags in kitty, the
# Nerd fonts and herdr is not a VM profile.

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

assert_dir()  { [[ -d "$1" ]] && pass "dir $1" || fail "missing dir $1"; }
assert_file() { [[ -f "$1" ]] && pass "file $1" || fail "missing file $1"; }

assert_command() {
    if command -v "$1" >/dev/null 2>&1; then pass "command $1"
    else fail "command $1 not found"; fi
}

# Asserts the OPPOSITE — used for the GUI components a VM must not install.
refute_command() {
    if command -v "$1" >/dev/null 2>&1; then
        fail "command $1 should NOT be installed in the VM profile"
    else
        pass "$1 correctly absent"
    fi
}

refute_path() {
    if [[ -e "$1" ]]; then fail "$1 should NOT exist in the VM profile"
    else pass "$1 correctly absent"; fi
}

# The environment under test is what an INTERACTIVE shell gets, not what a
# bare `bash script.sh` inherits. config/shell/env.sh is the single definition
# of that PATH (~/.local/bin, ~/.fzf/bin, ~/go/bin, ...), so source it before
# asserting — otherwise every tool installed to ~/.local/bin reports MISSING
# even though it installed perfectly.
DOTFILES="${DOTFILES:-$HOME/my-dotfiles}"
# shellcheck source=/dev/null
[ -f "$DOTFILES/config/shell/env.sh" ] && . "$DOTFILES/config/shell/env.sh"

echo ""
echo "  vm-setup.sh assertions"
echo ""

# ── shell ─────────────────────────────────────────────────────────────────────
echo "shell:"
assert_symlink "$HOME/.bashrc"       "$DOTFILES/config/bash/.bashrc"
assert_symlink "$HOME/.bash_profile" "$DOTFILES/config/bash/.bash_profile"
assert_symlink "$HOME/.zshrc"        "$DOTFILES/config/zsh/.zshrc"
assert_file    "$HOME/.config/shell/preferred"
if [[ "$(cat "$HOME/.config/shell/preferred" 2>/dev/null)" == "bash" ]]; then
    pass "shell preference is bash"
else
    fail "shell preference is bash (got: $(cat "$HOME/.config/shell/preferred" 2>/dev/null || echo unset))"
fi
if bash -n "$HOME/.bashrc" 2>/dev/null; then pass ".bashrc parses"
else fail ".bashrc parses"; fi

# ── editor + multiplexer ──────────────────────────────────────────────────────
echo "editor / multiplexer:"
assert_command nvim
assert_command tmux
assert_symlink "$HOME/.tmux.conf" "$DOTFILES/config/tmux/tmux.conf"
assert_dir     "$HOME/.config/nvim"

# ── CLI tools the shared aliases depend on ────────────────────────────────────
# config/shell/aliases.sh guards each of these, but the VM profile is supposed
# to actually install them — the guards are a safety net, not the plan.
echo "CLI tools:"
assert_command fzf
assert_command eza
assert_command zoxide
assert_command rg
assert_command git
for c in batcat bat; do
    if command -v "$c" >/dev/null 2>&1; then pass "command $c"; break; fi
    [[ "$c" == bat ]] && fail "neither batcat nor bat found"
done

# ── terminfo tooling ──────────────────────────────────────────────────────────
# Without infocmp/tic the TERM-sanity block in config/shell/env.sh is a no-op,
# which is precisely how you end up with doubled keypresses over SSH.
echo "terminfo:"
assert_command infocmp
assert_command tic

# ── GUI components must be ABSENT ─────────────────────────────────────────────
echo "GUI components correctly skipped:"
refute_command kitty
refute_command herdr
refute_path "$HOME/.config/kitty"
refute_path "$HOME/.config/herdr"
refute_path "$HOME/.local/kitty.app"
# Nerd fonts are rendered by the client terminal, not the VM.
refute_path "$HOME/.local/share/fonts/JetBrainsMonoNerdFontMono-Regular.ttf"

# ── summary ───────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
echo ""

[[ $FAIL -eq 0 ]] && echo "All assertions passed." || { echo "Some assertions FAILED."; exit 1; }
