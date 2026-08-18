#!/bin/bash
# Terminal Setup - symlinks dotfile configs and installs shell tooling
#
# Installs missing tools at pinned versions matching the author's setup,
# then symlinks configs. Installs: oh-my-zsh, zsh plugins, oh-my-posh, NvChad.
# Symlinks: zshrc, kitty config, tmux config. Initialises tmux submodules.
#
# Usage: bash terminal-setup.sh [--non-interactive] [--dry-run] [--update] [--minimal]
#
# --minimal  headless/VM mode: skip everything that only makes sense with a GUI
#            (kitty + its config, Nerd fonts, herdr, oh-my-posh kitty theme
#            mapping, imagemagick, wl-clipboard). Shell + nvim + tmux + the CLI
#            tools the shared aliases depend on are still installed.

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "$DOTFILES_DIR/lib/common.sh"
# Pinned tool installers, shared with profiles/install-packages.sh.
# MUST come after common.sh — it depends on log_*, run_or_dry, ensure_dir.
# shellcheck source=../lib/installers.sh
source "$DOTFILES_DIR/lib/installers.sh"

# ============================================================================
# Pinned versions (matching author's current setup)
# ============================================================================
# NOTE: oh-my-posh is intentionally NOT pinned — its installer always fetches
# the current release. There was a PINNED_OMP_VERSION constant here that was
# never referenced by anything, which made the pin look real.

# ============================================================================
# Argument parsing
# ============================================================================
NONINTERACTIVE=0
UPDATE_MODE=0
MINIMAL=0
for arg in "$@"; do
    [[ "$arg" == "--non-interactive" ]] && NONINTERACTIVE=1
    [[ "$arg" == "--update" ]]          && UPDATE_MODE=1
    [[ "$arg" == "--minimal" ]]         && MINIMAL=1
done

init_common "$@"

# Total number of log_step calls in this script — drives the X/N counter.
# --minimal skips 3 of them (Nerd fonts, kitty config, herdr).
if [[ $MINIMAL -eq 1 ]]; then
    STEP_TOTAL=8
else
    STEP_TOTAL=11
fi

# ============================================================================
# PATH — adopt the same PATH an interactive shell will have
# ============================================================================
# Most tools here install into ~/.local/bin (nvim, oh-my-posh, zoxide, kitty)
# or ~/.fzf/bin. Those directories are put on PATH by the shell rc files via
# config/shell/env.sh, which this process never inherited. Without sourcing it,
# every `command -v <tool>` check below is answered against the wrong PATH:
# already-installed tools look missing and get needlessly reinstalled.
#
# ORDER MATTERS: env.sh's _prepend_path only adds a directory that already
# EXISTS. On a fresh machine ~/.local/bin does not exist until the first
# installer creates it, so sourcing env.sh first would be a no-op for the one
# directory that matters most. Create it up front.
ensure_dir "$HOME/.local/bin"

if [[ -f "$DOTFILES_DIR/config/shell/env.sh" ]]; then
    # shellcheck source=../config/shell/env.sh
    source "$DOTFILES_DIR/config/shell/env.sh"
fi


# ============================================================================
# apt-get update deduplication — run at most once per invocation
# ============================================================================

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
# Pre-flight: check for required tools, offer to install missing ones
# ============================================================================
log_step "Checking for required tools"


# Tools to check/install. --minimal drops the GUI-only ones: kitty (terminal
# emulator), imagemagick (used for image previews in kitty), wl-clipboard
# (Wayland-only) and herdr (a graphical-terminal multiplexer). tmux covers
# multiplexing on a headless box.
if [[ $MINIMAL -eq 1 ]]; then
    TOOL_LIST=(tmux nvim zsh git curl npm fzf eza batcat zoxide tree glow rsync rg fdfind pip3)
else
    TOOL_LIST=(tmux nvim kitty zsh git curl npm fzf eza batcat zoxide tree glow rsync rg fdfind magick pip3 wl-copy herdr)
fi

# The registry and the install/upgrade loop live in lib/installers.sh so
# install-packages.sh uses the identical logic. It previously had its own
# `command -v` loop with no version awareness, which is how a pre-existing
# outdated kitty was waved through as "already installed".
install_tools "${TOOL_LIST[@]}"

# fzf may be installed via apt but the oh-my-zsh plugin requires ~/.fzf to exist
if command -v fzf >/dev/null 2>&1 && [[ ! -d "$HOME/.fzf" ]]; then
    log_info "fzf found via apt but ~/.fzf missing — running git install for oh-my-zsh plugin..."
    install_fzf
fi

# Remove apt's kitty even when the pinned one is already installed.
#
# The loop above only calls install_kitty() when kitty is missing or outdated,
# and the purge used to live inside it. So on a machine that already had 0.47.4,
# an apt kitty sitting alongside it was never removed — and since
# /usr/share/applications/kitty.desktop launches `Exec=kitty` against the
# session PATH (which often lacks ~/.local/bin), the panel and app menu kept
# starting the buggy 0.21.2. That is the herdr double-keypress coming back on
# every new setup despite the pinned install "succeeding".
if [[ $MINIMAL -eq 0 ]] && command -v dpkg >/dev/null 2>&1; then
    purge_apt_kitty || true
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
# FONTS  (GUI only — a headless VM has no font renderer)
# ============================================================================
if [[ $MINIMAL -eq 1 ]]; then
    log_info "Skipping Nerd fonts (--minimal)"
else
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
        # Best-effort: the fonts are already on disk, fc-cache only refreshes
        # fontconfig's index. Not worth aborting the whole profile over, and on
        # a minimal image fontconfig may not be installed at all.
        if command -v fc-cache >/dev/null 2>&1; then
            log_info "Rebuilding font cache..."
            run_or_dry fc-cache -f "$fonts_dst" || log_warning "fc-cache failed — fonts installed anyway"
        else
            log_warning "fc-cache not found — fonts installed, cache not refreshed"
        fi
        log_success "Installed $new_fonts nerd font(s)"
    else
        log_success "Nerd fonts already installed"
    fi
else
    log_warning "assets/fonts not found — skipping font install"
fi
fi  # end --minimal font guard

# ============================================================================
# KITTY  (GUI only)
# ============================================================================
if [[ $MINIMAL -eq 1 ]]; then
    log_info "Skipping kitty configuration (--minimal)"
else
log_step "kitty configuration"

if [[ -d "$DOTFILES_DIR/config/kitty" ]]; then
    safe_symlink "$DOTFILES_DIR/config/kitty" "$HOME/.config/kitty"
    log_success "kitty config linked"
else
    log_error "Kitty config not found at $DOTFILES_DIR/config/kitty"
fi
fi  # end --minimal kitty guard

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
                # stdin — the installer hangs on piped stdin, so give it a real
                # tty when one exists. In a container/CI there is no /dev/tty and
                # redirecting from it fails outright, so fall back to /dev/null.
                RUNZSH=no KEEP_ZSHRC=yes \
                    sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
                    "" --unattended <"$OMZ_STDIN" || true

                # Verify rather than assume. The old code unconditionally logged
                # success even when the installer had failed, which made a broken
                # install look clean until something downstream tripped over it.
                if [[ -d "$HOME/.oh-my-zsh" ]]; then
                    log_success "Oh My Zsh installed"
                else
                    log_error "Oh My Zsh install failed — zsh plugins will be skipped"
                fi
            else
                log_info "[DRY RUN] Would install Oh My Zsh"
            fi
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

        # NOTE: we deliberately do NOT chsh to zsh any more.
        #
        # bash is the primary interactive shell, and it is already the login
        # shell on every distro we target — so the correct login shell needs no
        # change. Which shell you actually land in is decided by
        # ~/.config/shell/preferred (see config/shell/switch.sh), which the bash
        # step below seeds to "bash". `shell-toggle` flips it, `tozsh` is a
        # one-off.
        #
        # The old code path also appended an `exec zsh` fallback to ~/.bashrc.
        # That is now actively harmful: ~/.bashrc is a symlink into this repo,
        # so the append would have written into a tracked file and dirtied the
        # working tree on every install.
        #
        # Make sure zsh is still a valid login shell so `shell-toggle` and
        # `chsh` work if you decide to flip back manually.
        zsh_path="$(command -v zsh || true)"
        if [[ -n "$zsh_path" ]] && ! grep -qxF "$zsh_path" /etc/shells 2>/dev/null; then
            log_info "Registering $zsh_path in /etc/shells (for manual chsh)..."
            run_or_dry sudo bash -c "echo '$zsh_path' >> /etc/shells" <"$TTY_STDIN" \
                || log_warning "Could not update /etc/shells (non-fatal)"
        fi
        log_success "zsh configured (bash remains the default — use 'shell-toggle' to switch)"

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
                # `|| true` keeps a transient network failure from aborting the
                # whole run, but the result MUST then be verified — otherwise a
                # failed download is reported as a successful install.
                curl -s https://ohmyposh.dev/install.sh | bash -s -- -d "$HOME/.local/bin" || true
            else
                log_info "[DRY RUN] Would install oh-my-posh to ~/.local/bin"
            fi
            _confirm_install oh-my-posh "oh-my-posh" \
                || log_warning "oh-my-posh missing — prompt will fall back to plain PS1"
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

    # Seed the shell preference. bash is the primary interactive shell; zsh
    # stays fully configured and is one `shell-toggle` (or `tozsh`) away.
    ensure_dir "$HOME/.config/shell"
    if [[ ! -f "$HOME/.config/shell/preferred" ]]; then
        if [[ $DRY_RUN -eq 0 ]]; then
            echo "bash" > "$HOME/.config/shell/preferred"
        fi
        log_info "Set default shell preference: bash (run 'shell-toggle' to switch to zsh)"
    else
        _existing_pref="$(cat "$HOME/.config/shell/preferred" 2>/dev/null)"
        if [[ "$_existing_pref" == "bash" ]]; then
            log_success "shell preference already set: bash"
        else
            # Deliberately NOT overwritten: this file is a user choice, and
            # silently flipping it would be worse than leaving it. But it is
            # also the single thing that makes every new bash session bounce
            # into zsh, so reporting it as a plain success (which is what used
            # to happen) hides the cause of "I can't use bash".
            log_warning "shell preference is '${_existing_pref:-empty}', not bash"
            log_info "  Every interactive bash session will exec into ${_existing_pref:-?}."
            log_info "  To make bash primary:  shell-toggle"
            log_info "  Or directly:           echo bash > ~/.config/shell/preferred"
            log_info "  For a one-off session without changing it: tobash"
        fi
    fi

    # ble.sh — bash's answer to zsh-autosuggestions + zsh-syntax-highlighting.
    # Not in the TOOL_LIST loop above because it is not a binary on PATH; it is
    # a library sourced by .bashrc from ~/.local/share/blesh.
    if [[ -f "$HOME/.local/share/blesh/ble.sh" ]]; then
        log_success "ble.sh already installed"
    else
        install_blesh
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

# ~/.local/bin is created and put on PATH at the top of this script, so this
# should never fire. If it does, something unset PATH mid-run.
if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
    log_warning "~/.local/bin unexpectedly missing from PATH — tool checks may misreport"
fi

# ============================================================================
# HERDR  (GUI terminal multiplexer — tmux covers this on a headless box)
# ============================================================================
if [[ $MINIMAL -eq 1 ]]; then
    log_info "Skipping herdr configuration (--minimal; use tmux instead)"
else
log_step "herdr configuration"

if [[ -d "$DOTFILES_DIR/config/herdr" ]]; then
    ensure_dir "$HOME/.config/herdr"

    # If herdr has already run once it will have written its own config.toml,
    # seeding default_shell from whatever $SHELL was at the time. On a machine
    # whose login shell is still zsh that bakes in "/bin/zsh", and every pane
    # herdr opens is zsh no matter what ~/.config/shell/preferred says — the
    # symlink below fixes it, but only if the file it replaces is noticed.
    # Call it out explicitly, because safe_symlink backs up silently and the
    # symptom (wrong shell in new panes) looks unrelated to this step.
    if [[ -f "$HOME/.config/herdr/config.toml" && ! -L "$HOME/.config/herdr/config.toml" ]]; then
        gen_shell="$(grep -oP 'default_shell\s*=\s*"\K[^"]+' "$HOME/.config/herdr/config.toml" 2>/dev/null || true)"
        log_warning "Replacing herdr's own generated config (not from this repo)"
        [[ -n "$gen_shell" ]] && log_info "  it set default_shell = $gen_shell"
        log_info "  the original is backed up alongside it"
    fi

    safe_symlink "$DOTFILES_DIR/config/herdr/config.toml" "$HOME/.config/herdr/config.toml"
    log_success "herdr config linked"
else
    log_warning "config/herdr not found — skipping"
fi
fi  # end --minimal herdr guard

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

    # Create kt↔omp mapping symlinks from theme-mappings.conf.
    # Pointless without kitty, so skip it in --minimal.
    mappings_file="$DOTFILES_DIR/config/oh-my-posh/theme-mappings.conf"
    omp_cache_dir="$HOME/.cache/oh-my-posh/themes"
    omp_gh_base="https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes"
    if [[ $MINIMAL -eq 1 ]]; then
        log_info "Skipping kitty↔omp theme mappings (--minimal)"
    elif [[ -f "$mappings_file" ]]; then
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

# Verify against the PATH an INTERACTIVE shell will actually have, not the one
# this script inherited. Tools land in ~/.local/bin (nvim, oh-my-posh, zoxide)
# and ~/.fzf/bin (fzf); those directories are put on PATH by the shell rc files
# via config/shell/env.sh, which this process never sourced.
#
# Without this the verifier reported nvim/oh-my-posh/fzf/zoxide as MISSING
# immediately after installing them successfully — alarming, and wrong.
if [[ -f "$DOTFILES_DIR/config/shell/env.sh" ]]; then
    # shellcheck source=../config/shell/env.sh
    source "$DOTFILES_DIR/config/shell/env.sh"
fi

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
verify_symlink ".bashrc"                   "$HOME/.bashrc"
verify_symlink ".zshrc"                    "$HOME/.zshrc"
verify_symlink ".tmux.conf"                "$HOME/.tmux.conf"
if [[ $MINIMAL -eq 0 ]]; then
    verify_symlink ".config/kitty"             "$HOME/.config/kitty"
    verify_symlink ".config/herdr/config.toml" "$HOME/.config/herdr/config.toml"
    verify_symlink ".local/bin/kt"             "$HOME/.local/bin/kt"
fi

echo ""
echo "  Tools in PATH"
verify_cmd "bash"         bash
verify_cmd "zsh"          zsh
verify_cmd "tmux"         tmux
[[ $MINIMAL -eq 0 ]] && verify_cmd "kitty" kitty || true
verify_cmd "nvim"         nvim
verify_cmd "oh-my-posh"   oh-my-posh
[[ $MINIMAL -eq 0 ]] && verify_cmd "herdr" herdr || true
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

# Preferred shell (this, not the login shell, decides where you land —
# see config/shell/switch.sh).
pref_file="$HOME/.config/shell/preferred"
if [[ -r "$pref_file" ]]; then _vok "Shell preference" "$(cat "$pref_file")"
else _vfail "Shell preference" "unset (will use login shell)"; fi

# Login shell vs preference.
#
# The preference only redirects *interactive* shells, via the exec in
# switch.sh. Anything non-interactive — scripts, cron, and tools that read
# $SHELL to decide what to spawn — still gets the login shell from
# /etc/passwd. When the two disagree, terminals look correct while everything
# else quietly uses the other shell.
#
# This bites hardest with terminal multiplexers: herdr writes its own
# config.toml on first run if none exists, seeding default_shell from the
# environment. If that happens while the login shell is still zsh, every pane
# it opens is zsh regardless of this preference.
#
# We only warn. chsh needs the user's password, so it cannot run unattended,
# and this profile is deliberately sudo-free so it stays usable on locked-down
# work machines.
# $USER is only exported by login shells, so it is unset in a container exec,
# a systemd unit, or `sudo` without -i — which is fatal under `set -u`. Derive
# it instead. (This is exactly how the Docker terminal suite caught this.)
_user_name="${USER:-$(id -un)}"
login_shell="$(getent passwd "$_user_name" 2>/dev/null | cut -d: -f7)"
pref_shell="$(cat "$pref_file" 2>/dev/null)"
if [[ -n "$pref_shell" && -n "$login_shell" ]]; then
    if [[ "$(basename "$login_shell")" == "$pref_shell" ]]; then
        _vok "Login shell matches preference" "$login_shell"
    else
        _vfail "Login shell" "$login_shell but preference is $pref_shell"
        log_info "  Interactive shells will still redirect to $pref_shell."
        log_info "  To align non-interactive contexts too:"
        log_info "    sudo chsh -s \$(command -v $pref_shell) $_user_name"
        log_info "  (note the username — 'sudo chsh -s ...' without it changes root's shell)"
    fi
fi

# terminfo: the entry kitty advertises must actually resolve, or full-screen
# TUIs (herdr especially) mis-parse key sequences and double up keystrokes.
if [[ $MINIMAL -eq 0 ]]; then
    if infocmp xterm-kitty >/dev/null 2>&1; then _vok "xterm-kitty terminfo"
    else _vfail "xterm-kitty terminfo" "missing — herdr may double keypresses"; fi
fi

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
[[ -L "$HOME/.bashrc" ]] && echo "  • Open a new terminal to activate bash + oh-my-posh ('shell-toggle' for zsh)"
echo ""
log_warning "IMPORTANT: Open a new terminal before running nvim — the correct nvim from ~/.local/bin must be in PATH"
echo ""
log_info "Tmux prefix: Ctrl+Space"
echo "  • Split horizontal : prefix + h"
echo "  • Split vertical   : prefix + v"
echo "  • Switch windows   : Alt+H / Alt+L  or  Alt+1-9"
echo "  • Install plugins  : prefix + I"
