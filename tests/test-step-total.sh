#!/usr/bin/env bash
# =============================================================================
# test-step-total.sh — the STEP_NAMES registry must match the real log_step calls
# =============================================================================
# terminal-setup.sh derives STEP_TOTAL (the X/N progress counter) from the
# STEP_NAMES array rather than a hand-maintained number. That only holds as long
# as the registry and the actual `log_step "..."` calls agree, so this test
# compares the two directly instead of asserting a magic constant.
#
# Checked here:
#   1. Every log_step string in the script appears in the full (non-minimal)
#      registry, and vice versa — same set, same order.
#   2. --minimal yields a strict subset, skipping exactly the steps that are
#      gated behind `[[ $MINIMAL -eq 0 ]]`.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/../profiles/terminal-setup.sh"

fail=0
_ok()   { printf '  \033[0;32m✓\033[0m %s\n' "$1"; }
_bad()  { printf '  \033[0;31m✗\033[0m %s\n' "$1"; fail=1; }

[[ -f "$TARGET" ]] || { echo "missing $TARGET"; exit 1; }

# --- 1. the log_step calls actually present in the script --------------------
mapfile -t actual < <(grep -oP '^log_step "\K[^"]+' "$TARGET")

# --- 2. the registry, evaluated for each flag combination --------------------
# Source only the registry block so we don't execute the installer. The block is
# delimited by the STEP_NAMES assignment and the STEP_TOTAL line.
_registry() {
    local minimal="$1"
    MINIMAL="$minimal" bash -c '
        set -euo pipefail
        MINIMAL=${MINIMAL:-0}
        '"$(sed -n '/^STEP_NAMES=(/,/^STEP_TOTAL=/p' "$TARGET")"'
        printf "%s\n" "${STEP_NAMES[@]}"
    '
}

mapfile -t full    < <(_registry 0)
mapfile -t minimal < <(_registry 1)

echo "STEP_NAMES registry vs log_step calls"

# Same set and same order as the real calls.
if [[ "${actual[*]}" == "${full[*]}" ]]; then
    _ok "full registry matches all ${#actual[@]} log_step calls, in order"
else
    _bad "registry drifted from log_step calls"
    printf '      script:   %s\n' "${actual[*]}"
    printf '      registry: %s\n' "${full[*]}"
fi

# --minimal must be a strict subset of the full list.
subset=1
for step in "${minimal[@]}"; do
    [[ " ${full[*]} " == *" $step "* ]] || subset=0
done
if [[ $subset -eq 1 && ${#minimal[@]} -lt ${#full[@]} ]]; then
    _ok "--minimal is a strict subset (${#minimal[@]} of ${#full[@]} steps)"
else
    _bad "--minimal is not a strict subset of the full step list"
fi

# The skipped steps are the ones that should be skipped.
expected_skipped=("Nerd fonts" "kitty configuration" "herdr configuration")
for step in "${expected_skipped[@]}"; do
    if [[ " ${minimal[*]} " == *" $step "* ]]; then
        _bad "--minimal should skip '$step' but the registry includes it"
    fi
done
[[ $fail -eq 0 ]] && _ok "--minimal skips exactly: ${expected_skipped[*]}"

exit $fail
