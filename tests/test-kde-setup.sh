#!/bin/bash
# Assertions for kde-setup.sh --config-only.
# Run inside a container AFTER kde-setup.sh --config-only has completed.
#
# SCOPE — what this suite does and does NOT cover.
#
# It covers the config-wiring half of the profile: the steps that copy this
# repo's own files into $HOME (touchegg, Kvantum, Firefox userChrome, global
# shortcuts) plus the fonts. Those are the steps that were dead weight until
# recently — 704 KB of config that no code path touched — so they are exactly
# the ones worth regression-testing.
#
# It does NOT cover setup_repositories, install_packages,
# install_binary_packages or install_ant_dark_theme. Those need the Papirus
# PPA, ~2GB of KDE packages, a working dpkg for the vendored .debs and a clone
# of EliverLara/Ant. Exercising them in CI would take tens of minutes to prove
# that `apt install` works. --config-only exists precisely to draw that line.
#
# Consequence to keep in mind: a break in the apt/theme half will NOT be caught
# here.

set -euo pipefail

PASS=0
FAIL=0

pass() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); }

assert_file() { [[ -f "$1" ]] && pass "file $1" || fail "missing file $1"; }
assert_dir()  { [[ -d "$1" ]] && pass "dir $1"  || fail "missing dir $1"; }

assert_contains() {
    local file="$1" needle="$2"
    if [[ ! -f "$file" ]]; then
        fail "$file missing (looking for '$needle')"
    elif grep -qF "$needle" "$file"; then
        pass "$file contains '$needle'"
    else
        fail "$file does NOT contain '$needle'"
    fi
}

DOTFILES="${DOTFILES:-$HOME/my-dotfiles}"

echo ""
echo "======================================"
echo "  kde-setup.sh --config-only assertions"
echo "======================================"
echo ""

# ── Touchegg ──────────────────────────────────────────────────────────────────
echo "touchegg:"
assert_dir  "$HOME/.config/touchegg"
assert_file "$HOME/.config/touchegg/touchegg.conf"
# The runtime lock file used to be tracked in git and copied out to every
# machine. Assert it does NOT come along.
if [[ -e "$HOME/.config/touchegg/.touchegg:0.lock" ]]; then
    fail "stale .touchegg:0.lock was copied into ~/.config/touchegg"
else
    pass "no stale touchegg lock file"
fi

# ── Kvantum ───────────────────────────────────────────────────────────────────
# The engine is apt-installed by install_packages, but the THEME and the
# kvantum.kvconfig that selects it live in this repo. Installing the engine
# alone leaves you on the default theme — that was the actual bug.
echo "kvantum:"
assert_dir  "$HOME/.config/Kvantum"
assert_dir  "$HOME/.config/Kvantum/Ant-Dark"
assert_file "$HOME/.config/Kvantum/Ant-Dark/Ant-Dark.kvconfig"
assert_file "$HOME/.config/Kvantum/Ant-Dark/Ant-Dark.svg"
assert_file "$HOME/.config/Kvantum/kvantum.kvconfig"
assert_contains "$HOME/.config/Kvantum/kvantum.kvconfig" "theme=Ant-Dark"

# ── Firefox userChrome ────────────────────────────────────────────────────────
# Two things are required and it is easy to do only one: the CSS must land in
# <profile>/chrome/, AND the legacy-stylesheets pref must be enabled or Firefox
# ignores the whole directory. Assert both.
echo "firefox:"
FF_PROFILE_DIR=""
if [[ -f "$HOME/.mozilla/firefox/profiles.ini" ]]; then
    for d in "$HOME"/.mozilla/firefox/*.default*; do
        [[ -d "$d" ]] && FF_PROFILE_DIR="$d" && break
    done
fi

if [[ -z "$FF_PROFILE_DIR" ]]; then
    fail "no Firefox profile found (test fixture should have created one)"
else
    pass "resolved Firefox profile: $(basename "$FF_PROFILE_DIR")"
    assert_dir  "$FF_PROFILE_DIR/chrome"
    assert_file "$FF_PROFILE_DIR/chrome/userChrome.css"
    assert_contains "$FF_PROFILE_DIR/user.js" "legacyUserProfileCustomizations"
fi

# ── Global shortcuts ──────────────────────────────────────────────────────────
# Merged key-by-key with kwriteconfig5 rather than copied wholesale, so that
# local bindings absent from the scheme survive. Assert both halves of that.
echo "shortcuts:"
KGS="$HOME/.config/kglobalshortcutsrc"
if command -v kwriteconfig5 >/dev/null 2>&1; then
    assert_file "$KGS"
    # A group+key that exists in config/kde/shortcuts/global-shortcuts.kksrc.
    assert_contains "$KGS" "[ActivityManager]"
    # The pre-existing sentinel written by the fixture BEFORE the import must
    # survive — that is what distinguishes a merge from an overwrite.
    assert_contains "$KGS" "SENTINEL_PRESERVED"
    # spotify_tools was deleted; its shortcut must not reappear.
    if grep -qF "spotify_like" "$KGS" 2>/dev/null; then
        fail "dangling spotify_like shortcut was imported"
    else
        pass "no dangling spotify_like shortcut"
    fi
else
    echo "  SKIP  kwriteconfig5 not installed — shortcut import not exercised"
fi

# ── Fonts ─────────────────────────────────────────────────────────────────────
echo "fonts:"
FONT_DIR="/usr/share/fonts/truetype/jetbrains-mono-nerd"
assert_dir "$FONT_DIR"
assert_file "$FONT_DIR/JetBrainsMonoNerdFontMono-Regular.ttf"
# install_fonts copies only .ttf/.otf; README.md and LICENSE.md must not follow.
if [[ -e "$FONT_DIR/README.md" || -e "$FONT_DIR/LICENSE.md" ]]; then
    fail "non-font files were copied into $FONT_DIR"
else
    pass "only font files copied (no README/LICENSE)"
fi

# ── Steps that must NOT have run under --config-only ──────────────────────────
# If these appear, --config-only is not actually gating the heavy steps and CI
# would start pulling 2GB of KDE packages.
echo "--config-only correctly skipped heavy steps:"
if [[ -f /etc/apt/sources.list.d/papirus-ppa.list ]]; then
    fail "Papirus PPA was added despite --config-only"
else
    pass "Papirus PPA not added"
fi
if [[ -d "$HOME/Downloads/Ant" ]]; then
    fail "Ant theme repo was cloned despite --config-only"
else
    pass "Ant theme repo not cloned"
fi

# ── summary ───────────────────────────────────────────────────────────────────
echo ""
echo "Results: $PASS passed, $FAIL failed"
echo ""

[[ $FAIL -eq 0 ]] && echo "All assertions passed." || { echo "Some assertions FAILED."; exit 1; }
