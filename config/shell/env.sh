# Shell-agnostic environment — sourced by BOTH .zshrc and .bashrc.
# Keep everything here POSIX-compatible (no zsh/bash-only syntax).
#
# This file MUST be safe to source from a script running under
# `set -euo pipefail`. The install profiles and the test suites both do so to
# get the canonical PATH. That imposes two rules:
#
#   1. Every variable that may be unset is referenced as ${VAR:-} — a bare
#      "$TMUX" aborts instantly under `set -u`.
#   2. No bare `[ ... ] && cmd` at top level — when the test is false the
#      whole statement returns 1, which aborts under `set -e`. Use if/fi.
#
# Violating either produced a failure mode with NO output at all: the sourcing
# script simply exited 1 before printing anything.

export EDITOR=nvim
export GOPATH="$HOME/go"
export NVM_DIR="$HOME/.nvm"
export FZF_BASE="$HOME/.fzf"
export BUN_INSTALL="$HOME/.bun"

# --- PATH -------------------------------------------------------------------
# Prepend only if the dir exists and isn't already on PATH (idempotent).
_prepend_path() {
    case ":$PATH:" in
        *":$1:"*) ;;                       # already present
        *) if [ -d "$1" ]; then PATH="$1:$PATH"; fi ;;
    esac
}
_prepend_path "$HOME/.local/bin"
_prepend_path "$HOME/.opencode/bin"
_prepend_path "/usr/local/go/bin"
_prepend_path "$GOPATH/bin"
_prepend_path "$BUN_INSTALL/bin"
# fzf installs itself by git-cloning to ~/.fzf, with the binaries in ~/.fzf/bin.
# zsh used to get this for free via the oh-my-zsh `fzf` plugin; bash has no
# equivalent, so it must be on PATH explicitly or `fzf` is simply missing.
_prepend_path "$FZF_BASE/bin"
export PATH
unset -f _prepend_path

# --- Terminal identity ------------------------------------------------------
# oh-my-posh renders themes based on TERM_PROGRAM, which multiplexers
# (tmux / herdr) do not always pass through. Restore it to kitty.
if [ -n "${TMUX:-}" ]; then
    export TERM_PROGRAM="kitty"
fi
export TERM_PROGRAM="${TERM_PROGRAM:-kitty}"

# --- TERM sanity ------------------------------------------------------------
# kitty sets TERM=xterm-kitty, but that terminfo entry only exists where kitty
# (or the kitty-terminfo package) has been installed. On a machine that never
# had it — a fresh box, a VM, or the far side of an ssh hop — every curses app
# gets a broken/absent capability set. The classic symptom is duplicated
# keypresses and doubled backspaces in full-screen TUIs like herdr, because the
# app falls back to guessing key sequences.
#
# If the entry can't be resolved, downgrade to a universally-present superset
# rather than leaving TERM pointing at nothing.
if [ -n "${TERM:-}" ] && command -v infocmp >/dev/null 2>&1; then
    if ! infocmp "$TERM" >/dev/null 2>&1; then
        case "$TERM" in
            *-kitty|*-256color|*-direct)
                if infocmp xterm-256color >/dev/null 2>&1; then
                    export TERM=xterm-256color
                else
                    export TERM=xterm
                fi
                ;;
            *)
                export TERM=xterm
                ;;
        esac
    fi
fi

