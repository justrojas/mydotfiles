#!/usr/bin/env bash
# =============================================================================
# run-host-tests.sh — the tests that are safe to run on a real workstation
# =============================================================================
# The Docker suites (run-docker-tests.sh) assert things like "kitty is not
# installed", which are false on a configured machine. These tests only read
# the repo, parse configs or use temp directories, so they can run anywhere.
#
# Usage: bash tests/run-host-tests.sh
# =============================================================================
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOST_TESTS=(
    test-step-total.sh
    test-cat-art.sh
    test-bar-watch.sh
    test-kitty-purge-safety.sh
    test-rofi-theme.sh
    test-dotfiles-cli.sh
)

failed=()
for t in "${HOST_TESTS[@]}"; do
    printf '\n\033[1m%s\033[0m\n' "$t"
    bash "$DIR/$t" || failed+=("$t")
done

echo ""
if [[ ${#failed[@]} -eq 0 ]]; then
    echo "All ${#HOST_TESTS[@]} host test files passed."
else
    echo "Failed: ${failed[*]}"
    exit 1
fi
