#!/bin/bash
# Bar Setup — installs and configures the polybar top bar.
#
# WHY POLYBAR AND NOT WAYBAR
# --------------------------
# Waybar is Wayland-only: it positions itself using the wlroots layer-shell
# protocol, which KDE Plasma on X11 does not provide. This setup is X11
# (see profiles/kde-setup.sh), so waybar physically cannot anchor to a screen
# edge here. Polybar is the X11 equivalent — same declarative-config,
# independent-modules, arbitrary-script-modules model.
#
# What you get from the Hyprland/waybar aesthetic:
#   • a floating, detached bar with a margin (not edge-to-edge)
#   • per-module rounded "pills" with their own backgrounds
#   • a flat Tokyo Night Storm palette matching the oh-my-posh prompt
#   • a Spotify/MPRIS module driven by playerctl
#
# This profile also detects Plasma panels on the top edge and offers to remove
# or auto-hide them, since otherwise you get two bars fighting over the same
# screen edge and doubled struts.
#
# Usage: bash bar-setup.sh [--non-interactive] [--dry-run]

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$DOTFILES_DIR/lib/common.sh"

NONINTERACTIVE=0
for arg in "$@"; do
    [[ "$arg" == "--non-interactive" ]] && NONINTERACTIVE=1
done

init_common "$@"

STEP_TOTAL=5

echo ""
echo "======================================"
echo "   Top Bar Setup (polybar)"
echo "======================================"
echo ""

# ============================================================================
log_step "Preflight checks"

OS=$(detect_os)
if [[ ! "$OS" =~ ^(ubuntu|debian|pop|linuxmint)$ ]]; then
    log_error "bar-setup supports Ubuntu/Debian only (detected: $OS)"
    exit 1
fi

DISPLAY_SERVER=$(detect_display_server)
if [[ "$DISPLAY_SERVER" == "wayland" ]]; then
    log_error "You are on a Wayland session. Polybar is X11-only."
    log_info  "Either log into the 'Plasma (X11)' session, or install waybar"
    log_info  "instead — but note this repo's bar config is polybar syntax."
    exit 1
elif [[ "$DISPLAY_SERVER" != "x11" ]]; then
    log_warning "No display server detected (\$DISPLAY unset)."
    log_warning "Configs will still be linked, but the bar can't be started from here."
fi
log_success "Display server: ${DISPLAY_SERVER:-none}"

# ============================================================================
log_step "Installing polybar + playerctl"

# playerctl is the MPRIS client that drives the Spotify module. pavucontrol is
# what the volume pill opens on right-click. fonts-noto-color-emoji backs the
# emoji font declared in config.ini. rofi renders the wifi dropdown — without
# it network-menu.sh falls back to a centred kdialog box, which works but is
# not a dropdown.
BAR_PACKAGES=(polybar playerctl pavucontrol wmctrl rofi fonts-noto-color-emoji)

if [[ $DRY_RUN -eq 0 ]]; then
    sudo apt-get update -qq
    sudo apt-get install -y "${BAR_PACKAGES[@]}"
else
    log_info "[DRY RUN] Would run: sudo apt-get install -y ${BAR_PACKAGES[*]}"
fi
log_success "Bar packages installed"

# The Nerd Font glyphs in config.ini come from assets/fonts, installed by
# terminal-setup. Warn rather than fail if that hasn't been run yet.
if ! fc-list 2>/dev/null | grep -qi "JetBrainsMono Nerd Font"; then
    log_warning "JetBrainsMono Nerd Font not found — bar icons will render as boxes."
    log_info    "Run profiles/terminal-setup.sh first to install the fonts."
fi

# ============================================================================
log_step "Linking polybar config"

if [[ -d "$DOTFILES_DIR/config/polybar" ]]; then
    safe_symlink "$DOTFILES_DIR/config/polybar" "$HOME/.config/polybar"
    run_or_dry chmod +x "$DOTFILES_DIR/config/polybar/launch.sh"
    run_or_dry chmod +x "$DOTFILES_DIR/config/polybar/scripts/spotify.sh"

    ensure_dir "$HOME/.local/bin"
    run_or_dry ln -sf "$DOTFILES_DIR/config/polybar/launch.sh" "$HOME/.local/bin/bar"
    log_success "polybar config linked (launch with: bar)"
else
    log_error "config/polybar not found at $DOTFILES_DIR/config/polybar"
    exit 1
fi

# ============================================================================
log_step "Autostart + existing panels"

# Autostart the bar on login. KDE reads ~/.config/autostart/*.desktop.
autostart_dir="$HOME/.config/autostart"
autostart_file="$autostart_dir/polybar.desktop"
ensure_dir "$autostart_dir"
if [[ $DRY_RUN -eq 0 ]]; then
    cat > "$autostart_file" <<EOF
[Desktop Entry]
Type=Application
Name=Polybar
Comment=Top bar (managed by my-dotfiles)
Exec=$HOME/.local/bin/bar
Terminal=false
X-GNOME-Autostart-enabled=true
X-KDE-autostart-phase=2
EOF
    log_success "Autostart entry written to $autostart_file"
else
    log_info "[DRY RUN] Would write $autostart_file"
fi

# ----------------------------------------------------------------------------
# Plasma panels
#
# The KDE panel is drawn by plasmashell. A Plasma panel at the top and polybar
# at the top means two bars fighting for the same screen edge and strut.
#
# We only care about panels on the SAME edge as our bar (top) — a bottom panel
# coexists with polybar perfectly well, so we leave those alone.
#
# (Latte Dock is not considered here: it was archived upstream in 2023 and
# never supported Plasma 6. A vestigial cleanup for it runs further down.)
# ----------------------------------------------------------------------------
qdbus_bin="$(command -v qdbus || command -v qdbus6 || command -v qdbus-qt5 || true)"

if [[ -z "$qdbus_bin" ]]; then
    log_info "qdbus not found — skipping Plasma panel check"
elif ! pgrep -x plasmashell >/dev/null 2>&1; then
    log_info "plasmashell not running — skipping Plasma panel check"
else
    top_panels=$("$qdbus_bin" org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript \
        'var n=0; panels().forEach(function(p){ if (p.location=="top") n++; }); print(n);' 2>/dev/null | tr -d '[:space:]')

    if [[ "$top_panels" =~ ^[0-9]+$ ]] && [[ "$top_panels" -gt 0 ]]; then
        log_warning "Found $top_panels Plasma panel(s) at the top of the screen."
        log_warning "polybar also docks at the top — they will overlap."
        echo ""
        log_info "  [r] Remove the top Plasma panel(s)   (config backed up first)"
        log_info "  [a] Set them to auto-hide            (reversible in System Settings)"
        log_info "  [n] Leave them alone                 (bars will overlap)"
        echo ""
        panel_reply=$(prompt_yn "Choice [r/a/N]: " "n")

        # The panel layout lives here. Back it up before touching anything so a
        # bad outcome is a file copy away from being undone.
        plasma_cfg="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"

        case "${panel_reply,,}" in
            r)
                if [[ $DRY_RUN -eq 0 ]]; then
                    [[ -f "$plasma_cfg" ]] && backup_path "$plasma_cfg"
                    "$qdbus_bin" org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript \
                        'panels().forEach(function(p){ if (p.location=="top") p.remove(); });' >/dev/null 2>&1 \
                        && log_success "Removed $top_panels top Plasma panel(s)" \
                        || log_warning "Could not remove panels — do it manually: right-click panel > Remove Panel"
                    log_info "Restore: copy the .bak file back over $plasma_cfg, then 'plasmashell --replace &'"
                else
                    log_info "[DRY RUN] Would back up $plasma_cfg and remove top Plasma panels"
                fi
                ;;
            a)
                if [[ $DRY_RUN -eq 0 ]]; then
                    [[ -f "$plasma_cfg" ]] && backup_path "$plasma_cfg"
                    "$qdbus_bin" org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript \
                        'panels().forEach(function(p){ if (p.location=="top") p.hiding="autohide"; });' >/dev/null 2>&1 \
                        && log_success "Set top Plasma panel(s) to auto-hide" \
                        || log_warning "Could not change panel hiding — do it manually in Panel Settings"
                else
                    log_info "[DRY RUN] Would set top Plasma panels to autohide"
                fi
                ;;
            *)
                log_info "Leaving Plasma panels as-is — polybar will overlap them"
                log_info "To fix later: right-click the panel > Enter Edit Mode > Remove Panel"
                ;;
        esac
    else
        log_success "No Plasma panels at the top — no conflict with polybar"
    fi
fi

# Legacy: Latte Dock was archived upstream in 2023 (no Plasma 6 support). This
# repo no longer installs it, but older machines provisioned by a previous
# version of kde-setup.sh may still have it autostarting into the same space.
if command -v latte-dock >/dev/null 2>&1; then
    log_warning "Latte Dock is installed but is deprecated upstream (archived 2023)."
    reply=$(prompt_yn "Stop it and disable its autostart? [y/N] " "y")
    if [[ "$reply" =~ ^[Yy]$ ]]; then
        if [[ $DRY_RUN -eq 0 ]]; then
            killall -q latte-dock 2>/dev/null || true
            cat > "$autostart_dir/org.kde.latte-dock.desktop" <<'LATTE_EOF'
[Desktop Entry]
Type=Application
Name=Latte Dock
Exec=/bin/true
Hidden=true
X-GNOME-Autostart-enabled=false
LATTE_EOF
        fi
        log_success "Latte Dock disabled (rm ~/.config/autostart/org.kde.latte-dock.desktop to undo)"
    fi
fi

# ============================================================================
log_step "Verifying"

_ok()   { printf "  ${GREEN}✓${NC}  %s\n" "$1"; }
_bad()  { printf "  ${RED}✗${NC}  %s\n" "$1"; }

command -v polybar   >/dev/null 2>&1 && _ok "polybar"   || _bad "polybar"
command -v playerctl >/dev/null 2>&1 && _ok "playerctl" || _bad "playerctl"
[[ -L "$HOME/.config/polybar" ]]     && _ok "~/.config/polybar linked" || _bad "~/.config/polybar linked"
[[ -x "$HOME/.local/bin/bar" ]]      && _ok "~/.local/bin/bar"  || _bad "~/.local/bin/bar"

if command -v playerctl >/dev/null 2>&1; then
    if playerctl -l >/dev/null 2>&1; then
        _ok "MPRIS reachable (players: $(playerctl -l 2>/dev/null | tr '\n' ' ' || echo none))"
    else
        printf "  ${YELLOW}!${NC}  %s\n" "No MPRIS player running — start Spotify to test the module"
    fi
fi

echo ""
log_success "Bar setup complete"
echo ""
echo "  • Start it now:      bar"
echo "  • Logs:              ~/.cache/polybar.log"
echo "  • Edit modules:      $DOTFILES_DIR/config/polybar/config.ini"
echo "  • Spotify controls:  click the track pill (play/pause), ◀ ▶ to skip,"
echo "                       scroll over it for volume, right-click to focus"
echo ""
