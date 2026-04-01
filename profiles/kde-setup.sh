#!/bin/bash
# KDE Setup - installs KDE Plasma themes, packages, and desktop customisations
#
# Usage: bash kde-setup.sh [--dry-run]

# Get the dotfiles directory
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Source common utilities
source "$DOTFILES_DIR/lib/common.sh" "$@"

# ============================================================================
# PRE-FLIGHT CHECKS
# ============================================================================

pre_flight_checks() {
    log_step "Running pre-flight checks..."

    check_not_root || exit 1
    check_sudo || exit 1
    check_internet || exit 1
    check_disk_space 2000 || exit 1  # Need 2GB for KDE packages

    # Verify we're on Ubuntu/Debian
    local os=$(detect_os)
    if [[ "$os" != "ubuntu" && "$os" != "debian" ]]; then
        log_error "This script is designed for Ubuntu/Debian systems"
        log_error "Detected OS: $os"
        exit 1
    fi

    # Detect Ubuntu version for PPA
    UBUNTU_CODENAME=$(detect_ubuntu_codename)
    if [[ -z "$UBUNTU_CODENAME" ]]; then
        log_warning "Could not detect Ubuntu codename, defaulting to 'jammy'"
        UBUNTU_CODENAME="jammy"
    else
        log_success "Detected Ubuntu codename: $UBUNTU_CODENAME"
    fi

    log_success "Pre-flight checks passed"
}

# ============================================================================
# REPOSITORY SETUP
# ============================================================================

setup_repositories() {
    log_step "Setting up external repositories..."

    # Papirus icon theme PPA
    log_info "Adding Papirus icon theme repository..."
    local papirus_list="/etc/apt/sources.list.d/papirus-ppa.list"
    if [[ ! -f "$papirus_list" || $DRY_RUN -eq 0 ]]; then
        run_or_dry sudo sh -c "echo 'deb http://ppa.launchpad.net/papirus/papirus/ubuntu $UBUNTU_CODENAME main' > $papirus_list"
        run_or_dry sudo wget -qO /etc/apt/trusted.gpg.d/papirus-ppa.asc \
            'https://keyserver.ubuntu.com/pks/lookup?op=get&search=0x9461999446FAF0DF770BFC9AE58A9D36647CAE7F'
    fi

    log_success "Repositories configured"
}

# ============================================================================
# PACKAGE INSTALLATION
# ============================================================================

install_packages() {
    log_step "Installing KDE packages and dependencies..."

    local packages=(
        # Build dependencies
        gcc make autoconf automake pkg-config flex bison
        libpango1.0-dev libpangocairo-1.0-0 libcairo2-dev
        libglib2.0-dev libgdk-pixbuf2.0-dev
        libstartup-notification0-dev libxkbcommon-dev
        libxkbcommon-x11-dev libxcb1-dev libxcb-xkb-dev
        libxcb-randr0-dev libxcb-xinerama0-dev
        meson ninja-build libxcb-util-dev libxcb-ewmh-dev
        libxcb-icccm4-dev libxcb-cursor-dev
        libpugixml1v5 g++ libx11-dev libxext-dev

        # Qt5/KDE libraries
        qtbase5-dev libqt5svg5-dev libqt5x11extras5-dev
        libkf5windowsystem-dev qttools5-dev
        libkf5configwidgets-dev libkf5globalaccel-dev
        libkf5notifications-dev

        # KDE desktop packages
        latte-dock kwin-bismuth kwin-dev
        qt5-style-kvantum qt5-style-kvantum-themes
        papirus-icon-theme

        # Applications
        kitty

        # Build tools
        git cmake gettext extra-cmake-modules qttools5-dev
    )

    apt_install "${packages[@]}"
}

# ============================================================================
# BINARY PACKAGES
# ============================================================================

install_binary_packages() {
    log_step "Installing binary packages..."

    # Touchegg (gesture control)
    local touchegg_deb="$DOTFILES_DIR/scripts/packages/touchegg_2.0.17_amd64.deb"
    if [[ -f "$touchegg_deb" ]]; then
        log_info "Installing Touchegg from local package..."
        run_or_dry sudo dpkg -i "$touchegg_deb"
    else
        log_warning "Touchegg package not found at $touchegg_deb"
        log_info "Attempting to install from repository..."
        apt_install touchegg || log_warning "Could not install touchegg"
    fi

    # Rounded corners KWin effect
    local shapecorners_deb="$DOTFILES_DIR/scripts/packages/kwin4_effect_shapecorners_kubuntu2204.deb"
    if [[ -f "$shapecorners_deb" ]]; then
        log_info "Installing rounded corners effect..."
        run_or_dry sudo dpkg -i "$shapecorners_deb"
    else
        log_warning "Rounded corners package not found at $shapecorners_deb"
        log_warning "Skipping rounded corners installation"
    fi
}

# ============================================================================
# CONFIGURATION SETUP
# ============================================================================

setup_touchegg_config() {
    log_step "Setting up Touchegg configuration..."

    local source_dir="$DOTFILES_DIR/config/kde/touchegg"
    local target_dir="$HOME/.config/touchegg"

    if [[ ! -d "$source_dir" ]]; then
        log_warning "Touchegg config not found at $source_dir, skipping..."
        return
    fi

    # Backup existing config
    if [[ -d "$target_dir" ]]; then
        backup_path "$target_dir"
    fi

    # Copy config directory
    log_info "Copying touchegg config..."
    ensure_dir "$(dirname "$target_dir")"
    run_or_dry cp -r "$source_dir" "$target_dir"

    # Create symlink for config file
    safe_symlink "$DOTFILES_DIR/config/kde/touchegg/touchegg.conf" \
                 "$target_dir/touchegg.conf"
}

setup_latte_dock_config() {
    log_step "Setting up Latte-dock configuration..."

    local source_dir="$DOTFILES_DIR/config/kde/latte"
    local target_dir="$HOME/.config/latte"

    if [[ ! -d "$source_dir" ]]; then
        log_warning "Latte-dock config not found at $source_dir, skipping..."
        return
    fi

    # Backup existing config
    if [[ -d "$target_dir" ]]; then
        backup_path "$target_dir"
    fi

    # Copy latte config
    log_info "Copying latte-dock config..."
    run_or_dry cp -r "$source_dir" "$target_dir"

    log_success "Latte-dock configuration installed"
}

# ============================================================================
# FONTS
# ============================================================================

install_fonts() {
    log_step "Installing custom fonts..."

    local fonts_dir="$DOTFILES_DIR/assets/fonts"

    if [[ ! -d "$fonts_dir" ]]; then
        log_warning "Fonts directory not found at $fonts_dir, skipping..."
        return
    fi

    log_info "Copying fonts to /usr/share/fonts/..."
    run_or_dry sudo cp -r "$fonts_dir"/* /usr/share/fonts/

    log_info "Rebuilding font cache..."
    run_or_dry sudo fc-cache -fv

    log_success "Fonts installed successfully"
}

# ============================================================================
# THEME INSTALLATION
# ============================================================================

install_ant_dark_theme() {
    log_step "Installing Ant-Dark theme..."

    local downloads_dir="$HOME/Downloads"
    ensure_dir "$downloads_dir"

    local ant_repo="$downloads_dir/Ant"
    local dark_dir="$downloads_dir/Dark"

    # Clone Ant theme repository
    if [[ ! -d "$ant_repo" ]]; then
        log_info "Cloning Ant theme repository..."
        (
            cd "$downloads_dir" || exit 1
            run_or_dry git clone https://github.com/EliverLara/Ant.git
        ) || {
            log_error "Failed to clone Ant theme repository"
            return 1
        }
    fi

    # Extract Dark theme
    if [[ -d "$ant_repo/kde/Dark" ]]; then
        log_info "Extracting Dark theme..."
        run_or_dry cp -r "$ant_repo/kde/Dark" "$dark_dir"
    fi

    # Install theme components
    if [[ -d "$dark_dir" ]]; then
        log_info "Installing Ant-Dark theme components..."

        # Plasma desktop theme
        run_or_dry sudo cp -r "$dark_dir/plasma/desktoptheme/Ant-Dark/" \
            /usr/share/plasma/desktoptheme/

        # Look and Feel
        run_or_dry sudo cp -r "$dark_dir/plasma/look-and-feel/Ant-Dark/" \
            /usr/share/plasma/look-and-feel/

        # Icons
        run_or_dry sudo cp -r "$dark_dir/icons/Ant-Dark/" \
            /usr/share/icons/

        # SDDM theme
        run_or_dry sudo cp -r "$dark_dir/sddm/Ant-Dark/" \
            /usr/share/sddm/themes/

        # Aurorae (window decoration)
        ensure_dir "$HOME/.local/share/aurorae/themes"
        run_or_dry cp -r "$dark_dir/aurorae/Ant-Dark/" \
            "$HOME/.local/share/aurorae/themes/"

        log_success "Ant-Dark theme installed successfully"
    else
        log_error "Dark theme directory not found after extraction"
        return 1
    fi

    # Cleanup
    log_info "Cleaning up temporary files..."
    run_or_dry rm -rf "$ant_repo" "$dark_dir"
}

# ============================================================================
# MAIN INSTALLATION
# ============================================================================

main() {
    log_info "KDE Plasma Desktop Customization Script"
    log_info "========================================"

    if [[ $DRY_RUN -eq 1 ]]; then
        log_warning "DRY RUN MODE - No changes will be made"
    fi

    # Run pre-flight checks
    pre_flight_checks

    # Confirm before proceeding
    if [[ $DRY_RUN -eq 0 ]]; then
        echo
        log_warning "This script will:"
        echo "  - Add external repositories (Papirus)"
        echo "  - Install KDE packages and dependencies"
        echo "  - Install themes and customizations"
        echo "  - Backup existing configurations"
        echo
        confirm "Do you want to continue?" "y" || {
            log_info "Installation cancelled by user"
            exit 0
        }
    fi

    # Run installation steps
    setup_repositories
    install_packages
    install_binary_packages
    setup_touchegg_config
    setup_latte_dock_config
    install_fonts
    install_ant_dark_theme

    log_success "KDE setup complete!"
    log_info ""
    log_info "Next steps:"
    log_info "  1. Restart your KDE session (logout and login)"
    log_info "  2. Apply the Ant-Dark theme in System Settings > Appearance"
    log_info "  3. Configure Latte-dock as needed"
    log_info ""
    log_info "Backup files are saved with timestamp: $BACKUP_TIMESTAMP"
}

# Run main function
main "$@"
