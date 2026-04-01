#!/bin/bash
# Dotfiles Installation — interactive menu
# Delegates to profiles/ scripts based on user choice.
#
# Usage: bash install.sh [--dry-run]

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$DOTFILES_DIR/lib/common.sh"

init_common "$@"

# ============================================================================
# OS detection (informational only — profiles enforce their own requirements)
# ============================================================================
OS=$(detect_os)

# ============================================================================
# Menu
# ============================================================================
clear
echo ""
echo "======================================"
echo "   Dotfiles Installation"
echo "======================================"
echo ""
log_info "OS detected: $OS"
[[ $DRY_RUN -eq 1 ]] && log_warning "Dry-run mode — no changes will be made"
echo ""
echo "Select a profile:"
echo ""
echo "  1) Terminal Setup"
echo "     Configure tmux, kitty, neovim, zsh"
echo "     No sudo required — links configs from this repo"
echo ""
echo "  2) Desktop Setup  (Ubuntu/Debian only)"
echo "     Install all packages + configure terminal + optional KDE"
echo "     Requires sudo"
echo ""
echo "  3) Quit"
echo ""
read -rp "Choice [1-3]: " -n 1 choice
echo ""

run_profile() {
    local script="$DOTFILES_DIR/profiles/$1"
    if [[ ! -f "$script" ]]; then
        log_error "Profile script not found: $script"
        exit 1
    fi
    local flags=()
    [[ $DRY_RUN -eq 1 ]] && flags+=("--dry-run")
    bash "$script" "${flags[@]}"
}

case "$choice" in
    1)
        echo ""
        log_info "Terminal Setup: configures tmux, kitty, neovim, zsh"
        log_info "Existing configs will be backed up with a timestamp"
        echo ""
        read -rp "Continue? [y/N] " -n 1
        echo ""
        if [[ "$REPLY" =~ ^[Yy]$ ]]; then
            run_profile terminal-setup.sh
        else
            log_info "Cancelled."
        fi
        ;;

    2)
        if [[ ! "$OS" =~ ^(ubuntu|debian)$ ]]; then
            log_error "Desktop Setup only supports Ubuntu/Debian (detected: $OS)"
            exit 1
        fi
        echo ""
        log_info "Desktop Setup: installs packages + configures terminal + optional KDE"
        log_warning "Requires sudo access"
        echo ""
        read -rp "Continue? [y/N] " -n 1
        echo ""
        if [[ "$REPLY" =~ ^[Yy]$ ]]; then
            run_profile desktop-setup.sh
        else
            log_info "Cancelled."
        fi
        ;;

    3)
        log_info "Goodbye!"
        exit 0
        ;;

    *)
        log_error "Invalid choice: $choice (expected 1-3)"
        exit 1
        ;;
esac

echo ""
log_success "Done. See $DOTFILES_DIR/docs/ for further guidance."
