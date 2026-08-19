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
#
# Usage:
#   bar            launch one bar per connected monitor, once
#   bar --watch    same, then stay resident and relaunch whenever the set of
#                  connected monitors changes (dock / undock / hotplug)
#
# WHY --watch EXISTS
# ------------------
# polybar is started once per monitor with MONITOR=<name> baked in. It does
# notice RandR changes on its own and reloads — but on reload it re-reads the
# config and exits if the monitor it was pinned to is gone:
#
#   randr_screen_change_notify (7040x1440)... reloading
#   error: Monitor "eDP-1" not found or disconnected
#
# Undocking produces exactly that: a burst of RandR events during which
# outputs briefly vanish. Every bar dies and nothing respawns them, so the bar
# disappears until you run this script by hand. --watch re-runs the whole
# launch after the monitor set settles.

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

# (Stopping existing instances is handled by launch_bars, which also runs on
# every monitor change in --watch mode.)

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
current_monitors() {
    if command -v polybar >/dev/null 2>&1 && polybar --list-monitors >/dev/null 2>&1; then
        polybar --list-monitors | cut -d: -f1 | sort
    fi
}

launch_bars() {
    # Stop any running instances and wait for them to actually die, otherwise
    # the new ones fight the old ones for the same strut.
    killall -q polybar 2>/dev/null
    for _ in $(seq 1 20); do
        pgrep -x polybar >/dev/null || break
        sleep 0.1
    done

    local monitors
    monitors="$(current_monitors)"

    local log="${XDG_CACHE_HOME:-$HOME/.cache}/polybar.log"
    mkdir -p "$(dirname "$log")"
    : > "$log"

    if [ -n "$monitors" ]; then
        while IFS= read -r m; do
            [ -z "$m" ] && continue
            MONITOR="$m" polybar --reload -c "$CONFIG" main >>"$log" 2>&1 &
        done <<< "$monitors"
        echo "polybar launched on: $(echo "$monitors" | tr '\n' ' ')(log: $log)"
    else
        # No monitor list available (polybar too old, or X not ready). One
        # unpinned bar is better than none.
        polybar --reload -c "$CONFIG" main >>"$log" 2>&1 &
        echo "polybar launched (no monitor list; log: $log)"
    fi
}

# --- Watch for monitor changes ---------------------------------------------
#
# Event-driven via `xev -root -event randr` rather than polling: a dock or
# undock is a burst of events, and polling either misses the settle point or
# wastes wakeups forever.
#
# The debounce matters. During an undock, outputs disappear and reappear over
# roughly a second; relaunching on the first event pins bars to monitors that
# are about to vanish, which is the original bug. Wait for quiet, then compare.
watch_monitors() {
    local known settle
    known="$(current_monitors)"

    if ! command -v xev >/dev/null 2>&1; then
        # Fallback: poll. Cheaper to write than to require x11-utils.
        echo "bar --watch: xev not found, falling back to polling every 5s" >&2
        while sleep 5; do
            local now; now="$(current_monitors)"
            if [ "$now" != "$known" ]; then
                known="$now"
                echo "bar --watch: monitors changed -> relaunching"
                launch_bars
            fi
        done
        return
    fi

    echo "bar --watch: watching for monitor changes (xev)"
    # shellcheck disable=SC2016
    xev -root -event randr 2>/dev/null | while IFS= read -r line; do
        case "$line" in
            *RRScreenChangeNotify*|*RRNotify*) ;;
            *) continue ;;
        esac

        # Drain the burst: keep reading with a short timeout until quiet.
        settle=0
        while [ "$settle" -lt 12 ]; do
            if read -r -t 0.5 _; then
                settle=0            # still arriving, keep waiting
            else
                settle=$((settle + 1))
                [ "$settle" -ge 2 ] && break
            fi
        done

        local now
        now="$(current_monitors)"
        if [ "$now" != "$known" ]; then
            known="$now"
            echo "bar --watch: monitors changed -> $(echo "$now" | tr '\n' ' ')"
            launch_bars
        fi
    done
}

# Only act when executed. Sourcing defines the functions without launching
# anything, which is what tests/test-bar-watch.sh relies on.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    launch_bars
    if [ "${1:-}" = "--watch" ]; then
        watch_monitors
    fi
fi
