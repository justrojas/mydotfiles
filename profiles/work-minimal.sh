#!/bin/bash
# Work Minimal Setup - tmux, kitty, neovim configs only
# Designed for work environments where you have limited sudo access
# Only configures existing installations - does NOT install packages

set -e

# Get the dotfiles directory (works from any location)
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Backup existing file/directory
backup_if_exists() {
    local path=$1
    if [ -e "$path" ] && [ ! -L "$path" ]; then
        local backup="${path}.bak.$(date +%Y%m%d_%H%M%S)"
        print_warning "Backing up existing $path to $backup"
        mv "$path" "$backup"
    elif [ -L "$path" ]; then
        # If it's already a symlink, just remove it
        rm "$path"
    fi
}

echo ""
echo "======================================"
echo "  Work Minimal Setup"
echo "  tmux + kitty + neovim configs"
echo "======================================"
echo ""
print_info "Dotfiles directory: $DOTFILES_DIR"
echo ""

# Check for required tools
print_info "Checking for required tools..."
MISSING_TOOLS=()

if ! command_exists tmux; then
    print_warning "tmux not found"
    MISSING_TOOLS+=("tmux")
fi

if ! command_exists nvim; then
    print_warning "neovim not found"
    MISSING_TOOLS+=("neovim")
fi

if ! command_exists kitty; then
    print_warning "kitty not found"
    MISSING_TOOLS+=("kitty")
fi

if [ ${#MISSING_TOOLS[@]} -gt 0 ]; then
    echo ""
    print_warning "Missing tools: ${MISSING_TOOLS[*]}"
    print_info "Install them with:"
    echo "  Ubuntu/Debian: sudo apt install tmux neovim kitty"
    echo "  Fedora: sudo dnf install tmux neovim kitty"
    echo "  Arch: sudo pacman -S tmux neovim kitty"
    echo ""
    read -p "Continue with configuration anyway? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_error "Setup cancelled"
        exit 1
    fi
fi

echo ""
print_info "Configuring tools..."

# ============================================================================
# TMUX Configuration
# ============================================================================
print_info "Setting up tmux configuration..."

# Create tmux config directory
mkdir -p "$HOME/.config/tmux"

# Backup and link tmux config
if [ -f "$DOTFILES_DIR/config/tmux/tmux.conf" ]; then
    # Link to both locations for compatibility
    backup_if_exists "$HOME/.tmux.conf"
    ln -sf "$DOTFILES_DIR/config/tmux/tmux.conf" "$HOME/.tmux.conf"

    backup_if_exists "$HOME/.config/tmux/tmux.conf"
    ln -sf "$DOTFILES_DIR/config/tmux/tmux.conf" "$HOME/.config/tmux/tmux.conf"

    print_success "Linked tmux configuration"

    # Setup TPM (Tmux Plugin Manager)
    if [ ! -d "$HOME/.config/tmux/plugins/tpm" ]; then
        print_info "Installing Tmux Plugin Manager..."
        if command_exists git; then
            git clone https://github.com/tmux-plugins/tpm "$HOME/.config/tmux/plugins/tpm"
            print_success "TPM installed"
            print_info "After setup: run 'tmux' and press Ctrl+Space + I to install plugins"
        else
            print_warning "git not found - skipping TPM installation"
            print_info "Install git and run: git clone https://github.com/tmux-plugins/tpm ~/.config/tmux/plugins/tpm"
        fi
    else
        print_success "TPM already installed"
    fi
else
    print_error "Tmux config not found at $DOTFILES_DIR/config/tmux/tmux.conf"
fi

# ============================================================================
# KITTY Configuration
# ============================================================================
print_info "Setting up kitty configuration..."

if [ -d "$DOTFILES_DIR/config/kitty" ]; then
    backup_if_exists "$HOME/.config/kitty"
    ln -sf "$DOTFILES_DIR/config/kitty" "$HOME/.config/kitty"
    print_success "Linked kitty configuration"
else
    print_error "Kitty config not found at $DOTFILES_DIR/config/kitty"
fi

# ============================================================================
# NEOVIM Configuration
# ============================================================================
print_info "Setting up neovim configuration..."

# Check if nvim config already exists
if [ -d "$HOME/.config/nvim" ]; then
    print_warning "Neovim config already exists at ~/.config/nvim"
    read -p "Replace with NvChad? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if command_exists git; then
            backup_if_exists "$HOME/.config/nvim"
            git clone https://github.com/lsantos7654/NvChad.git "$HOME/.config/nvim"
            print_success "NvChad installed"
            print_info "Open nvim to trigger plugin installation"
        else
            print_error "git not found - cannot clone NvChad"
        fi
    else
        print_info "Keeping existing nvim config"
    fi
else
    # Install NvChad
    if command_exists git; then
        print_info "Installing NvChad..."
        git clone https://github.com/lsantos7654/NvChad.git "$HOME/.config/nvim"
        print_success "NvChad installed"
        print_info "Open nvim to trigger plugin installation"
    else
        print_warning "git not found - skipping nvim config installation"
    fi
fi

# ============================================================================
# ZSH Configuration (Optional)
# ============================================================================
echo ""
read -p "Setup zsh configuration? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    if command_exists zsh; then
        print_info "Setting up zsh configuration..."

        # Check for OS-specific zshrc
        OS_SPECIFIC_ZSHRC=""
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            if [ -f "$DOTFILES_DIR/config/zsh/${ID}.zshrc" ]; then
                OS_SPECIFIC_ZSHRC="$DOTFILES_DIR/config/zsh/${ID}.zshrc"
            fi
        fi

        # Use OS-specific or fallback to generic
        if [ -n "$OS_SPECIFIC_ZSHRC" ]; then
            backup_if_exists "$HOME/.zshrc"
            ln -sf "$OS_SPECIFIC_ZSHRC" "$HOME/.zshrc"
            print_success "Linked OS-specific zshrc"
        elif [ -f "$DOTFILES_DIR/config/zsh/.zshrc" ]; then
            backup_if_exists "$HOME/.zshrc"
            ln -sf "$DOTFILES_DIR/config/zsh/.zshrc" "$HOME/.zshrc"
            print_success "Linked generic zshrc"
        else
            print_error "No zshrc found in dotfiles"
        fi

        # Link p10k config if it exists
        if [ -f "$DOTFILES_DIR/config/zsh/.p10k.zsh" ]; then
            backup_if_exists "$HOME/.p10k.zsh"
            ln -sf "$DOTFILES_DIR/config/zsh/.p10k.zsh" "$HOME/.p10k.zsh"
            print_success "Linked p10k config"
        fi

        # Install Oh My Zsh if not present
        if [ ! -d "$HOME/.oh-my-zsh" ]; then
            print_info "Installing Oh My Zsh..."
            if command_exists curl; then
                sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended || true
                print_success "Oh My Zsh installed"
            else
                print_warning "curl not found - skipping Oh My Zsh installation"
            fi
        fi

        # Install zsh plugins
        ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
        if [ -d "$HOME/.oh-my-zsh" ] && command_exists git; then
            print_info "Installing zsh plugins..."

            [ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ] && \
                git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions" 2>/dev/null || true

            [ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ] && \
                git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" 2>/dev/null || true

            [ ! -d "$ZSH_CUSTOM/themes/powerlevel10k" ] && \
                git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$ZSH_CUSTOM/themes/powerlevel10k" 2>/dev/null || true

            print_success "Zsh plugins installed"
        fi
    else
        print_warning "zsh not found - skipping zsh configuration"
    fi
fi

# ============================================================================
# UTILITY SCRIPTS Installation
# ============================================================================
print_info "Setting up utility scripts..."

# Ensure ~/.local/bin exists
mkdir -p "$HOME/.local/bin"

# Link all utility scripts
if [ -d "$DOTFILES_DIR/scripts/utilities" ]; then
    for script in "$DOTFILES_DIR/scripts/utilities"/*.sh; do
        if [ -f "$script" ]; then
            script_name=$(basename "$script")
            backup_if_exists "$HOME/.local/bin/$script_name"
            ln -sf "$script" "$HOME/.local/bin/$script_name"
            chmod +x "$HOME/.local/bin/$script_name"
        fi
    done

    # Link kt (kitty theme switcher) - not a .sh file
    if [ -f "$DOTFILES_DIR/scripts/utilities/kt" ]; then
        backup_if_exists "$HOME/.local/bin/kt"
        ln -sf "$DOTFILES_DIR/scripts/utilities/kt" "$HOME/.local/bin/kt"
        chmod +x "$HOME/.local/bin/kt"
        print_success "Linked kt (kitty theme switcher)"
    fi

    print_success "Utility scripts linked"
else
    print_warning "Utilities directory not found"
fi

# Check if ~/.local/bin is in PATH
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    print_warning "~/.local/bin is not in your PATH"
    print_info "Add this to your shell config (~/.bashrc or ~/.zshrc):"
    echo '  export PATH="$HOME/.local/bin:$PATH"'
fi

# ============================================================================
# Summary
# ============================================================================
echo ""
print_success "======================================"
print_success "  Work Minimal Setup Complete!"
print_success "======================================"
echo ""
print_info "Configured tools:"
[ -L "$HOME/.tmux.conf" ] && echo "  ✓ tmux (config at $DOTFILES_DIR/config/tmux/tmux.conf)"
[ -L "$HOME/.config/kitty" ] && echo "  ✓ kitty (config at $DOTFILES_DIR/config/kitty/)"
[ -d "$HOME/.config/nvim" ] && echo "  ✓ neovim (NvChad config)"
[ -L "$HOME/.zshrc" ] && echo "  ✓ zsh (config at $DOTFILES_DIR/config/zsh/)"
[ -L "$HOME/.local/bin/kt" ] && echo "  ✓ utilities (kt theme switcher and more)"

echo ""
print_info "Next steps:"
if [ -L "$HOME/.tmux.conf" ]; then
    echo "  • Run 'tmux' and press Ctrl+Space + I to install tmux plugins"
fi
if [ -d "$HOME/.config/nvim" ]; then
    echo "  • Open nvim to trigger plugin installation"
fi
if [ -L "$HOME/.zshrc" ]; then
    echo "  • Run 'source ~/.zshrc' or restart your shell"
fi

echo ""
print_info "Tmux keybindings:"
echo "  • Prefix: Ctrl+Space"
echo "  • Split horizontal: prefix + h"
echo "  • Split vertical: prefix + v"
echo "  • Switch windows: Alt+H/L or Alt+1-9"
echo "  • Install plugins: prefix + I"
