#!/bin/bash
# Desktop Setup - installs system packages + configures terminal + optional KDE
# Designed for bootstrapping a fresh personal machine with sudo access.
#
# Usage: bash desktop-setup.sh [--non-interactive] [--dry-run]

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$DOTFILES_DIR/lib/common.sh"

init_common "$@"

# ============================================================================
# Argument parsing
# ============================================================================
NONINTERACTIVE=0
for arg in "$@"; do
    [[ "$arg" == "--non-interactive" ]] && NONINTERACTIVE=1
done

# ============================================================================
# OS check
# ============================================================================
OS=$(detect_os)
if [[ ! "$OS" =~ ^(ubuntu|debian)$ ]]; then
    log_error "This script only supports Ubuntu/Debian (detected: $OS)"
    exit 1
fi

check_not_root
check_sudo
check_internet

# ============================================================================
# Banner
# ============================================================================
echo ""
echo "======================================"
echo "  Desktop Setup"
echo "  Packages + Terminal + Optional KDE"
echo "======================================"
echo ""
[[ $NONINTERACTIVE -eq 1 ]] && log_info "Running non-interactively"
[[ $DRY_RUN -eq 1 ]]        && log_warning "Dry-run mode — no changes will be made"
echo ""

# ============================================================================
# Step 1: Base tools
# ============================================================================
log_step "Step 1/4 — Install system packages"
BASE_SCRIPT="$DOTFILES_DIR/profiles/install-packages.sh"
if [[ ! -f "$BASE_SCRIPT" ]]; then
    log_error "install-packages.sh not found at $BASE_SCRIPT"
    exit 1
fi

PASSTHROUGH_FLAGS=()
[[ $DRY_RUN -eq 1 ]] && PASSTHROUGH_FLAGS+=("--dry-run")

bash "$BASE_SCRIPT" "${PASSTHROUGH_FLAGS[@]}"
log_success "Base tools installed"

# ============================================================================
# Step 2: Terminal configuration
# ============================================================================
log_step "Step 2/4 — Terminal configuration"
MINIMAL_SCRIPT="$DOTFILES_DIR/profiles/terminal-setup.sh"
if [[ ! -f "$MINIMAL_SCRIPT" ]]; then
    log_error "terminal-setup.sh not found at $MINIMAL_SCRIPT"
    exit 1
fi

MINIMAL_FLAGS=("--non-interactive" "${PASSTHROUGH_FLAGS[@]}")
bash "$MINIMAL_SCRIPT" "${MINIMAL_FLAGS[@]}"
log_success "Terminal configured"

# ============================================================================
# Step 3: KDE customisations (optional)
# ============================================================================
log_step "Step 3/4 — KDE Plasma customisations"

install_kde=false
if [[ $NONINTERACTIVE -eq 0 ]]; then
    reply=$(prompt_yn "Install KDE Plasma customisations? [y/N] " "n")
    [[ "$reply" =~ ^[Yy]$ ]] && install_kde=true
fi

KDE_SCRIPT="$DOTFILES_DIR/profiles/kde-setup.sh"
if $install_kde; then
    if [[ -f "$KDE_SCRIPT" ]]; then
        bash "$KDE_SCRIPT" "${PASSTHROUGH_FLAGS[@]}"
        log_success "KDE customisations applied"
    else
        log_error "KDE script not found at $KDE_SCRIPT"
    fi
else
    log_info "Skipping KDE customisations"
fi

# ============================================================================
# Step 4: Top bar (optional)
# ============================================================================
log_step "Step 4/4 — Top bar (polybar)"

install_bar=false
if [[ $NONINTERACTIVE -eq 0 ]]; then
    echo ""
    log_info "Installs a floating, Waybar-style top bar with per-module pills,"
    log_info "a Tokyo Night palette, and Spotify/MPRIS controls via playerctl."
    log_warning "This will offer to remove/hide any Plasma panel on the top edge."
    echo ""
    reply=$(prompt_yn "Install the polybar top bar? [y/N] " "n")
    [[ "$reply" =~ ^[Yy]$ ]] && install_bar=true
fi

BAR_SCRIPT="$DOTFILES_DIR/profiles/bar-setup.sh"
if $install_bar; then
    if [[ -f "$BAR_SCRIPT" ]]; then
        bash "$BAR_SCRIPT" "${PASSTHROUGH_FLAGS[@]}"
        log_success "Top bar installed"
    else
        log_error "Bar script not found at $BAR_SCRIPT"
    fi
else
    log_info "Skipping top bar"
fi

# ============================================================================
# Summary
# ============================================================================
echo ""
log_success "======================================"
log_success "  Desktop Setup Complete!"
log_success "======================================"
echo ""
log_info "Installed and configured:"
echo "  + Base development tools (git, zsh, tmux, kitty, neovim, fzf, eza, ...)"
echo "  + Shell: bash (default) + zsh + Oh My Zsh + oh-my-posh"
echo "  + Terminal configs (tmux, kitty, bash, zsh, neovim/NvChad)"
$install_kde && echo "  + KDE Plasma customisations" || true
$install_bar && echo "  + polybar top bar with Spotify controls" || true
echo ""
log_info "Next steps:"
echo "  • Open a new terminal to load bash (run 'shell-toggle' to switch to zsh)"
echo "  • Start tmux and press Ctrl+Space + I to install tmux plugins"
echo "  • Run 'nvim' to bootstrap NvChad plugins"
$install_kde && echo "  • Log out and back in to apply KDE changes" || true
$install_bar && echo "  • Start the bar with 'bar' (it also autostarts on login)" || true
