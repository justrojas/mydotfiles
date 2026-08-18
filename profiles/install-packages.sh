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
# Pinned tool installers, shared with profiles/terminal-setup.sh — single source
# of truth for kitty/nvim/eza/glow/zoxide and their version pins.
# shellcheck source=../lib/installers.sh
source "$DOTFILES_DIR/lib/installers.sh"

init_common "$@"

# This script has never prompted: it is the unattended package-installation
# stage, invoked by desktop-setup.sh and by the Docker suites. install_tools()
# falls back to an interactive three-way prompt for a missing tool, so declare
# non-interactive intent explicitly — otherwise a missing tool would block
# waiting for input that is never coming, or read EOF and silently skip the
# install. Honours an explicit --non-interactive too, for symmetry.
NONINTERACTIVE=1

STEP_TOTAL=5

# Tools installed by lib/installers.sh land in ~/.local/bin. Create it and adopt
# the shell's canonical PATH BEFORE any install runs, otherwise _confirm_install
# checks against a PATH that lacks the very directory the installers write to,
# and reports successful installs as failures.
# (env.sh's _prepend_path only adds directories that already exist — hence the
# ensure_dir first.)
ensure_dir "$HOME/.local/bin"
if [[ -f "$DOTFILES_DIR/config/shell/env.sh" ]]; then
    # shellcheck source=../config/shell/env.sh
    source "$DOTFILES_DIR/config/shell/env.sh"
fi

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
# NOTE: tmux and fzf are deliberately absent.
#
# apt's tmux on 22.04 is older than the pinned 3.4, and apt's fzf is too old
# for the oh-my-zsh plugin integration, so terminal-setup builds tmux from
# source and installs fzf via git immediately afterwards. Listing them here
# meant a desktop install downloaded, compiled and discarded a second copy of
# each — the same double-install this file's header already documents having
# fixed for kitty and neovim. The build dependencies below (autoconf, libevent,
# ncurses) are kept precisely because the source build needs them.
apt_install \
    git wget curl unzip \
    zsh \
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
    gpg \
    gawk

# ============================================================================
# Pinned third-party tools
# ============================================================================
# kitty, eza, glow, zoxide and neovim all used to be installed again here, with
# their own copy-pasted implementations. Because profiles/desktop-setup.sh runs
# this script and then terminal-setup.sh, that meant kitty was downloaded and
# extracted twice, and neovim was installed twice to two different paths:
# an unpinned 'stable' AppImage into /usr/local/bin here, versus the pinned
# tarball into ~/.local/bin there — two binaries on PATH, pin silently defeated.
#
# All of it now lives once in lib/installers.sh, which both profiles source.
#
# The presence check used to be a bare `command -v` here, while terminal-setup
# had a full version table. That gap is how apt kitty 0.21.2 survived a desktop
# install: it satisfied `command -v kitty`, so this step reported "already
# installed" and skipped it, and the herdr double-keypress came back. Both
# profiles now share install_tools(), which knows about pinned versions and
# hard minimums.
log_step "Installing pinned third-party tools"

# tmux and fzf are here rather than in the apt list above because both need
# versions newer than 22.04 ships: tmux is built from source at the pin, and
# fzf is installed via git so the oh-my-zsh plugin can find it. Routing them
# through install_tools means terminal-setup's later pass sees them already
# present and current, instead of building a second copy.
install_tools kitty eza glow zoxide nvim tmux fzf


# ============================================================================
# TypeScript (global npm package)
# ============================================================================
log_step "Installing TypeScript"

# Ubuntu 22.04's `nodejs` package is v12, which is EOL and below the engine
# floor of every current npm package. Installing latest `typescript` there
# "succeeds" with an EBADENGINE warning and produces a `tsc` that cannot run.
#
# So: check the node major version and install a TypeScript that actually
# works with it, rather than silently shipping a broken binary.
if command -v tsc >/dev/null 2>&1; then
    log_success "TypeScript already installed ($(tsc --version 2>/dev/null || echo 'version unknown'))"
elif ! command -v node >/dev/null 2>&1; then
    log_warning "node not found — skipping TypeScript"
else
    node_major=$(node --version 2>/dev/null | sed 's/^v//' | cut -d. -f1)
    if [[ -z "$node_major" ]]; then
        log_warning "Could not determine node version — skipping TypeScript"
    elif [[ "$node_major" -lt 14 ]]; then
        # TypeScript 4.x is the last line supporting node 12.
        log_warning "node v${node_major} is EOL (Ubuntu 22.04 ships v12)"
        log_info "Installing typescript@4 — the last release compatible with node <14"
        log_info "For a modern toolchain install node via nvm, then: npm i -g typescript"
        run_or_dry sudo npm install -g 'typescript@4' \
            || log_warning "TypeScript install failed — continuing"
    else
        run_or_dry sudo npm install -g typescript \
            || log_warning "TypeScript install failed — continuing"
    fi
    _confirm_install tsc "TypeScript" || true
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
