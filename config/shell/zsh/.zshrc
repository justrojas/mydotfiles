# ZSHRC Configuration - PowerLevel10k Clean & Minimal (OPTIMIZED)
# ============================================================================

# Enable Powerlevel10k instant prompt.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# Oh My Zsh Configuration
export ZSH="$HOME/.oh-my-zsh"

# Environment Variables and Exports
export EDITOR=nvim
export BDAI="$HOME/bdai"
export PATH=/home/$USER/.local/bin:$PATH
export PATH=$PATH:/usr/local/go/bin
export GOPATH=$HOME/go
export PATH=$PATH:$GOPATH/bin

# LAZY LOAD: Only set these when needed
function _lazy_gcp_auth() {
  export ARTIFACT_REGISTRY_TOKEN=$(gcloud auth application-default print-access-token)
  export UV_EXTRA_INDEX_URL=https://oauth2accesstoken:$ARTIFACT_REGISTRY_TOKEN@us-python.pkg.dev/engineering-380817/bdai-pip/simple
}

export ROS_DOMAIN_ID=30
export NVM_DIR="$HOME/.nvm"
export HISTSIZE=10000
export SAVEHIST=10000
export HISTFILE=~/.zsh_history

# PowerLevel10k Theme
ZSH_THEME="powerlevel10k/powerlevel10k"

# Plugins
plugins=(
  git
  sudo
  zsh-autosuggestions
  zsh-syntax-highlighting
  fzf
)

# Load Oh My Zsh
source $ZSH/oh-my-zsh.sh

# Shell Options
setopt AUTO_CD
setopt AUTO_PUSHD
setopt PUSHD_IGNORE_DUPS
setopt PUSHD_MINUS

# Aliases
alias  l='eza -lh  --icons=auto'
alias ls='eza --icons=auto'
alias la='eza -lha --icons=auto --sort=name --group-directories-first'
alias ld='eza -lhD --icons=auto'
alias lt='tree -h --du ./'
alias cat='batcat --paging=never'
alias cpr='rsync --recursive --progress'
alias n='nvim'
alias re='glow README.md'
alias fcd=fuzzycd
alias gpu='__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia glmark2'
alias tls='tmux ls'
alias tkill='tmux kill-session -t '
alias claude="/home/jrojas/.claude/local/claude"
alias bdai_auth_gcp='_lazy_gcp_auth && gcloud auth login && gcloud auth application-default login'

# Functions
# =============================================================
function fuzzycd() {
  local file=$(find . -type f | fzf --query="$1" +m)
  if [ -n "$file" ]; then
    cd "$(dirname "$file")" || return
  fi
}

function bdcd() {
  cd "$(bdai cd "$@")"
}

function open_nvim() {
  nvim .
}
zle -N open_nvim

function clear_screen() {
  clear
  zle reset-prompt
}
zle -N clear_screen

function remove_flow() {
  kubectl delete workflowtemplate $1 -n team-dc
}

function trigger_flow() {
  if [[ "$2" == "-h" ]]; then
    kubectl get workflowtemplate $1 -n team-dc -o jsonpath='{.metadata.annotations.metaflow\/parameters}' | \
    jq -r 'to_entries | .[] | "\n  --\(.key)\n    Description: \(.value.description)\n    Default: \(.value.value)\n    Type: \(.value.type)"'
  else
    argo submit --from workflowtemplate/$1 -n team-dc "${@:2}"
  fi
}

function remove_pod() {
    kubectl delete pod $1 -n team-dc
}
# ============================================================================
# Key Bindings
bindkey '^n' open_nvim
bindkey '^p' clear_screen

# LAZY LOAD: Autocompletion
if [[ -n ${ZDOTDIR}/.zcompdump(#qN.mh+24) ]]; then
  compinit
else
  compinit -C
fi

# LAZY LOAD: External Tool Initialization

# NVM - Load only when node/npm is needed
function _load_nvm() {
  [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
  [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
}

# Create lazy-loading aliases for node tools
function node() { _load_nvm; node "$@"; }
function npm() { _load_nvm; npm "$@"; }
function npx() { _load_nvm; npx "$@"; }

# LAZY LOAD: Zoxide
function _load_zoxide() {
  if command -v zoxide >/dev/null 2>&1; then
    eval "$(zoxide init zsh)"
    if [[ $- == *i* ]]; then
      alias cd='z'
    fi
  else
    echo "zoxide not found. Install with 'brew install zoxide' or your package manager."
  fi
}

# Load zoxide on first cd
function cd() {
  unfunction cd  # Remove this function
  _load_zoxide   # Load zoxide
  cd "$@"        # Now call the real cd (or z if zoxide loaded)
}

# LAZY LOAD: Kubectl completion
function _load_kubectl_completion() {
  if command -v kubectl >/dev/null 2>&1; then
    if [[ ! -f ~/.kube/completion.zsh.inc ]] || [[ ~/.kube/completion.zsh.inc -ot $(which kubectl) ]]; then
      kubectl completion zsh > ~/.kube/completion.zsh.inc 2>/dev/null
    fi
    [[ -f ~/.kube/completion.zsh.inc ]] && source ~/.kube/completion.zsh.inc
  fi
}

# Only load kubectl completions when kubectl is used
function kubectl() {
  _load_kubectl_completion
  kubectl "$@"
}

# DEFERRED: Load these after shell is ready
function _deferred_load() {
  # Docker functions (if available)
  [ -f "$HOME/Documents/my-dotfiles/config/shell/docker_functions.bash" ] && \
    source "$HOME/Documents/my-dotfiles/config/shell/docker_functions.bash"

  # Load remaining completions
  function _tmux_sessions() {
      sessions=("${(@f)$(tmux list-sessions -F '#{session_name}')}")
      _wanted sessions expl 'tmux sessions' compadd -a sessions
  }
  compdef _tmux_sessions tkill

  function flow_completions() {
      local curcontext="$curcontext" state line
      typeset -A opt_args
      _arguments -C \
          "1:templates:($(kubectl get workflowtemplates -n team-dc --no-headers -o custom-columns=':metadata.name'))"
  }
  compdef flow_completions remove_flow
  compdef flow_completions trigger_flow
}

# Schedule deferred loading
zmodload zsh/sched
sched +1 _deferred_load

# PowerLevel10k Configuration
# ============================================================================
# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
