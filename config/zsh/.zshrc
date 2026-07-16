# ~/.zshrc — interactive zsh configuration.
# Shell-agnostic pieces live in $DOTFILES/config/shell/*.sh (shared with bash).

# --- Resolve dotfiles root from this file's (symlinked) location -----------
export DOTFILES="$(cd "$(dirname "$(readlink -f "${(%):-%x}")")"/../.. && pwd)"

# --- Shell preference / bash<->zsh toggle (may exec away) -------------------
source "$DOTFILES/config/shell/switch.sh"

# --- History ----------------------------------------------------------------
export HISTSIZE=10000
export SAVEHIST=10000
export HISTFILE="$HOME/.zsh_history"

# --- Shared environment + aliases ------------------------------------------
export ZSH="$HOME/.oh-my-zsh"
typeset -U path
source "$DOTFILES/config/shell/env.sh"
source "$DOTFILES/config/shell/aliases.sh"

# --- Work-specific (untracked) ---------------------------------------------
[[ -f ~/.zshrc.work ]] && source ~/.zshrc.work

# --- Oh My Zsh --------------------------------------------------------------
ZSH_THEME=""   # prompt handled by oh-my-posh below
plugins=(git sudo zsh-autosuggestions zsh-syntax-highlighting fzf)
source "$ZSH/oh-my-zsh.sh"

# --- Options ----------------------------------------------------------------
setopt AUTO_CD AUTO_PUSHD PUSHD_IGNORE_DUPS PUSHD_MINUS

# --- Functions --------------------------------------------------------------
fcd() {  # fuzzy-jump to the directory of a selected file
    local file
    file=$(find . -type f | fzf --query="$1" +m)
    [[ -n "$file" ]] && cd "$(dirname "$file")"
}

# --- Keybindings ------------------------------------------------------------
open_nvim()     { nvim . }
open_opencode() { opencode }
clear_screen()  { clear; zle reset-prompt }
zle -N open_nvim
zle -N open_opencode
zle -N clear_screen
bindkey '^n' open_nvim
bindkey '^g' open_opencode
bindkey '^p' clear_screen

# --- Lazy loading -----------------------------------------------------------
# nvm: load on first use of node/npm/npx (keeps startup fast).
load_nvm() {
    [[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"
    [[ -s "$NVM_DIR/bash_completion" ]] && source "$NVM_DIR/bash_completion"
}
for cmd in node npm npx; do
    eval "$cmd() { unfunction node npm npx 2>/dev/null; load_nvm; $cmd \"\$@\"; }"
done

# kubectl: cache + lazy-load completion on first use.
kubectl() {
    if command -v kubectl >/dev/null 2>&1; then
        local completion_file="$HOME/.kube/completion.zsh.inc"
        if [[ ! -f "$completion_file" || "$completion_file" -ot $(command -v kubectl) ]]; then
            mkdir -p "$HOME/.kube"
            command kubectl completion zsh > "$completion_file" 2>/dev/null
        fi
        [[ -f "$completion_file" ]] && source "$completion_file"
    fi
    unfunction kubectl
    command kubectl "$@"
}

# zoxide: smarter cd.
if command -v zoxide >/dev/null 2>&1; then
    eval "$(zoxide init zsh --cmd cd)"
fi

# --- Completion -------------------------------------------------------------
fpath+=~/.zfunc
autoload -Uz compinit
if [[ -n ${ZDOTDIR:-$HOME}/.zcompdump(#qNmh+24) ]]; then
    compinit -d "${ZDOTDIR:-$HOME}/.zcompdump"
else
    compinit -C -d "${ZDOTDIR:-$HOME}/.zcompdump"
fi
zstyle ':completion:*' menu select

# tmux session-name completion for `tkill`.
_tmux_sessions() {
    local sessions
    sessions=(${(f)"$(tmux list-sessions -F '#{session_name}' 2>/dev/null)"})
    _describe 'sessions' sessions
}
compdef _tmux_sessions tkill

# --- Deferred loading -------------------------------------------------------
deferred_load() {
    [[ -f "$DOTFILES/config/zsh/docker_functions.bash" ]] && \
        source "$DOTFILES/config/zsh/docker_functions.bash"
}
zmodload zsh/sched 2>/dev/null && sched +1 deferred_load

# --- Prompt (oh-my-posh) ----------------------------------------------------
if command -v oh-my-posh >/dev/null 2>&1; then
    OMP_CONFIG="$HOME/.config/oh-my-posh/current.omp.json"
    [[ ! -f "$OMP_CONFIG" ]] && OMP_CONFIG="$DOTFILES/config/zsh/oh-my-posh.omp.json"
    [[ ! -f "$OMP_CONFIG" ]] && OMP_CONFIG="$HOME/.cache/oh-my-posh/themes/catppuccin_mocha.omp.json"
    eval "$(oh-my-posh init zsh --config "$OMP_CONFIG")"
fi

# --- Local extras (untracked) ----------------------------------------------
[[ -f ~/.env ]] && source ~/.env
[[ -s "$HOME/.bun/_bun" ]] && source "$HOME/.bun/_bun"
