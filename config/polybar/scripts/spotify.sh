#!/usr/bin/env bash
# Spotify / MPRIS control + status for polybar.
#
# Talks to the real MPRIS D-Bus interface via playerctl, so it works with the
# Spotify desktop client, and equally with mpv, VLC, Firefox, YouTube Music,
# etc. There is no OAuth, no ~/.spotify/.env, and no network round-trip — the
# old scripts/utilities/spotify_tools/ package used the Spotify Web API, which
# needed credentials on every machine and had ~5s of polling latency.
#
# The one thing the Web API could do that MPRIS cannot is "like/save track".
# That genuinely requires the Web API, so it is intentionally not offered here.
#
# Usage: spotify.sh <status|play-pause|next|previous|focus|volume-up|volume-down|next-icon|prev-icon>

set -uo pipefail

# Prefer Spotify when it's running, otherwise fall back to whatever is playing.
PLAYER_PREFERENCE="spotify"

# Trim long titles so the bar doesn't jump around. polybar's label-maxlen also
# caps this, but truncating here lets us add a proper ellipsis.
MAX_LEN=45

have_playerctl() { command -v playerctl >/dev/null 2>&1; }

# Resolve which player to drive. Returns non-zero if nothing is available.
pick_player() {
    local players
    players="$(playerctl -l 2>/dev/null)" || return 1
    [ -z "$players" ] && return 1

    # Exact-ish match on the preferred player first.
    local p
    while IFS= read -r p; do
        case "$p" in
            "$PLAYER_PREFERENCE"|"$PLAYER_PREFERENCE".*) printf '%s\n' "$p"; return 0 ;;
        esac
    done <<< "$players"

    # Otherwise: the first one that is actually playing.
    while IFS= read -r p; do
        if [ "$(playerctl -p "$p" status 2>/dev/null)" = "Playing" ]; then
            printf '%s\n' "$p"; return 0
        fi
    done <<< "$players"

    # Last resort: the first player at all (probably paused).
    printf '%s\n' "$(head -n1 <<< "$players")"
}

# Run a playerctl subcommand against the chosen player.
pc() {
    local player
    player="$(pick_player)" || return 1
    playerctl -p "$player" "$@" 2>/dev/null
}

cmd_status() {
    have_playerctl || { echo ""; return 0; }

    local player status title artist icon text
    player="$(pick_player)" || { echo ""; return 0; }

    status="$(playerctl -p "$player" status 2>/dev/null)" || { echo ""; return 0; }

    case "$status" in
        Playing) icon="" ;;
        Paused)  icon="" ;;
        *)       echo ""; return 0 ;;
    esac

    title="$(playerctl -p "$player" metadata xesam:title  2>/dev/null)"
    artist="$(playerctl -p "$player" metadata xesam:artist 2>/dev/null)"

    # Ads and some streams report no title at all.
    if [ -z "$title" ]; then
        echo "$icon —"
        return 0
    fi

    if [ -n "$artist" ]; then
        text="$artist — $title"
    else
        text="$title"
    fi

    # Collapse newlines/tabs; polybar treats them as formatting.
    text="$(printf '%s' "$text" | tr '\n\t' '  ')"

    if [ "${#text}" -gt "$MAX_LEN" ]; then
        text="${text:0:$((MAX_LEN - 1))}…"
    fi

    printf '%s %s\n' "$icon" "$text"
}

# The prev/next buttons hide themselves when nothing is playing, so the bar
# collapses to just the clock instead of showing three dead pills.
cmd_icon() {
    have_playerctl || return 0
    local player status
    player="$(pick_player)" || return 0
    status="$(playerctl -p "$player" status 2>/dev/null)"
    case "$status" in
        Playing|Paused) printf '%s\n' "$1" ;;
        *) return 0 ;;
    esac
}

# Focus/raise the player window. MPRIS Raise() is the portable way; fall back
# to wmctrl for players that don't implement it (Spotify historically didn't).
cmd_focus() {
    have_playerctl || return 0
    if ! pc raise; then
        command -v wmctrl >/dev/null 2>&1 && wmctrl -x -a spotify
    fi
}

# Compact play/pause glyph for the minimal bar: no title, no artist, just the
# transport state. Prints nothing when no player is running, so the three
# transport buttons collapse rather than sitting there dead.
cmd_state_icon() {
    have_playerctl || return 0
    local player status
    player="$(pick_player)" || return 0
    status="$(playerctl -p "$player" status 2>/dev/null)"
    case "$status" in
        Playing) printf '%s\n' $'\uf04c' ;;   # fa-pause  (click to pause)
        Paused)  printf '%s\n' $'\uf04b' ;;   # fa-play   (click to resume)
        *)       return 0 ;;
    esac
}

# ---------------------------------------------------------------------------
# follow — the whole media group as ONE live polybar module.
#
# The old layout was three interval-polled modules (prev / toggle / next), so a
# click took up to a second to show. Here `playerctl --follow` pushes a line on
# every status or track change and we re-render immediately (tail = true).
#
# Output: ⏮  ⏯  ⏭   Artist — Title, each part wrapped in a polybar action tag.
# Clicking the title opens the now-playing card (album art + controls).
# Prints an empty line when nothing is playing, so the group disappears.
# ---------------------------------------------------------------------------
SELF="$HOME/.config/polybar/scripts/spotify.sh"
FG_DIM="#6e6482"
FG_ACCENT="#9d7cd8"
TITLE_LEN=32

# Polybar markup is %{...}; a literal % or } in a title would break the line.
bar_escape() { local s="${1//%/%%}"; printf '%s' "${s//\}/)}"; }

render() {
    local status="$1" artist="$2" title="$3" toggle text
    case "$status" in
        Playing) toggle=$'\uf04c' ;;
        Paused)  toggle=$'\uf04b' ;;
        *)       echo ""; return ;;
    esac

    text="$title"
    [ -n "$artist" ] && text="$artist — $title"
    [ -z "$title" ] && text="—"
    text="$(printf '%s' "$text" | tr '\n\t' '  ')"
    [ "${#text}" -gt "$TITLE_LEN" ] && text="${text:0:$((TITLE_LEN - 1))}…"
    text="$(bar_escape "$text")"

    local scroll="%{A4:$SELF volume-up:}%{A5:$SELF volume-down:}"
    printf '%s%%{F%s}%%{A1:%s previous:} %s %%{A}%%{F-}  %%{F%s}%%{A1:%s play-pause:} %s %%{A}%%{F-}  %%{F%s}%%{A1:%s next:} %s %%{A}%%{F-}   %%{A1:%s card:}%s%%{A}%%{A}%%{A}\n' \
        "$scroll" \
        "$FG_DIM" "$SELF" $'\uf048' \
        "$FG_ACCENT" "$SELF" "$toggle" \
        "$FG_DIM" "$SELF" $'\uf051' \
        "$SELF" "$text"
}

cmd_follow() {
    have_playerctl || { echo ""; sleep infinity; }
    # Re-spawn the follower if it ever exits (e.g. playerctld restarts).
    while :; do
        playerctl -p "$PLAYER_PREFERENCE,%any" --follow metadata \
            --format $'{{status}}\x1f{{artist}}\x1f{{title}}' 2>/dev/null |
            while IFS=$'\x1f' read -r status artist title; do
                render "$status" "$artist" "$title"
            done
        echo ""
        sleep 2
    done
}

# card — the now-playing popup (album art, live progress, seek, controls).
# It is a small GTK window in media-card.py: rofi could neither refresh the
# progress nor accept single clicks. Running it again closes the open card.
cmd_card() {
    setsid python3 "$(dirname "$(readlink -f "$0")")/media-card.py" >/dev/null 2>&1 &
}

case "${1:-status}" in
    status)      cmd_status ;;
    follow)      cmd_follow ;;
    card)        cmd_card ;;
    play-pause)  pc play-pause ;;
    play)        pc play ;;
    pause)       pc pause ;;
    next)        pc next ;;
    previous)    pc previous ;;
    focus)       cmd_focus ;;
    volume-up)   pc volume 0.05+ ;;
    volume-down) pc volume 0.05- ;;
    state-icon)  cmd_state_icon ;;
    next-icon)   cmd_icon $'\uf051' ;;
    prev-icon)   cmd_icon $'\uf048' ;;
    *)
        echo "usage: $(basename "$0") <status|state-icon|play-pause|play|pause|next|previous|focus|volume-up|volume-down|prev-icon|next-icon>" >&2
        exit 1
        ;;
esac
