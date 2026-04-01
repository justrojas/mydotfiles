#!/bin/bash
# Docker-based test runner for dotfiles installation scripts
#
# Each test: builds a clean Ubuntu image, runs the install script
# non-interactively, then runs the assertion script inside the container.
#
# Usage:
#   ./tests/run-docker-tests.sh [options]
#
# Options:
#   -s, --suite SUITE    Run a specific test suite: terminal | packages | all (default: all)
#   -u, --ubuntu VER     Ubuntu version to test against: 2204 | 2404 | all (default: all)
#   -k, --keep           Keep containers after tests (useful for debugging)
#   --dry-run            Pass --dry-run to install scripts (skips actual installs)
#   -h, --help           Show this help

set -euo pipefail

DOTFILES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCKER_DIR="$DOTFILES_ROOT/tests/docker"
TESTS_DIR="$DOTFILES_ROOT/tests"

# ── defaults ──────────────────────────────────────────────────────────────────
UBUNTU_VERSIONS=("2204" "2404")
SUITES=("terminal" "packages")
KEEP=false
DRY_RUN_FLAG=""
SPECIFIC_VERSION=""
SPECIFIC_SUITE=""

# ── colours ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

log_info()    { echo -e "${BLUE}[INFO]${NC}    $*"; }
log_success() { echo -e "${GREEN}[PASS]${NC}    $*"; }
log_warning() { echo -e "${YELLOW}[WARN]${NC}    $*"; }
log_error()   { echo -e "${RED}[FAIL]${NC}    $*" >&2; }
log_section() { echo -e "\n${CYAN}══ $* ══${NC}"; }

# ── help ──────────────────────────────────────────────────────────────────────
show_help() {
cat <<EOF
Usage: $0 [options]

Options:
  -s, --suite SUITE    Test suite to run: terminal | packages | all  (default: all)
  -u, --ubuntu VER     Ubuntu version: 2204 | 2404 | all             (default: all)
  -k, --keep           Keep containers after tests for debugging
      --dry-run        Pass --dry-run to install scripts
  -h, --help           Show this help

Test suites:
  terminal   Runs terminal-setup.sh then asserts symlinks, oh-my-zsh,
             oh-my-posh, NvChad, and utility scripts are in place.

  packages   Runs install-packages.sh then asserts all expected
             commands (git, zsh, nvim, eza, zoxide, glow, ...) exist.

Examples:
  $0                          # run all suites on all Ubuntu versions
  $0 --suite terminal         # only run terminal-setup tests
  $0 --ubuntu 2204            # only test on Ubuntu 22.04
  $0 --suite packages --ubuntu 2404 --keep
EOF
}

# ── arg parsing ───────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--suite)   SPECIFIC_SUITE="$2";   shift 2 ;;
        -u|--ubuntu)  SPECIFIC_VERSION="$2"; shift 2 ;;
        -k|--keep)    KEEP=true;             shift   ;;
        --dry-run)    DRY_RUN_FLAG="--dry-run"; shift ;;
        -h|--help)    show_help; exit 0 ;;
        *) log_error "Unknown option: $1"; show_help; exit 1 ;;
    esac
done

[[ -n "$SPECIFIC_VERSION" ]] && UBUNTU_VERSIONS=("$SPECIFIC_VERSION")
[[ -n "$SPECIFIC_SUITE"   ]] && SUITES=("$SPECIFIC_SUITE")

# ── suite definitions ─────────────────────────────────────────────────────────
# suite_install_cmd <suite>  — the command run as testuser to install
suite_install_cmd() {
    case "$1" in
        terminal) echo "bash my-dotfiles/profiles/terminal-setup.sh --non-interactive $DRY_RUN_FLAG" ;;
        packages) echo "bash my-dotfiles/profiles/install-packages.sh $DRY_RUN_FLAG" ;;
        *) log_error "Unknown suite: $1"; exit 1 ;;
    esac
}

# suite_assert_script <suite>  — the assertion script to run afterwards
suite_assert_script() {
    case "$1" in
        terminal) echo "my-dotfiles/tests/test-terminal-setup.sh" ;;
        packages) echo "my-dotfiles/tests/test-install-packages.sh" ;;
        *) log_error "Unknown suite: $1"; exit 1 ;;
    esac
}

# ── docker helpers ────────────────────────────────────────────────────────────
check_docker() {
    command -v docker >/dev/null 2>&1 || { log_error "Docker not installed."; exit 1; }
    docker info >/dev/null 2>&1       || { log_error "Docker daemon not running."; exit 1; }
}

image_name() { echo "dotfiles-test:ubuntu$1"; }

build_image() {
    local ver="$1"
    local ubuntu_ver
    ubuntu_ver="${ver:0:2}.${ver:2:2}"   # "2204" → "22.04"

    log_section "Building image for Ubuntu $ubuntu_ver"
    docker build \
        --build-arg "UBUNTU_VERSION=${ubuntu_ver}" \
        -t "$(image_name "$ver")" \
        -f "$DOCKER_DIR/Dockerfile" \
        "$DOTFILES_ROOT" \
        --quiet
    log_info "Image ready: $(image_name "$ver")"
}

# run_suite <ubuntu_ver> <suite>
# Returns 0 on pass, 1 on fail.
run_suite() {
    local ver="$1" suite="$2"
    local image; image="$(image_name "$ver")"
    local container="dotfiles-test-${ver}-${suite}-$$"
    local install_cmd; install_cmd="$(suite_install_cmd "$suite")"
    local assert_script; assert_script="$(suite_assert_script "$suite")"

    log_section "Ubuntu ${ver:0:2}.${ver:2:2}  ·  suite: $suite"

    local run_flags=("--name" "$container")
    $KEEP || run_flags+=("--rm")

    local exit_code=0
    docker run "${run_flags[@]}" -w /home/testuser "$image" bash -c "
        set -euo pipefail
        echo '--- install ---'
        $install_cmd
        echo '--- assert ---'
        bash $assert_script
    " || exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        log_success "Ubuntu ${ver:0:2}.${ver:2:2} / $suite"
    else
        log_error "Ubuntu ${ver:0:2}.${ver:2:2} / $suite (exit $exit_code)"
        if $KEEP; then
            log_info "Container kept: $container"
            log_info "  Inspect: docker exec -it $container bash"
            log_info "  Remove:  docker rm -f $container"
        fi
    fi

    return $exit_code
}

cleanup_old_containers() {
    local old
    old=$(docker ps -a --format '{{.Names}}' | grep '^dotfiles-test-' || true)
    if [[ -n "$old" ]]; then
        log_info "Removing stale test containers..."
        echo "$old" | xargs docker rm -f >/dev/null 2>&1 || true
    fi
}

# ── main ──────────────────────────────────────────────────────────────────────
main() {
    echo ""
    echo "======================================"
    echo "  Dotfiles Test Runner"
    echo "======================================"
    echo ""
    log_info "Suites  : ${SUITES[*]}"
    log_info "Ubuntu  : ${UBUNTU_VERSIONS[*]}"
    [[ -n "$DRY_RUN_FLAG" ]] && log_warning "Dry-run mode — installs will be skipped"
    echo ""

    check_docker
    $KEEP || cleanup_old_containers

    # Build all required images first
    for ver in "${UBUNTU_VERSIONS[@]}"; do
        build_image "$ver"
    done

    # Run all suite × version combinations
    local passed=() failed=()
    for ver in "${UBUNTU_VERSIONS[@]}"; do
        for suite in "${SUITES[@]}"; do
            if run_suite "$ver" "$suite"; then
                passed+=("Ubuntu ${ver:0:2}.${ver:2:2} / $suite")
            else
                failed+=("Ubuntu ${ver:0:2}.${ver:2:2} / $suite")
            fi
        done
    done

    # Summary
    echo ""
    echo "======================================"
    echo "  Results"
    echo "======================================"
    echo "  Passed : ${#passed[@]}"
    echo "  Failed : ${#failed[@]}"
    echo ""
    for t in "${passed[@]}"; do echo -e "  ${GREEN}✓${NC} $t"; done
    for t in "${failed[@]}"; do echo -e "  ${RED}✗${NC} $t"; done
    echo ""

    [[ ${#failed[@]} -eq 0 ]] && { log_success "All tests passed!"; exit 0; } \
                               || { log_error   "Some tests failed.";  exit 1; }
}

main
