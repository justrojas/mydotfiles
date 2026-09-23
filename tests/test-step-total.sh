#!/usr/bin/env bash
# =============================================================================
# test-step-total.sh — the STEP_NAMES registry must match the real log_step calls
# =============================================================================
# terminal-setup.sh derives STEP_TOTAL (the X/N progress counter) from the
# STEP_NAMES registry rather than a hand-maintained number. That only holds as
# long as the registry and the actual `log_step "..."` calls agree, so this test
# compares the two directly instead of asserting a magic constant.
#
# The registry is now a function of two flags — --minimal and --shell — so the
# checks cover all four combinations:
#   1. Every name in a registry corresponds to a real log_step call in the file.
#   2. The union of the bash and zsh registries accounts for every log_step call
#      in the file, so a newly added step cannot be missed by both.
#   3. --minimal is a strict subset, skipping exactly the GUI-only steps.
#   4. Exactly one of "bash configuration" / "zsh configuration" is ever present.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$SCRIPT_DIR/../profiles/terminal-setup.sh"

fail=0
_ok()  { printf '  \033[0;32m✓\033[0m %s\n' "$1"; }
_bad() { printf '  \033[0;31m✗\033[0m %s\n' "$1"; fail=1; }

[[ -f "$TARGET" ]] || { echo "missing $TARGET"; exit 1; }

# All log_step calls in the file, regardless of indentation (the zsh step is
# nested inside a `if [[ "$SHELL_CHOICE" == "zsh" ]]` block).
mapfile -t all_calls < <(grep -oP 'log_step "\K[^"]+' "$TARGET" | sort -u)

# Evaluate the registry block for a given flag combination, without running the
# installer: extract just the STEP_NAMES..STEP_TOTAL region and source it.
_registry() {
    MINIMAL="$1" SHELL_CHOICE="$2" bash -c '
        set -euo pipefail
        '"$(sed -n '/^STEP_NAMES=(/,/^STEP_TOTAL=/p' "$TARGET")"'
        printf "%s\n" "${STEP_NAMES[@]}"
    '
}

echo "STEP_NAMES registry vs log_step calls"

declare -A counts
for shell in bash zsh; do
    for minimal in 0 1; do
        mapfile -t reg < <(_registry "$minimal" "$shell")
        counts["$shell/$minimal"]=${#reg[@]}

        # 1. every registry entry is a real log_step call
        for step in "${reg[@]}"; do
            if [[ " ${all_calls[*]} " != *" $step "* ]]; then
                _bad "--shell=$shell MINIMAL=$minimal: '$step' is in the registry but has no log_step call"
            fi
        done

        # 4. exactly one shell-configuration step
        local_shell_steps=0
        for step in "${reg[@]}"; do
            [[ "$step" == "bash configuration" || "$step" == "zsh configuration" ]] \
                && local_shell_steps=$((local_shell_steps + 1))
        done
        if [[ $local_shell_steps -ne 1 ]]; then
            _bad "--shell=$shell MINIMAL=$minimal: expected exactly 1 shell step, found $local_shell_steps"
        fi
        if [[ " ${reg[*]} " != *" $shell configuration "* ]]; then
            _bad "--shell=$shell MINIMAL=$minimal: registry is missing '$shell configuration'"
        fi
    done
done
[[ $fail -eq 0 ]] && _ok "every registry entry maps to a real log_step call (all 4 flag combinations)"
[[ $fail -eq 0 ]] && _ok "exactly one shell-configuration step per combination"

# 2. union of both shells covers every log_step in the file
mapfile -t union < <({ _registry 0 bash; _registry 0 zsh; } | sort -u)
if [[ "${union[*]}" == "${all_calls[*]}" ]]; then
    _ok "bash+zsh registries cover all ${#all_calls[@]} log_step calls"
else
    _bad "registry/log_step mismatch — a step is unreachable or unregistered"
    printf '      in file:     %s\n' "${all_calls[*]}"
    printf '      in registry: %s\n' "${union[*]}"
fi

# 3. --minimal is a strict subset skipping exactly the GUI-only steps
for shell in bash zsh; do
    if [[ ${counts["$shell/1"]} -ge ${counts["$shell/0"]} ]]; then
        _bad "--shell=$shell: --minimal (${counts["$shell/1"]}) should be smaller than full (${counts["$shell/0"]})"
    fi
    mapfile -t min_reg < <(_registry 1 "$shell")
    for step in "Nerd fonts" "kitty configuration" "herdr configuration"; do
        [[ " ${min_reg[*]} " == *" $step "* ]] \
            && _bad "--shell=$shell --minimal should skip '$step'"
    done
done
[[ $fail -eq 0 ]] && _ok "--minimal skips Nerd fonts, kitty and herdr for both shells"

if [[ $fail -eq 0 ]]; then
    printf '  step counts: bash %s/%s, zsh %s/%s (full/minimal)\n' \
        "${counts[bash/0]}" "${counts[bash/1]}" "${counts[zsh/0]}" "${counts[zsh/1]}"
fi

exit $fail
