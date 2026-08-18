#!/usr/bin/env bash
# Phase 0 verification: purge_apt_kitty must never leave a machine without kitty.
#
# Exercises the exact regression shipped in 15adf7b: apt kitty present, no
# pinned replacement, purge called -> kitty removed entirely.
#
# Runs against the real lib/installers.sh with sudo/dpkg stubbed, so no
# packages are touched.
set -uo pipefail

REPO="${REPO:-/home/jrojas/Documents/my-dotfiles}"
PASS=0; FAIL=0
ok()  { echo "  PASS  $*"; PASS=$((PASS+1)); }
bad() { echo "  FAIL  $*"; FAIL=$((FAIL+1)); }

run_case() {
    local name="$1" have_pinned="$2" pinned_ver="$3" expect="$4"
    local tmp; tmp="$(mktemp -d)"

    # Fake HOME so we control whether a pinned kitty "exists".
    mkdir -p "$tmp/home/.local/kitty.app/bin"
    if [[ "$have_pinned" == yes ]]; then
        printf '#!/bin/sh\necho "kitty %s created by Kovid Goyal"\n' "$pinned_ver" \
            > "$tmp/home/.local/kitty.app/bin/kitty"
        chmod +x "$tmp/home/.local/kitty.app/bin/kitty"
    fi

    # Stub dpkg (apt kitty present) and sudo (records the purge instead of doing it).
    mkdir -p "$tmp/bin"
    printf '#!/bin/sh\n[ "$1" = "-l" ] && { echo "ii  kitty  0.21.2"; exit 0; }\nexit 1\n' > "$tmp/bin/dpkg"
    printf '#!/bin/sh\necho PURGED >> "%s/purged"\nexit 0\n' "$tmp" > "$tmp/bin/sudo"
    chmod +x "$tmp/bin/dpkg" "$tmp/bin/sudo"

    (
        export HOME="$tmp/home" PATH="$tmp/bin:$PATH" DRY_RUN=0
        # Minimal logging shims so installers.sh can be sourced standalone.
        log_info(){ :; }; log_success(){ :; }; log_warning(){ :; }; log_error(){ :; }
        export -f log_info log_success log_warning log_error 2>/dev/null || true
        # shellcheck disable=SC1090
        source "$REPO/lib/installers.sh" >/dev/null 2>&1
        purge_apt_kitty >/dev/null 2>&1
    )

    local purged=no
    [[ -f "$tmp/purged" ]] && purged=yes

    if [[ "$purged" == "$expect" ]]; then
        ok "$name (purged=$purged)"
    else
        bad "$name — expected purged=$expect, got $purged"
    fi
    rm -rf "$tmp"
}

echo "purge_apt_kitty safety:"
# The regression: no replacement installed -> must NOT purge.
run_case "refuses to purge with no pinned kitty"      no  ""       no
# Replacement too old -> still must not purge.
run_case "refuses to purge when replacement is 0.21.2" yes "0.21.2" no
# Good replacement -> purge is correct and expected.
run_case "purges when a good replacement exists"       yes "0.47.4" yes

echo ""
echo "Results: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
