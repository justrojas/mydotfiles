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

# --- node (nvm's default version, on PATH for CHILD PROCESSES) --------------
#
# .bashrc lazy-loads nvm by defining node/npm/npx as shell FUNCTIONS. Shell
# functions are not inherited by child processes, so that only ever worked for
# a human typing `node` at the prompt. Anything that *spawns* node resolves it
# through PATH and gets whatever is in /usr/bin — on Ubuntu 22.04 that is node
# 12, and every tool with a modern floor fails:
#
#   Formatter 'prettier' error: prettier requires at least version 14 of Node
#
# That error was recurring in conform.log for months while `node --version` in
# the shell reported a perfectly good v18, because the two were resolving
# different binaries.
#
# So put nvm's default version on PATH directly. This is a glob and a string
# compare — it does NOT source nvm.sh, so shell startup stays fast and the lazy
# loading below is untouched.
if [ -d "$NVM_DIR/versions/node" ]; then
    _nvm_want="$(cat "$NVM_DIR/alias/default" 2>/dev/null || echo '')"
    _nvm_bin=""

    case "$_nvm_want" in
        v[0-9]*)
            # A full version, e.g. "v18.20.6".
            if [ -d "$NVM_DIR/versions/node/$_nvm_want/bin" ]; then
                _nvm_bin="$NVM_DIR/versions/node/$_nvm_want/bin"
            fi
            ;;
        [0-9]*)
            # A major line, e.g. "18" — take the highest installed match.
            for _d in "$NVM_DIR/versions/node/v$_nvm_want".*; do
                if [ -d "$_d/bin" ]; then _nvm_bin="$_d/bin"; fi
            done
            ;;
    esac

    # No usable default (unset, or an alias like lts/*): fall back to the
    # newest installed version rather than leaving node 12 in charge.
    if [ -z "$_nvm_bin" ]; then
        for _d in "$NVM_DIR"/versions/node/v*; do
            if [ -d "$_d/bin" ]; then _nvm_bin="$_d/bin"; fi
        done
    fi

    if [ -n "$_nvm_bin" ]; then
        case ":$PATH:" in
            *":$_nvm_bin:"*) ;;
            *) PATH="$_nvm_bin:$PATH" ;;
        esac
    fi
    unset _nvm_want _nvm_bin _d
fi

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

