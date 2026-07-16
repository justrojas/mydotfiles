#!/bin/bash
# Terminal Setup - symlinks dotfile configs and installs shell tooling
#
# Installs missing tools at pinned versions matching the author's setup,
# then symlinks configs. Installs: oh-my-zsh, zsh plugins, oh-my-posh, NvChad.
# Symlinks: zshrc, kitty config, tmux config. Initialises tmux submodules.
#
# Usage: bash terminal-setup.sh [--non-interactive] [--dry-run]

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$DOTFILES_DIR/lib/common.sh"

# ============================================================================
# Pinned versions (matching author's current setup)
# ============================================================================
readonly PINNED_TMUX_VERSION="3.4"
readonly PINNED_NVIM_VERSION="v0.11.6"
readonly PINNED_KITTY_VERSION="0.47.4"
readonly PINNED_ZSH_VERSION="5.8.1"
readonly PINNED_OMP_VERSION="29.9.2"
readonly PINNED_HERDR_VERSION="latest"

# ============================================================================
# Argument parsing
# ============================================================================
NONINTERACTIVE=0
UPDATE_MODE=0
for arg in "$@"; do
    [[ "$arg" == "--non-interactive" ]] && NONINTERACTIVE=1
    [[ "$arg" == "--update" ]]          && UPDATE_MODE=1
done

init_common "$@"

# Total number of log_step calls in this script — drives the X/N counter
STEP_TOTAL=11

# ============================================================================
# apt-get update deduplication — run at most once per invocation
# ============================================================================
_APT_UPDATED=0
apt_update_once() {
    if [[ $_APT_UPDATED -eq 0 && $DRY_RUN -eq 0 ]]; then
        sudo apt-get update -qq
        _APT_UPDATED=1
    fi
}

# Prompt helper: non-interactive mode returns the default answer
prompt_yn() {
    local question="$1" default="${2:-n}"
    if [[ $NONINTERACTIVE -eq 1 ]]; then
        echo "$default"
        return
    fi
    read -rp "$question" -n 1 </dev/tty
    echo >&2
    echo "${REPLY:-$default}"
}

# ============================================================================
# Banner
# ============================================================================
echo ""
echo "======================================"
echo "  Terminal Setup"
echo "  tmux + kitty + neovim + zsh"
echo "======================================"
echo ""
log_info "Dotfiles: $DOTFILES_DIR"
[[ $NONINTERACTIVE -eq 1 ]] && log_info "Running non-interactively (safe defaults)"
[[ $UPDATE_MODE -eq 1 ]]    && log_info "Update mode — pinned tools will be upgraded if stale"
[[ $DRY_RUN -eq 1 ]]        && log_warning "Dry-run mode — no changes will be made"
echo ""

# ============================================================================
# Install helpers (pinned versions)
# ============================================================================

# Install zsh via apt (pinned version is in Ubuntu 22.04+ repos)
install_zsh() {
    log_info "Installing zsh ${PINNED_ZSH_VERSION} via apt..."
    if [[ $DRY_RUN -eq 0 ]]; then
        apt_update_once
        sudo apt-get install -y zsh
    else
        log_info "[DRY RUN] Would run: sudo apt-get install -y zsh"
    fi
    log_success "zsh installed"
}

# Install kitty from the official release tarball into ~/.local/kitty.app.
#
# NOTE: apt on Ubuntu 22.04 only ships kitty 0.21.2, which has a Kitty
# keyboard-protocol bug that makes Enter/Tab/Backspace fire twice inside
# apps like herdr (fixed upstream in 0.33.0). We therefore pin a modern
# version from GitHub releases instead of using apt.
install_kitty() {
    log_info "Installing kitty ${PINNED_KITTY_VERSION} from official release tarball..."
    if [[ $DRY_RUN -eq 1 ]]; then
        log_info "[DRY RUN] Would install kitty ${PINNED_KITTY_VERSION} to ~/.local/kitty.app"
        return 0
    fi

    local tmpdir
    tmpdir=$(mktemp -d)
    trap "rm -rf $tmpdir" RETURN

    local arch tarch
    arch="$(uname -m)"
    case "$arch" in
        x86_64)  tarch="x86_64" ;;
        aarch64|arm64) tarch="arm64" ;;
        *) log_error "Unsupported architecture '$arch' for kitty tarball"; return 1 ;;
    esac

    local tarball="kitty-${PINNED_KITTY_VERSION}-${tarch}.txz"
    local url="https://github.com/kovidgoyal/kitty/releases/download/v${PINNED_KITTY_VERSION}/${tarball}"

    log_info "Downloading kitty ${PINNED_KITTY_VERSION} (${tarch})..."
    curl -fsSL "$url" -o "$tmpdir/$tarball"

    ensure_dir "$HOME/.local/bin"
    rm -rf "$HOME/.local/kitty.app"
    mkdir -p "$HOME/.local/kitty.app"
    tar -xJf "$tmpdir/$tarball" -C "$HOME/.local/kitty.app"

    # Symlink onto PATH (~/.local/bin sits ahead of /usr/bin, so this wins
    # over any stale apt-installed kitty).
    ln -sf "$HOME/.local/kitty.app/bin/kitty"  "$HOME/.local/bin/kitty"
    ln -sf "$HOME/.local/kitty.app/bin/kitten" "$HOME/.local/bin/kitten"

    # Desktop integration: install launcher entries pointing at the new binary
    # into the user applications dir (overrides any system /usr/share entry).
    # Without this, the app-menu/panel launcher keeps opening an old apt kitty,
    # which reintroduces the herdr double-keypress bug.
    local app_dst="$HOME/.local/share/applications"
    ensure_dir "$app_dst"
    local desk
    for desk in kitty.desktop kitty-open.desktop; do
        [[ -f "$HOME/.local/kitty.app/share/applications/$desk" ]] || continue
        cp "$HOME/.local/kitty.app/share/applications/$desk" "$app_dst/$desk"
        sed -i "s|Icon=kitty|Icon=$HOME/.local/kitty.app/share/icons/hicolor/256x256/apps/kitty.png|g" "$app_dst/$desk"
        sed -i "s|Exec=kitty|Exec=$HOME/.local/kitty.app/bin/kitty|g" "$app_dst/$desk"
    done
    update-desktop-database "$app_dst" 2>/dev/null || true

    log_success "kitty ${PINNED_KITTY_VERSION} installed to ~/.local/kitty.app"
}

# Install a package via apt — returns 1 (non-fatal) if the package is not found
install_apt_package() {
    local pkg="$1"
    log_info "Installing $pkg via apt..."
    if [[ $DRY_RUN -eq 0 ]]; then
        apt_update_once
        if ! sudo apt-get install -y "$pkg" 2>&1; then
            log_error "apt could not install '$pkg' — package may not be in the default repos"
            return 1
        fi
    else
        log_info "[DRY RUN] Would run: sudo apt-get install -y $pkg"
    fi
    log_success "$pkg installed"
}

# Install nodejs + npm via apt (needed by nvim Mason LSPs)
install_nodejs() {
    log_info "Installing nodejs and npm via apt..."
    if [[ $DRY_RUN -eq 0 ]]; then
        apt_update_once
        if ! sudo apt-get install -y nodejs npm 2>&1; then
            log_error "apt could not install nodejs/npm"
            return 1
        fi
    else
        log_info "[DRY RUN] Would run: sudo apt-get install -y nodejs npm"
    fi
    log_success "nodejs and npm installed"
}

# Install eza via the official gierens apt repo (not in default Ubuntu 22.04 repos)
install_eza() {
    log_info "Installing eza via gierens apt repo..."
    if [[ $DRY_RUN -eq 0 ]]; then
        apt_update_once
        sudo apt-get install -y gpg
        sudo mkdir -p /etc/apt/keyrings
        curl -fsSL https://raw.githubusercontent.com/eza-community/eza/main/deb.asc \
            | sudo gpg --dearmor -o /etc/apt/keyrings/gierens.gpg
        echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" \
            | sudo tee /etc/apt/sources.list.d/gierens.list >/dev/null
        sudo chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list
        sudo apt-get update -qq   # must re-run after adding the new repo
        sudo apt-get install -y eza
    else
        log_info "[DRY RUN] Would add gierens apt repo and install eza"
    fi
    log_success "eza installed"
}

# Install glow via the charm.sh apt repo (not in default Ubuntu 22.04 repos)
install_glow() {
    log_info "Installing glow via charm.sh apt repo..."
    if [[ $DRY_RUN -eq 0 ]]; then
        apt_update_once
        sudo apt-get install -y gpg
        sudo mkdir -p /etc/apt/keyrings
        curl -fsSL https://repo.charm.sh/apt/gpg.key \
            | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg
        echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" \
            | sudo tee /etc/apt/sources.list.d/charm.list >/dev/null
        sudo chmod 644 /etc/apt/keyrings/charm.gpg /etc/apt/sources.list.d/charm.list
        sudo apt-get update -qq   # must re-run after adding the new repo
        sudo apt-get install -y glow
    else
        log_info "[DRY RUN] Would add charm.sh apt repo and install glow"
    fi
    log_success "glow installed"
}

# Install zoxide via official installer (apt version 0.4.x is too old for 'zoxide init zsh --cmd cd')
install_zoxide() {
    log_info "Installing zoxide via official installer..."
    if [[ $DRY_RUN -eq 0 ]]; then
        curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash
    else
        log_info "[DRY RUN] Would install zoxide via official installer"
    fi
    log_success "zoxide installed"
}

# Install herdr — agent-aware terminal multiplexer
install_herdr() {
    log_info "Installing herdr via official installer..."
    if [[ $DRY_RUN -eq 0 ]]; then
        curl -fsSL https://herdr.dev/install.sh | sh
    else
        log_info "[DRY RUN] Would install herdr via https://herdr.dev/install.sh"
    fi
    log_success "herdr installed"
}

# Install fzf via git (required by oh-my-zsh fzf plugin — apt install alone is not enough)
install_fzf() {
    log_info "Installing fzf via git..."
    if [[ $DRY_RUN -eq 0 ]]; then
        if [[ -d "$HOME/.fzf" ]]; then
            git -C "$HOME/.fzf" pull --quiet
        else
            git clone --depth 1 https://github.com/junegunn/fzf.git "$HOME/.fzf"
        fi
        "$HOME/.fzf/install" --all --no-bash --no-fish --no-update-rc 2>/dev/null
    else
        log_info "[DRY RUN] Would clone fzf to ~/.fzf and run install"
    fi
    log_success "fzf installed"
}

# Install tmux 3.4 from source (Ubuntu 22.04 apt only has 3.2a)
install_tmux() {
    log_info "Installing tmux ${PINNED_TMUX_VERSION} from source..."
    if [[ $DRY_RUN -eq 1 ]]; then
        log_info "[DRY RUN] Would build tmux ${PINNED_TMUX_VERSION} from source"
        return 0
    fi

    local tmpdir
    tmpdir=$(mktemp -d)
    trap "rm -rf $tmpdir" RETURN

    log_info "Installing build dependencies..."
    apt_update_once
    sudo apt-get install -y build-essential libevent-dev libncurses-dev pkg-config bison

    local tarball="tmux-${PINNED_TMUX_VERSION}.tar.gz"
    local url="https://github.com/tmux/tmux/releases/download/${PINNED_TMUX_VERSION}/${tarball}"

    log_info "Downloading tmux ${PINNED_TMUX_VERSION}..."
    curl -fsSL "$url" -o "$tmpdir/$tarball"
    tar -xzf "$tmpdir/$tarball" -C "$tmpdir"

    log_info "Compiling tmux..."
    (
        builtin cd "$tmpdir/tmux-${PINNED_TMUX_VERSION}"
        ./configure --prefix="$HOME/.local"
        make -j"$(nproc)"
        make install
    )

    log_success "tmux ${PINNED_TMUX_VERSION} installed to ~/.local/bin/tmux"
    log_info "Ensure ~/.local/bin is early in PATH to use this version"
}

# Install neovim v0.11.6 from GitHub release binary
install_nvim() {
    log_info "Installing neovim ${PINNED_NVIM_VERSION} from GitHub release..."
    if [[ $DRY_RUN -eq 1 ]]; then
        log_info "[DRY RUN] Would install neovim ${PINNED_NVIM_VERSION} to ~/.local/bin/nvim"
        return 0
    fi

    local tmpdir
    tmpdir=$(mktemp -d)
    trap "rm -rf $tmpdir" RETURN

    local url="https://github.com/neovim/neovim/releases/download/${PINNED_NVIM_VERSION}/nvim-linux-x86_64.tar.gz"
    log_info "Downloading neovim ${PINNED_NVIM_VERSION}..."
    curl -fsSL "$url" -o "$tmpdir/nvim.tar.gz"
    tar -xzf "$tmpdir/nvim.tar.gz" -C "$tmpdir"

    ensure_dir "$HOME/.local/bin"
    ensure_dir "$HOME/.local/lib"

    # Copy binary and runtime
    cp "$tmpdir/nvim-linux-x86_64/bin/nvim" "$HOME/.local/bin/nvim"
    chmod +x "$HOME/.local/bin/nvim"
    rsync -a "$tmpdir/nvim-linux-x86_64/lib/nvim" "$HOME/.local/lib/" 2>/dev/null || \
        cp -r "$tmpdir/nvim-linux-x86_64/lib/nvim" "$HOME/.local/lib/"
    rsync -a "$tmpdir/nvim-linux-x86_64/share/" "$HOME/.local/share/" 2>/dev/null || \
        cp -r "$tmpdir/nvim-linux-x86_64/share/." "$HOME/.local/share/"

    log_success "neovim ${PINNED_NVIM_VERSION} installed to ~/.local/bin/nvim"
}

# Prompt the user whether to install a missing tool, then call the installer
handle_missing_tool() {
    local tool="$1"
    local install_fn="$2"
    local pinned_version="$3"

    echo ""
    log_warning "$tool is not installed (pinned version: $pinned_version)"

    if [[ $NONINTERACTIVE -eq 1 ]]; then
        log_info "Non-interactive mode: installing $tool automatically"
        $install_fn || log_warning "$tool installation failed — continuing without it"
        return
    fi

    echo "  [1/i] Install pinned version ($pinned_version)"
    echo "  [2/s] Skip (continue without $tool)"
    echo "  [3/a] Abort setup"
    echo ""
    read -rp "Choice [1/2/3]: " -n 1 choice </dev/tty
    echo "" >&2

    case "${choice,,}" in
        1|i) $install_fn || log_warning "$tool installation failed — continuing without it" ;;
        2|s) log_info "Skipping $tool" ;;
        3|a) log_error "Setup aborted."; exit 1 ;;
        *) log_info "No valid choice — skipping $tool" ;;
    esac
}

# ============================================================================
# Pre-flight: check for required tools, offer to install missing ones
# ============================================================================
log_step "Checking for required tools"

# Returns the installed version string for tools we track precisely; empty for others.
get_installed_version() {
    case "$1" in
        nvim)  nvim --version 2>/dev/null | head -1 | grep -oP 'v\d+\.\d+\.\d+' || true ;;
        tmux)  tmux -V 2>/dev/null | grep -oP '\d+\.\d+[a-z]?' | head -1 || true ;;
        kitty) kitty --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1 || true ;;
        *)     echo "" ;;
    esac
}

# Returns 0 (up-to-date / no check needed) or 1 (stale / needs upgrade).
is_tool_outdated() {
    local tool="$1"
    case "$tool" in
        nvim)
            local actual pinned
            actual=$(get_installed_version nvim)
            pinned="$PINNED_NVIM_VERSION"
            [[ -z "$actual" ]] && return 1
            local a_minor p_minor
            a_minor=$(echo "$actual" | grep -oP '\d+\.\d+' | head -1)
            p_minor=$(echo "$pinned"  | grep -oP '\d+\.\d+' | head -1)
            [[ "$(printf '%s\n' "$a_minor" "$p_minor" | sort -V | head -1)" != "$p_minor" ]] && return 1
            return 0
            ;;
        tmux)
            local actual="$( get_installed_version tmux )"
            [[ -z "$actual" ]] && return 1
            [[ "$(printf '%s\n' "$actual" "$PINNED_TMUX_VERSION" | sort -V | head -1)" != "$PINNED_TMUX_VERSION" ]] && return 1
            return 0
            ;;
        kitty)
            local actual="$( get_installed_version kitty )"
            [[ -z "$actual" ]] && return 1
            # Minimum acceptable kitty: 0.33.0 (keyboard-protocol fix)
            [[ "$(printf '%s\n' "$actual" "0.33.0" | sort -V | head -1)" != "0.33.0" ]] && return 1
            return 0
            ;;
        *)  return 0 ;;  # system tools — no pinned version to enforce
    esac
}

declare -A TOOL_VERSIONS=(
    [tmux]="$PINNED_TMUX_VERSION"
    [nvim]="$PINNED_NVIM_VERSION"
    [kitty]="$PINNED_KITTY_VERSION"
    [zsh]="$PINNED_ZSH_VERSION"
    [git]="system"
    [curl]="system"
    [npm]="system"
    [fzf]="system"
    [eza]="system"
    [batcat]="system"
    [zoxide]="system"
    [tree]="system"
    [glow]="system"
    [rsync]="system"
    [rg]="system"
    [fdfind]="system"
    [magick]="system"
    [pip3]="system"
    [wl-copy]="system"
    [herdr]="$PINNED_HERDR_VERSION"
)

declare -A TOOL_INSTALLERS=(
    [tmux]="install_tmux"
    [nvim]="install_nvim"
    [kitty]="install_kitty"
    [zsh]="install_zsh"
    [git]="install_apt_package git"
    [curl]="install_apt_package curl"
    [npm]="install_nodejs"
    [fzf]="install_fzf"
    [eza]="install_eza"
    [batcat]="install_apt_package bat"
    [zoxide]="install_zoxide"
    [tree]="install_apt_package tree"
    [glow]="install_glow"
    [rsync]="install_apt_package rsync"
    [rg]="install_apt_package ripgrep"
    [fdfind]="install_apt_package fd-find"
    [magick]="install_apt_package imagemagick"
    [pip3]="install_apt_package python3-pip"
    [wl-copy]="install_apt_package wl-clipboard"
    [herdr]="install_herdr"
)

for tool in tmux nvim kitty zsh git curl npm fzf eza batcat zoxide tree glow rsync rg fdfind magick pip3 wl-copy herdr; do
    if command -v "$tool" >/dev/null 2>&1; then
        if is_tool_outdated "$tool"; then
            actual=$(get_installed_version "$tool")
            pinned="${TOOL_VERSIONS[$tool]}"
            log_warning "$tool is outdated (installed: ${actual:-?}, pinned: $pinned)"
            if [[ $UPDATE_MODE -eq 1 ]]; then
                log_info "Upgrading $tool..."
                ${TOOL_INSTALLERS[$tool]} || log_warning "$tool upgrade failed — continuing"
            else
                log_info "Re-run with --update to upgrade automatically"
            fi
        else
            # For tools with a detectable version, show it; otherwise just confirm presence
            actual=$(get_installed_version "$tool")
            if [[ -n "$actual" ]]; then
                log_success "$tool found ($actual)"
            else
                log_success "$tool found"
            fi
        fi
    else
        handle_missing_tool "$tool" "${TOOL_INSTALLERS[$tool]}" "${TOOL_VERSIONS[$tool]}"
    fi
done

# fzf may be installed via apt but the oh-my-zsh plugin requires ~/.fzf to exist
if command -v fzf >/dev/null 2>&1 && [[ ! -d "$HOME/.fzf" ]]; then
    log_info "fzf found via apt but ~/.fzf missing — running git install for oh-my-zsh plugin..."
    install_fzf
fi
echo ""

# ============================================================================
# TMUX
# ============================================================================
log_step "tmux configuration"

if [[ -d "$DOTFILES_DIR/config/tmux" ]]; then
    safe_symlink "$DOTFILES_DIR/config/tmux/tmux.conf" "$HOME/.tmux.conf"
    safe_symlink "$DOTFILES_DIR/config/tmux" "$HOME/.config/tmux"
    log_success "tmux config linked"

    # Initialise plugin submodules (plugins live inside the repo as submodules)
    if [[ -f "$DOTFILES_DIR/.gitmodules" ]]; then
        log_info "Initialising tmux plugin submodules..."
        if [[ $DRY_RUN -eq 0 ]]; then
            git -C "$DOTFILES_DIR" submodule update --init --recursive
        else
            log_info "[DRY RUN] Would run: git submodule update --init --recursive"
        fi
        log_success "Tmux plugins ready"
        log_info "Start tmux and press Ctrl+Space + I to install/update plugins"
    fi
else
    log_error "Tmux config not found at $DOTFILES_DIR/config/tmux"
fi

# ============================================================================
# FONTS
# ============================================================================
log_step "Nerd fonts"

fonts_src="$DOTFILES_DIR/assets/fonts"
fonts_dst="$HOME/.local/share/fonts"

if [[ -d "$fonts_src" ]]; then
    ensure_dir "$fonts_dst"
    new_fonts=0
    for f in "$fonts_src"/*.ttf "$fonts_src"/*.otf; do
        [[ -f "$f" ]] || continue
        dest="$fonts_dst/$(basename "$f")"
        if [[ ! -f "$dest" ]]; then
            run_or_dry cp "$f" "$dest"
            (( new_fonts++ )) || true
        fi
    done
    if [[ $new_fonts -gt 0 ]]; then
        log_info "Rebuilding font cache..."
        run_or_dry fc-cache -f "$fonts_dst"
        log_success "Installed $new_fonts nerd font(s)"
    else
        log_success "Nerd fonts already installed"
    fi
else
    log_warning "assets/fonts not found — skipping font install"
fi

# ============================================================================
# KITTY
# ============================================================================
log_step "kitty configuration"

if [[ -d "$DOTFILES_DIR/config/kitty" ]]; then
    safe_symlink "$DOTFILES_DIR/config/kitty" "$HOME/.config/kitty"
    log_success "kitty config linked"
else
    log_error "Kitty config not found at $DOTFILES_DIR/config/kitty"
fi

# ============================================================================
# NEOVIM (NvChad)
# ============================================================================
log_step "neovim configuration (NvChad)"

install_nvchad() {
    if command -v git >/dev/null 2>&1; then
        log_info "Cloning NvChad..."
        run_or_dry git clone https://github.com/lsantos7654/dotnvim.git "$HOME/.config/nvim"
        log_success "NvChad installed — open nvim to trigger plugin bootstrap"
    else
        log_error "git not found — cannot clone NvChad"
    fi
}

if [[ -d "$HOME/.config/nvim" ]]; then
    log_warning "~/.config/nvim already exists"
    if [[ $NONINTERACTIVE -eq 0 ]]; then
        echo ""
        echo "  [b] Backup existing config and install NvChad"
        echo "  [s] Skip (keep existing config)"
        echo ""
        read -rp "Choice [b/s]: " -n 1 nvim_choice </dev/tty
        echo "" >&2
    else
        nvim_choice="s"
    fi

    case "${nvim_choice,,}" in
        b)
            backup_path "$HOME/.config/nvim"
            install_nvchad
            ;;
        *)
            log_info "Keeping existing nvim config"
            ;;
    esac
else
    install_nvchad
fi

# ============================================================================
# ZSH + Oh My Zsh + plugins + oh-my-posh
# ============================================================================
log_step "zsh configuration"

setup_zsh=true
if [[ $NONINTERACTIVE -eq 0 ]]; then
    reply=$(prompt_yn "Set up zsh configuration? [Y/n] " "y")
    [[ ! "$reply" =~ ^[Yy]$ ]] && setup_zsh=false
fi

if $setup_zsh; then
    if ! command -v zsh >/dev/null 2>&1; then
        log_warning "zsh not found — skipping zsh configuration"
    else
        # Oh My Zsh — install first, then re-apply the .zshrc symlink
        # (the --unattended installer overwrites ~/.zshrc with its own template)
        if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
            log_info "Installing Oh My Zsh..."
            if [[ $DRY_RUN -eq 0 ]]; then
                # RUNZSH=no  — don't exec zsh at the end (would kill this script)
                # KEEP_ZSHRC=yes — don't overwrite .zshrc (we symlink ours after)
                # </dev/tty  — prevent installer from hanging on piped stdin
                RUNZSH=no KEEP_ZSHRC=yes \
                    sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
                    "" --unattended </dev/tty || true
            else
                log_info "[DRY RUN] Would install Oh My Zsh"
            fi
            log_success "Oh My Zsh installed"
        else
            log_success "Oh My Zsh already installed"
        fi

        # .zshrc symlink — set AFTER oh-my-zsh so it overwrites the generated one
        if [[ -f "$DOTFILES_DIR/config/zsh/.zshrc" ]]; then
            safe_symlink "$DOTFILES_DIR/config/zsh/.zshrc" "$HOME/.zshrc"
            log_success ".zshrc linked"
        else
            log_error "No .zshrc found at $DOTFILES_DIR/config/zsh/.zshrc"
        fi

        # Set zsh as the login shell if not already set
        zsh_path="$(command -v zsh)"
        if [[ "$SHELL" != "$zsh_path" ]]; then
            log_info "Setting login shell to zsh ($zsh_path)..."
            # Ensure zsh is in /etc/shells (needed for chsh)
            if ! grep -qxF "$zsh_path" /etc/shells 2>/dev/null; then
                log_info "Adding $zsh_path to /etc/shells..."
                run_or_dry sudo bash -c "echo '$zsh_path' >> /etc/shells" </dev/tty
            fi
            if [[ $DRY_RUN -eq 0 ]]; then
                # Prefer usermod (no interactive password prompt); fall back to chsh
                if sudo usermod -s "$zsh_path" "$USER" 2>/dev/null; then
                    log_success "Login shell set to zsh via usermod — open a new terminal to apply"
                elif chsh -s "$zsh_path" </dev/tty 2>/dev/null; then
                    log_success "Login shell set to zsh — open a new terminal to apply"
                else
                    log_warning "Could not change login shell automatically (non-local user?)"
                    # Fallback: add exec zsh to ~/.bashrc so bash immediately hands off to zsh
                    if ! grep -qF "exec zsh" "$HOME/.bashrc" 2>/dev/null; then
                        log_info "Adding 'exec zsh' fallback to ~/.bashrc..."
                        printf '\n# Switch to zsh (login shell could not be changed)\n[ -x "%s" ] && exec "%s" -l\n' \
                            "$zsh_path" "$zsh_path" >> "$HOME/.bashrc"
                        log_success "~/.bashrc will launch zsh automatically"
                    else
                        log_success "~/.bashrc already has exec zsh fallback"
                    fi
                fi
            else
                log_info "[DRY RUN] Would run: chsh -s $zsh_path"
            fi
        else
            log_success "Login shell is already zsh"
        fi

        # zsh plugins
        ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
        if [[ -d "$HOME/.oh-my-zsh" ]] && command -v git >/dev/null 2>&1; then
            log_info "Installing zsh plugins..."
            declare -A ZSH_PLUGINS=(
                [zsh-autosuggestions]="https://github.com/zsh-users/zsh-autosuggestions"
                [zsh-syntax-highlighting]="https://github.com/zsh-users/zsh-syntax-highlighting"
            )
            for plugin in "${!ZSH_PLUGINS[@]}"; do
                target="$ZSH_CUSTOM/plugins/$plugin"
                if [[ ! -d "$target" ]]; then
                    run_or_dry git clone "${ZSH_PLUGINS[$plugin]}" "$target"
                    log_success "$plugin installed"
                else
                    log_success "$plugin already present"
                fi
            done
        fi

        # oh-my-posh
        if [[ -x "$HOME/.local/bin/oh-my-posh" ]]; then
            log_success "oh-my-posh already installed ($("$HOME/.local/bin/oh-my-posh" --version))"
        else
            log_info "Installing oh-my-posh..."
            ensure_dir "$HOME/.local/bin"
            if [[ $DRY_RUN -eq 0 ]]; then
                # oh-my-posh installer requires unzip
                if ! command -v unzip >/dev/null 2>&1; then
                    sudo apt-get install -y unzip >/dev/null 2>&1 || true
                fi
                curl -s https://ohmyposh.dev/install.sh | bash -s -- -d "$HOME/.local/bin" || true
            else
                log_info "[DRY RUN] Would install oh-my-posh to ~/.local/bin"
            fi
            log_success "oh-my-posh installed"
        fi
    fi
fi

# ============================================================================
# BASH (work shell) + bash<->zsh toggle preference
# ============================================================================
log_step "bash configuration"

if [[ -d "$DOTFILES_DIR/config/bash" ]]; then
    safe_symlink "$DOTFILES_DIR/config/bash/.bashrc"       "$HOME/.bashrc"
    safe_symlink "$DOTFILES_DIR/config/bash/.bash_profile" "$HOME/.bash_profile"
    log_success "bash config linked (.bashrc, .bash_profile)"

    # Seed the shell preference (defaults to zsh — the author's preference).
    # Interactive shells auto-switch toward this; `shell-toggle` flips it.
    ensure_dir "$HOME/.config/shell"
    if [[ ! -f "$HOME/.config/shell/preferred" ]]; then
        if [[ $DRY_RUN -eq 0 ]]; then
            echo "zsh" > "$HOME/.config/shell/preferred"
        fi
        log_info "Set default shell preference: zsh (run 'shell-toggle' to switch to bash)"
    else
        log_success "shell preference already set: $(cat "$HOME/.config/shell/preferred" 2>/dev/null)"
    fi
else
    log_error "bash config not found at $DOTFILES_DIR/config/bash"
fi

# ============================================================================
# Utility scripts → ~/.local/bin
# ============================================================================
log_step "Utility scripts"

ensure_dir "$HOME/.local/bin"

if [[ -d "$DOTFILES_DIR/scripts/utilities" ]]; then
    for script in "$DOTFILES_DIR/scripts/utilities"/*.sh; do
        [[ -f "$script" ]] || continue
        script_name=$(basename "$script")
        safe_symlink "$script" "$HOME/.local/bin/$script_name"
        run_or_dry chmod +x "$HOME/.local/bin/$script_name"
    done

    # kt (kitty theme switcher, no .sh extension)
    if [[ -f "$DOTFILES_DIR/scripts/utilities/kt" ]]; then
        safe_symlink "$DOTFILES_DIR/scripts/utilities/kt" "$HOME/.local/bin/kt"
        run_or_dry chmod +x "$HOME/.local/bin/kt"
        log_success "kt (kitty theme switcher) linked"
    fi

    log_success "Utility scripts linked to ~/.local/bin"
else
    log_warning "scripts/utilities not found — skipping utility scripts"
fi

if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    log_warning "~/.local/bin is not in PATH"
    log_info "Add to your shell config:  export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

# ============================================================================
# HERDR
# ============================================================================
log_step "herdr configuration"

if [[ -d "$DOTFILES_DIR/config/herdr" ]]; then
    ensure_dir "$HOME/.config/herdr"
    safe_symlink "$DOTFILES_DIR/config/herdr/config.toml" "$HOME/.config/herdr/config.toml"
    log_success "herdr config linked"
else
    log_warning "config/herdr not found — skipping"
fi

# ============================================================================
# OH-MY-POSH THEMES
# ============================================================================
log_step "oh-my-posh themes"

if [[ -d "$DOTFILES_DIR/config/oh-my-posh" ]]; then
    ensure_dir "$HOME/.config/oh-my-posh"

    # Symlink each custom theme file
    for theme in "$DOTFILES_DIR/config/oh-my-posh"/*.omp.json; do
        [[ -f "$theme" ]] || continue
        safe_symlink "$theme" "$HOME/.config/oh-my-posh/$(basename "$theme")"
    done

    # Set current.omp.json → tokyonight_storm (always on fresh install;
    # skip only if the user has already pointed it somewhere else via kt)
    omp_current="$HOME/.config/oh-my-posh/current.omp.json"
    omp_default="$HOME/.config/oh-my-posh/tokyonight_storm.omp.json"
    if [[ ! -L "$omp_current" ]]; then
        # No symlink yet (fresh install or was deleted) — create it
        run_or_dry ln -sf "$omp_default" "$omp_current"
        log_info "Set default omp theme: tokyonight_storm"
    elif [[ ! -e "$omp_current" ]]; then
        # Symlink exists but is broken — fix it
        run_or_dry ln -sf "$omp_default" "$omp_current"
        log_info "Repaired broken omp current theme → tokyonight_storm"
    else
        log_success "omp current theme already set: $(basename "$(readlink "$omp_current")" .omp.json)"
    fi

    # Create kt↔omp mapping symlinks from theme-mappings.conf
    mappings_file="$DOTFILES_DIR/config/oh-my-posh/theme-mappings.conf"
    omp_cache_dir="$HOME/.cache/oh-my-posh/themes"
    omp_gh_base="https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes"
    if [[ -f "$mappings_file" ]]; then
        log_info "Creating kitty↔omp theme mappings..."
        mapped=0
        while IFS='=' read -r kitty_theme omp_theme; do
            # Skip comments and blank lines
            [[ "$kitty_theme" =~ ^[[:space:]]*# || -z "${kitty_theme// }" ]] && continue
            kitty_theme="${kitty_theme// /}"
            omp_theme="${omp_theme// /}"
            dest="$HOME/.config/oh-my-posh/${kitty_theme}.omp.json"
            cache_src="$omp_cache_dir/${omp_theme}.omp.json"
            if [[ -f "$cache_src" ]]; then
                # Point to the already-cached stock theme
                run_or_dry ln -sf "$cache_src" "$dest"
                (( mapped++ )) || true
            elif [[ $DRY_RUN -eq 0 ]]; then
                # Cache not populated yet — download directly from GitHub
                curl -fsSL "${omp_gh_base}/${omp_theme}.omp.json" -o "$dest" 2>/dev/null && \
                    (( mapped++ )) || true
            else
                log_info "[DRY RUN] Would download omp theme ${omp_theme} for kitty theme ${kitty_theme}"
            fi
        done < "$mappings_file"
        log_success "Mapped $mapped kitty themes to oh-my-posh themes"
    fi

    log_success "oh-my-posh themes linked"
else
    log_warning "config/oh-my-posh not found — skipping"
fi

# ============================================================================
# VERIFICATION
# ============================================================================
log_step "Verifying installation"

VERIFY_PASS=0
VERIFY_FAIL=0

_vok()  { printf "  ${GREEN}✓${NC}  %-38s ${GREEN}%s${NC}\n"  "$1" "${2:-ok}"; (( VERIFY_PASS++ )) || true; }
_vfail(){ printf "  ${RED}✗${NC}  %-38s ${RED}%s${NC}\n"    "$1" "${2:-MISSING}"; (( VERIFY_FAIL++ )) || true; }

verify_symlink() {
    local label="$1" path="$2"
    if [[ -L "$path" && -e "$path" ]]; then _vok  "$label"
    elif [[ -L "$path" ]];                  then _vfail "$label" "broken symlink → $(readlink "$path")"
    else                                         _vfail "$label"
    fi
}

verify_cmd() {
    local label="$1" cmd="$2"
    if command -v "$cmd" >/dev/null 2>&1; then _vok "$label" "$(command -v "$cmd")"
    else                                        _vfail "$label"
    fi
}

echo ""
echo "  Symlinks"
verify_symlink ".zshrc"                    "$HOME/.zshrc"
verify_symlink ".tmux.conf"                "$HOME/.tmux.conf"
verify_symlink ".config/kitty"             "$HOME/.config/kitty"
verify_symlink ".config/herdr/config.toml" "$HOME/.config/herdr/config.toml"
verify_symlink ".local/bin/kt"             "$HOME/.local/bin/kt"

echo ""
echo "  Tools in PATH"
verify_cmd "zsh"          zsh
verify_cmd "tmux"         tmux
verify_cmd "kitty"        kitty
verify_cmd "nvim"         nvim
verify_cmd "oh-my-posh"   oh-my-posh
verify_cmd "herdr"        herdr
verify_cmd "fzf"          fzf
verify_cmd "eza"          eza
verify_cmd "zoxide"       zoxide
verify_cmd "bat / batcat" batcat
verify_cmd "rg"           rg

echo ""
echo "  Shell environment"
# Oh My Zsh
if [[ -d "$HOME/.oh-my-zsh" ]]; then _vok  "Oh My Zsh installed"
else                                  _vfail "Oh My Zsh installed"
fi

# Login shell
login_shell=$(getent passwd "$USER" 2>/dev/null | cut -d: -f7 || echo "")
if [[ "$login_shell" == "$(command -v zsh)" ]]; then _vok "Login shell is zsh"
else _vfail "Login shell is zsh" "current: ${login_shell:-unknown}"; fi

# omp theme
omp_current="$HOME/.config/oh-my-posh/current.omp.json"
if [[ -L "$omp_current" && -e "$omp_current" ]]; then
    _vok "omp current theme" "$(basename "$(readlink "$omp_current")" .omp.json)"
elif [[ -L "$omp_current" ]]; then
    _vfail "omp current theme" "broken → $(readlink "$omp_current")"
else
    _vfail "omp current theme"
fi

# NvChad
if [[ -d "$HOME/.config/nvim" ]]; then _vok "NvChad config present"
else                                    _vfail "NvChad config present"
fi

echo ""
if [[ $VERIFY_FAIL -eq 0 ]]; then
    log_success "All checks passed ($VERIFY_PASS/$((VERIFY_PASS + VERIFY_FAIL)))"
else
    log_warning "$VERIFY_FAIL check(s) failed — see above"
fi

# ============================================================================
# Summary
# ============================================================================
echo ""
log_success "======================================"
log_success "  Terminal Setup Complete!"
log_success "======================================"
echo ""
log_info "Next steps:"
[[ -L "$HOME/.tmux.conf" ]] && echo "  • Start tmux and press Ctrl+Space + I to install plugins"
[[ -L "$HOME/.config/herdr/config.toml" ]] && echo "  • Launch herdr with 'herdr' — prefix is Ctrl+Space (mirrors tmux bindings)"
[[ -d "$HOME/.config/nvim" ]] && echo "  • Open a NEW terminal, then run 'nvim' to bootstrap plugins"
[[ -L "$HOME/.zshrc" ]] && echo "  • Open a new terminal (or run 'exec zsh') to activate zsh + oh-my-posh"
echo ""
log_warning "IMPORTANT: Open a new terminal before running nvim — the correct nvim from ~/.local/bin must be in PATH"
echo ""
log_info "Tmux prefix: Ctrl+Space"
echo "  • Split horizontal : prefix + h"
echo "  • Split vertical   : prefix + v"
echo "  • Switch windows   : Alt+H / Alt+L  or  Alt+1-9"
echo "  • Install plugins  : prefix + I"
