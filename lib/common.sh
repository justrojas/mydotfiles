#!/bin/bash
# Common utilities for dotfiles installation scripts
# Source this file at the beginning of installation scripts

# ============================================================================
# GLOBAL VARIABLES
# ============================================================================

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Dry run mode (set to 1 to preview changes without executing)
DRY_RUN=${DRY_RUN:-0}

# Backup timestamp
readonly BACKUP_TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# ============================================================================
# LOGGING FUNCTIONS
# ============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_step() {
    echo -e "\n${GREEN}==>${NC} ${BLUE}$*${NC}"
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

# ============================================================================
# SYSTEM DETECTION
# ============================================================================

# Detect OS type
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo "$ID"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
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
detect_display_server() {
    if [[ -n "$WAYLAND_DISPLAY" ]]; then
        echo "wayland"
    elif [[ -n "$DISPLAY" ]]; then
        echo "x11"
    else
        echo "unknown"
    fi
}

# Get appropriate clipboard command
get_clipboard_cmd() {
    local display_server=$(detect_display_server)

    if [[ "$display_server" == "wayland" ]] && command -v wl-copy >/dev/null 2>&1; then
        echo "wl-copy"
    elif [[ "$display_server" == "x11" ]] && command -v xclip >/dev/null 2>&1; then
        echo "xclip -selection clipboard"
    else
        echo ""
    fi
}

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
check_internet() {
    log_info "Checking internet connectivity..."
    if ! ping -c 1 8.8.8.8 >/dev/null 2>&1 && ! ping -c 1 1.1.1.1 >/dev/null 2>&1; then
        log_error "No internet connection detected. This script requires internet access."
        return 1
    fi
    log_success "Internet connection verified"
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

# Check if command exists
check_command() {
    local cmd=$1
    local required=${2:-false}

    if command -v "$cmd" >/dev/null 2>&1; then
        log_success "$cmd is installed"
        return 0
    else
        if [[ "$required" == "true" ]]; then
            log_error "$cmd is required but not installed"
            return 1
        else
            log_warning "$cmd is not installed"
            return 1
        fi
    fi
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
# DOWNLOAD FUNCTIONS
# ============================================================================

# Download file with checksum verification
download_with_checksum() {
    local url=$1
    local output=$2
    local expected_checksum=$3
    local checksum_type=${4:-sha256}  # Default to sha256

    log_info "Downloading $url..."

    if [[ $DRY_RUN -eq 1 ]]; then
        log_info "[DRY RUN] Would download: $url to $output"
        return 0
    fi

    # Ensure output directory exists
    ensure_dir "$(dirname "$output")"

    # Download file
    if command -v wget >/dev/null 2>&1; then
        wget -q --show-progress -O "$output" "$url" || return 1
    elif command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$output" "$url" || return 1
    else
        log_error "Neither wget nor curl is installed"
        return 1
    fi

    # Verify checksum if provided
    if [[ -n "$expected_checksum" ]]; then
        log_info "Verifying checksum..."
        local actual_checksum
        case "$checksum_type" in
            sha256)
                actual_checksum=$(sha256sum "$output" | awk '{print $1}')
                ;;
            sha512)
                actual_checksum=$(sha512sum "$output" | awk '{print $1}')
                ;;
            md5)
                actual_checksum=$(md5sum "$output" | awk '{print $1}')
                ;;
            *)
                log_error "Unsupported checksum type: $checksum_type"
                return 1
                ;;
        esac

        if [[ "$actual_checksum" != "$expected_checksum" ]]; then
            log_error "Checksum verification failed!"
            log_error "Expected: $expected_checksum"
            log_error "Got:      $actual_checksum"
            rm -f "$output"
            return 1
        fi
        log_success "Checksum verification passed"
    fi

    log_success "Download complete: $output"
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
confirm() {
    local prompt="${1:-Do you want to continue?}"
    local default="${2:-n}"  # Default to 'n' for safety

    local options
    if [[ "$default" == "y" ]]; then
        options="[Y/n]"
    else
        options="[y/N]"
    fi

    read -p "$prompt $options " -r response
    response=${response:-$default}

    case "$response" in
        [yY]|[yY][eE][sS])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
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

# Initialize common settings
init_common() {
    # Parse --dry-run flag
    for arg in "$@"; do
        if [[ "$arg" == "--dry-run" ]]; then
            DRY_RUN=1
            log_warning "Running in DRY RUN mode - no changes will be made"
        fi
    done

    # Set up error handling
    setup_error_handling
}

# Call init if this script is being sourced
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    init_common "$@"
fi
