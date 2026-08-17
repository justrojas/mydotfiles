#!/usr/bin/env bash
# Network switcher for the polybar wifi module.
#
# Removing the Plasma panel also removed the systray network applet, leaving no
# way to change wifi from the bar. This restores that with whatever the machine
# actually has, in order of preference.
#
# plasma-nm has no standalone window — it is a systray applet only — so
# "just launch the KDE one" is not an option once the tray is gone. The
# fallbacks below are ordered from best UX to lowest common denominator.

set -uo pipefail

launch() { setsid "$@" >/dev/null 2>&1 & }

# 1. nm-connection-editor — full GUI, part of network-manager-gnome. Best
#    experience: shows saved connections, lets you add/edit/delete.
if command -v nm-connection-editor >/dev/null 2>&1; then
    launch nm-connection-editor
    exit 0
fi

# 2. plasma-nm's KCM, if the standalone module is installed.
if command -v kcmshell5 >/dev/null 2>&1 && kcmshell5 --list 2>/dev/null | grep -q kcm_networkmanagement; then
    launch kcmshell5 kcm_networkmanagement
    exit 0
fi

# 3. A terminal TUI. nmtui ships with NetworkManager itself, so on a machine
#    using NM it is essentially always present.
if command -v nmtui >/dev/null 2>&1; then
    for term in kitty konsole alacritty x-terminal-emulator xterm; do
        if command -v "$term" >/dev/null 2>&1; then
            launch "$term" -e nmtui
            exit 0
        fi
    done
fi

# 4. Nothing suitable — say so visibly rather than failing silently, since this
#    is triggered by a click and a silent no-op looks like a broken bar.
if command -v notify-send >/dev/null 2>&1; then
    notify-send "Network" "No network UI found.\nInstall network-manager-gnome for nm-connection-editor,\nor use 'nmtui' in a terminal."
fi
exit 1
