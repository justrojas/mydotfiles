#!/bin/bash
# Open a URL in a new Firefox window and toggle fullscreen

URL="${1:-https://www.google.com}"

if ! command -v firefox &>/dev/null; then
    echo "Error: Firefox is not installed"
    exit 1
fi

firefox -new-window "$URL" &

if command -v xdotool &>/dev/null; then
    sleep 1
    xdotool key F11
fi
