#!/usr/bin/env bash
# Launch polybar — one bar per connected monitor, with hardware-specific
# values detected at runtime instead of hardcoded in config.ini.
#
# Two things a static polybar config always gets wrong:
#   • the network interface name (wlp3s0 / wlan0 / enp0s31f6 / ...)
#   • the battery + adapter names (BAT0/BAT1, AC/ADP1/ACAD)
# We probe for them here and pass them in as environment variables, which
# config.ini picks up through polybar's ${env:VAR:fallback} syntax.
#
# Installed to ~/.local/bin/bar by profiles/bar-setup.sh.

set -uo pipefail

CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/polybar/config.ini"

if ! command -v polybar >/dev/null 2>&1; then
    echo "polybar is not installed. Run: bash profiles/bar-setup.sh" >&2
    exit 1
fi

if [ ! -f "$CONFIG" ]; then
    echo "polybar config not found at $CONFIG" >&2
    exit 1
fi

# --- Stop any running instances and wait for them to actually die -----------
killall -q polybar 2>/dev/null
for _ in $(seq 1 20); do
    pgrep -x polybar >/dev/null || break
    sleep 0.1
done

# --- Detect the wireless (or failing that, wired) interface ----------------
detect_iface() {
    local i
    for i in /sys/class/net/*; do
        [ -e "$i/wireless" ] && { basename "$i"; return; }
    done
    for i in /sys/class/net/*; do
        case "$(basename "$i")" in lo|docker*|veth*|br-*|virbr*) continue ;; esac
        [ "$(cat "$i/operstate" 2>/dev/null)" = "up" ] && { basename "$i"; return; }
    done
}

detect_battery() {
    local b
    for b in /sys/class/power_supply/BAT*; do
        [ -e "$b" ] && { basename "$b"; return; }
    done
}

detect_adapter() {
    local a
    for a in /sys/class/power_supply/*; do
        [ -e "$a/type" ] || continue
        [ "$(cat "$a/type" 2>/dev/null)" = "Mains" ] && { basename "$a"; return; }
    done
}

NET_IFACE="$(detect_iface)"
BATTERY="$(detect_battery)"
ADAPTER="$(detect_adapter)"

export NET_IFACE BATTERY ADAPTER

[ -z "$NET_IFACE" ] && echo "launch.sh: no network interface detected — network module will show 'off'" >&2
[ -z "$BATTERY"   ] && echo "launch.sh: no battery detected (desktop?) — battery module will be inactive" >&2

# --- One bar per connected monitor -----------------------------------------
if command -v polybar >/dev/null 2>&1 && polybar --list-monitors >/dev/null 2>&1; then
    MONITORS="$(polybar --list-monitors | cut -d: -f1)"
else
    MONITORS=""
fi

LOG="${XDG_CACHE_HOME:-$HOME/.cache}/polybar.log"
mkdir -p "$(dirname "$LOG")"
: > "$LOG"

if [ -n "$MONITORS" ]; then
    while IFS= read -r m; do
        [ -z "$m" ] && continue
        MONITOR="$m" polybar --reload -c "$CONFIG" main >>"$LOG" 2>&1 &
    done <<< "$MONITORS"
else
    polybar --reload -c "$CONFIG" main >>"$LOG" 2>&1 &
fi

echo "polybar launched (log: $LOG)"
