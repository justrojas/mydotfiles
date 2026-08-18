#!/usr/bin/env bash
# Fixture: run terminal-setup twice, snapshotting state between runs.
#
# The assertions in tests/test-idempotency.sh compare the two snapshots. This
# has to be a fixture rather than part of the assertion script because the
# runner's contract is "install once, then assert" — the second install and the
# snapshots either side of it are the thing under test.
#
# Why this exists: nearly every hard-won comment in this repo describes
# something that came back, got overwritten, or got backed up again on a
# re-run. safe_symlink backs up whatever it replaces, so a profile that is not
# idempotent quietly accumulates .bak.<timestamp> copies and rewrites state
# every single time it runs. Nothing tested that before.

set -uo pipefail

REPO="${REPO:-$HOME/my-dotfiles}"
OUT="${OUT:-/tmp/idem}"
mkdir -p "$OUT"

# Capture the things a non-idempotent run would disturb.
snapshot() {
    local dest="$1"

    # 1. Backup files. A second run should create ZERO new ones: everything it
    #    would replace is already the symlink it wants.
    find "$HOME" -maxdepth 4 -name '*.bak.*' -not -path "$REPO/*" 2>/dev/null \
        | sort > "$dest.baks"

    # 2. Where every managed symlink points.
    {
        for p in "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.zshrc" \
                 "$HOME/.tmux.conf" "$HOME/.config/tmux" "$HOME/.config/kitty" \
                 "$HOME/.config/herdr/config.toml" "$HOME/.config/shell/preferred" \
                 "$HOME/.config/oh-my-posh/current.omp.json"; do
            if [[ -L "$p" ]]; then
                echo "$p -> $(readlink "$p")"
            elif [[ -e "$p" ]]; then
                echo "$p [regular] $(md5sum < "$p" 2>/dev/null | cut -d' ' -f1)"
            else
                echo "$p [absent]"
            fi
        done
    } | sort > "$dest.links"

    # 3. The repo itself must never be dirtied by running an installer.
    git -C "$REPO" status --porcelain 2>/dev/null | sort > "$dest.git"

    # 4. Everything symlinked onto PATH.
    find "$HOME/.local/bin" -maxdepth 1 2>/dev/null | sort > "$dest.bin"
}

echo "--- idempotency: baseline (before any run) ---"
# Snapshot BEFORE the first run. The repo is COPY'd into the image from the
# host working tree, so it may already contain untracked or modified files
# that have nothing to do with the installer. Asserting "git status is empty"
# would therefore fail for reasons entirely outside the test. What matters is
# whether running the installer *adds* anything.
snapshot "$OUT/snap0"

echo "--- idempotency: first run ---"
bash "$REPO/profiles/terminal-setup.sh" --non-interactive >"$OUT/run1.log" 2>&1
echo "first run exit=$?"
snapshot "$OUT/snap1"

echo "--- idempotency: second run ---"
bash "$REPO/profiles/terminal-setup.sh" --non-interactive >"$OUT/run2.log" 2>&1
echo "second run exit=$?"
snapshot "$OUT/snap2"

echo "snapshots written to $OUT"
