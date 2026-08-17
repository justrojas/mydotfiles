#!/bin/bash
# Compatibility shim — the installer lives at the repository root.
#
# This path (scripts/install.sh) was the entry point in an older layout. It is
# kept so existing bookmarks, notes and muscle memory keep working, and so that
# anyone who finds it does not conclude the repo is broken.
#
# It forwards every argument, so all of these behave identically:
#
#   bash scripts/install.sh
#   bash scripts/install.sh --dry-run
#   bash install.sh --dry-run
#
# If you are reading this in a script you are writing: call the root
# ../install.sh directly, or better, invoke a profile without the menu:
#
#   bash profiles/terminal-setup.sh --non-interactive
#   bash profiles/vm-setup.sh --dry-run

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT_INSTALLER="$DOTFILES_DIR/install.sh"

if [[ ! -f "$ROOT_INSTALLER" ]]; then
    echo "error: root installer not found at $ROOT_INSTALLER" >&2
    echo "       this shim expects to live in <repo>/scripts/" >&2
    exit 1
fi

echo "note: the installer moved to the repository root; forwarding to install.sh" >&2
exec bash "$ROOT_INSTALLER" "$@"
