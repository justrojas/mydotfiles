#!/bin/bash
# Shim — delegates to the root install.sh.
# Use the root install.sh directly:
#
#   bash "$(dirname "$0")/../install.sh"
#
# The root install.sh provides an interactive menu to select the appropriate
# installation profile (terminal-setup or desktop-setup).

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "[INFO] Redirecting to root install.sh..."
exec bash "$DOTFILES_DIR/install.sh" "$@"
