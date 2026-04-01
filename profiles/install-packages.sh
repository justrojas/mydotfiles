#!/bin/bash
# Install Packages - installs system packages on Ubuntu/Debian
# This script only installs packages; it does NOT configure dotfiles.
# Run terminal-setup.sh afterwards to configure your terminal environment.
#
# Usage: bash install-packages.sh [--dry-run]

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$DOTFILES_DIR/lib/common.sh"

init_common "$@"

# ============================================================================
# OS check
# ============================================================================
log_step "Checking OS compatibility"
OS=$(detect_os)
if [[ ! "$OS" =~ ^(ubuntu|debian)$ ]]; then
    log_error "This script only supports Ubuntu/Debian (detected: $OS)"
    exit 1
fi
log_success "OS: $OS"

check_not_root
check_sudo
check_internet

# ============================================================================
# Core apt packages
# ============================================================================
log_step "Installing core packages"
apt_install \
    git wget curl unzip \
    zsh \
    tmux \
    kitty \
    fzf \
    bat \
    btop nvtop \
    neofetch xclip \
    vim \
    tldr \
    python3 python3-venv \
    npm nodejs \
    p7zip-full \
    autoconf automake libtool \
    build-essential libevent-dev libncurses5-dev libncursesw5-dev \
    gpg

# ============================================================================
# eza (modern ls replacement)
# ============================================================================
log_step "Installing eza"
if command -v eza >/dev/null 2>&1; then
    log_success "eza already installed"
else
    log_info "Adding eza apt repository..."
    run_or_dry sudo mkdir -p /etc/apt/keyrings
    if [[ $DRY_RUN -eq 0 ]]; then
        wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc \
            | sudo gpg --dearmor -o /etc/apt/keyrings/gierens.gpg
        echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" \
            | sudo tee /etc/apt/sources.list.d/gierens.list
        sudo chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list
    fi
    apt_install eza
fi

# ============================================================================
# glow (markdown renderer)
# ============================================================================
log_step "Installing glow"
if command -v glow >/dev/null 2>&1; then
    log_success "glow already installed"
else
    log_info "Adding Charm apt repository..."
    if [[ $DRY_RUN -eq 0 ]]; then
        curl -fsSL https://repo.charm.sh/apt/gpg.key \
            | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg
        echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" \
            | sudo tee /etc/apt/sources.list.d/charm.list
    fi
    apt_install glow
fi

# ============================================================================
# zoxide (smart cd)
# ============================================================================
log_step "Installing zoxide"
if command -v zoxide >/dev/null 2>&1; then
    log_success "zoxide already installed"
else
    if [[ $DRY_RUN -eq 0 ]]; then
        curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
    else
        log_info "[DRY RUN] Would install zoxide via install script"
    fi
    log_success "zoxide installed"
fi

# ============================================================================
# neovim (latest stable AppImage)
# ============================================================================
log_step "Installing neovim"
if command -v nvim >/dev/null 2>&1; then
    log_success "neovim already installed ($(nvim --version | head -1))"
else
    log_info "Downloading neovim AppImage..."
    NVIM_TMP="$HOME/Downloads/nvim.appimage"
    ensure_dir "$HOME/Downloads"
    if [[ $DRY_RUN -eq 0 ]]; then
        wget -q --show-progress \
            -O "$NVIM_TMP" \
            https://github.com/neovim/neovim/releases/download/stable/nvim.appimage
        chmod +x "$NVIM_TMP"
        sudo mv "$NVIM_TMP" /usr/local/bin/nvim

        if ! nvim --version >/dev/null 2>&1; then
            log_warning "AppImage failed, falling back to apt..."
            sudo apt-get install -y neovim
        fi
    else
        log_info "[DRY RUN] Would download and install neovim AppImage"
    fi
    log_success "neovim installed"
fi

# ============================================================================
# TypeScript (global npm package)
# ============================================================================
log_step "Installing TypeScript"
if command -v tsc >/dev/null 2>&1; then
    log_success "TypeScript already installed"
else
    run_or_dry sudo npm install -g typescript
    log_success "TypeScript installed"
fi

# ============================================================================
# tldr database update
# ============================================================================
log_step "Updating tldr database"
run_or_dry tldr --update || log_warning "tldr update failed (non-fatal)"

# ============================================================================
# Done
# ============================================================================
echo ""
log_success "Base tools installation complete!"
log_info "Run profiles/terminal-setup.sh to configure your terminal environment."
