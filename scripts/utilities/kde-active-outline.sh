#!/usr/bin/env bash
# Active-window outline for KDE Plasma (X11), via the kwin4_effect_shapecorners
# KWin effect.
#
# THE PROBLEM
# -----------
# With a tiling layout (bismuth) and a dark Aurorae decoration, every window
# looks identical and there is no reliable visual cue for which one has focus.
# Plasma's own decorations differentiate active/inactive only by a subtle
# titlebar shade, which disappears entirely on tiled or maximised windows where
# the titlebar may be hidden.
#
# THE FIX
# -------
# shapecorners draws a coloured outline around the focused window, independent
# of the decoration theme, and it keeps working on tiled and maximised windows.
# The effect is shipped as a .deb in scripts/packages/ and installed by
# profiles/kde-setup.sh.
#
# WHY NOT ...
#   * Breeze "draw a thin border" — applies to all windows equally, so it does
#     not distinguish focus.
#   * A different Aurorae theme — same problem, and throws away the Ant-Dark
#     look the rest of this repo is themed around.
#   * KWin's "Focus Follows Mouse" indicator — not a thing on Plasma 5.
#
# Usage:
#   kde-active-outline.sh                    apply defaults (Tokyo Night blue)
#   kde-active-outline.sh --color 7aa2f7     set the active outline colour (hex)
#   kde-active-outline.sh --thickness 3      set outline thickness in px
#   kde-active-outline.sh --radius 8         corner radius
#   kde-active-outline.sh --off              remove the outline (thickness 0)
#   kde-active-outline.sh --show             print the current settings
#
# CONFIG LOCATION — this is the part that is easy to get wrong.
#
# The effect reads ~/.config/shapecornersrc, group [General]. It does NOT read
# kwinrc's [Effect-shapecorners] group, despite that being where KWin effect
# settings normally live and despite the config UI plugin exposing kcfg_*
# names that look like kwinrc keys. Writing there is silently ignored: the
# effect stays loaded, reports enabled, and simply draws nothing.
#
# Colours are R,G,B,A (four components). A three-component value is not
# rendered.
#
# Requires: kwriteconfig5 / kreadconfig5 (plasma-desktop), qdbus.

set -euo pipefail

# --- Defaults ---------------------------------------------------------------
# Tokyo Night Storm blue — matches config/oh-my-posh/tokyonight_storm.omp.json
# and the polybar accent, so focus colour is consistent across the desktop.
ACTIVE_COLOR="7aa2f7"
ACTIVE_THICKNESS=2
ACTIVE_ALPHA=255

# Inactive windows get no outline at all. A dim outline is worse than none: it
# reads as "sort of focused" and defeats the purpose.
INACTIVE_THICKNESS=0
INACTIVE_ALPHA=0

CORNER_RADIUS=8

ACTION="apply"

# --- Args -------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --color)     ACTIVE_COLOR="${2#\#}"; shift 2 ;;
        --thickness) ACTIVE_THICKNESS="$2";  shift 2 ;;
        --radius)    CORNER_RADIUS="$2";     shift 2 ;;
        --off)       ACTION="off";           shift   ;;
        --show)      ACTION="show";          shift   ;;
        -h|--help)   sed -n '2,40p' "$0"; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

for bin in kwriteconfig5 kreadconfig5; do
    command -v "$bin" >/dev/null 2>&1 || {
        echo "error: $bin not found (install plasma-desktop)" >&2; exit 1; }
done

CONFIG_FILE="shapecornersrc"
GROUP="General"

# hex RRGGBB -> "R,G,B,A". The effect expects four components; three renders
# as nothing.
hex_to_rgba() {
    local h="${1#\#}" alpha="${2:-255}"
    printf '%d,%d,%d,%d' "0x${h:0:2}" "0x${h:2:2}" "0x${h:4:2}" "$alpha"
}

set_key() { kwriteconfig5 --file "$CONFIG_FILE" --group "$GROUP" --key "$1" "$2"; }
get_key() { kreadconfig5 --file "$CONFIG_FILE" --group "$GROUP" --key "$1" 2>/dev/null; }

reload_kwin() {
    # Re-read config, then bounce the effect so the new values take hold.
    # reconfigure alone does not always re-init shader uniforms.
    qdbus org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
    qdbus org.kde.kwin.Effects /Effects unloadEffect "kwin4_effect_shapecorners" >/dev/null 2>&1 || true
    qdbus org.kde.kwin.Effects /Effects loadEffect   "kwin4_effect_shapecorners" >/dev/null 2>&1 || true
}

case "$ACTION" in
    show)
        echo "[$GROUP] in ~/.config/$CONFIG_FILE"
        for k in Size InactiveCornerRadius \
                 OutlineColor OutlineThickness ActiveOutlineUseCustom ActiveOutlineUsePalette \
                 InactiveOutlineColor InactiveOutlineThickness InactiveOutlineUseCustom \
                 SecondOutlineThickness InactiveSecondOutlineThickness \
                 DisableOutlineTile DisableOutlineMaximize IncludeNormalWindows; do
            printf '  %-26s %s\n' "$k" "$(get_key "$k" || echo '(unset)')"
        done
        echo ""
        echo "effect enabled: $(kreadconfig5 --file kwinrc --group Plugins --key kwin4_effect_shapecornersEnabled 2>/dev/null || echo '(unset -> default)')"
        exit 0
        ;;
    off)
        set_key OutlineThickness 0
        set_key InactiveOutlineThickness 0
        reload_kwin
        echo "Active window outline disabled."
        exit 0
        ;;
esac

# --- Apply ------------------------------------------------------------------
# The effect must be enabled or none of this renders. Note the kwinrc key is
# kwin4_effect_shapecornersEnabled, NOT shapecornersEnabled — but the effect's
# OWN settings live in shapecornersrc (see the note at the top of this file).
kwriteconfig5 --file kwinrc --group Plugins \
    --key kwin4_effect_shapecornersEnabled true

# Corner radius, active and inactive kept equal so windows don't change shape
# on focus — only the outline should change.
set_key Size "$CORNER_RADIUS"
set_key InactiveCornerRadius "$CORNER_RADIUS"

# Active outline.
set_key OutlineColor            "$(hex_to_rgba "$ACTIVE_COLOR" "$ACTIVE_ALPHA")"
set_key OutlineThickness        "$ACTIVE_THICKNESS"
set_key ActiveOutlineUseCustom  true
set_key ActiveOutlineUsePalette false

# Inactive outline: fully off. A dim outline reads as "sort of focused" and
# defeats the point of having a focus indicator at all.
set_key InactiveOutlineColor     "0,0,0,0"
set_key InactiveOutlineThickness "$INACTIVE_THICKNESS"
set_key InactiveOutlineUseCustom true
set_key InactiveOutlineUsePalette false

# Secondary outlines off — one clear ring is the goal.
set_key SecondOutlineThickness         0
set_key InactiveSecondOutlineThickness 0

# Make sure ordinary windows are actually decorated by the effect.
set_key IncludeNormalWindows true
set_key IncludeDialogs       true

# CRITICAL for a tiling setup: by default the effect can skip the outline on
# tiled and maximised windows, which is exactly when the titlebar cue is also
# missing — i.e. it would switch off precisely when it is most needed.
set_key DisableOutlineTile     false
set_key DisableOutlineMaximize false

reload_kwin

echo "Active window outline applied:"
echo "  colour     #${ACTIVE_COLOR}  ($(hex_to_rgba "$ACTIVE_COLOR" "$ACTIVE_ALPHA"))"
echo "  thickness  ${ACTIVE_THICKNESS}px"
echo "  radius     ${CORNER_RADIUS}px"
echo "  inactive   no outline"
echo ""
echo "Config written to ~/.config/$CONFIG_FILE [$GROUP]"
echo ""
echo "If nothing changed, compositing may be off:"
echo "  System Settings > Display and Monitor > Compositor > Enable on startup"
echo "Tune with: kde-active-outline.sh --color <hex> --thickness <px>"
