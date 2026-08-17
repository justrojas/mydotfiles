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
# Usage: taskbar.sh [max_title_len]

set -uo pipefail

MAX_LEN="${1:-22}"

# --- Palette (Breeze-ish, matches config.ini) --------------------------------
FG="#eff0f1"        # normal task text
FG_DIM="#7f8c8d"    # minimised / inactive
BG_ACTIVE="#3daee9" # Breeze highlight blue
FG_ACTIVE="#1b1e2b"

command -v wmctrl >/dev/null 2>&1 || { echo "wmctrl not installed"; exit 0; }

# Current desktop index (the line flagged with '*').
current=$(wmctrl -d | awk '/\*/ {print $1; exit}')
[ -z "$current" ] && exit 0

# Active window id, normalised to the 0x0000000 form wmctrl prints.
active_raw=$(xprop -root _NET_ACTIVE_WINDOW 2>/dev/null | awk '{print $NF}')
active=$(printf '0x%08x' "$active_raw" 2>/dev/null || echo "")

# Map WM_CLASS to a Nerd Font glyph. Plasma uses real app icons; polybar can
# only render glyphs from its configured fonts, so this is the closest we get.
icon_for() {
    case "${1,,}" in
        *firefox*)                echo "" ;;
        *chrome*|*chromium*)      echo "" ;;
        *kitty*|*konsole*|*term*) echo "" ;;
        *code*|*vscodium*)        echo "" ;;
        *dolphin*|*nautilus*|*thunar*) echo "" ;;
        *spotify*)                echo "" ;;
        *slack*)                  echo "" ;;
        *discord*)                echo "" ;;
        *thunderbird*|*mail*)     echo "" ;;
        *libreoffice*|*writer*)   echo "" ;;
        *gimp*|*inkscape*)        echo "" ;;
        *vlc*|*mpv*)              echo "" ;;
        *steam*)                  echo "" ;;
        *settings*|*systemsettings*) echo "" ;;
        *nvim*|*vim*)             echo "" ;;
        *)                        echo "" ;;
    esac
}

# `wmctrl -lx` columns are: WID DESKTOP WM_CLASS HOSTNAME TITLE, separated by
# VARIABLE whitespace (the class column is padded). Splitting on a fixed column
# count therefore leaks the hostname into the title. Let awk consume the first
# four fields and hand back the remainder, tab-delimited.
out=""
while IFS=$'\t' read -r win_id win_desk win_class title; do
    [ -z "$win_id" ] && continue

    # Only windows on the current desktop. -1 means "sticky / all desktops".
    [ "$win_desk" != "$current" ] && [ "$win_desk" != "-1" ] && continue

    # wmctrl -l lists the desktop/panel pseudo-window; skip it.
    case "${win_class,,}" in
        *plasmashell*|*polybar*|*desktop*) continue ;;
    esac

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
