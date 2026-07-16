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
# kitty (pinned modern release — NOT apt)
# ============================================================================
# apt on Ubuntu 22.04 only ships kitty 0.21.2, which has a Kitty
# keyboard-protocol bug that makes Enter/Tab/Backspace fire twice inside
# apps like herdr (fixed upstream in 0.33.0). Install a modern release from
# GitHub into ~/.local/kitty.app instead.
readonly KITTY_VERSION="0.47.4"
log_step "Installing kitty ${KITTY_VERSION}"
kitty_actual=$(kitty --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1 || echo "0.0.0")
if command -v kitty >/dev/null 2>&1 && \
   [[ "$(printf '%s\n' "$kitty_actual" "0.33.0" | sort -V | head -1)" == "0.33.0" || \
      "$kitty_actual" == "0.33.0" ]]; then
    log_success "kitty already installed ($kitty_actual)"
elif [[ $DRY_RUN -eq 1 ]]; then
    log_info "[DRY RUN] Would install kitty ${KITTY_VERSION} to ~/.local/kitty.app"
else
    arch="$(uname -m)"
    case "$arch" in
        x86_64)        tarch="x86_64" ;;
        aarch64|arm64) tarch="arm64" ;;
        *) log_error "Unsupported architecture '$arch' for kitty tarball"; tarch="" ;;
    esac
    if [[ -n "$tarch" ]]; then
        kitty_tmp=$(mktemp -d)
        tarball="kitty-${KITTY_VERSION}-${tarch}.txz"
        url="https://github.com/kovidgoyal/kitty/releases/download/v${KITTY_VERSION}/${tarball}"
        log_info "Downloading kitty ${KITTY_VERSION} (${tarch})..."
        curl -fsSL "$url" -o "$kitty_tmp/$tarball"
        ensure_dir "$HOME/.local/bin"
        rm -rf "$HOME/.local/kitty.app"
        mkdir -p "$HOME/.local/kitty.app"
        tar -xJf "$kitty_tmp/$tarball" -C "$HOME/.local/kitty.app"
        ln -sf "$HOME/.local/kitty.app/bin/kitty"  "$HOME/.local/bin/kitty"
        ln -sf "$HOME/.local/kitty.app/bin/kitten" "$HOME/.local/bin/kitten"
        # Desktop integration so the app-menu launcher uses the new binary
        # (otherwise a stale /usr/bin/kitty keeps opening).
        app_dst="$HOME/.local/share/applications"
        ensure_dir "$app_dst"
        for desk in kitty.desktop kitty-open.desktop; do
            [ -f "$HOME/.local/kitty.app/share/applications/$desk" ] || continue
            cp "$HOME/.local/kitty.app/share/applications/$desk" "$app_dst/$desk"
            sed -i "s|Icon=kitty|Icon=$HOME/.local/kitty.app/share/icons/hicolor/256x256/apps/kitty.png|g" "$app_dst/$desk"
            sed -i "s|Exec=kitty|Exec=$HOME/.local/kitty.app/bin/kitty|g" "$app_dst/$desk"
        done
        update-desktop-database "$app_dst" 2>/dev/null || true
        rm -rf "$kitty_tmp"
        log_success "kitty ${KITTY_VERSION} installed to ~/.local/kitty.app"
    fi
fi

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
