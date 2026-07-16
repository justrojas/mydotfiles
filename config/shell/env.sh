# Shell-agnostic environment — sourced by BOTH .zshrc and .bashrc.
# Keep everything here POSIX-compatible (no zsh/bash-only syntax).

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
        *) [ -d "$1" ] && PATH="$1:$PATH" ;;
    esac
}
_prepend_path "$HOME/.local/bin"
_prepend_path "$HOME/.opencode/bin"
_prepend_path "/usr/local/go/bin"
_prepend_path "$GOPATH/bin"
_prepend_path "$BUN_INSTALL/bin"
export PATH
unset -f _prepend_path

# --- Terminal identity ------------------------------------------------------
# oh-my-posh renders themes based on TERM_PROGRAM, which multiplexers
# (tmux / herdr) do not always pass through. Restore it to kitty.
[ -n "$TMUX" ] && export TERM_PROGRAM="kitty"
export TERM_PROGRAM="${TERM_PROGRAM:-kitty}"
