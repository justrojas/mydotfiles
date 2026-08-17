#!/bin/bash
# KDE Setup — installs KDE Plasma themes, packages, and desktop customisations.
#
# Usage: bash kde-setup.sh [--dry-run] [--non-interactive] [--config-only]
#
#   --import-shortcuts
#                   Import the global shortcut scheme without prompting. This
#                   OVERWRITES conflicting keybindings, so it is opt-in: the
#                   interactive prompt defaults to "no" and --non-interactive
#                   skips the step entirely unless this flag is given.
#
#   --config-only   Skip everything requiring apt, sudo or network: the PPA,
#                   the KDE package install, the .deb installs and the Ant-Dark
#                   theme clone. Only the steps that copy this repo's own config
#                   into $HOME are run (touchegg, Kvantum, Firefox, shortcuts,
#                   focus ring). This is what makes the profile testable in a
#                   container — the full path needs ~2GB of KDE packages.

set -euo pipefail

# Get the dotfiles directory
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Source common utilities.
# NOTE: common.sh auto-calls init_common when sourced, but pass args explicitly
# below as well so this profile matches the others and does not depend on that
# implicit behaviour for --dry-run parsing.
# shellcheck source=../lib/common.sh
source "$DOTFILES_DIR/lib/common.sh"

NONINTERACTIVE=0
CONFIG_ONLY=0
IMPORT_SHORTCUTS=0
for arg in "$@"; do
    [[ "$arg" == "--non-interactive" ]]  && NONINTERACTIVE=1
    [[ "$arg" == "--config-only" ]]      && CONFIG_ONLY=1
    [[ "$arg" == "--import-shortcuts" ]] && IMPORT_SHORTCUTS=1
done || true

init_common "$@"

# Set in pre_flight_checks; declared here so `set -u` is safe if a caller
# invokes a single function directly (as the test suite does).
UBUNTU_CODENAME="${UBUNTU_CODENAME:-jammy}"

# Number of log_step calls actually executed, for the "X/N" counter.
# --config-only skips setup_repositories, install_packages,
# install_binary_packages and install_ant_dark_theme.
if [[ $CONFIG_ONLY -eq 1 ]]; then
    STEP_TOTAL=6
else
    STEP_TOTAL=10
fi

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
        # NOTE: latte-dock was deliberately removed. It was archived upstream in
        # 2023 and never gained Plasma 6 support. Use native Plasma panels, or
        # the polybar top bar from profiles/bar-setup.sh.
        kwin-bismuth kwin-dev
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
        run_or_dry sudo dpkg -i "$touchegg_deb" \
            || log_warning "dpkg failed for touchegg — gestures will not work"
    else
        log_warning "Touchegg package not found at $touchegg_deb"
        log_info "Attempting to install from repository..."
        apt_install touchegg || log_warning "Could not install touchegg"
    fi

    # Rounded corners + focus-outline KWin effect.
    #
    # The filename encodes the distro it was built for (…_kubuntu2204.deb), so
    # glob rather than hardcode — otherwise adding a 24.04 build silently does
    # nothing because the hardcoded 22.04 name no longer matches.
    local shapecorners_deb=""
    for candidate in "$DOTFILES_DIR"/scripts/packages/kwin4_effect_shapecorners*.deb; do
        [[ -f "$candidate" ]] && shapecorners_deb="$candidate"
    done

    if [[ -n "$shapecorners_deb" ]]; then
        log_info "Installing rounded corners effect ($(basename "$shapecorners_deb"))..."
        if ! run_or_dry sudo dpkg -i "$shapecorners_deb"; then
            log_warning "dpkg failed for $(basename "$shapecorners_deb")"
            log_warning "It is built for a specific distro release — the focus"
            log_warning "outline (setup_active_window_outline) will be skipped."
        fi
    else
        log_warning "No kwin4_effect_shapecorners*.deb in scripts/packages/"
        log_warning "Skipping rounded corners — focus outline will be unavailable"
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

# DEPRECATED — intentionally no longer called from main().
#
# Latte Dock was archived by its maintainer in 2023 and has no Plasma 6 support.
# The layouts under config/kde/latte/ are kept only as a historical reference;
# nothing installs them. Use native Plasma panels, or the polybar top bar from
# profiles/bar-setup.sh.
#
# Kept (rather than deleted) so an older machine can still restore its old dock
# by hand: cp -r config/kde/latte ~/.config/latte
setup_latte_dock_config() {
    log_warning "setup_latte_dock_config is deprecated and does nothing."
    log_info "Latte Dock was archived upstream in 2023. Use Plasma panels or"
    log_info "run profiles/bar-setup.sh for the polybar top bar."
    return 0
}

# ============================================================================
# KVANTUM (Qt theme engine)
# ============================================================================

# Install the Ant-Dark Kvantum theme and select it.
#
# kde-setup already apt-installs qt5-style-kvantum + qt5-style-kvantum-themes,
# but nothing ever copied THIS repo's Ant-Dark theme or the kvantum.kvconfig
# that selects it — so the engine was installed and then left on its default
# theme. That gap is why the desktop never matched the rest of the theming.
setup_kvantum_config() {
    log_step "Setting up Kvantum theme..."

    local source_dir="$DOTFILES_DIR/config/kde/Kvantum"
    local target_dir="$HOME/.config/Kvantum"

    if [[ ! -d "$source_dir" ]]; then
        log_warning "Kvantum config not found at $source_dir, skipping..."
        return
    fi

    if ! command -v kvantummanager >/dev/null 2>&1 \
       && [[ ! -d /usr/share/Kvantum ]]; then
        log_warning "Kvantum engine not installed — skipping theme config"
        log_info "It comes from qt5-style-kvantum, installed by install_packages()"
        return
    fi

    ensure_dir "$target_dir"

    # Theme directory (Ant-Dark/*.kvconfig + *.svg).
    if [[ -d "$source_dir/Ant-Dark" ]]; then
        if [[ -d "$target_dir/Ant-Dark" ]]; then backup_path "$target_dir/Ant-Dark"; fi
        run_or_dry cp -r "$source_dir/Ant-Dark" "$target_dir/"
        log_success "Ant-Dark Kvantum theme installed"
    fi

    # kvantum.kvconfig selects the active theme. Back up any existing choice.
    if [[ -f "$source_dir/kvantum.kvconfig" ]]; then
        if [[ -f "$target_dir/kvantum.kvconfig" ]]; then backup_path "$target_dir/kvantum.kvconfig"; fi
        run_or_dry cp "$source_dir/kvantum.kvconfig" "$target_dir/kvantum.kvconfig"
        log_success "Kvantum theme set to Ant-Dark"
    fi

    log_info "Apply with: System Settings > Appearance > Application Style > kvantum"
}

# ============================================================================
# GLOBAL SHORTCUTS
# ============================================================================

# Import the KDE global shortcut scheme from config/kde/shortcuts/.
#
# This OVERWRITES existing keybindings, so it is prompted and the current
# kglobalshortcutsrc is backed up first.
#
# A .kksrc is the same INI format as ~/.config/kglobalshortcutsrc, using
# [Component][Global Shortcuts] group headers. We merge key-by-key with
# kwriteconfig5 rather than copying the file wholesale, so shortcuts that exist
# locally but not in the scheme are preserved.
setup_kde_shortcuts() {
    log_step "Setting up global shortcuts..."

    local scheme="$DOTFILES_DIR/config/kde/shortcuts/global-shortcuts.kksrc"

    if [[ ! -f "$scheme" ]]; then
        log_warning "Shortcut scheme not found at $scheme, skipping..."
        return
    fi

    if ! command -v kwriteconfig5 >/dev/null 2>&1; then
        log_warning "kwriteconfig5 not found — skipping shortcut import"
        return
    fi

    # Importing replaces conflicting keybindings, so it is deliberately opt-in.
    # The prompt defaults to "no"; --non-interactive skips entirely unless
    # --import-shortcuts was passed.
    if [[ $IMPORT_SHORTCUTS -eq 0 ]]; then
        log_warning "Importing shortcuts REPLACES conflicting keybindings."
        local reply
        reply=$(prompt_yn "Import the global shortcut scheme? [y/N] " "n")
        if [[ ! "$reply" =~ ^[Yy]$ ]]; then
            log_info "Skipping shortcut import"
            log_info "Import manually: System Settings > Shortcuts > ... > Import Scheme"
            log_info "Or re-run with --import-shortcuts"
            return
        fi
    else
        log_info "--import-shortcuts: importing without prompting"
    fi

    local target="$HOME/.config/kglobalshortcutsrc"

    # COPY the backup, do NOT use backup_path() — it uses `mv`, which moves the
    # existing file out of the way and leaves kwriteconfig5 to create a fresh
    # empty one. That turns this "merge" into a total overwrite and silently
    # destroys every shortcut the user had that is not in our scheme.
    #
    # Caught by the SENTINEL_PRESERVED assertion in tests/test-kde-setup.sh.
    if [[ -f "$target" ]]; then
        local backup="${target}.bak.${BACKUP_TIMESTAMP}"
        log_info "Backing up $target to $backup"
        run_or_dry cp -p "$target" "$backup"
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        log_info "[DRY RUN] Would merge $(grep -c '^\[' "$scheme") groups into $target"
        return
    fi

    local group="" sub="" line key value imported=0
    while IFS= read -r line; do
        # Group header: [Component][Subgroup]  or  [Component]
        if [[ "$line" =~ ^\[(.+)\]\[(.+)\]$ ]]; then
            group="${BASH_REMATCH[1]}"; sub="${BASH_REMATCH[2]}"; continue
        elif [[ "$line" =~ ^\[(.+)\]$ ]]; then
            group="${BASH_REMATCH[1]}"; sub=""; continue
        fi
        if [[ -z "$line" || "$line" == \#* ]]; then continue; fi
        if [[ "$line" != *=* ]]; then continue; fi

        key="${line%%=*}"; value="${line#*=}"
        if [[ -z "$group" ]]; then continue; fi

        if [[ -n "$sub" ]]; then
            kwriteconfig5 --file kglobalshortcutsrc \
                --group "$group" --group "$sub" --key "$key" "$value" 2>/dev/null && (( imported++ )) || true
        else
            kwriteconfig5 --file kglobalshortcutsrc \
                --group "$group" --key "$key" "$value" 2>/dev/null && (( imported++ )) || true
        fi
    done < "$scheme"

    log_success "Imported $imported shortcut bindings (backup saved)"
    log_info "Log out and back in for all of them to take effect"
}

# ============================================================================
# FIREFOX USERCHROME
# ============================================================================

# Install the Firefox userChrome.css customisations.
#
# Two things are required and it is easy to do only one:
#   1. the CSS must land in <profile>/chrome/
#   2. toolkit.legacyUserProfileCustomizations.stylesheets must be true, or
#      Firefox silently ignores the whole chrome/ directory
setup_firefox_chrome() {
    log_step "Setting up Firefox customisations..."

    local source_dir="$DOTFILES_DIR/config/kde/applications/firefox/chrome"

    if [[ ! -d "$source_dir" ]]; then
        log_warning "Firefox chrome config not found at $source_dir, skipping..."
        return
    fi

    local ff_dir="$HOME/.mozilla/firefox"
    if [[ ! -d "$ff_dir" ]]; then
        log_warning "No Firefox profile directory — run Firefox once first, then re-run"
        return
    fi

    # Resolve the default profile from profiles.ini rather than globbing, which
    # picks the wrong one on installs that have several profiles.
    local profile=""
    if [[ -f "$ff_dir/profiles.ini" ]]; then
        profile=$(awk -F= '/^\[Install/{i=1} i&&/^Default=/{print $2; exit}' "$ff_dir/profiles.ini")
    fi
    if [[ -z "$profile" ]]; then
        profile=$(awk -F= '/^Default=1/{found=1} /^Path=/{p=$2} found&&p{print p; exit}' "$ff_dir/profiles.ini" 2>/dev/null)
    fi
    if [[ -z "$profile" ]]; then
        profile=$(basename "$(find "$ff_dir" -maxdepth 1 -name '*.default*' -type d | head -1)" 2>/dev/null)
    fi

    if [[ -z "$profile" || ! -d "$ff_dir/$profile" ]]; then
        log_warning "Could not determine the default Firefox profile — skipping"
        return
    fi

    log_info "Using Firefox profile: $profile"

    local chrome_dir="$ff_dir/$profile/chrome"
    if [[ -d "$chrome_dir" ]]; then backup_path "$chrome_dir"; fi
    ensure_dir "$chrome_dir"
    run_or_dry cp -r "$source_dir/." "$chrome_dir/"

    # Without this pref Firefox ignores chrome/ entirely.
    local prefs="$ff_dir/$profile/user.js"
    local pref_line='user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true);'
    if [[ $DRY_RUN -eq 0 ]]; then
        if ! grep -qF "legacyUserProfileCustomizations" "$prefs" 2>/dev/null; then
            printf '%s\n' "$pref_line" >> "$prefs"
        fi
    else
        log_info "[DRY RUN] Would enable legacyUserProfileCustomizations in user.js"
    fi

    log_success "Firefox userChrome installed (restart Firefox to apply)"
}

# ============================================================================
# ACTIVE WINDOW OUTLINE
# ============================================================================

# Draw a coloured ring around the focused window.
#
# With bismuth tiling enabled and a dark Aurorae decoration, there is otherwise
# no reliable cue for which window has focus — Plasma differentiates only by a
# subtle titlebar shade, which vanishes entirely on tiled/maximised windows
# where the titlebar is hidden.
#
# Implemented by the kwin4_effect_shapecorners effect installed above from
# scripts/packages/. The real work lives in the standalone utility so it can be
# re-run and re-tuned without a full kde-setup pass.
setup_active_window_outline() {
    log_step "Configuring active window outline..."

    local script="$DOTFILES_DIR/scripts/utilities/kde-active-outline.sh"

    if [[ ! -f "$script" ]]; then
        log_warning "kde-active-outline.sh not found, skipping..."
        return
    fi

    if ! dpkg -l kwin4_effect_shapecorners 2>/dev/null | grep -q '^ii'; then
        log_warning "kwin4_effect_shapecorners not installed — outline unavailable"
        log_info "It ships in scripts/packages/ and is installed by install_binary_packages()"
        return
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        log_info "[DRY RUN] Would run kde-active-outline.sh"
        return
    fi

    bash "$script" || log_warning "Could not apply window outline (non-fatal)"
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

    # Install into a dedicated subdirectory rather than the top of
    # /usr/share/fonts, and copy ONLY font files — the previous `cp -r *` also
    # dumped README.md and LICENSE.md in there, which fc-cache then warns about
    # on every rebuild.
    local dest="/usr/share/fonts/truetype/jetbrains-mono-nerd"
    log_info "Copying fonts to $dest ..."
    run_or_dry sudo mkdir -p "$dest"

    local copied=0 f
    for f in "$fonts_dir"/*.ttf "$fonts_dir"/*.otf; do
        [[ -f "$f" ]] || continue
        run_or_dry sudo cp "$f" "$dest/"
        (( copied++ )) || true
    done

    if [[ $copied -eq 0 ]]; then
        log_warning "No .ttf/.otf files found in $fonts_dir"
        return
    fi

    # Remove the Hack fonts a previous version of this script scattered across
    # the top level of /usr/share/fonts, so the old family doesn't keep winning
    # fontconfig matches after the switch to JetBrains Mono.
    if [[ $DRY_RUN -eq 0 ]]; then
        sudo rm -f /usr/share/fonts/HackNerdFont*.ttf \
                   /usr/share/fonts/README.md \
                   /usr/share/fonts/LICENSE.md 2>/dev/null || true
    else
        log_info "[DRY RUN] Would remove stale /usr/share/fonts/HackNerdFont*.ttf"
    fi

    # Rebuilding the cache is best-effort, NOT fatal.
    #
    # The fonts are already on disk at this point — fc-cache only refreshes
    # fontconfig's index, and the system rebuilds it lazily anyway. Treating a
    # failure here as fatal means a machine without fontconfig installed (a
    # minimal image, a container) aborts the whole profile AFTER having
    # successfully installed the fonts, which is both wrong and confusing.
    #
    # This is exactly what `set -euo pipefail` surfaced when it was added: the
    # failure was previously swallowed silently, so neither behaviour was
    # correct — it just failed quietly instead of loudly.
    if command -v fc-cache >/dev/null 2>&1; then
        log_info "Rebuilding font cache..."
        run_or_dry sudo fc-cache -f || log_warning "fc-cache failed — fonts installed, cache will rebuild on next login"
    else
        log_warning "fc-cache not found (fontconfig not installed)"
        log_info "Fonts are installed; the cache will be built when fontconfig is"
    fi

    log_success "Installed $copied font file(s)"
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

        # Copy each theme component independently.
        #
        # These come from a third-party repo (EliverLara/Ant) whose layout we do
        # not control. Under `set -e` a single missing subdirectory would abort
        # the entire profile part-way through, leaving the theme half-installed
        # and skipping everything downstream. A missing component is worth a
        # warning, not a hard stop — so each copy is individually tolerant and
        # we report what actually landed.
        local installed=0 skipped=0
        _copy_theme_component() {
            local src="$1" dst="$2" label="$3" use_sudo="${4:-yes}"
            if [[ ! -d "$src" ]]; then
                log_warning "Ant-Dark: $label not found upstream — skipping"
                (( skipped++ )) || true
                return 0
            fi
            if [[ "$use_sudo" == "yes" ]]; then
                run_or_dry sudo cp -r "$src" "$dst" || {
                    log_warning "Ant-Dark: failed to install $label"; (( skipped++ )) || true; return 0; }
            else
                run_or_dry cp -r "$src" "$dst" || {
                    log_warning "Ant-Dark: failed to install $label"; (( skipped++ )) || true; return 0; }
            fi
            (( installed++ )) || true
        }

        _copy_theme_component "$dark_dir/plasma/desktoptheme/Ant-Dark/"   /usr/share/plasma/desktoptheme/   "Plasma desktop theme"
        _copy_theme_component "$dark_dir/plasma/look-and-feel/Ant-Dark/"  /usr/share/plasma/look-and-feel/  "Look and Feel"
        _copy_theme_component "$dark_dir/icons/Ant-Dark/"                 /usr/share/icons/                 "icons"
        _copy_theme_component "$dark_dir/sddm/Ant-Dark/"                  /usr/share/sddm/themes/           "SDDM theme"

        ensure_dir "$HOME/.local/share/aurorae/themes"
        _copy_theme_component "$dark_dir/aurorae/Ant-Dark/" "$HOME/.local/share/aurorae/themes/" "Aurorae decoration" no

        unset -f _copy_theme_component

        if [[ $installed -eq 0 ]]; then
            log_error "Ant-Dark: no components installed — upstream layout may have changed"
        elif [[ $skipped -gt 0 ]]; then
            log_warning "Ant-Dark installed with $skipped component(s) missing"
        else
            log_success "Ant-Dark theme installed successfully"
        fi
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

    # Pre-flight checks demand sudo, network and 2GB free — all of which only
    # matter for the apt/theme steps. --config-only touches none of them, so
    # requiring them there would make the profile untestable for no benefit.
    if [[ $CONFIG_ONLY -eq 0 ]]; then
        pre_flight_checks
    else
        log_info "--config-only: skipping sudo/network/disk pre-flight checks"
        local os
        os=$(detect_os)
        if [[ "$os" != "ubuntu" && "$os" != "debian" ]]; then
            log_warning "Not Ubuntu/Debian (detected: $os) — config paths may differ"
        fi
    fi

    # Confirm before proceeding. Honour --non-interactive so this can run
    # unattended from desktop-setup.sh and from the test harness.
    if [[ $DRY_RUN -eq 0 && $CONFIG_ONLY -eq 0 && $NONINTERACTIVE -eq 0 ]]; then
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

    # Steps that need apt / sudo / network. Skipped by --config-only, which is
    # how the container test suite exercises the config-copying logic without
    # pulling ~2GB of KDE packages.
    if [[ $CONFIG_ONLY -eq 0 ]]; then
        setup_repositories
        install_packages
        install_binary_packages
    else
        log_info "--config-only: skipping repositories, packages and .deb installs"
    fi

    # Steps that only copy this repo's config into $HOME.
    setup_touchegg_config
    setup_kvantum_config
    setup_firefox_chrome
    setup_kde_shortcuts
    setup_active_window_outline
    install_fonts

    if [[ $CONFIG_ONLY -eq 0 ]]; then
        install_ant_dark_theme
    else
        log_info "--config-only: skipping Ant-Dark theme clone"
    fi

    log_success "KDE setup complete!"
    log_info ""
    log_info "Next steps:"
    log_info "  1. Restart your KDE session (logout and login)"
    log_info "  2. Apply the Ant-Dark theme in System Settings > Appearance"
    log_info "  3. For a top bar, run: bash profiles/bar-setup.sh (polybar)"
    log_info "  4. Tune the focus ring: kde-active-outline.sh --color <hex> --thickness <px>"
    log_info ""
    log_info "Backup files are saved with timestamp: $BACKUP_TIMESTAMP"
}

# Run main function
main "$@"
