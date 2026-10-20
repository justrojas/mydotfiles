#!/bin/bash
# Common utilities for dotfiles installation scripts
# Source this file at the beginning of installation scripts

# ============================================================================
# GLOBAL VARIABLES
# ============================================================================

# Color codes for output. Empty when stdout is not a terminal or NO_COLOR is
# set (https://no-color.org), so logs and CI output carry no escape codes.
# Guarded so a second `source` (profiles source each other) does not trip
# readonly.
if [[ -z "${_DOTFILES_COLORS_SET:-}" ]]; then
    _DOTFILES_COLORS_SET=1
    if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
        readonly RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[0;33m' BLUE='\033[0;34m'
        readonly CYAN='\033[0;36m' MAGENTA='\033[0;35m' BOLD='\033[1m' DIM='\033[2m' NC='\033[0m'
    else
        readonly RED='' GREEN='' YELLOW='' BLUE='' CYAN='' MAGENTA='' BOLD='' DIM='' NC=''
    fi
fi

# Dry run mode (set to 1 to preview changes without executing)
DRY_RUN=${DRY_RUN:-0}

# Backup timestamp. Guarded like the colours: a second `source` must not fail
# on re-assigning a readonly (under set -e that killed the script).
if [[ -z "${BACKUP_TIMESTAMP:-}" ]]; then
    BACKUP_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    readonly BACKUP_TIMESTAMP
fi

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

# Layout matches the `dotfiles` CLI (cli/dotfiles.py) and the team's rich-based
# tools: dim time, a fixed-width dim level, then the message.
#
#   14:02:11 INFO     Linking tmux config
#   14:02:12 WARNING  ~/.tmux.conf exists, backed up
#
# cli/dotfiles.py parses WARNING / ERROR and the step lines below out of the
# install transcript for its summary panel — keep those tokens stable.
#
# The message is printed with %s, not %b: logged text often contains commands
# ("Would execute: printf '\n'...") whose backslashes must stay literal.
_log() {
    local color="$1" level="$2"; shift 2
    printf "${DIM}%s${NC} ${color}%-8s${NC} %s\n" "$(date +%H:%M:%S)" "$level" "$*"
}

log_info()    { _log "${DIM}${BLUE}"  INFO    "$*"; }
log_success() { _log "${GREEN}"       OK      "$*"; }
log_warning() { _log "${YELLOW}"      WARNING "$*"; }
# Colour is decided from stdout, but errors go to stderr: `2>errors.log` with a
# terminal on stdout must not write escape codes into the file.
log_error() {
    if [[ -t 2 ]]; then
        _log "${RED}" ERROR "$*" >&2
    else
        printf '%s %-8s %s\n' "$(date +%H:%M:%S)" ERROR "$*" >&2
    fi
}

STEP_NUM=0
STEP_TOTAL=0  # Set this in the calling script for "X/N" display

# Profile header, printed once at the top of each profile:
#
#   Terminal  tmux · kitty · neovim · shell
#   ────────────────────────────────────────
log_banner() {
    local title="$1" sub="${2:-}"
    echo ""
    echo -e "${BOLD}${MAGENTA}${title}${NC}  ${DIM}${sub}${NC}"
    echo -e "${DIM}$(printf '─%.0s' $(seq 1 $(( ${#title} + ${#sub} + 2 ))))${NC}"
}

# A step header reads as a section break:   ── [3/10] Installing tmux
#
# Profiles nest (desktop runs install-packages, terminal, kde and bar; vm runs
# terminal). A child's steps are printed indented as sub-steps:
#
#   ── [2/4] Terminal configuration
#      · [1/10] Checking for required tools
#
# so the outer counter stays meaningful and cli/dotfiles.py, which counts only
# unindented "── [n/N]" lines, reports the top-level profile's progress.
# Depth is passed to children through DOTFILES_STEP_DEPTH, bumped the first
# time a profile prints a step (install.sh never does, so the profile it
# launches is still top-level).
_STEP_DEPTH="${DOTFILES_STEP_DEPTH:-0}"
log_step() {
    (( STEP_NUM++ )) || true
    export DOTFILES_STEP_DEPTH=$(( _STEP_DEPTH + 1 ))
    local counter=""
    [[ $STEP_TOTAL -gt 0 ]] && counter="${YELLOW}[${STEP_NUM}/${STEP_TOTAL}]${NC} "
    if [[ $_STEP_DEPTH -gt 0 ]]; then
        echo -e "\n   ${DIM}·${NC} ${counter}${CYAN}$*${NC}"
    else
        echo -e "\n${DIM}──${NC} ${counter}${BOLD}${CYAN}$*${NC}"
    fi
}

# ============================================================================
# DRY RUN FUNCTIONS
# ============================================================================

# Execute command or show what would be executed
run_or_dry() {
    if [[ $DRY_RUN -eq 1 ]]; then
        log_info "[DRY RUN] Would execute: $*"
        return 0
    else
        "$@"
    fi
}

# Run a vendor install script, but only after it has fully downloaded.
#
#   run_remote_installer <url> <bash|sh> [args...]
#
# `curl URL | bash` executes whatever arrives: without -f an HTTP error page
# is fed to the interpreter, and a dropped connection runs a truncated script.
# Download to a temp file first, require a successful transfer and a shebang,
# then run it. Returns non-zero on any failure (callers verify the binary).
run_remote_installer() {
    local url="$1" interp="$2"; shift 2
    local tmp rc=0
    tmp="$(mktemp)" || return 1
    if ! curl -fsSL --retry 2 --max-time 60 -o "$tmp" "$url"; then
        log_warning "Download failed: $url"
        rm -f "$tmp"; return 1
    fi
    if [[ "$(head -c 2 "$tmp")" != "#!" ]]; then
        log_warning "Not an install script (no shebang): $url"
        rm -f "$tmp"; return 1
    fi
    "$interp" "$tmp" "$@" || rc=$?
    rm -f "$tmp"
    return $rc
}

# ============================================================================
# SYSTEM DETECTION
# ============================================================================

# Detect OS type
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo "$ID"
    elif [[ "${OSTYPE:-}" == "darwin"* ]]; then
        echo "macos"
    else
        echo "unknown"
    fi
}

# Detect Ubuntu/Debian version codename
detect_ubuntu_codename() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}"
    else
        echo ""
    fi
}

# Detect display server (X11 or Wayland)
# NOTE: every caller runs under `set -u`, so these MUST use ${VAR:-} — a bare
# "$WAYLAND_DISPLAY" aborts the script on any box where the variable is unset
# (i.e. every X11 session, and every headless/SSH session).
detect_display_server() {
    if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
        echo "wayland"
    elif [[ -n "${DISPLAY:-}" ]]; then
        echo "x11"
    else
        echo "unknown"
    fi
}

# A stdin source that is safe to redirect from.
#
# Several third-party installers (Oh My Zsh, rustup, ...) hang when stdin is a
# pipe, so the usual fix is `<​/dev/tty`. But in a container, a CI runner, or
# under `ssh -T` there IS no /dev/tty, and redirecting from it fails outright —
# which previously got swallowed by `|| true` and reported as success.
#
# Use as:  some-installer <"$TTY_STDIN"
#
# The probe runs in a subshell with stderr redirected FIRST. Redirections are
# applied left to right, so `: </dev/tty 2>/dev/null` still prints
# "/dev/tty: No such device or address" — the failing redirect happens before
# stderr is silenced. Order matters here.
if ( exec 2>/dev/null </dev/tty ); then
    TTY_STDIN=/dev/tty
else
    TTY_STDIN=/dev/null
fi
export TTY_STDIN
# Backwards-compatible alias used by the Oh My Zsh step.
OMZ_STDIN="$TTY_STDIN"
export OMZ_STDIN

# ============================================================================
# VALIDATION FUNCTIONS
# ============================================================================

# Check if running as root
check_not_root() {
    if [[ $EUID -eq 0 ]]; then
        log_error "This script should not be run as root. Please run as a normal user."
        return 1
    fi
}

# Check if sudo is available
check_sudo() {
    if ! command -v sudo >/dev/null 2>&1; then
        log_error "sudo is not installed. Please install sudo first."
        return 1
    fi

    if ! sudo -n true 2>/dev/null; then
        log_info "Checking sudo access (you may be prompted for your password)..."
        if ! sudo true; then
            log_error "This script requires sudo access."
            return 1
        fi
    fi
}

# Check internet connectivity
# Verify we can actually reach the network.
#
# Deliberately does NOT use `ping`:
#   * `iputils-ping` is absent from most minimal images (including this repo's
#     own tests/docker image), so the probe failed on a machine with perfectly
#     working networking. That made profiles/install-packages.sh abort at step
#     1/5 and meant its test suite never ran a single assertion.
#   * ICMP to 8.8.8.8 is blocked outright on plenty of corporate networks and
#     cloud VPCs, while HTTPS works fine.
#
# What the installers actually need is DNS + outbound HTTPS, so probe for that
# instead, in order of preference, falling back through what is available.
check_internet() {
    log_info "Checking internet connectivity..."

    # 1. HTTPS to a host we genuinely depend on. curl is a hard dependency of
    #    every installer here, so it is essentially always present.
    if command -v curl >/dev/null 2>&1; then
        if curl -fsS --max-time 8 -o /dev/null https://github.com 2>/dev/null; then
            log_success "Internet connection verified"
            return 0
        fi
    fi

    # 2. wget, for images that ship it instead of curl.
    if command -v wget >/dev/null 2>&1; then
        if wget -q --spider --timeout=8 https://github.com 2>/dev/null; then
            log_success "Internet connection verified"
            return 0
        fi
    fi

    # 3. DNS only. Proves resolution works even if HTTPS is proxied in a way
    #    the two probes above cannot negotiate.
    if command -v getent >/dev/null 2>&1; then
        if getent hosts github.com >/dev/null 2>&1; then
            log_warning "HTTPS probe failed but DNS resolves — continuing"
            return 0
        fi
    fi

    # 4. Last resort: ICMP, if ping happens to exist.
    if command -v ping >/dev/null 2>&1; then
        if ping -c 1 -W 3 8.8.8.8 >/dev/null 2>&1 || ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1; then
            log_success "Internet connection verified (ICMP)"
            return 0
        fi
    fi

    log_error "No internet connection detected. This script requires internet access."
    return 1
}

# Check disk space (minimum in MB)
check_disk_space() {
    local min_space_mb=${1:-1000}  # Default 1GB
    local available_mb=$(df -BM "$HOME" | awk 'NR==2 {print $4}' | sed 's/M//')

    if [[ $available_mb -lt $min_space_mb ]]; then
        log_error "Insufficient disk space. Need at least ${min_space_mb}MB, have ${available_mb}MB"
        return 1
    fi
    log_success "Disk space check passed (${available_mb}MB available)"
}

# ============================================================================
# FILE OPERATIONS
# ============================================================================

# Create directory if it doesn't exist
ensure_dir() {
    local dir=$1
    if [[ ! -d "$dir" ]]; then
        log_info "Creating directory: $dir"
        run_or_dry mkdir -p "$dir"
    fi
}

# Backup file or directory with timestamp
backup_path() {
    local path=$1
    local backup_path="${path}.bak.${BACKUP_TIMESTAMP}"

    if [[ -e "$path" ]]; then
        log_info "Backing up $path to $backup_path"
        run_or_dry mv "$path" "$backup_path"
        return 0
    fi
    return 1
}

# Create symlink with backup
safe_symlink() {
    local source=$1
    local target=$2

    if [[ ! -e "$source" ]]; then
        log_error "Source does not exist: $source"
        return 1
    fi

    # Remove existing symlink or backup existing file/directory
    if [[ -L "$target" ]]; then
        log_info "Removing existing symlink: $target"
        run_or_dry rm "$target"
    elif [[ -e "$target" ]]; then
        backup_path "$target"
    fi

    # Ensure parent directory exists
    ensure_dir "$(dirname "$target")"

    log_info "Creating symlink: $target -> $source"
    run_or_dry ln -sf "$source" "$target"
}

# ============================================================================
# PACKAGE MANAGEMENT
# ============================================================================

# Run apt commands with sudo (Ubuntu/Debian)
apt_install() {
    if [[ $DRY_RUN -eq 1 ]]; then
        log_info "[DRY RUN] Would install packages: $*"
        return 0
    fi

    log_info "Installing packages: $*"
    sudo apt-get update -qq || return 1
    sudo apt-get install -y "$@" || return 1
    log_success "Packages installed successfully"
}

# ============================================================================
# CONFIRMATION
# ============================================================================

# Ask for user confirmation
# Single-character prompt that echoes the chosen key to STDOUT.
#
# Differs from confirm() below: confirm() returns an exit status and is for
# plain yes/no gates, whereas prompt_yn echoes the raw key so the caller can
# switch on multi-way choices (e.g. bar-setup's [r]emove / [a]utohide / [n]one).
#
# Honours $NONINTERACTIVE (returns $default without prompting), so profiles run
# unattended in CI and from desktop-setup.sh.
#
# Reads from $TTY_STDIN, not /dev/tty — in a container or under `ssh -T` there
# is no /dev/tty and the redirect fails outright.
#
# Usage: reply=$(prompt_yn "Question? [y/N] " "n")
# The single prompting primitive. A second helper, confirm(), used to exist
# alongside this one; it read plain stdin and ignored $NONINTERACTIVE, so it
# behaved differently from every other prompt in the repo in exactly the
# environments (containers, ssh -T, CI) the $TTY_STDIN probe exists to handle.
# It had one caller and has been removed.
prompt_yn() {
    local question="$1" default="${2:-n}"
    if [[ ${NONINTERACTIVE:-0} -eq 1 ]]; then
        echo "$default"
        return 0
    fi
    read -rp "$question" -n 1 <"$TTY_STDIN"
    echo >&2
    echo "${REPLY:-$default}"
}


# ============================================================================
# ERROR HANDLING
# ============================================================================

# Trap handler for cleanup on exit
cleanup_on_exit() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Script failed with exit code $exit_code"
        log_info "Some changes may have been partially applied."
        log_info "Backup files are timestamped with: $BACKUP_TIMESTAMP"
    fi
}

# Set up trap for cleanup
setup_error_handling() {
    trap cleanup_on_exit EXIT
    set -E  # Inherit ERR trap
}

# ============================================================================
# INITIALIZATION
# ============================================================================

# Initialize common settings.
#
# Runs twice in most scripts: once automatically when this file is sourced
# (below) and again when the script calls it explicitly with its own "$@".
# Both are kept — the explicit call is what sees the script's real arguments —
# but the dry-run notice is printed once per install, not once per call and
# again in every child profile. The guard is exported so desktop-setup.sh's
# nested terminal/kde runs stay quiet too.
init_common() {
    for arg in "$@"; do
        if [[ "$arg" == "--dry-run" ]]; then
            DRY_RUN=1
            if [[ -z "${DOTFILES_DRY_RUN_ANNOUNCED:-}" ]]; then
                log_warning "Dry run — no changes will be made"
                export DOTFILES_DRY_RUN_ANNOUNCED=1
            fi
        fi
    done

    setup_error_handling
}

# Call init if this script is being sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    init_common "$@"
fi
