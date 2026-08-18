#!/bin/bash
# lib/installers.sh — pinned tool installers, shared by the install profiles.
#
# WHY THIS FILE EXISTS
# --------------------
# kitty, neovim, eza, glow and zoxide used to be installed by BOTH
# profiles/install-packages.sh and profiles/terminal-setup.sh, with separate
# copy-pasted implementations. profiles/desktop-setup.sh runs one after the
# other, so a full desktop install downloaded and extracted kitty twice, and
# installed neovim twice to two different locations:
#
#   install-packages.sh  ->  unpinned 'stable' AppImage  ->  /usr/local/bin/nvim
#   terminal-setup.sh    ->  pinned tarball              ->  ~/.local/bin/nvim
#
# leaving two different neovim binaries on PATH and silently defeating the pin.
# The kitty copies had two independent version constants that had to be kept in
# sync by hand, and the install-packages.sh copy was the inferior one — it
# lacked both the apt-purge step and the terminfo install.
#
# Everything now lives here exactly once. Both profiles source this file.
#
# CONTRACT
#   * Requires lib/common.sh to be sourced FIRST (log_*, run_or_dry, ensure_dir,
#     DRY_RUN, apt_update_once).
#   * Every installer returns non-zero on failure. Do not add an unconditional
#     log_success — use _confirm_install, which verifies a binary actually
#     exists afterwards. See its comment for why that matters.

# ============================================================================
# Pinned versions — the single source of truth
# ============================================================================
readonly PINNED_TMUX_VERSION="${PINNED_TMUX_VERSION:-3.4}"
readonly PINNED_NVIM_VERSION="${PINNED_NVIM_VERSION:-v0.11.6}"
readonly PINNED_KITTY_VERSION="${PINNED_KITTY_VERSION:-0.47.4}"
readonly PINNED_ZSH_VERSION="${PINNED_ZSH_VERSION:-5.8.1}"
readonly PINNED_HERDR_VERSION="${PINNED_HERDR_VERSION:-latest}"

# Minimum kitty that does NOT have the keyboard-protocol bug which double-fires
# Enter/Tab/Backspace inside herdr. Referenced by the version check and by the
# apt-purge rationale in install_kitty().
readonly MIN_KITTY_VERSION="0.33.0"

# NOTE: oh-my-posh is intentionally NOT pinned — its installer always fetches
# the current release.

# Version comparison: true when <have> is older than <want>.
#
# Lives here rather than in a profile because both the version checks and
# purge_apt_kitty need it. It was previously nested *inside* is_tool_outdated()
# in terminal-setup.sh, so it did not exist for anything sourcing only this
# file — purge_apt_kitty's safety check silently fell through to a bare
# "command not found" and purged anyway.
#
# sort -V handles the usual dotted forms (0.21.2, 3.4, v0.11.6 once stripped).
_older_than() {
    [[ "$(printf '%s\n' "$1" "$2" | sort -V | head -1)" == "$1" && "$1" != "$2" ]]
}

# ============================================================================
# apt-get update deduplication — run at most once per sourcing process
# ============================================================================
_APT_UPDATED=0
apt_update_once() {
    if [[ $_APT_UPDATED -eq 0 && ${DRY_RUN:-0} -eq 0 ]]; then
        sudo apt-get update -qq
        _APT_UPDATED=1
    fi
}

# ============================================================================
# Install verification
# ============================================================================
# Confirm an installer actually produced a working binary, instead of trusting
# that it did.
#
# This exists because every installer used to end with an unconditional
# `log_success "<tool> installed"`. Two real failures hid behind that:
#
#   * `curl ... | bash` returns the exit status of *bash*, so a curl failure
#     (e.g. an HTTP 429 from the zoxide installer) is invisible to the pipeline.
#   * The tool loop calls installers as `$installer || log_warning ...`, and a
#     function invoked on the left of `||` runs with `set -e` suppressed for its
#     whole body — so even a genuinely failing command does not stop the
#     function reaching its success line.
#
# The net effect was "[SUCCESS] zoxide installed" printed immediately after
# "curl: (22) The requested URL returned error: 429".
#
# Usage: _confirm_install <command-to-check> <human label>
# <command-to-check> may be a space-separated list of acceptable binary names;
# the first one found wins. Needed where upstream renamed the binary between
# versions — e.g. ImageMagick 6 ships `convert`, ImageMagick 7 ships `magick`,
# and which one you get depends entirely on the distro release.
_confirm_install() {
    local cmds="$1" label="${2:-$1}" cmd

    if [[ $DRY_RUN -eq 1 ]]; then
        log_success "$label installed"
        return 0
    fi

    # Re-resolve: bash caches command lookups, and would otherwise keep
    # returning the old (absent) result for something just installed.
    hash -r 2>/dev/null || true

    for cmd in $cmds; do
        if command -v "$cmd" >/dev/null 2>&1; then
            log_success "$label installed ($(command -v "$cmd"))"
            return 0
        fi
    done

    # Not on PATH — but an installer may have just CREATED its own bin
    # directory during this run, after env.sh computed PATH at startup.
    # Check the known install targets directly and adopt whichever one has it,
    # so a perfectly good install is not reported as a failure.
    local d
    for d in "$HOME/.local/bin" "${FZF_BASE:-$HOME/.fzf}/bin" "$HOME/bin" "$HOME/.cargo/bin"; do
        for cmd in $cmds; do
            if [[ -x "$d/$cmd" ]]; then
                case ":$PATH:" in
                    *":$d:"*) ;;
                    *) PATH="$d:$PATH"; export PATH ;;
                esac
                hash -r 2>/dev/null || true
                log_success "$label installed ($d/$cmd)"
                return 0
            fi
        done
    done

    log_error "$label install FAILED — none of '$cmds' found on PATH or in ~/.local/bin"
    return 1
}

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
    _confirm_install zsh "zsh"
}

# Install kitty from the official release tarball into ~/.local/kitty.app.
#
# NOTE: apt on Ubuntu 22.04 only ships kitty 0.21.2, which has a Kitty
# keyboard-protocol bug that makes Enter/Tab/Backspace fire twice inside
# apps like herdr (fixed upstream in 0.33.0). We therefore pin a modern
# version from GitHub releases instead of using apt, AND purge the apt
# package at the end of this function so the buggy binary can never win.
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

    purge_apt_kitty

    _confirm_install kitty "kitty ${PINNED_KITTY_VERSION}" || return 1

    install_kitty_terminfo
}

# Remove the apt-provided kitty (0.21.2 on Ubuntu 22.04).
#
# Its Kitty-keyboard-protocol bug double-fires Backspace/Enter/Tab inside herdr.
# Removing the package is the only way to guarantee the buggy binary can never
# be launched, because /usr/share/applications/kitty.desktop runs `Exec=kitty`
# and resolves it against the *session* PATH — which frequently lacks
# ~/.local/bin, so the panel and app-menu launch /usr/bin/kitty even when the
# shell resolves kitty to the pinned 0.47.4.
#
# This is a separate function, and is called independently of install_kitty(),
# because install_kitty() only runs when kitty is missing or outdated. On a
# machine that already had the pinned version, the purge never ran — so an apt
# kitty reinstalled by some later step (kde-setup used to list it) stayed
# forever, and the double-keypress came back on every setup.
#
# The xterm-kitty terminfo entry is handled by install_kitty_terminfo(), which
# does not depend on the apt kitty-terminfo package surviving this.
purge_apt_kitty() {
    if [[ ${DRY_RUN:-0} -eq 1 ]]; then
        log_info "[DRY RUN] Would purge apt-provided kitty if a working replacement exists"
        return 0
    fi

    dpkg -l kitty 2>/dev/null | grep -q '^ii' || return 0

    # NEVER purge without a working replacement in place.
    #
    # The tool loop in terminal-setup only *upgrades* an outdated tool when
    # --update is passed; otherwise it warns and moves on. So on a machine
    # whose only kitty was apt's 0.21.2, an unconditional purge here removed
    # the sole terminal emulator and installed nothing — leaving the user with
    # no kitty at all. Verify the pinned build is actually present and new
    # enough first, and say why we're skipping if it isn't.
    local pinned_bin="$HOME/.local/kitty.app/bin/kitty"
    if [[ ! -x "$pinned_bin" ]]; then
        log_warning "Not purging apt kitty: no replacement at $pinned_bin"
        log_info    "  Install the pinned build first (terminal-setup.sh --update),"
        log_info    "  otherwise removing apt kitty would leave you with no terminal."
        return 1
    fi

    local pinned_ver
    pinned_ver="$("$pinned_bin" --version 2>/dev/null | awk '{print $2}')"
    if [[ -z "$pinned_ver" ]] || _older_than "$pinned_ver" "$MIN_KITTY_VERSION"; then
        log_warning "Not purging apt kitty: replacement is ${pinned_ver:-unreadable}, older than $MIN_KITTY_VERSION"
        return 1
    fi

    log_info "Purging apt-provided kitty (buggy 0.21.2) to stop herdr double-keypress..."
    log_info "  replacement in place: kitty $pinned_ver at $pinned_bin"
    if sudo apt-get purge -y kitty 2>/dev/null; then
        log_success "Removed apt kitty"
    else
        log_warning "Could not purge apt kitty — remove /usr/bin/kitty manually"
        return 1
    fi
}

# Install the xterm-kitty terminfo entry into ~/.terminfo.
#
# kitty sets TERM=xterm-kitty. If that entry cannot be resolved, ncurses apps
# fall back to guessing escape sequences, which is what produces the herdr
# double-keypress / double-backspace behaviour on a freshly imaged machine.
#
# Previously this repo relied entirely on the apt `kitty-terminfo` package
# staying behind after `apt-get purge kitty`. That only works if apt kitty was
# ever installed. On a machine where kitty came solely from the pinned tarball,
# nothing ever provided the entry. The tarball ships its own copy, so compile
# that into the user's private terminfo dir — no root required, and it always
# matches the kitty version actually in use.
install_kitty_terminfo() {
    log_info "Installing xterm-kitty terminfo entry..."
    if [[ $DRY_RUN -eq 1 ]]; then
        log_info "[DRY RUN] Would compile xterm-kitty terminfo into ~/.terminfo"
        return 0
    fi

    # Already resolvable (apt kitty-terminfo, or a previous run)? Nothing to do.
    if infocmp xterm-kitty >/dev/null 2>&1; then
        log_success "xterm-kitty terminfo already present"
        return 0
    fi

    if ! command -v tic >/dev/null 2>&1; then
        log_info "tic not found — installing ncurses-bin..."
        sudo apt-get install -y ncurses-bin 2>/dev/null \
            || { log_warning "Could not install ncurses-bin; skipping terminfo setup"; return 0; }
    fi

    # The tarball ships the source under lib/kitty/terminfo/ (newer releases)
    # or share/terminfo/ (older ones). Accept either.
    local src
    for src in \
        "$HOME/.local/kitty.app/lib/kitty/terminfo/kitty.terminfo" \
        "$HOME/.local/kitty.app/share/terminfo/kitty.terminfo"
    do
        if [[ -f "$src" ]]; then
            ensure_dir "$HOME/.terminfo"
            if tic -x -o "$HOME/.terminfo" "$src" 2>/dev/null; then
                log_success "xterm-kitty terminfo compiled into ~/.terminfo"
                return 0
            fi
        fi
    done

    # Fall back to a pre-compiled tree shipped in the tarball, if present.
    if [[ -d "$HOME/.local/kitty.app/share/terminfo" ]]; then
        ensure_dir "$HOME/.terminfo"
        cp -rn "$HOME/.local/kitty.app/share/terminfo/." "$HOME/.terminfo/" 2>/dev/null || true
        if infocmp xterm-kitty >/dev/null 2>&1; then
            log_success "xterm-kitty terminfo copied into ~/.terminfo"
            return 0
        fi
    fi

    # Last resort: apt.
    if sudo apt-get install -y kitty-terminfo 2>/dev/null && infocmp xterm-kitty >/dev/null 2>&1; then
        log_success "xterm-kitty terminfo installed via apt (kitty-terminfo)"
        return 0
    fi

    log_warning "Could not install xterm-kitty terminfo — config/shell/env.sh will fall back to xterm-256color"
    return 0
}

# Install a package via apt — returns 1 (non-fatal) if the package is not found
# install_apt_package <package> [binary-to-verify ...]
#
# The Debian package name and the binary it provides are frequently different:
#   bat -> batcat, fd-find -> fdfind, ripgrep -> rg,
#   python3-pip -> pip3, wl-clipboard -> wl-copy,
#   imagemagick -> magick (IM7) or convert (IM6) depending on the release.
# Pass the binary name(s) whenever they differ from the package name, or
# verification reports a false failure for a package that installed perfectly.
#
# Candidates are taken as TRAILING ARGUMENTS, not as one quoted string. Values
# in the TOOL_INSTALLERS map are dispatched by unquoted word-splitting, so an
# embedded \"magick convert\" arrives as two literal args `"magick` and `convert"`
# — quotes and all. Accepting "$@" works with that splitting instead of against
# it, and reads better at the call site:
#
#   install_apt_package imagemagick magick convert
install_apt_package() {
    local pkg="$1"; shift
    local check_cmds="${*:-$pkg}"
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
    _confirm_install "$check_cmds" "$pkg"
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
    _confirm_install npm "nodejs/npm"
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
    _confirm_install eza "eza"
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
    _confirm_install glow "glow"
}

# Install zoxide via official installer (apt version 0.4.x is too old for 'zoxide init zsh --cmd cd')
install_zoxide() {
    log_info "Installing zoxide via official installer..."
    if [[ $DRY_RUN -eq 0 ]]; then
        curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash
    else
        log_info "[DRY RUN] Would install zoxide via official installer"
    fi
    _confirm_install zoxide "zoxide"
}

# Install herdr — agent-aware terminal multiplexer
install_herdr() {
    log_info "Installing herdr via official installer..."
    if [[ $DRY_RUN -eq 0 ]]; then
        curl -fsSL https://herdr.dev/install.sh | sh
    else
        log_info "[DRY RUN] Would install herdr via https://herdr.dev/install.sh"
    fi
    _confirm_install herdr "herdr"
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
        # --no-update-rc: our rc files are symlinks into this repo; letting the
        #   installer append to them would dirty the working tree every run.
        # bash is NOT excluded any more (it used to be --no-bash, from when zsh
        #   was the primary shell) — .bashrc sources ~/.fzf/shell/*.bash itself.
        "$HOME/.fzf/install" --key-bindings --completion --no-update-rc 2>/dev/null
    else
        log_info "[DRY RUN] Would clone fzf to ~/.fzf and run install"
    fi
    _confirm_install fzf "fzf"
}

# Install ble.sh — the Bash Line Editor.
#
# This is what closes the last real gap between our bash and zsh setups. Bash
# has no native equivalent of zsh-autosuggestions (grey inline ghost text from
# history) or zsh-syntax-highlighting (commands coloured as you type). ble.sh
# replaces readline wholesale and provides both, plus a proper selectable
# completion menu.
#
# Built from source: there is no apt package, and the release tarballs lag.
install_blesh() {
    log_info "Installing ble.sh (bash autosuggestions + syntax highlighting)..."
    if [[ $DRY_RUN -eq 1 ]]; then
        log_info "[DRY RUN] Would build ble.sh into ~/.local/share/blesh"
        return 0
    fi

    if ! command -v make >/dev/null 2>&1; then
        log_warning "make not found — skipping ble.sh (install build-essential and re-run)"
        return 0
    fi

    # ble.sh's build is written against GNU awk specifically and refuses to run
    # with mawk, which is what Ubuntu ships by default. Without this the build
    # dies with "Sorry, gawk could not be found."
    if ! command -v gawk >/dev/null 2>&1; then
        log_info "Installing gawk (required to build ble.sh)..."
        apt_update_once
        sudo apt-get install -y gawk 2>/dev/null || {
            log_warning "Could not install gawk — skipping ble.sh"
            return 0
        }
    fi

    local src="$HOME/.cache/ble.sh"
    if [[ -d "$src/.git" ]]; then
        git -C "$src" pull --quiet --recurse-submodules || {
            log_warning "ble.sh update failed — keeping existing install"
            return 0
        }
    else
        rm -rf "$src"
        git clone --recursive --depth 1 --shallow-submodules \
            https://github.com/akinomyoga/ble.sh.git "$src" --quiet || {
            log_warning "Could not clone ble.sh — continuing without it"
            return 0
        }
    fi

    # Installs to $PREFIX/share/blesh.
    if make -C "$src" install PREFIX="$HOME/.local" >/dev/null 2>&1; then
        log_success "ble.sh installed to ~/.local/share/blesh"
    else
        log_warning "ble.sh build failed — bash will fall back to plain readline"
    fi
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

    _confirm_install tmux "tmux ${PINNED_TMUX_VERSION}"
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

    _confirm_install nvim "neovim ${PINNED_NVIM_VERSION}"
}
