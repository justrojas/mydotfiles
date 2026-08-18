#!/usr/bin/env bash
# Validate the cat art in assets/cats/.
#
# Runs on the host (no Docker needed) — it only reads files.
#
# WHY THIS EXISTS
# ---------------
# Art gets pasted in from the web, and a single stray character is enough to
# wreck it in ways that are invisible in a diff:
#
#   * a CJK or emoji character is DOUBLE-WIDTH, so it silently shifts every
#     column after it — the art looks fine in the editor that produced it and
#     skewed in the terminal
#   * a plain ASCII space among braille padding collapses differently
#   * ragged line lengths mean the art cannot be centred or boxed reliably
#   * a tab renders as anything from 1 to 8 columns
#
# The braille block (U+2800-U+28FF) is entirely single-width, which is exactly
# why it is the right choice here. This asserts we stay inside it.

set -uo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CATS_DIR="$DOTFILES_DIR/assets/cats"

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; NC='\033[0m'
pass=0; fail=0
ok()   { echo -e "  ${GREEN}PASS${NC}  $*"; pass=$((pass + 1)); }
bad()  { echo -e "  ${RED}FAIL${NC}  $*"; fail=$((fail + 1)); }
warn() { echo -e "  ${YELLOW}WARN${NC}  $*"; }

echo "cat art:"

if [[ ! -d "$CATS_DIR" ]]; then
    bad "assets/cats/ is missing"
    exit 1
fi

shopt -s nullglob
art_files=("$CATS_DIR"/*.txt)
if [[ ${#art_files[@]} -eq 0 ]]; then
    bad "no .txt art files found in assets/cats/"
    exit 1
fi
ok "found ${#art_files[@]} art file(s)"

# Max width the art may occupy. 80 is the classic default terminal; anything
# wider wraps and turns a cat into confetti.
MAX_WIDTH="${CAT_MAX_WIDTH:-80}"

for f in "${art_files[@]}"; do
    name="$(basename "$f")"

    report="$(python3 - "$f" "$MAX_WIDTH" <<'PY'
import sys, unicodedata

path, max_width = sys.argv[1], int(sys.argv[2])
raw = open(path, encoding="utf-8").read()
lines = raw.split("\n")
if lines and lines[-1] == "":
    lines.pop()                      # trailing newline is expected

problems, widths = [], []
for i, line in enumerate(lines, 1):
    cols = 0
    for ch in line:
        cp = ord(ch)
        if ch == "\t":
            problems.append(f"line {i}: tab character (renders as 1-8 columns)")
            continue
        ea = unicodedata.east_asian_width(ch)
        if ea in ("W", "F"):
            problems.append(
                f"line {i}: double-width U+{cp:04X} {unicodedata.name(ch, '?')}"
                " — shifts every column after it")
            cols += 2
            continue
        # Allowed: braille block, plus printable ASCII for labels.
        if not (0x2800 <= cp <= 0x28FF or 0x20 <= cp <= 0x7E):
            problems.append(
                f"line {i}: unexpected U+{cp:04X} {unicodedata.name(ch, '?')}")
        cols += 1
    widths.append(cols)

print("HEIGHT", len(lines))
print("WIDTH", max(widths) if widths else 0)
print("RAGGED", "yes" if len(set(widths)) > 1 else "no")
print("OVERWIDE", "yes" if widths and max(widths) > max_width else "no")
for p in problems[:5]:
    print("PROBLEM", p)
PY
)" || { bad "$name: could not be parsed"; continue; }

    height=$(awk '/^HEIGHT/{print $2}' <<<"$report")
    width=$(awk '/^WIDTH/{print $2}' <<<"$report")
    ragged=$(awk '/^RAGGED/{print $2}' <<<"$report")
    overwide=$(awk '/^OVERWIDE/{print $2}' <<<"$report")
    problems=$(grep '^PROBLEM' <<<"$report" | sed 's/^PROBLEM //')

    if [[ -n "$problems" ]]; then
        bad "$name: disallowed characters"
        sed 's/^/          /' <<<"$problems"
    else
        ok "$name: braille+ASCII only (${width}x${height})"
    fi

    [[ "$overwide" == yes ]] && bad "$name: ${width} columns exceeds ${MAX_WIDTH}"

    # Ragged lines are legal but make centring inconsistent, so flag rather
    # than fail: trailing braille-blank padding is often trimmed by editors.
    [[ "$ragged" == yes ]] && warn "$name: lines are not all the same width (centring may drift)"
done

echo ""
echo "Results: $pass passed, $fail failed"
[[ $fail -eq 0 ]] || exit 1
echo "All assertions passed."
