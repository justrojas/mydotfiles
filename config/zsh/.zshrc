# ZSHRC Configuration
# ============================================================================
# ENVIRONMENT VARIABLES
# ============================================================================
export ZSH="$HOME/.oh-my-zsh"
export EDITOR=nvim
export GOPATH=$HOME/go
export NVM_DIR="$HOME/.nvm"
export DOTFILES="$HOME/Documents/my-dotfiles"
# History
export HISTSIZE=10000
export SAVEHIST=10000
export HISTFILE=~/.zsh_history
# PATH
typeset -U path
path=(
  $HOME/.local/bin
  $HOME/.opencode/bin
  /usr/local/go/bin
  $GOPATH/bin
  $path
)
# ============================================================================
# WORK-SPECIFIC CONFIGURATION
# ============================================================================
# Load work-specific config and tokens (not tracked in git)
[[ -f ~/.zshrc.work ]] && source ~/.zshrc.work
# ============================================================================
# OH MY ZSH CONFIGURATION
# ============================================================================
ZSH_THEME=""  # Managed by oh-my-posh
plugins=(git sudo zsh-autosuggestions zsh-syntax-highlighting fzf)
source $ZSH/oh-my-zsh.sh
# ============================================================================
# SHELL OPTIONS
# ============================================================================
setopt AUTO_CD AUTO_PUSHD PUSHD_IGNORE_DUPS PUSHD_MINUS
# ============================================================================
# ALIASES
# ============================================================================
# File listing (eza)
alias l='eza -lh --icons=auto'
alias ls='eza --icons=auto'
alias la='eza -lha --icons=auto --sort=name --group-directories-first'
alias ld='eza -lhD --icons=auto'
# Utilities
alias lt='tree -h --du ./'
alias cat='batcat --paging=never'
alias cpr='rsync --recursive --progress'
alias n='nvim'
alias re='glow README.md'
alias gpu='__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia glmark2'
# Tmux
alias tls='tmux ls'
alias tkill='tmux kill-session -t'
# ============================================================================
# FUNCTIONS
# ============================================================================
# Fuzzy file navigation - jump to directory of selected file
fcd() {
  local file=$(find . -type f | fzf --query="$1" +m)
  [[ -n "$file" ]] && cd "$(dirname "$file")"
}
# ============================================================================
# KEY BINDINGS
# ============================================================================
# Nvim launcher
open_nvim() { nvim . }
zle -N open_nvim
bindkey '^n' open_nvim
# Opencode launcher
open_opencode() { opencode }
zle -N open_opencode
bindkey '^g' open_opencode
# Clear screen
clear_screen() { clear; zle reset-prompt }
zle -N clear_screen
bindkey '^p' clear_screen
# ============================================================================
# LAZY LOADING
# ============================================================================
# NVM - load on first use
load_nvm() {
  [[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"
  [[ -s "$NVM_DIR/bash_completion" ]] && source "$NVM_DIR/bash_completion"
}
for cmd in node npm npx; do
  eval "$cmd() { unfunction $cmd; load_nvm; $cmd \"\$@\"; }"
done
# Zoxide - smarter cd
if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init zsh --cmd cd)"
fi
# Kubectl completion - cached and lazy loaded
kubectl() {
  if command -v kubectl >/dev/null 2>&1; then
    local completion_file=~/.kube/completion.zsh.inc
    if [[ ! -f "$completion_file" || "$completion_file" -ot $(which kubectl) ]]; then
      kubectl completion zsh > "$completion_file" 2>/dev/null
    fi
    [[ -f "$completion_file" ]] && source "$completion_file"
  fi
  unfunction kubectl
  kubectl "$@"
}
# ============================================================================
# COMPLETION SETUP
# ============================================================================
fpath+=~/.zfunc
autoload -Uz compinit
if [[ -n ${ZDOTDIR:-$HOME}/.zcompdump(#qNmh+24) ]]; then
  compinit -d "${ZDOTDIR:-$HOME}/.zcompdump"
else
  compinit -C -d "${ZDOTDIR:-$HOME}/.zcompdump"
fi
zstyle ':completion:*' menu select
# Tmux session completion
_tmux_sessions() {
  local sessions
  sessions=(${(f)"$(tmux list-sessions -F '#{session_name}' 2>/dev/null)"})
  _describe 'sessions' sessions
}
compdef _tmux_sessions tkill
# ============================================================================
# DEFERRED LOADING
# ============================================================================
deferred_load() {
  [[ -f "$DOTFILES/config/zsh/docker_functions.bash" ]] && \
    source "$DOTFILES/config/zsh/docker_functions.bash"
}
if zmodload zsh/sched 2>/dev/null; then
  sched +1 deferred_load
fi
# ============================================================================
# OH-MY-POSH
# ============================================================================
if command -v oh-my-posh >/dev/null 2>&1; then
  OMP_CONFIG="${DOTFILES}/config/zsh/oh-my-posh.omp.json"
  [[ ! -f "$OMP_CONFIG" ]] && OMP_CONFIG="${HOME}/.cache/oh-my-posh/themes/catppuccin_mocha.omp.json"
  eval "$(oh-my-posh init zsh --config "$OMP_CONFIG")"
fi

[ -f ~/.env ] && source ~/.env
