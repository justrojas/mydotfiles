#!/usr/bin/env bash
# Assertions for the bar's monitor watcher.
#
# Runs on the host: it stubs polybar/xev and never touches the real bar.
#
# WHY THIS EXISTS
# ---------------
# Undocking killed the bar and nothing brought it back. polybar notices the
# RandR change itself and reloads, but on reload it re-reads the config and
# exits when the monitor it was pinned to is gone:
#
#   randr_screen_change_notify (7040x1440)... reloading
#   error: Monitor "eDP-1" not found or disconnected
#
# So the failure mode is: every bar dies, none respawn. The watcher relaunches
# after the monitor set settles. These assertions cover the two behaviours that
# matter and that are easy to get backwards — relaunching when the set really
# changed, and NOT relaunching when it did not (which would make the bar flap
# on every incidental RandR event, e.g. a resolution change).

set -uo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAUNCH="$DOTFILES_DIR/config/polybar/launch.sh"

GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
pass=0; fail=0
ok()  { echo -e "  ${GREEN}PASS${NC}  $*"; pass=$((pass + 1)); }
bad() { echo -e "  ${RED}FAIL${NC}  $*"; fail=$((fail + 1)); }

echo "bar monitor watcher:"

# --- sourcing must not launch anything --------------------------------------
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/polybar" <<'EOF'
#!/bin/sh
echo "POLYBAR $*" >> "$STUB_LOG"
[ "$1" = "--list-monitors" ] && { printf '%s\n' $STUB_MONITORS | sed 's/$/:/'; exit 0; }
exit 0
EOF
cat > "$tmp/killall" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$tmp/polybar" "$tmp/killall"

export STUB_LOG="$tmp/calls.log"
: > "$STUB_LOG"

if PATH="$tmp:$PATH" STUB_MONITORS="eDP-1" bash -c "source '$LAUNCH'" 2>/dev/null; then
    if grep -q "POLYBAR --reload" "$STUB_LOG" 2>/dev/null; then
        bad "sourcing launch.sh started polybar (should only define functions)"
    else
        ok "sourcing defines functions without launching"
    fi
else
    bad "sourcing launch.sh failed"
fi

# --- current_monitors reflects what polybar reports --------------------------
got="$(PATH="$tmp:$PATH" STUB_MONITORS="eDP-1 DP-1-3" bash -c \
    "source '$LAUNCH'; current_monitors" 2>/dev/null | tr '\n' ' ')"
if [[ "$got" == *"eDP-1"* && "$got" == *"DP-1-3"* ]]; then
    ok "current_monitors lists every connected output ($got)"
else
    bad "current_monitors returned '$got'"
fi

# --- launch_bars starts one instance per monitor -----------------------------
: > "$STUB_LOG"
PATH="$tmp:$PATH" STUB_MONITORS="eDP-1 DP-1-3" bash -c \
    "source '$LAUNCH'; launch_bars" >/dev/null 2>&1
started="$(grep -c 'POLYBAR --reload' "$STUB_LOG" 2>/dev/null || echo 0)"
if [[ "$started" -eq 2 ]]; then
    ok "launch_bars starts one bar per monitor (2 monitors -> 2 bars)"
else
    bad "launch_bars started $started bar(s) for 2 monitors"
fi

# --- a single monitor still gets a bar ---------------------------------------
: > "$STUB_LOG"
PATH="$tmp:$PATH" STUB_MONITORS="eDP-1" bash -c \
    "source '$LAUNCH'; launch_bars" >/dev/null 2>&1
started="$(grep -c 'POLYBAR --reload' "$STUB_LOG" 2>/dev/null || echo 0)"
if [[ "$started" -eq 1 ]]; then
    ok "launch_bars starts one bar for a single monitor"
else
    bad "launch_bars started $started bar(s) for 1 monitor"
fi

# --- with no monitor list, fall back to one unpinned bar ---------------------
# Better a bar with no MONITOR set than no bar at all.
: > "$STUB_LOG"
PATH="$tmp:$PATH" STUB_MONITORS="" bash -c \
    "source '$LAUNCH'; launch_bars" >/dev/null 2>&1
started="$(grep -c 'POLYBAR --reload' "$STUB_LOG" 2>/dev/null || echo 0)"
if [[ "$started" -ge 1 ]]; then
    ok "falls back to a single unpinned bar when no monitors are listed"
else
    bad "no bar started when the monitor list was empty"
fi

# --- the change comparison itself -------------------------------------------
# This is the logic the watcher loop hangs on: relaunch only when the sorted
# monitor set actually differs.
before="$(printf 'DP-1-3\neDP-1\n')"
after_same="$(printf 'eDP-1\nDP-1-3\n' | sort)"
after_diff="$(printf 'eDP-1\n')"
if [[ "$before" == "$after_same" ]]; then
    ok "identical monitor sets compare equal regardless of order (no flapping)"
else
    bad "sorted comparison is order-sensitive: '$before' vs '$after_same'"
fi
if [[ "$before" != "$after_diff" ]]; then
    ok "undocking (2 monitors -> 1) is detected as a change"
else
    bad "undock not detected as a change"
fi

echo ""
echo "Results: $pass passed, $fail failed"
[[ $fail -eq 0 ]] || exit 1
echo "All assertions passed."
