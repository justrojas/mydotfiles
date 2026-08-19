#!/bin/bash
# VM Setup — headless / virtual-machine profile.
#
# Installs the smallest set of things that still gives you the full working
# environment on a box with no GUI: shell (bash primary, zsh available),
# neovim, tmux, and the CLI tools that config/shell/aliases.sh depends on.
#
# Deliberately EXCLUDED (see profiles/desktop-setup.sh if you want these):
#   kitty        — a terminal emulator is meaningless without a display; you
#                  connect to a VM through some other terminal.
#   Nerd fonts   — rendered by the *client* terminal, not the VM. Install them
#                  on the machine you're SSH-ing FROM.
#   herdr        — GUI-oriented multiplexer; tmux covers this over SSH and is
#                  what you already have configured.
#   KDE / Latte / polybar / touchegg — desktop only.
#   imagemagick, wl-clipboard — image previews and Wayland clipboard need a
#                  display server.
#
# Clipboard note: over SSH neither wl-copy nor xclip will do what you want.
# tmux's own copy-mode buffer is the practical answer, and OSC-52 lets tmux
# push to your *local* clipboard — already enabled via tmux-yank.
#
# Usage: bash vm-setup.sh [--non-interactive] [--dry-run] [--update]

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$DOTFILES_DIR/lib/common.sh"
# shellcheck source=../lib/ui.sh
source "$DOTFILES_DIR/lib/ui.sh"

NONINTERACTIVE=0
UPDATE_MODE=0
for arg in "$@"; do
    [[ "$arg" == "--non-interactive" ]] && NONINTERACTIVE=1
    [[ "$arg" == "--update" ]]          && UPDATE_MODE=1
done

init_common "$@"

STEP_TOTAL=3

echo ""
echo "======================================"
echo "   VM / Headless Setup"
echo "======================================"
echo ""

# ============================================================================
# Preflight
# ============================================================================
log_step "Preflight checks"

OS=$(detect_os)
case "$OS" in
    ubuntu|debian|pop|linuxmint)
        log_success "Supported OS detected: $OS"
        ;;
    *)
        log_error "vm-setup currently supports Ubuntu/Debian only (detected: $OS)"
        log_info "The config symlinks are distro-agnostic — you can run"
        log_info "  bash profiles/terminal-setup.sh --minimal"
        log_info "after installing the packages yourself."
        exit 1
        ;;
esac

if [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
    log_warning "A display server appears to be running (DISPLAY/WAYLAND_DISPLAY set)."
    log_warning "If this is a desktop, you probably want profiles/desktop-setup.sh instead."
fi

if ! sudo -n true 2>/dev/null; then
    log_info "This profile needs sudo for apt. You may be prompted."
fi

# ============================================================================
# Packages
# ============================================================================
log_step "Installing base packages"

# Only what a headless box actually needs. Compare with
# profiles/install-packages.sh, which additionally pulls in GUI tooling.
VM_PACKAGES=(
    # shells + multiplexer
    bash zsh tmux
    # editor toolchain (nvim itself comes from the pinned tarball below)
    git curl wget unzip
    build-essential
    # things config/shell/aliases.sh and the nvim config expect
    bat tree rsync ripgrep fd-find
    python3 python3-venv python3-pip
    # terminfo database — without ncurses-bin there is no `tic`/`infocmp`,
    # and config/shell/env.sh cannot validate or repair a bogus $TERM.
    ncurses-bin ncurses-term
    # misc
    unzip ca-certificates gnupg
)

if [[ $DRY_RUN -eq 0 ]]; then
    sudo apt-get update -qq
    sudo apt-get install -y "${VM_PACKAGES[@]}"
else
    log_info "[DRY RUN] Would run: sudo apt-get install -y ${VM_PACKAGES[*]}"
fi
log_success "Base packages installed"

# ============================================================================
# Delegate to terminal-setup in minimal mode
# ============================================================================
log_step "Configuring shell environment"

# --minimal skips fonts, kitty and herdr, and drops the GUI-only entries from
# the tool-install list, but still installs nvim/tmux/fzf/eza/zoxide/glow at
# their pinned versions and links every config.
flags=(--minimal)
[[ $NONINTERACTIVE -eq 1 ]] && flags+=(--non-interactive)
[[ $UPDATE_MODE   -eq 1 ]] && flags+=(--update)
[[ $DRY_RUN       -eq 1 ]] && flags+=(--dry-run)

bash "$DOTFILES_DIR/profiles/terminal-setup.sh" "${flags[@]}"

echo ""
log_success "VM setup complete"
echo ""
echo "  Next steps:"
echo "  • Open a new shell (bash is the default; 'shell-toggle' switches to zsh)"
echo "  • Start tmux and press Ctrl+Space + I to install tmux plugins"
echo "  • Launch nvim once to let lazy.nvim sync plugins"
echo ""
echo "  Note: your *client* terminal supplies the font and the terminfo entry."
echo "  If TUIs look wrong over SSH, connect with 'kitten ssh' from kitty —"
echo "  the shared aliases already do this automatically when TERM=xterm-kitty."
echo ""
