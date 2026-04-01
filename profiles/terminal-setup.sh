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
readonly PINNED_KITTY_VERSION="0.21.2"
readonly PINNED_ZSH_VERSION="5.8.1"
readonly PINNED_OMP_VERSION="29.9.2"

# ============================================================================
# Argument parsing
# ============================================================================
NONINTERACTIVE=0
for arg in "$@"; do
    [[ "$arg" == "--non-interactive" ]] && NONINTERACTIVE=1
done

init_common "$@"

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
[[ $DRY_RUN -eq 1 ]]        && log_warning "Dry-run mode — no changes will be made"
echo ""

# ============================================================================
# Install helpers (pinned versions)
# ============================================================================

# Install zsh via apt (pinned version is in Ubuntu 22.04+ repos)
install_zsh() {
    log_info "Installing zsh ${PINNED_ZSH_VERSION} via apt..."
    if [[ $DRY_RUN -eq 0 ]]; then
        sudo apt-get update -qq
        sudo apt-get install -y zsh
    else
        log_info "[DRY RUN] Would run: sudo apt-get install -y zsh"
    fi
    log_success "zsh installed"
}

# Install kitty via apt (0.21.2 available on Ubuntu 22.04)
install_kitty() {
    log_info "Installing kitty ${PINNED_KITTY_VERSION} via apt..."
    if [[ $DRY_RUN -eq 0 ]]; then
        sudo apt-get update -qq
        sudo apt-get install -y kitty
    else
        log_info "[DRY RUN] Would run: sudo apt-get install -y kitty"
    fi
    log_success "kitty installed"
}

# Install git/curl via apt
install_apt_package() {
    local pkg="$1"
    log_info "Installing $pkg via apt..."
    if [[ $DRY_RUN -eq 0 ]]; then
        sudo apt-get update -qq
        sudo apt-get install -y "$pkg"
    else
        log_info "[DRY RUN] Would run: sudo apt-get install -y $pkg"
    fi
    log_success "$pkg installed"
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
    sudo apt-get update -qq
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
        $install_fn
        return
    fi

    echo "  [1/i] Install pinned version ($pinned_version)"
    echo "  [2/s] Skip (continue without $tool)"
    echo "  [3/a] Abort setup"
    echo ""
    read -rp "Choice [1/2/3]: " -n 1 choice </dev/tty
    echo "" >&2

    case "${choice,,}" in
        1|i) $install_fn ;;
        2|s) log_info "Skipping $tool" ;;
        3|a) log_error "Setup aborted."; exit 1 ;;
        *) log_info "No valid choice — skipping $tool" ;;
    esac
}

# ============================================================================
# Pre-flight: check for required tools, offer to install missing ones
# ============================================================================
log_step "Checking for required tools"

declare -A TOOL_VERSIONS=(
    [tmux]="$PINNED_TMUX_VERSION"
    [nvim]="$PINNED_NVIM_VERSION"
    [kitty]="$PINNED_KITTY_VERSION"
    [zsh]="$PINNED_ZSH_VERSION"
    [git]="system"
    [curl]="system"
)

declare -A TOOL_INSTALLERS=(
    [tmux]="install_tmux"
    [nvim]="install_nvim"
    [kitty]="install_kitty"
    [zsh]="install_zsh"
    [git]="install_apt_package git"
    [curl]="install_apt_package curl"
)

for tool in tmux nvim kitty zsh git curl; do
    if command -v "$tool" >/dev/null 2>&1; then
        log_success "$tool found"
    else
        handle_missing_tool "$tool" "${TOOL_INSTALLERS[$tool]}" "${TOOL_VERSIONS[$tool]}"
    fi
done
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
            # Ensure zsh is in /etc/shells
            if ! grep -qxF "$zsh_path" /etc/shells 2>/dev/null; then
                log_info "Adding $zsh_path to /etc/shells..."
                run_or_dry sudo bash -c "echo '$zsh_path' >> /etc/shells"
            fi
            if [[ $DRY_RUN -eq 0 ]]; then
                # chsh only works for local /etc/passwd users; fall back to usermod
                # Redirect stdin from /dev/tty so chsh password prompt doesn't hang
                if chsh -s "$zsh_path" </dev/tty 2>/dev/null; then
                    log_success "Login shell set to zsh — open a new terminal to apply"
                elif sudo usermod -s "$zsh_path" "$USER" 2>/dev/null; then
                    log_success "Login shell set to zsh via usermod — open a new terminal to apply"
                else
                    log_warning "Could not change login shell automatically (non-local user?)"
                    # Fallback: add exec zsh to ~/.bashrc so bash immediately hands off to zsh
                    if ! grep -qF "exec zsh" "$HOME/.bashrc" 2>/dev/null; then
                        log_info "Adding 'exec zsh' fallback to ~/.bashrc..."
                        run_or_dry bash -c "printf '\n# Switch to zsh (login shell could not be changed)\n[ -x \"$zsh_path\" ] && exec \"$zsh_path\" -l\n' >> \"\$HOME/.bashrc\""
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
# Summary
# ============================================================================
echo ""
log_success "======================================"
log_success "  Terminal Setup Complete!"
log_success "======================================"
echo ""
log_info "What was configured:"
[[ -L "$HOME/.tmux.conf" ]]         && echo "  + tmux       ($DOTFILES_DIR/config/tmux/tmux.conf)"
[[ -L "$HOME/.config/kitty" ]]      && echo "  + kitty      ($DOTFILES_DIR/config/kitty/)"
[[ -d "$HOME/.config/nvim" ]]       && echo "  + neovim     (NvChad)"
[[ -L "$HOME/.zshrc" ]]             && echo "  + zsh        ($DOTFILES_DIR/config/zsh/.zshrc)"
[[ -L "$HOME/.local/bin/kt" ]]      && echo "  + utilities  (kt + others in ~/.local/bin)"
echo ""
log_info "Next steps:"
[[ -L "$HOME/.tmux.conf" ]] && echo "  • Start tmux and press Ctrl+Space + I to install plugins"
[[ -d "$HOME/.config/nvim" ]] && echo "  • Run 'nvim' to bootstrap plugins"
[[ -L "$HOME/.zshrc" ]] && echo "  • Run 'exec zsh' or open a new terminal"
echo ""
log_info "Tmux prefix: Ctrl+Space"
echo "  • Split horizontal : prefix + h"
echo "  • Split vertical   : prefix + v"
echo "  • Switch windows   : Alt+H / Alt+L  or  Alt+1-9"
echo "  • Install plugins  : prefix + I"
