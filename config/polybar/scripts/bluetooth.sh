#!/usr/bin/env bash
# Bluetooth status + dropdown for polybar.
#
# Like the wifi menu, this replaces a systray applet (bluedevil) that went away
# with the Plasma panel. Status comes from bluetoothctl; the menu is rofi,
# styled by config/rofi/config.rasi and anchored under the right end of the bar.
#
# bluetoothctl 5.64 (Ubuntu 22.04) has no `devices Connected` filter — that
# arrived in 5.65 — so connection state is read per device from `info`.
#
# Glyphs are written as $'\uXXXX' escapes: literal Nerd Font private-use
# characters get silently stripped somewhere in the toolchain.
#
# Usage: bluetooth.sh <status|menu|toggle>

set -uo pipefail

ICON_ON=$'\uf293'          # fa-bluetooth
ICON_OFF=$'\U000f00b2'     # md-bluetooth_off
ICON_CONN=$'\U000f00b1'    # md-bluetooth_connect

DIM="#6e6482"
ACCENT="#9d7cd8"

BAR_HEIGHT="${BT_MENU_YOFFSET:-46}"
X_OFFSET="${BT_MENU_XOFFSET:--24}"

launch() { setsid "$@" >/dev/null 2>&1 & }
notify() { command -v notify-send >/dev/null 2>&1 && notify-send -a Bluetooth "Bluetooth" "$1"; }

powered() { bluetoothctl show 2>/dev/null | grep -q "Powered: yes"; }

# "MAC<TAB>name" for every paired device. Falls back to `devices` if the old
# paired-devices command is ever removed.
paired() {
    { bluetoothctl paired-devices 2>/dev/null || bluetoothctl devices Paired 2>/dev/null; } |
        awk '/^Device /{mac=$2; $1=$2=""; sub(/^  /,""); print mac "\t" $0}'
}

is_connected() { bluetoothctl info "$1" 2>/dev/null | grep -q "Connected: yes"; }

battery_of() {
    bluetoothctl info "$1" 2>/dev/null |
        sed -n 's/.*Battery Percentage: 0x[0-9a-fA-F]* (\([0-9]*\)).*/\1/p'
}

cmd_status() {
    if ! command -v bluetoothctl >/dev/null 2>&1 || ! powered; then
        printf '%%{F%s}%s%%{F-}\n' "$DIM" "$ICON_OFF"
        return
    fi

    local mac name names=() bat=""
    while IFS=$'\t' read -r mac name; do
        [ -z "$mac" ] && continue
        if is_connected "$mac"; then
            names+=("$name")
            [ -z "$bat" ] && bat="$(battery_of "$mac")"
        fi
    done < <(paired)

    if [ "${#names[@]}" -eq 0 ]; then
        printf '%s\n' "$ICON_ON"
        return
    fi

    # Short label: first device, trimmed. Battery when the device reports it.
    local label="${names[0]}"
    [ "${#label}" -gt 18 ] && label="${label:0:17}…"
    [ "${#names[@]}" -gt 1 ] && label="$label +$(( ${#names[@]} - 1 ))"
    [ -n "$bat" ] && label="$label $bat%"
    printf '%%{F%s}%s%%{F-} %s\n' "$ACCENT" "$ICON_CONN" "$label"
}

cmd_toggle() {
    if powered; then bluetoothctl power off >/dev/null; else bluetoothctl power on >/dev/null; fi
}

open_settings() {
    if kcmshell5 --list 2>/dev/null | grep -q kcm_bluetooth; then
        launch kcmshell5 kcm_bluetooth
    elif command -v blueman-manager >/dev/null 2>&1; then
        launch blueman-manager
    else
        notify "No Bluetooth settings app found"
    fi
}

cmd_menu() {
    command -v rofi >/dev/null 2>&1 || { open_settings; return; }

    local entries="" mac name macs=() line
    if powered; then
        while IFS=$'\t' read -r mac name; do
            [ -z "$mac" ] && continue
            if is_connected "$mac"; then
                line=$'\u2713 '"$name"
                local b; b="$(battery_of "$mac")"
                [ -n "$b" ] && line="$line  $b%"
            else
                line="  $name"
            fi
            entries+="$line"$'\n'
            macs+=("$mac")
        done < <(paired)
        entries+=$'\u2014 pair new device\n'
        entries+=$'\u2014 turn bluetooth off\n'
    else
        entries+=$'\u2014 turn bluetooth on\n'
    fi
    entries+=$'\u2014 bluetooth settings'

    local idx
    idx=$(printf '%s' "$entries" | rofi -dmenu -i -format i -p "bluetooth" \
        -location 3 -xoffset "$X_OFFSET" -yoffset "$BAR_HEIGHT") || return 0
    [ -z "$idx" ] && return 0

    local choice; choice="$(printf '%s' "$entries" | sed -n "$((idx + 1))p")"
    case "$choice" in
        *"pair new device")     launch bluedevil-wizard ;;
        *"turn bluetooth off")  bluetoothctl power off >/dev/null ;;
        *"turn bluetooth on")   bluetoothctl power on  >/dev/null ;;
        *"bluetooth settings")  open_settings ;;
        *)
            mac="${macs[$idx]:-}"
            [ -z "$mac" ] && return 0
            name="${choice#??}"; name="${name%%  *}"
            if is_connected "$mac"; then
                bluetoothctl disconnect "$mac" >/dev/null && notify "Disconnected $name"
            else
                notify "Connecting $name…"
                if bluetoothctl connect "$mac" >/dev/null 2>&1; then
                    notify "Connected $name"
                else
                    notify "Could not connect $name"
                fi
            fi
            ;;
    esac
}

case "${1:-status}" in
    status) cmd_status ;;
    menu)   cmd_menu ;;
    toggle) cmd_toggle ;;
    *) echo "usage: $(basename "$0") <status|menu|toggle>" >&2; exit 1 ;;
esac
