#!/usr/bin/env bash
# Taskbar module for polybar — lists the windows on the CURRENT virtual desktop,
# the way the KDE Plasma "Task Manager" widget does.
#
# WHY THIS EXISTS
# ---------------
# polybar has no window-list module. `internal/xworkspaces` shows desktop
# names/numbers, and `internal/xwindow` shows only the *active* window title.
# Neither answers "what is on this desktop", which is what a Plasma panel shows.
# So we build it from wmctrl.
#
# Output uses polybar's formatting tags:
#   %{A1:cmd:}...%{A}  clickable area (button 1)
#   %{F#rrggbb}...%{F-} foreground colour
#   %{B#rrggbb}...%{B-} background colour
# The active window is highlighted, matching Plasma's task manager.
#
# Usage: taskbar.sh [max_title_len] [--watch]

set -uo pipefail

# Args are order-independent: --watch anywhere, and the first non-flag argument
# is the max title length. Parsing $1 positionally broke the moment --watch was
# added, silently setting MAX_LEN to the literal string "--watch".
MAX_LEN=22
WATCH=0
for arg in "$@"; do
    case "$arg" in
        --watch) WATCH=1 ;;
        ''|*[!0-9]*) ;;      # ignore anything that is not a plain number
        *) MAX_LEN="$arg" ;;
    esac
done

# --- Palette (Breeze-ish, matches config.ini) --------------------------------
FG="#eff0f1"        # normal task text
FG_DIM="#7f8c8d"    # minimised / inactive
BG_ACTIVE="#3daee9" # Breeze highlight blue
FG_ACTIVE="#1b1e2b"

command -v wmctrl >/dev/null 2>&1 || { echo "wmctrl not installed"; exit 0; }

render() {
    # Current desktop index (the line flagged with '*').
    current=$(wmctrl -d | awk '/\*/ {print $1; exit}')
    [ -z "$current" ] && exit 0

    # Active window id, normalised to the 0x0000000 form wmctrl prints.
    active_raw=$(xprop -root _NET_ACTIVE_WINDOW 2>/dev/null | awk '{print $NF}')
    active=$(printf '0x%08x' "$active_raw" 2>/dev/null || echo "")

    # Icon table and the ignore-list are shared with workspaces.sh so the two can
    # never disagree about which glyph an application gets.
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    # shellcheck source=./icons.sh
    source "$SCRIPT_DIR/icons.sh"

    # `wmctrl -lx` columns are: WID DESKTOP WM_CLASS HOSTNAME TITLE, separated by
    # VARIABLE whitespace (the class column is padded). Splitting on a fixed column
    # count therefore leaks the hostname into the title. Let awk consume the first
    # four fields and hand back the remainder, tab-delimited.
    out=""
    while IFS=$'\t' read -r win_id win_desk win_class title; do
        [ -z "$win_id" ] && continue

        # Only windows on the current desktop. -1 means "sticky / all desktops".
        [ "$win_desk" != "$current" ] && [ "$win_desk" != "-1" ] && continue

        # wmctrl lists the desktop shell and our own bar; skip those.
        is_ignorable_class "$win_class" && continue

        icon=$(icon_for "$win_class")

        # Truncate long titles so the bar does not reflow constantly.
        if [ "${#title}" -gt "$MAX_LEN" ]; then
            title="${title:0:$((MAX_LEN - 1))}…"
        fi

        if [ "$win_id" = "$active" ]; then
            entry="%{B${BG_ACTIVE}}%{F${FG_ACTIVE}} ${icon} ${title} %{F-}%{B-}"
        else
            entry="%{F${FG}} ${icon} ${title} %{F-}"
        fi

        # Clicking focuses the window, like a Plasma task button.
        out="${out}%{A1:wmctrl -i -a ${win_id}:}${entry}%{A}"
    done < <(wmctrl -lx 2>/dev/null | awk '{
        wid=$1; desk=$2; cls=$3;
        $1=""; $2=""; $3=""; $4="";          # drop id, desktop, class, hostname
        sub(/^[ \t]+/, "");                   # remaining text is the title
        printf "%s\t%s\t%s\t%s\n", wid, desk, cls, $0;
    }')

    printf '%s\n' "$out"
}

# --- Event-driven mode -------------------------------------------------------
# `--watch` renders once, then blocks on X property changes and re-renders the
# instant anything relevant happens. polybar consumes this with `tail = true`.
#
# The alternative — polybar's `interval = 1` polling — means up to a full second
# of lag after switching desktops, which reads as the bar being broken. It also
# spawns wmctrl twice a second forever. Watching costs one blocked xprop.
#
# Properties watched:
#   _NET_CURRENT_DESKTOP  desktop switched
#   _NET_CLIENT_LIST      window opened or closed
#   _NET_ACTIVE_WINDOW    focus moved
#   _NET_DESKTOP_NAMES    desktop added or removed
watch_mode() {
    render

    if ! command -v xprop >/dev/null 2>&1; then
        # No xprop: degrade to slow polling rather than showing nothing.
        while sleep 2; do render; done
        return
    fi

    # xprop -spy emits a line per change. Coalesce bursts (opening a window
    # touches several properties at once) so we redraw once, not four times.
    local last=0 now
    xprop -spy -root \
        _NET_CURRENT_DESKTOP _NET_CLIENT_LIST _NET_ACTIVE_WINDOW _NET_DESKTOP_NAMES \
        2>/dev/null | while read -r _; do
        now=$(date +%s%N)
        if (( now - last > 40000000 )); then   # 40ms debounce
            render
            last=$now
        fi
    done
}

if [[ $WATCH -eq 1 ]]; then
    watch_mode
    exit 0
fi

render
