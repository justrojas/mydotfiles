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

# Remove a previously-installed ble.sh.
#
# ble.sh provided bash's answer to zsh-autosuggestions and
# zsh-syntax-highlighting. It was removed because it garbles multi-line input.
#
# The specific failure: ble.sh binds RET to accept-single-line-or-newline, so
# the moment a command contains a newline — a pasted block, a for-loop, a
# backslash continuation — it switches to MULTILINE mode where Enter inserts
# another newline and only C-j executes. C-j is bound to pane navigation in
# both herdr and tmux, so it never reaches the shell and the command sits
# half-typed. Rebinding RET to `accept-line syntax` was tried and did not hold.
#
# Every machine that ran the old profile has an install left behind, so clean
# it up rather than leaving ~26MB of unused build plus a stale clone that a
# future .bashrc edit might start sourcing again by accident.
remove_blesh() {
    local installed="$HOME/.local/share/blesh"
    local src="$HOME/.cache/ble.sh"

    [[ -d "$installed" || -d "$src" ]] || return 0

    if [[ ${DRY_RUN:-0} -eq 1 ]]; then
        log_info "[DRY RUN] Would remove $installed and $src"
        return 0
    fi

    log_info "Removing ble.sh (no longer used — it garbles multi-line input)..."
    rm -rf "$installed" "$src"
    log_success "ble.sh removed"
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

# ============================================================================
# Tool registry + the shared install/upgrade loop
# ============================================================================
#
# This lives here, not in a profile, because two profiles need it and used to
# implement it twice. install-packages.sh had its own ad-hoc loop that checked
# only `command -v`, so a tool that was present but *outdated* was reported
# "already installed" and skipped — which is how apt kitty 0.21.2 survived a
# full desktop install and kept the herdr double-keypress alive. Version
# awareness now applies wherever tools are installed.

# Installed version for tools we track precisely; empty for everything else.
get_installed_version() {
    case "$1" in
        nvim)  nvim --version 2>/dev/null | head -1 | grep -oP 'v\d+\.\d+\.\d+' || true ;;
        tmux)  tmux -V 2>/dev/null | grep -oP '\d+\.\d+[a-z]?' | head -1 || true ;;
        kitty) kitty --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' | head -1 || true ;;
        *)     echo "" ;;
    esac
}

# Is the installed tool older than the pinned version?
#
# CONVENTION: returns 0 (true) when the tool IS outdated, 1 (false) otherwise —
# matching the function name and the `if is_tool_outdated ...; then upgrade`
# call site.
#
# This was previously inverted (0 meant "up to date"), which made every check
# backwards: current tools were reported stale, genuinely stale ones were
# reported fine, and every "system" tool printed the nonsense
# "is outdated (installed: ?, pinned: system)".
is_tool_outdated() {
    case "$1" in
        nvim)
            local actual a_minor p_minor
            actual=$(get_installed_version nvim)
            # Unknown version — can't prove it's stale, so don't nag.
            [[ -z "$actual" ]] && return 1
            a_minor=$(echo "$actual"              | grep -oP '\d+\.\d+' | head -1)
            p_minor=$(echo "$PINNED_NVIM_VERSION" | grep -oP '\d+\.\d+' | head -1)
            _older_than "$a_minor" "$p_minor"
            ;;
        tmux)
            local actual
            actual="$(get_installed_version tmux)"
            [[ -z "$actual" ]] && return 1
            _older_than "$actual" "$PINNED_TMUX_VERSION"
            ;;
        kitty)
            local actual
            actual="$(get_installed_version kitty)"
            [[ -z "$actual" ]] && return 1
            _older_than "$actual" "$MIN_KITTY_VERSION"
            ;;
        *)  return 1 ;;  # system tools — no pinned version to enforce
    esac
}

# True when a tool is below its hard MINIMUM — a version known to be broken,
# as opposed to merely behind the pin.
#
# Only kitty has such a floor today: releases before 0.33.0 carry the
# keyboard-protocol bug that double-fires Enter/Tab/Backspace inside herdr.
# Behind the pin is a preference and waits for --update; below the minimum is a
# defect and is fixed immediately.
is_tool_below_minimum() {
    case "$1" in
        kitty)
            local actual
            actual="$(get_installed_version kitty)"
            [[ -z "$actual" ]] && return 1
            _older_than "$actual" "$MIN_KITTY_VERSION"
            ;;
        *)  return 1 ;;
    esac
}

declare -A TOOL_VERSIONS=(
    [tmux]="$PINNED_TMUX_VERSION"
    [nvim]="$PINNED_NVIM_VERSION"
    [kitty]="$PINNED_KITTY_VERSION"
    [zsh]="$PINNED_ZSH_VERSION"
    [herdr]="$PINNED_HERDR_VERSION"
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
)

declare -A TOOL_INSTALLERS=(
    [tmux]="install_tmux"
    [nvim]="install_nvim"
    [kitty]="install_kitty"
    [zsh]="install_zsh"
    [herdr]="install_herdr"
    [git]="install_apt_pkg git"
    [curl]="install_apt_pkg curl"
    [npm]="install_apt_pkg npm"
    [fzf]="install_fzf"
    [eza]="install_eza"
    [batcat]="install_apt_pkg bat"
    [zoxide]="install_zoxide"
    [tree]="install_apt_pkg tree"
    [glow]="install_glow"
    [rsync]="install_apt_pkg rsync"
    [rg]="install_apt_pkg ripgrep"
    [fdfind]="install_apt_pkg fd-find"
    [magick]="install_apt_pkg imagemagick"
    [pip3]="install_apt_pkg python3-pip"
    [wl-copy]="install_apt_pkg wl-clipboard"
)

# Some tools are reachable under more than one binary name depending on the
# distro release. Keyed by tool name; value is the set of acceptable binaries.
# Without this, a present-but-differently-named tool is treated as missing and
# reinstalled on every single run.
declare -A TOOL_ALIASES=(
    [batcat]="batcat bat"
    [fdfind]="fdfind fd"
    [magick]="magick convert"
)

_tool_present() {
    local candidate
    for candidate in ${TOOL_ALIASES[$1]:-$1}; do
        command -v "$candidate" >/dev/null 2>&1 && return 0
    done
    return 1
}

# Prompt whether to install a missing tool, then call the installer.
handle_missing_tool() {
    local tool="$1" install_fn="$2" pinned_version="$3"

    echo ""
    log_warning "$tool is not installed (pinned version: $pinned_version)"

    if [[ ${NONINTERACTIVE:-0} -eq 1 ]]; then
        log_info "Non-interactive mode: installing $tool automatically"
        $install_fn || log_warning "$tool installation failed — continuing without it"
        return
    fi

    echo "  [1/i] Install pinned version ($pinned_version)"
    echo "  [2/s] Skip (continue without $tool)"
    echo "  [3/a] Abort setup"
    echo ""
    # Reads $TTY_STDIN, not /dev/tty — in a container or under `ssh -T` there
    # is no /dev/tty and the redirect fails before the prompt is even shown.
    local choice
    read -rp "Choice [1/2/3]: " -n 1 choice <"${TTY_STDIN:-/dev/stdin}"
    echo "" >&2

    case "${choice,,}" in
        1|i) $install_fn || log_warning "$tool installation failed — continuing without it" ;;
        2|s) log_info "Skipping $tool" ;;
        3|a) log_error "Setup aborted."; exit 1 ;;
        *) log_info "No valid choice — skipping $tool" ;;
    esac
}

# install_tools <tool>...
#
# The single place that decides, per tool: install it, upgrade it, or leave it
# alone. Honours UPDATE_MODE for "behind the pin" and always acts on "below the
# documented minimum".
install_tools() {
    local tool actual pinned
    for tool in "$@"; do
        if _tool_present "$tool"; then
            if is_tool_outdated "$tool"; then
                actual=$(get_installed_version "$tool")
                pinned="${TOOL_VERSIONS[$tool]:-?}"
                log_warning "$tool is outdated (installed: ${actual:-?}, pinned: $pinned)"

                if is_tool_below_minimum "$tool"; then
                    log_warning "  ${actual:-?} is below the minimum safe version — upgrading regardless of --update"
                    ${TOOL_INSTALLERS[$tool]} || log_warning "$tool upgrade failed — continuing"
                elif [[ ${UPDATE_MODE:-0} -eq 1 ]]; then
                    log_info "Upgrading $tool..."
                    ${TOOL_INSTALLERS[$tool]} || log_warning "$tool upgrade failed — continuing"
                else
                    log_info "Re-run with --update to upgrade automatically"
                fi
            else
                actual=$(get_installed_version "$tool")
                if [[ -n "$actual" ]]; then
                    log_success "$tool found ($actual)"
                else
                    log_success "$tool found"
                fi
            fi
        else
            handle_missing_tool "$tool" "${TOOL_INSTALLERS[$tool]}" "${TOOL_VERSIONS[$tool]:-?}"
        fi
    done
}

# Install a monospaced font that covers the braille block (U+2800-U+28FF).
#
# The cat art in assets/cats/ is drawn entirely in braille, which is a good
# choice because every character in that block is single-width. But coverage is
# not guaranteed: JetBrainsMono Nerd Font does not include the block at all,
# and on a default Ubuntu install NO monospaced font does —
# `fc-list ':charset=28FF:spacing=100'` returns nothing. fontconfig then falls
# back to DejaVu Sans, which is proportional, and the art skews.
#
# fonts-dejavu-core supplies DejaVu Sans Mono; config/kitty/kitty.conf maps the
# block to it explicitly with symbol_map.
install_braille_font() {
    # Already covered by some monospaced font? Nothing to do.
    if fc-list ':charset=28FF:spacing=100' 2>/dev/null | grep -q .; then
        log_success "Braille glyphs already available in a monospaced font"
        return 0
    fi

    if [[ ${DRY_RUN:-0} -eq 1 ]]; then
        log_info "[DRY RUN] Would install fonts-dejavu-core for braille coverage"
        return 0
    fi

    log_info "Installing fonts-dejavu-core (monospaced braille for the cat art)..."
    apt_update_once
    if sudo apt-get install -y fonts-dejavu-core >/dev/null 2>&1; then
        fc-cache -f >/dev/null 2>&1 || true
        if fc-list ':charset=28FF:spacing=100' 2>/dev/null | grep -q .; then
            log_success "Braille coverage installed"
        else
            log_warning "fonts-dejavu-core installed but braille still unmapped"
        fi
    else
        # Non-fatal: the UI drops to the ASCII cats, which need no font at all.
        log_warning "Could not install fonts-dejavu-core — cat art will use the ASCII tier"
    fi
}
