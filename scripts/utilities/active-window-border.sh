#!/bin/bash
# active-window-border launcher — start/stop/restart the focus-outline daemon.
#
# Mirrors config/polybar/launch.sh: re-running it replaces any existing
# instance rather than stacking a second daemon on top of the first, so it is
# safe to call from autostart, from a keybinding, and by hand.
#
# Appearance defaults live here (not in the Python) so tweaking the look is a
# one-line edit in a config file rather than a code change.
#
# Usage: active-window-border.sh [start|stop|restart|status]

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DAEMON="$SCRIPT_DIR/active-window-border.py"

# Where the running PID is recorded. Pattern-matching with `pkill -f` is
# deliberately avoided: the daemon's path appears in the command line of any
# shell that launched it, so a -f match can kill the caller's own shell.
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
PIDFILE="$RUNTIME_DIR/active-window-border.pid"

# --- appearance -------------------------------------------------------------
# Purple matching the polybar accent, rgb(157,124,216).
COLOR="${AWB_COLOR:-9d7cd8}"
WIDTH="${AWB_WIDTH:-3}"
RADIUS="${AWB_RADIUS:-8}"
GAP="${AWB_GAP:-0}"
ALPHA="${AWB_ALPHA:-1.0}"
INTERVAL="${AWB_INTERVAL:-40}"
# inset draws the ring just inside the window edge, which stays visible no
# matter how the windows are tiled. outset draws it outside the frame and
# needs Bismuth gaps (Script-bismuth/tileLayoutGap) to have somewhere to go.
MODE="${AWB_MODE:-inset}"

is_running() {
    [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null
}

stop_daemon() {
    if is_running; then
        kill "$(cat "$PIDFILE")" 2>/dev/null
        # Give it a moment to unmap its window before a restart maps a new one.
        for _ in 1 2 3 4 5 6 7 8 9 10; do
            is_running || break
            sleep 0.1
        done
        is_running && kill -9 "$(cat "$PIDFILE")" 2>/dev/null
        echo "active-window-border: stopped"
    else
        echo "active-window-border: not running"
    fi
    rm -f "$PIDFILE"
}

start_daemon() {
    if [[ ! -x "$DAEMON" ]]; then
        echo "active-window-border: daemon not executable at $DAEMON" >&2
        exit 1
    fi
    if [[ -z "${DISPLAY:-}" ]]; then
        echo "active-window-border: \$DISPLAY unset — X11 session required" >&2
        exit 1
    fi

    setsid "$DAEMON" \
        --color "$COLOR" \
        --width "$WIDTH" \
        --radius "$RADIUS" \
        --gap "$GAP" \
        --alpha "$ALPHA" \
        --interval "$INTERVAL" \
        --mode "$MODE" \
        >/dev/null 2>&1 &

    echo $! > "$PIDFILE"
    echo "active-window-border: started (pid $(cat "$PIDFILE"), #$COLOR, ${WIDTH}px, $MODE)"
}

case "${1:-restart}" in
    start)
        is_running && { echo "active-window-border: already running (pid $(cat "$PIDFILE"))"; exit 0; }
        start_daemon
        ;;
    stop)
        stop_daemon
        ;;
    restart)
        stop_daemon >/dev/null
        start_daemon
        ;;
    status)
        if is_running; then
            echo "active-window-border: running (pid $(cat "$PIDFILE"))"
        else
            echo "active-window-border: not running"
            exit 1
        fi
        ;;
    *)
        echo "Usage: $(basename "$0") [start|stop|restart|status]" >&2
        exit 1
        ;;
esac
