#!/bin/bash
# Universal Dotfiles Installation Script
# Detects OS and runs appropriate setup

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored output
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

# Detect OS
detect_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            OS=$ID
            VER=$VERSION_ID
        fi
    else
        print_error "Unsupported OS: $OSTYPE"
        exit 1
    fi

    print_info "Detected OS: $OS"
}

# Run OS-specific installation
run_installation() {
    case $OS in
        ubuntu|debian)
            print_info "Running Ubuntu/Debian installation..."
            bash os/ubuntu/install.sh
            ;;
        *)
            print_error "No installation script found for $OS"
            exit 1
            ;;
    esac
}

# Link configuration files
link_configs() {
    print_info "Linking configuration files..."

    # Shell configurations
    if [ ! -d "$HOME/.config" ]; then
        mkdir -p "$HOME/.config"
    fi

    # Link OS-specific zsh config
    if [ -f "$HOME/.zshrc" ]; then
        print_warning "Backing up existing .zshrc to .zshrc.bak"
        mv "$HOME/.zshrc" "$HOME/.zshrc.bak"
    fi

    # Use OS-specific zshrc if available
    if [ -f "$PWD/os/$OS/zshrc" ]; then
        ln -sf "$PWD/os/$OS/zshrc" "$HOME/.zshrc"
        print_success "Linked $OS-specific zshrc"
    else
        ln -sf "$PWD/config/shell/zsh/.zshrc" "$HOME/.zshrc"
        print_success "Linked generic zshrc"
    fi

    # Note: p10k configuration removed - using custom zsh setup

    # Link tmux configuration
    if [ -f "$PWD/.config/tmux/tmux.conf" ]; then
        # Create .config/tmux directory if it doesn't exist
        mkdir -p "$HOME/.config/tmux"
        
        # Remove existing tmux config files if they exist
        if [ -f "$HOME/.tmux.conf" ] || [ -L "$HOME/.tmux.conf" ]; then
            print_warning "Backing up existing .tmux.conf to .tmux.conf.bak"
            mv "$HOME/.tmux.conf" "$HOME/.tmux.conf.bak"
        fi
        if [ -f "$HOME/.config/tmux/tmux.conf" ] || [ -L "$HOME/.config/tmux/tmux.conf" ]; then
            print_warning "Backing up existing .config/tmux/tmux.conf to .config/tmux/tmux.conf.bak"
            mv "$HOME/.config/tmux/tmux.conf" "$HOME/.config/tmux/tmux.conf.bak"
        fi
        
        # Symbolically link tmux config to both locations
        ln -sf "$PWD/.config/tmux/tmux.conf" "$HOME/.tmux.conf"
        ln -sf "$PWD/.config/tmux/tmux.conf" "$HOME/.config/tmux/tmux.conf"
        print_success "Linked tmux configuration to both ~/.tmux.conf and ~/.config/tmux/tmux.conf"

        # Link entire tmux plugins directory
        if [ -d "$PWD/.config/tmux/plugins" ]; then
            if [ -d "$HOME/.config/tmux/plugins" ] || [ -L "$HOME/.config/tmux/plugins" ]; then
                print_warning "Backing up existing tmux plugins directory"
                mv "$HOME/.config/tmux/plugins" "$HOME/.config/tmux/plugins.bak"
            fi
            ln -sf "$PWD/.config/tmux/plugins" "$HOME/.config/tmux/plugins"
            print_success "Linked tmux plugins directory"
        fi
        
        # Install tmux plugins
        print_info "Installing tmux plugins..."
        "$HOME/.config/tmux/plugins/tpm/bin/install_plugins" || print_warning "Failed to install tmux plugins - run manually later"
    fi

    # Link kitty configuration
    if [ -d "$PWD/.config/kitty" ]; then
        if [ -d "$HOME/.config/kitty" ] || [ -L "$HOME/.config/kitty" ]; then
            print_warning "Backing up existing kitty config to kitty.bak"
            mv "$HOME/.config/kitty" "$HOME/.config/kitty.bak"
        fi
        ln -sf "$PWD/.config/kitty" "$HOME/.config/kitty"
        print_success "Linked kitty configuration"
    fi

    # Link other configs as needed
    print_success "Configuration files linked"
}

# Main installation flow
main() {
    print_info "Starting dotfiles installation..."

    # Detect OS
    detect_os

    # Ask for installation type
    echo ""
    echo "Select installation type:"
    echo "1) Base system setup"
    echo "2) KDE Plasma setup"
    echo "3) Both"
    echo "4) Configuration files only"
    read -p "Enter choice [1-4]: " choice

    case $choice in
        1)
            run_installation
            link_configs
            ;;
        2)
            if [ -f "os/$OS/kde_install.sh" ]; then
                bash "os/$OS/kde_install.sh"
            else
                print_warning "No KDE installation script found for $OS"
            fi
            ;;
        3)
            run_installation
            link_configs
            if [ -f "os/$OS/kde_install.sh" ]; then
                bash "os/$OS/kde_install.sh"
            fi
            ;;
        4)
            link_configs
            ;;
        *)
            print_error "Invalid choice"
            exit 1
            ;;
    esac

    print_success "Installation completed!"
    print_info "Please restart your shell or run: source ~/.zshrc"
}

# Run main function
main
