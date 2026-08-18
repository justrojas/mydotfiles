#!/usr/bin/env bash
# Network menu for the polybar wifi module.
#
# Removing the Plasma panel also removed the systray network applet, leaving no
# way to change wifi from the bar. plasma-nm has no standalone window — it is a
# systray applet only — so "just launch the KDE one" is not an option once the
# tray is gone.
#
# Preference order:
#   1. rofi   — a real dropdown anchored under the bar, connect in two clicks
#   2. kdialog— native KDE, but a centred dialog rather than a dropdown
#   3. nm-connection-editor / kcmshell5 / nmtui — full settings windows
#
# Install rofi for the dropdown:  sudo apt install rofi

set -uo pipefail

launch() { setsid "$@" >/dev/null 2>&1 & }

# Bar geometry, so the dropdown lands under the wifi icon rather than in the
# middle of the screen. Keep in sync with config.ini's height + offset-y.
BAR_HEIGHT="${WIFI_MENU_YOFFSET:-46}"
X_OFFSET="${WIFI_MENU_XOFFSET:--24}"

# ---------------------------------------------------------------------------
# Fallback: full settings windows, for when no menu tool is available.
# ---------------------------------------------------------------------------
open_settings() {
    if command -v nm-connection-editor >/dev/null 2>&1; then
        launch nm-connection-editor
    elif command -v kcmshell5 >/dev/null 2>&1 &&
         kcmshell5 --list 2>/dev/null | grep -q kcm_networkmanagement; then
        launch kcmshell5 kcm_networkmanagement
    elif command -v nmtui >/dev/null 2>&1; then
        for term in kitty konsole alacritty x-terminal-emulator xterm; do
            if command -v "$term" >/dev/null 2>&1; then
                launch "$term" -e nmtui
                return 0
            fi
        done
        return 1
    else
        return 1
    fi
}

notify() {
    command -v notify-send >/dev/null 2>&1 && notify-send "Network" "$1"
}

# ---------------------------------------------------------------------------
# Connect, prompting for a password only if NetworkManager asks for one.
#
# `nmcli device wifi connect` reuses a saved profile when one exists, so the
# common case is passwordless. We only prompt after a failure that mentions a
# secret, rather than always asking and annoying the user on known networks.
# ---------------------------------------------------------------------------
connect_ssid() {
    local ssid="$1" out
    out=$(nmcli device wifi connect "$ssid" 2>&1)
    if [[ $? -eq 0 ]]; then
        notify "Connected to $ssid"
        return 0
    fi

    if grep -qi "secrets\|password\|authentication" <<<"$out"; then
        local pass
        pass=$(ask_password "$ssid") || return 1
        [[ -z "$pass" ]] && return 1
        if out=$(nmcli device wifi connect "$ssid" password "$pass" 2>&1); then
            notify "Connected to $ssid"
            return 0
        fi
    fi

    notify "Could not connect to $ssid: $out"
    return 1
}

ask_password() {
    if command -v rofi >/dev/null 2>&1; then
        # Hide the list entirely: there is nothing to choose from, and an empty
        # listview leaves a blank panel hanging under the prompt.
        rofi -dmenu -password -p "Password for $1" \
            -location 3 -xoffset "$X_OFFSET" -yoffset "$BAR_HEIGHT" \
            -theme-str 'listview { enabled: false; }' </dev/null
    elif command -v kdialog >/dev/null 2>&1; then
        kdialog --password "Password for $1"
    else
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Build the network list.
#
# nmcli -t escapes literal colons in field values as '\:', so split on
# unescaped colons only, then unescape. SSIDs genuinely do contain colons.
#
# nmcli reports one row per access point, so a network with several APs (mesh,
# or 2.4/5GHz on the same SSID) appears many times. Unfiltered, the network you
# are actually connected to can end up dozens of rows down the menu. Collapse
# to one row per SSID, keeping the connected AP if there is one and otherwise
# the strongest, then sort by signal with the connected network pinned first.
# ---------------------------------------------------------------------------
# nmcli triggers a fresh scan whenever NetworkManager considers its cache
# stale, and blocks until it completes — measured at 3.6s here, against 28ms
# when the cache is warm. That is the difference between a menu that opens
# instantly and one that feels broken, and it is intermittent, so it looks like
# random slowness rather than a scan.
#
# Always read the cache. NetworkManager scans periodically on its own, so the
# list is current within a minute or so, and the explicit "rescan" entry in the
# menu is there for when that isn't good enough.
#
# --rescan was added in nmcli 1.12 (Ubuntu 22.04 ships 1.36); fall back to a
# plain list if it is rejected, rather than returning nothing.
nmcli_wifi() {
    nmcli -t -f IN-USE,SIGNAL,SSID device wifi list --rescan no 2>/dev/null ||
        nmcli -t -f IN-USE,SIGNAL,SSID device wifi list 2>/dev/null
}

wifi_list() {
    nmcli_wifi |
        while IFS= read -r line; do
            local inuse signal ssid
            inuse="${line%%:*}";  line="${line#*:}"
            signal="${line%%:*}"; ssid="${line#*:}"
            ssid="${ssid//\\:/:}"
            [[ -z "$ssid" ]] && continue          # hidden network
            printf '%s\t%s\t%s\n' "$inuse" "$signal" "$ssid"
        done |
        awk -F'\t' '
            {
                ssid = $3
                connected = ($1 == "*") ? 1 : 0
                sig = $2 + 0
                # Keep this row if the SSID is new, if this AP is the connected
                # one, or if it is stronger than what we have so far.
                if (!(ssid in seen) || connected > conn[ssid] ||
                    (connected == conn[ssid] && sig > best[ssid])) {
                    seen[ssid] = 1
                    conn[ssid] = connected
                    best[ssid] = sig
                    inuse[ssid] = $1
                }
            }
            END {
                for (s in seen)
                    # Sort key: connected first, then descending signal.
                    printf "%d\t%03d\t%s\t%s\t%s\n",
                           1 - conn[s], 999 - best[s], inuse[s], best[s], s
            }
        ' |
        sort -k1,1n -k2,2n |
        cut -f3-
}

# Signal strength as a compact bar glyph. Built with $'\uXXXX' escapes:
# writing these Nerd Font private-use characters literally into a file gets
# them silently stripped somewhere in the toolchain.
bars() {
    local s="${1:-0}"
    if   (( s >= 75 )); then printf '%s' $'\u2582\u2584\u2586\u2588'
    elif (( s >= 50 )); then printf '%s' $'\u2582\u2584\u2586'
    elif (( s >= 25 )); then printf '%s' $'\u2582\u2584'
    else                     printf '%s' $'\u2582'
    fi
}

# ---------------------------------------------------------------------------
# rofi dropdown
# ---------------------------------------------------------------------------
rofi_menu() {
    local radio entries="" line inuse signal ssid marker
    radio=$(nmcli -t -f WIFI general status 2>/dev/null | head -1)

    while IFS=$'\t' read -r inuse signal ssid; do
        [[ -z "$ssid" ]] && continue
        # '*' marks the currently connected network in nmcli's IN-USE column.
        marker="  "
        [[ "$inuse" == "*" ]] && marker=$'\u2713 '
        entries+="${marker}${ssid}  $(bars "$signal")"$'\n'
    done < <(wifi_list)

    if [[ "$radio" == "enabled" ]]; then
        entries+=$'\u2014 turn wifi off\n'
    else
        entries="$(printf '%s' $'\u2014 turn wifi on')"$'\n'
    fi
    entries+=$'\u2014 rescan\n'
    entries+=$'\u2014 network settings'

    local choice
    # Width and row count come from the theme (config/rofi/config.rasi); the
    # deprecated -width/-lines flags would override it. Only the position is
    # passed here, since it depends on the bar's geometry.
    choice=$(printf '%s' "$entries" | rofi -dmenu -i \
        -p "wifi" \
        -location 3 \
        -xoffset "$X_OFFSET" \
        -yoffset "$BAR_HEIGHT") || return 0

    [[ -z "$choice" ]] && return 0

    case "$choice" in
        *"turn wifi off")   nmcli radio wifi off ;;
        *"turn wifi on")    nmcli radio wifi on ;;
        *"rescan")
            # `nmcli device wifi rescan` returns as soon as the scan is
            # requested, not when results arrive. Without a pause the menu
            # reopens against the same cache it just refreshed, so the rescan
            # appears to do nothing.
            nmcli device wifi rescan 2>/dev/null
            sleep 2
            exec "$0"
            ;;
        *"network settings") open_settings ;;
        *)
            # Strip the leading marker and the trailing signal bars to recover
            # the SSID exactly as nmcli reported it.
            local ssid_sel="${choice#??}"
            ssid_sel="${ssid_sel%%  *}"
            connect_ssid "$ssid_sel"
            ;;
    esac
}

# ---------------------------------------------------------------------------
# kdialog fallback — a dialog, not a dropdown, but needs nothing installed.
# ---------------------------------------------------------------------------
kdialog_menu() {
    local args=() inuse signal ssid i=0
    while IFS=$'\t' read -r inuse signal ssid; do
        [[ -z "$ssid" ]] && continue
        local label="$ssid  $(bars "$signal")"
        [[ "$inuse" == "*" ]] && label="$label  (connected)"
        args+=("$i" "$label")
        eval "SSID_$i=\$ssid"
        ((i++))
    done < <(wifi_list)

    args+=("settings" "Network settings…")

    local choice
    choice=$(kdialog --menu "Wi-Fi" "${args[@]}" 2>/dev/null) || return 0
    [[ -z "$choice" ]] && return 0
    [[ "$choice" == "settings" ]] && { open_settings; return 0; }

    local var="SSID_$choice"
    connect_ssid "${!var}"
}

# ---------------------------------------------------------------------------
if ! command -v nmcli >/dev/null 2>&1; then
    open_settings || notify "No network UI found. Install network-manager-gnome or use nmtui."
    exit 0
fi

if command -v rofi >/dev/null 2>&1; then
    rofi_menu
elif command -v kdialog >/dev/null 2>&1; then
    kdialog_menu
else
    open_settings || notify "Install rofi for the wifi dropdown: sudo apt install rofi"
fi
