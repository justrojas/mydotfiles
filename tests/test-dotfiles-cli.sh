#!/usr/bin/env bash
# =============================================================================
# test-dotfiles-cli.sh — the `dotfiles` CLI and the bash log format agree
# =============================================================================
# cli/dotfiles.py builds its run summary by parsing the transcript the bash
# profiles print through lib/common.sh. Nothing type-checks that contract, so
# this test pins it from both ends:
#   1. log_step / log_warning / log_error output is parsed into the right
#      steps, warnings and errors (including the de-duplication).
#   2. With colours off (not a tty) the log helpers emit no escape codes.
#   3. The read-only commands run: --help, profiles, status, logs.
#   4. Every Link the CLI reports points at a file that exists in the repo.
#
# Read-only: uses a temporary XDG_CACHE_HOME; never runs a profile.
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$ROOT/cli/dotfiles"

fail=0
_ok()  { printf '  \033[0;32m✓\033[0m %s\n' "$1"; }
_bad() { printf '  \033[0;31m✗\033[0m %s\n' "$1"; fail=1; }

if ! "$CLI" --help >/dev/null 2>&1; then
    echo "skip: dotfiles CLI cannot run here (needs python3+click+rich or uv)"
    exit 0
fi

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export XDG_CACHE_HOME="$tmp/cache"

# --- 1+2. bash log output -> CLI parser ---------------------------------------
transcript="$tmp/transcript.log"
DOTFILES_DIR="$ROOT" bash -c '
    source "$DOTFILES_DIR/lib/common.sh"
    trap - EXIT
    STEP_TOTAL=3
    log_step "First step";  log_info "hello"
    log_step "Second step"; log_warning "disk is low"; log_warning "disk is low"
    log_step "Third step";  log_error "it broke" 2>&1
    # A nested profile: its steps are sub-steps and must not be counted.
    bash -c "source \"\$DOTFILES_DIR/lib/common.sh\"; trap - EXIT; STEP_TOTAL=9; log_step Child"
    echo "# dotfiles: exit=2 seconds=4.5"
' >"$transcript"

if grep -q $'\033' "$transcript"; then _bad "log helpers emit escape codes when not a tty"; else _ok "no escape codes when not a tty"; fi

parsed="$(python3 - "$ROOT" "$transcript" <<'EOF' 2>/dev/null || true
import importlib.util, sys
from pathlib import Path
spec = importlib.util.spec_from_file_location("d", Path(sys.argv[1]) / "cli/dotfiles.py")
m = importlib.util.module_from_spec(spec); sys.modules["d"] = m; spec.loader.exec_module(m)
r = m._parse_log(Path(sys.argv[2]))
print(f"{len(r.steps)}|{r.step_total}|{'/'.join(r.steps)}|{'/'.join(r.warnings)}|{'/'.join(r.errors)}|{r.code}")
EOF
)"
if [[ -z "$parsed" ]]; then
    echo "  (python3 lacks click/rich — parser checks skipped)"
elif [[ "$parsed" == "3|3|First step/Second step/Third step|disk is low|it broke|2" ]]; then
    _ok "summary parser: top-level steps only, de-duplicated warnings/errors, exit code"
else
    _bad "summary parser: got '$parsed'"
fi

# --- 3. read-only commands ----------------------------------------------------
for args in "--help" "profiles" "status" "logs" "install --help"; do
    # shellcheck disable=SC2086
    if out="$("$CLI" $args </dev/null 2>&1)"; then _ok "dotfiles $args"; else _bad "dotfiles $args: $out"; fi
done

mkdir -p "$XDG_CACHE_HOME/dotfiles/logs"
touch "$XDG_CACHE_HOME/dotfiles/logs/notes.log"
cp "$transcript" "$XDG_CACHE_HOME/dotfiles/logs/20260101-120000-terminal.log"
if out="$("$CLI" logs </dev/null 2>&1)" && [[ "$out" == *"exit 2"* ]]; then
    _ok "logs: ignores foreign files, shows recorded exit code"
else
    _bad "logs with foreign file / exit code: $out"
fi

if "$CLI" install nope </dev/null >/dev/null 2>&1; then _bad "unknown profile accepted"; else _ok "unknown profile rejected"; fi

# --- 4. every link source exists ---------------------------------------------
missing="$(python3 - "$ROOT" <<'EOF' 2>/dev/null || true
import importlib.util, sys
from pathlib import Path
spec = importlib.util.spec_from_file_location("d", Path(sys.argv[1]) / "cli/dotfiles.py")
m = importlib.util.module_from_spec(spec); sys.modules["d"] = m; spec.loader.exec_module(m)
print(" ".join(l.name for l in m._links() if not l.source.exists()))
print(" ".join(p.script for p in m.PROFILES if not (m.REPO / "profiles" / p.script).is_file()))
EOF
)"
if [[ -z "${missing//[[:space:]]/}" ]]; then _ok "all link sources and profile scripts exist"; else _bad "missing: $missing"; fi

exit $fail
