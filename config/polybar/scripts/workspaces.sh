#!/usr/bin/env bash
# Virtual-desktop pager for polybar, showing the APPLICATIONS on each desktop
# rather than desktop numbers — the way Plasma's pager does.
#
# WHY THIS IS A SCRIPT MODULE
# ---------------------------
# polybar's `internal/xworkspaces` can only render a desktop's %index%, %name%
# or an icon chosen by NAME via its icon-N mapping. It has no idea what windows
# live on a desktop, so it cannot show contents. This builds that from wmctrl.
#
# Output per desktop, left to right:
#   • current desktop  — highlighted pill, shows every app icon on it
#   • occupied desktop — dim, shows its app icons
#   • empty desktop    — a small dot, so the row does not jump around as
#                        desktops empty and fill
#
# Each desktop is clickable and switches to it.
#
# Usage: workspaces.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./icons.sh
source "$SCRIPT_DIR/icons.sh"

# --- Palette (must match config.ini) ----------------------------------------
FG_ACTIVE="#1b1e2b"   # text on the highlighted pill
BG_ACTIVE="#7aa2f7"   # highlight
FG_OCCUPIED="#c0caf5"
FG_EMPTY="#3f4451"

command -v wmctrl >/dev/null 2>&1 || { echo "wmctrl missing"; exit 0; }

current=$(wmctrl -d 2>/dev/null | awk '/\*/ {print $1; exit}')
[ -z "$current" ] && exit 0

# Collect the icons present on each desktop, de-duplicated: five terminals on
# one desktop should render one terminal glyph, not five.
declare -A desk_icons=()
while IFS=$'\t' read -r win_desk win_class; do
    [ -z "$win_class" ] && continue
    is_ignorable_class "$win_class" && continue
    # -1 means sticky/all-desktops; not attributable to one desktop.
    [ "$win_desk" = "-1" ] && continue

    icon=$(icon_for "$win_class")
    existing="${desk_icons[$win_desk]:-}"
    case " $existing " in
        *" $icon "*) ;;                                  # already shown
        *) desk_icons[$win_desk]="${existing:+$existing }$icon" ;;
    esac
done < <(wmctrl -lx 2>/dev/null | awk '{printf "%s\t%s\n", $2, $3}')

total=$(wmctrl -d 2>/dev/null | wc -l)
out=""

for (( d=0; d<total; d++ )); do
    icons="${desk_icons[$d]:-}"
    num=$((d + 1))

    if [ "$d" = "$current" ]; then
        # Current desktop: highlighted. Show its icons, or the number when
        # empty so the active marker is never blank.
        body="${icons:-$num}"
        entry="%{B${BG_ACTIVE}}%{F${FG_ACTIVE}} ${body} %{F-}%{B-}"
    elif [ -n "$icons" ]; then
        entry="%{F${FG_OCCUPIED}} ${icons} %{F-}"
    else
        # Empty: a dot rather than a number, so switching desktops does not
        # reflow the whole row.
        entry="%{F${FG_EMPTY}} · %{F-}"
    fi

    out="${out}%{A1:wmctrl -s ${d}:}${entry}%{A}"
done

printf '%s\n' "$out"
