# ZSHRC Configuration - Clean & Efficient
# ============================================================================
# Powerlevel10k instant prompt
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi
# ============================================================================
# ENVIRONMENT VARIABLES
# ============================================================================
export ZSH="$HOME/.oh-my-zsh"
export EDITOR=nvim
export BDAI="$HOME/bdai"
export GOPATH=$HOME/go
export ROS_DOMAIN_ID=30
export NVM_DIR="$HOME/.nvm"
# History configuration
export HISTSIZE=10000
export SAVEHIST=10000
export HISTFILE=~/.zsh_history
# PATH configuration
typeset -U path  # Keep unique entries
path=(
  $HOME/.local/bin
  /usr/local/go/bin
  $GOPATH/bin
  $HOME/.nvm/versions/node/v18.20.6/bin  # Claude Code / npm global binaries
  $path
)
# ============================================================================
# WORK-SPECIFIC CONFIGURATION
# ============================================================================
# Load work-specific configuration and sensitive tokens (not tracked in git)
[[ -f ~/.zshrc.work ]] && source ~/.zshrc.work
# ============================================================================
# OH MY ZSH CONFIGURATION
# ============================================================================
ZSH_THEME="powerlevel10k/powerlevel10k"
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
alias fcd='fuzzycd'
alias gpu='__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia glmark2'
# Tmux
alias tls='tmux ls'
alias tkill='tmux kill-session -t'
# ============================================================================
# FUNCTIONS
# ============================================================================
# Fuzzy directory navigation
fuzzycd() {
  local file=$(find . -type f | fzf --query="$1" +m)
  [[ -n "$file" ]] && cd "$(dirname "$file")"
}
# BDAI navigation
bdcd() { cd "$(bdai cd "$@")" }
# Kubernetes workflow management
remove_flow() { kubectl delete workflowtemplate $1 -n team-dc }
remove_pod() { kubectl delete pod $1 -n team-dc }
trigger_flow() {
  if [[ "$2" == "-h" ]]; then
    kubectl get workflowtemplate $1 -n team-dc -o jsonpath='{.metadata.annotations.metaflow\/parameters}' | \
    jq -r 'to_entries | .[] | "\n  --\(.key)\n    Description: \(.value.description)\n    Default: \(.value.value)\n    Type: \(.value.type)"'
  else
    argo submit --from workflowtemplate/$1 -n team-dc "${@:2}"
  fi
}
# GCP authentication (lazy-loaded)
lazy_gcp_auth() {
  export ARTIFACT_REGISTRY_TOKEN=$(gcloud auth application-default print-access-token)
  export UV_EXTRA_INDEX_URL="https://oauth2accesstoken:$ARTIFACT_REGISTRY_TOKEN@us-python.pkg.dev/engineering-380817/bdai-pip/simple"
}
alias bdai_auth_gcp='lazy_gcp_auth && gcloud auth login && gcloud auth application-default login'
# ============================================================================
# KEY BINDINGS
# ============================================================================
# Nvim launcher
open_nvim() { nvim . }
zle -N open_nvim
bindkey '^n' open_nvim
# Clear screen
clear_screen() { clear; zle reset-prompt }
zle -N clear_screen
bindkey '^p' clear_screen
# ============================================================================
# LAZY LOADING
# ============================================================================
# NVM lazy loading
load_nvm() {
  [[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"
  [[ -s "$NVM_DIR/bash_completion" ]] && source "$NVM_DIR/bash_completion"
}
# Create lazy aliases for node tools
for cmd in node npm npx; do
  eval "$cmd() { unfunction $cmd; load_nvm; $cmd \"\$@\"; }"
done
# Zoxide initialization - replaces cd command
if command -v zoxide >/dev/null 2>&1; then
  eval "$(zoxide init zsh --cmd cd)"
fi
# Kubectl completion lazy loading
kubectl() {
  if command -v kubectl >/dev/null 2>&1; then
    # Load completion if not cached or outdated
    local completion_file=~/.kube/completion.zsh.inc
    if [[ ! -f "$completion_file" || "$completion_file" -ot $(which kubectl) ]]; then
      kubectl completion zsh > "$completion_file" 2>/dev/null
    fi
    [[ -f "$completion_file" ]] && source "$completion_file"
  fi
  # Replace this function with the real kubectl
  unfunction kubectl
  kubectl "$@"
}
# ============================================================================
# COMPLETION SETUP
# ============================================================================
# Optimized completion initialization
autoload -Uz compinit
if [[ -n ${ZDOTDIR:-$HOME}/.zcompdump(#qNmh+24) ]]; then
  compinit -d "${ZDOTDIR:-$HOME}/.zcompdump"
else
  compinit -C -d "${ZDOTDIR:-$HOME}/.zcompdump"
fi
# Tmux session completion
_tmux_sessions() {
  local sessions
  sessions=(${(f)"$(tmux list-sessions -F '#{session_name}' 2>/dev/null)"})
  _describe 'sessions' sessions
}
compdef _tmux_sessions tkill
# Workflow completion
_flow_completions() {
  local templates
  templates=(${(f)"$(kubectl get workflowtemplates -n team-dc --no-headers -o custom-columns=':metadata.name' 2>/dev/null)"})
  _describe 'templates' templates
}
compdef _flow_completions remove_flow trigger_flow
# ============================================================================
# DEFERRED LOADING
# ============================================================================
# Load additional configurations after shell initialization
deferred_load() {
  # Load docker functions if available
  [[ -f "$HOME/Documents/my-dotfiles/config/shell/docker_functions.bash" ]] && \
    source "$HOME/Documents/my-dotfiles/config/shell/docker_functions.bash"
}
# Schedule deferred loading
if zmodload zsh/sched 2>/dev/null; then
  sched +1 deferred_load
fi
# ============================================================================
# POWERLEVEL10K
# ============================================================================
[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh
