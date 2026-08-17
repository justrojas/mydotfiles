#!/bin/bash
# Test fixture for the `kde` suite — creates the pre-existing state that
# kde-setup.sh --config-only is supposed to interact with.
#
# Run INSIDE the container, BEFORE kde-setup.sh.
#
# Two things need to exist beforehand, because the behaviour worth testing is
# how the profile treats state that is already there:
#
#   1. A Firefox profile. setup_firefox_chrome resolves the target from
#      profiles.ini and skips entirely when no profile exists, so without this
#      the step would no-op and the suite would prove nothing.
#
#   2. An existing kglobalshortcutsrc containing a sentinel binding that is NOT
#      in the repo's scheme. The import is supposed to MERGE key-by-key, so the
#      sentinel must survive. If it disappears, the import is overwriting the
#      file wholesale and destroying user shortcuts — exactly the failure this
#      assertion exists to catch.

set -euo pipefail

echo "--- fixture: creating Firefox profile ---"
FF_DIR="$HOME/.mozilla/firefox"
PROFILE="testprofile.default-release"
mkdir -p "$FF_DIR/$PROFILE"

cat > "$FF_DIR/profiles.ini" <<EOF
[Install4F96D1932A9F858E]
Default=$PROFILE
Locked=1

[Profile0]
Name=default-release
IsRelative=1
Path=$PROFILE
Default=1

[General]
StartWithLastProfile=1
Version=2
EOF
echo "    created $FF_DIR/$PROFILE"

echo "--- fixture: seeding kglobalshortcutsrc with a sentinel ---"
mkdir -p "$HOME/.config"
cat > "$HOME/.config/kglobalshortcutsrc" <<'EOF'
[SENTINEL_PRESERVED][Global Shortcuts]
some-preexisting-binding=Meta+Shift+Z
EOF
echo "    seeded $HOME/.config/kglobalshortcutsrc"

echo "--- fixture: done ---"
