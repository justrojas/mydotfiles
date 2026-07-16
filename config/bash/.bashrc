# ~/.bashrc — interactive bash configuration.
# Rich pieces live in $DOTFILES/config/shell/*.sh (shared with zsh).
# Bash is kept lean since it exists mainly for work tooling that assumes bash.

# Interactive shells only.
case $- in *i*) ;; *) return;; esac

# --- Resolve dotfiles root from this file's (symlinked) location -----------
export DOTFILES="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"/../.. && pwd)"

# --- Shell preference / bash<->zsh toggle (may exec away) -------------------
source "$DOTFILES/config/shell/switch.sh"

# --- History ----------------------------------------------------------------
export HISTSIZE=10000
export HISTFILESIZE=10000
export HISTCONTROL=ignoreboth
shopt -s histappend checkwinsize

# --- Shared environment + aliases ------------------------------------------
source "$DOTFILES/config/shell/env.sh"
source "$DOTFILES/config/shell/aliases.sh"

# --- Work-specific (untracked) ---------------------------------------------
[ -f ~/.bashrc.work ] && source ~/.bashrc.work

# --- Completion -------------------------------------------------------------
if ! shopt -oq posix; then
    if [ -f /usr/share/bash-completion/bash_completion ]; then
        . /usr/share/bash-completion/bash_completion
    elif [ -f /etc/bash_completion ]; then
        . /etc/bash_completion
    fi
fi

# --- Lazy-loaded node/npm/npx (nvm is slow to source eagerly) --------------
load_nvm() {
    [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"
}
for _c in node npm npx; do
    eval "$_c() { unset -f node npm npx 2>/dev/null; load_nvm; $_c \"\$@\"; }"
done
unset _c

# --- Tools ------------------------------------------------------------------
if command -v zoxide >/dev/null 2>&1; then
    eval "$(zoxide init bash --cmd cd)"
fi

# --- Prompt (oh-my-posh) ----------------------------------------------------
if command -v oh-my-posh >/dev/null 2>&1; then
    OMP_CONFIG="$HOME/.config/oh-my-posh/current.omp.json"
    [ ! -f "$OMP_CONFIG" ] && OMP_CONFIG="$DOTFILES/config/zsh/oh-my-posh.omp.json"
    [ ! -f "$OMP_CONFIG" ] && OMP_CONFIG="$HOME/.cache/oh-my-posh/themes/catppuccin_mocha.omp.json"
    eval "$(oh-my-posh init bash --config "$OMP_CONFIG")"
fi

# --- Local extras (untracked) ----------------------------------------------
[ -f ~/.env ] && source ~/.env
