#!/usr/bin/env bash
# Assertions: running a profile twice must change nothing the second time.
#
# Paired with tests/fixtures/idempotency-fixture.sh, which does both runs and
# writes the snapshots this compares.

set -uo pipefail

OUT="${OUT:-/tmp/idem}"
GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
PASS=0; FAIL=0
ok()  { echo -e "  ${GREEN}PASS${NC}  $*"; PASS=$((PASS+1)); }
bad() { echo -e "  ${RED}FAIL${NC}  $*"; FAIL=$((FAIL+1)); }

echo "idempotency:"

# --- both runs must succeed ---------------------------------------------------
for n in 1 2; do
    if grep -qE "\[ERROR\]|Script failed" "$OUT/run$n.log" 2>/dev/null; then
        bad "run $n reported an error"
        grep -E "\[ERROR\]|Script failed" "$OUT/run$n.log" | head -3 | sed 's/^/        /'
    else
        ok "run $n completed without errors"
    fi
done

# --- the second run must not back anything up --------------------------------
# This is the sharpest signal. safe_symlink only backs up when it replaces a
# non-symlink, so once the first run has linked everything, a correct second
# run has nothing to back up. New .bak files mean something is being recreated
# as a regular file and re-replaced on every run.
new_baks="$(comm -13 "$OUT/snap1.baks" "$OUT/snap2.baks" 2>/dev/null)"
if [[ -z "$new_baks" ]]; then
    ok "second run created no new .bak files"
else
    bad "second run created $(wc -l <<<"$new_baks") new backup(s):"
    sed 's/^/        /' <<<"$new_baks" | head -6
fi

# --- symlinks must be identical ----------------------------------------------
if diff -q "$OUT/snap1.links" "$OUT/snap2.links" >/dev/null 2>&1; then
    ok "managed symlinks unchanged between runs"
else
    bad "managed symlinks differ between runs:"
    diff "$OUT/snap1.links" "$OUT/snap2.links" | head -8 | sed 's/^/        /'
fi

# --- ~/.local/bin must be stable ---------------------------------------------
if diff -q "$OUT/snap1.bin" "$OUT/snap2.bin" >/dev/null 2>&1; then
    ok "~/.local/bin contents unchanged between runs"
else
    bad "~/.local/bin differs between runs:"
    diff "$OUT/snap1.bin" "$OUT/snap2.bin" | head -8 | sed 's/^/        /'
fi

# --- the installer must never dirty the repo ---------------------------------
# A profile that writes into its own source tree makes `git pull` conflict on
# every machine it has ever run on.
#
# Compared against a baseline taken before the first run, not against "empty":
# the repo is copied into the image from the host working tree, so it can
# arrive with untracked files already present. Only growth is the installer's
# fault.
new_dirt="$(comm -13 "$OUT/snap0.git" "$OUT/snap2.git" 2>/dev/null)"
if [[ -z "$new_dirt" ]]; then
    ok "installer added nothing to the repo working tree"
else
    bad "installer dirtied the repo with $(wc -l <<<"$new_dirt") new entry/entries:"
    sed 's/^/        /' <<<"$new_dirt" | head -6
fi

echo ""
echo "Results: $PASS passed, $FAIL failed"
if [[ $FAIL -eq 0 ]]; then
    echo "All assertions passed."
else
    echo "Some assertions FAILED."
    exit 1
fi
