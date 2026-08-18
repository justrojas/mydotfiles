#!/usr/bin/env bash
# shell-doctor — explain why you landed in the shell you did.
#
# There are five independent places that decide which shell a new terminal
# runs, and they can disagree silently. When they do, the symptom ("my terminal
# opens zsh") looks nothing like the cause. This prints all of them at once.
#
#   1. /etc/passwd login shell        — used by anything non-interactive
#   2. ~/.config/shell/preferred      — switch.sh redirects interactive shells
#   3. kitty's `shell` directive      — overrides the login shell for kitty
#   4. herdr's default_shell          — overrides it for herdr panes
#   5. $SHELL in the running process  — inherited, may be stale
#
# Usage: shell-doctor.sh

set -uo pipefail

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
ok()   { printf "  ${GREEN}%-22s${NC} %s\n" "$1" "$2"; }
bad()  { printf "  ${RED}%-22s${NC} %s\n" "$1" "$2"; }
warn() { printf "  ${YELLOW}%-22s${NC} %s\n" "$1" "$2"; }
info() { printf "  ${BLUE}%-22s${NC} %s\n" "$1" "$2"; }

problems=0

# $USER is not guaranteed to be exported — it is set by login shells, so a
# non-login context (a container exec, a systemd unit, sudo without -i) can
# leave it unset, which is fatal under `set -u`. Derive it instead.
user_name="${USER:-$(id -un)}"

echo ""
echo "shell-doctor"
echo "============"
echo ""

# --- 1. login shell ---------------------------------------------------------
login_shell="$(getent passwd "$user_name" 2>/dev/null | cut -d: -f7)"
pref_file="${XDG_CONFIG_HOME:-$HOME/.config}/shell/preferred"
preferred="$(cat "$pref_file" 2>/dev/null || echo '')"

echo "Decision sources:"
if [[ -n "$preferred" ]]; then
    if [[ "$preferred" == "bash" ]]; then
        ok "preferred" "$preferred   ($pref_file)"
    else
        # This is the usual cause of "the switcher forces me into zsh": every
        # interactive bash session execs into the preferred shell, so bash
        # appears impossible to use even though it is installed and configured.
        warn "preferred" "$preferred   — interactive bash will exec into $preferred"
        info "" "make bash primary:  echo bash > $pref_file"
        info "" "one-off, unchanged: tobash"
        problems=$((problems + 1))
    fi
else
    bad "preferred" "unset — interactive shells will NOT be redirected"
    problems=$((problems + 1))
fi

if [[ -n "$preferred" && "$(basename "$login_shell")" == "$preferred" ]]; then
    ok "login shell" "$login_shell"
else
    warn "login shell" "$login_shell   (differs from preference)"
    problems=$((problems + 1))
fi

info "\$SHELL (inherited)" "${SHELL:-<unset>}"
if [[ -n "$login_shell" && "${SHELL:-}" != "$login_shell" ]]; then
    warn "" "\$SHELL disagrees with /etc/passwd — this process predates a chsh"
fi

# --- 2. kitty ---------------------------------------------------------------
echo ""
echo "kitty:"
kitty_dir="${KITTY_CONFIG_DIRECTORY:-$HOME/.config/kitty}"
[[ -n "${KITTY_CONFIG_DIRECTORY:-}" ]] && warn "KITTY_CONFIG_DIRECTORY" "$KITTY_CONFIG_DIRECTORY (overrides the default!)"

if [[ -L "$HOME/.config/kitty" ]]; then
    ok "config dir" "symlink -> $(readlink "$HOME/.config/kitty")"
elif [[ -d "$HOME/.config/kitty" ]]; then
    bad "config dir" "real directory, NOT symlinked to the repo"
    warn "" "kitty generated its own config; re-run terminal-setup.sh"
    problems=$((problems + 1))
else
    warn "config dir" "missing"
fi

if [[ -r "$kitty_dir/kitty.conf" ]]; then
    kshell="$(grep -E '^shell +' "$kitty_dir/kitty.conf" 2>/dev/null | tail -1 | awk '{print $2}')"
    if [[ -n "$kshell" ]]; then
        ok "shell directive" "$kshell"
    else
        warn "shell directive" "absent — kitty falls back to the login shell ($login_shell)"
        [[ "$(basename "$login_shell")" != "${preferred:-}" ]] && problems=$((problems + 1))
    fi
else
    warn "kitty.conf" "not readable at $kitty_dir/kitty.conf"
fi

# kitty version + which binary a GUI launcher would actually start.
#
# apt ships 0.21.2 on Ubuntu 22.04, whose Kitty-keyboard-protocol bug
# double-fires Enter/Tab/Backspace inside herdr. The shell may resolve kitty to
# the pinned build in ~/.local/bin while the desktop entry still launches
# /usr/bin/kitty, because Exec=kitty is resolved against the session PATH — so
# checking `kitty --version` alone is not enough.
if dpkg -l kitty 2>/dev/null | grep -q '^ii'; then
    bad "apt kitty" "INSTALLED — /usr/bin/kitty is the buggy 0.21.2"
    warn "" "the app menu can launch it even when your shell finds the newer one"
    warn "" "fix: sudo apt-get purge -y kitty"
    problems=$((problems + 1))
else
    ok "apt kitty" "not installed"
fi

if command -v kitty >/dev/null 2>&1; then
    kver="$(kitty --version 2>/dev/null | awk '{print $2}')"
    kpath="$(command -v kitty)"
    # 0.33.0 is the first release without the double-keypress bug.
    if [[ -n "$kver" ]] && printf '%s\n0.33.0\n' "$kver" | sort -V | head -1 | grep -qx "0.33.0"; then
        ok "kitty on PATH" "$kver  ($kpath)"
    else
        bad "kitty on PATH" "$kver  ($kpath) — older than 0.33.0, doubles keypresses in herdr"
        problems=$((problems + 1))
    fi
fi

# --- 3. herdr ---------------------------------------------------------------
echo ""
echo "herdr:"
herdr_cfg="$HOME/.config/herdr/config.toml"
if [[ -L "$herdr_cfg" ]]; then
    ok "config" "symlink -> $(readlink "$herdr_cfg")"
elif [[ -f "$herdr_cfg" ]]; then
    bad "config" "real file, NOT symlinked to the repo"
    warn "" "herdr writes its own config on first run, seeding default_shell"
    warn "" "from \$SHELL at that moment; re-run terminal-setup.sh"
    problems=$((problems + 1))
else
    info "config" "absent (herdr not configured here)"
fi

if [[ -r "$herdr_cfg" ]]; then
    hshell="$(grep -oP 'default_shell\s*=\s*"\K[^"]+' "$herdr_cfg" 2>/dev/null || true)"
    if [[ -n "$hshell" ]]; then
        if [[ -n "$preferred" && "$(basename "$hshell")" == "$preferred" ]]; then
            ok "default_shell" "$hshell"
        else
            bad "default_shell" "$hshell   (every herdr pane will use this)"
            problems=$((problems + 1))
        fi
    else
        info "default_shell" "unset — herdr uses the login shell"
    fi
fi

# --- 4. what is actually running -------------------------------------------
echo ""
echo "Reality check:"
this_shell="$(ps -o comm= -p $$ 2>/dev/null)"
info "this script's shell" "$this_shell"

parent="$(ps -o ppid= -p $$ 2>/dev/null | tr -d ' ')"
[[ -n "$parent" ]] && info "launched by" "$(ps -o comm= -p "$parent" 2>/dev/null) (pid $parent)"

# Does an interactive shell actually redirect? This is the end-to-end test:
# everything above is configuration, this is behaviour.
if command -v zsh >/dev/null 2>&1 && [[ "${preferred:-}" == "bash" ]]; then
    survivor="$(echo 'ps -o comm= -p $$' | timeout 15 zsh -i 2>/dev/null | tail -1 | tr -d ' ')"
    if [[ "$survivor" == "bash" ]]; then
        ok "zsh -i redirects to" "bash"
    else
        bad "zsh -i redirects to" "${survivor:-<nothing>} — switch.sh is not firing"
        problems=$((problems + 1))
    fi
fi

echo ""
if [[ $problems -eq 0 ]]; then
    printf "${GREEN}No problems found.${NC}\n"
else
    printf "${YELLOW}%d issue(s) above.${NC} Most are fixed by:\n" "$problems"
    echo "    bash profiles/terminal-setup.sh --non-interactive"
    echo "    sudo chsh -s \$(command -v ${preferred:-bash}) $user_name"
    echo "  Then open a NEW terminal — running shells keep the shell they started with."
fi
echo ""
