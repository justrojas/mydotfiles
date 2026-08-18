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
echo "     Configure tmux, kitty, neovim, bash/zsh"
echo "     No sudo required — links configs from this repo"
echo ""
echo "  2) Desktop Setup  (Ubuntu/Debian only)"
echo "     Install all packages + configure terminal + optional KDE/top bar"
echo "     Requires sudo"
echo ""
echo "  3) VM / Headless Setup  (Ubuntu/Debian only)"
echo "     Shell + neovim + tmux + CLI tools. No GUI, no kitty, no fonts."
echo "     Requires sudo"
echo ""
echo "  4) Top Bar only  (Ubuntu/Debian, X11)"
echo "     Waybar-style polybar with Spotify/MPRIS controls"
echo "     Requires sudo"
echo ""
echo "  5) Quit"
echo ""
# The menu reads plain stdin, NOT $TTY_STDIN.
#
# $TTY_STDIN exists for prompts that happen part-way through a script whose own
# stdin is busy — the `curl | bash` case — and it degrades to /dev/null when no
# tty exists. That is right for a mid-run confirmation (take the default and
# carry on) but wrong here: this menu selection *is* the script's input, so
# reading /dev/null would make `echo 1 | install.sh` impossible and, under
# `set -e`, the EOF would abort the script outright.
#
# `|| true` so an empty stdin falls through to the invalid-choice branch
# instead of killing the script.
choice=""
read -rp "Choice [1-5]: " -n 1 choice || true
echo ""
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
        reply=$(prompt_yn "Continue? [y/N] " "n")
        if [[ "$reply" =~ ^[Yy]$ ]]; then
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
        reply=$(prompt_yn "Continue? [y/N] " "n")
        if [[ "$reply" =~ ^[Yy]$ ]]; then
            run_profile desktop-setup.sh
        else
            log_info "Cancelled."
        fi
        ;;

    3)
        if [[ ! "$OS" =~ ^(ubuntu|debian|pop|linuxmint)$ ]]; then
            log_error "VM Setup only supports Ubuntu/Debian (detected: $OS)"
            exit 1
        fi
        echo ""
        log_info "VM Setup: shell + neovim + tmux + CLI tools (no GUI components)"
        log_warning "Requires sudo access"
        echo ""
        reply=$(prompt_yn "Continue? [y/N] " "n")
        if [[ "$reply" =~ ^[Yy]$ ]]; then
            run_profile vm-setup.sh
        else
            log_info "Cancelled."
        fi
        ;;

    4)
        if [[ ! "$OS" =~ ^(ubuntu|debian|pop|linuxmint)$ ]]; then
            log_error "Bar Setup only supports Ubuntu/Debian (detected: $OS)"
            exit 1
        fi
        echo ""
        log_info "Bar Setup: installs polybar + playerctl, links the bar config"
        log_warning "Requires sudo. Offers to remove/hide top Plasma panels."
        echo ""
        reply=$(prompt_yn "Continue? [y/N] " "n")
        if [[ "$reply" =~ ^[Yy]$ ]]; then
            run_profile bar-setup.sh
        else
            log_info "Cancelled."
        fi
        ;;

    5)
        log_info "Goodbye!"
        exit 0
        ;;

    "")
        # No input at all — stdin was empty or closed. That is not an error
        # worth the "changes may have been partially applied" warning from the
        # exit trap, because nothing ran.
        echo ""
        log_info "No choice made — nothing to do."
        exit 0
        ;;

    *)
        log_error "Invalid choice: $choice (expected 1-5)"
        exit 1
        ;;
esac

echo ""
log_info "See $DOTFILES_DIR/docs/ for further guidance."
