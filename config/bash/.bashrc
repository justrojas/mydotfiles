# ~/.bashrc — interactive bash configuration.
#
# Bash is the PRIMARY interactive shell for this setup. Shell-agnostic pieces
# live in $DOTFILES/config/shell/*.sh and are shared with zsh, which remains
# fully configured and reachable via `tozsh` / `shell-toggle`.

# Interactive shells only.
case $- in *i*) ;; *) return;; esac

# --- Resolve dotfiles root from this file's (symlinked) location -----------
export DOTFILES="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"/../.. && pwd)"

# NOTE: secrets (API tokens, JWTs, etc.) belong in ~/.env, which is untracked
# and sourced at the bottom of this file. Never hardcode them here.

# --- Shell preference / bash<->zsh toggle (may exec away) -------------------
source "$DOTFILES/config/shell/switch.sh"

# --- History ----------------------------------------------------------------
export HISTSIZE=10000
export HISTFILESIZE=10000
export HISTCONTROL=ignoreboth:erasedups
export HISTIGNORE='ls:la:l:cd:pwd:exit:clear:history'
shopt -s histappend cmdhist
# Flush each command to disk immediately so parallel terminals don't clobber
# each other's history (zsh does this by default; bash needs to be told).
PROMPT_COMMAND="history -a; ${PROMPT_COMMAND:-}"

# --- Shell options (bash equivalents of the zsh setopt line) ----------------
shopt -s checkwinsize    # keep $LINES/$COLUMNS correct after a resize
shopt -s autocd          # `foo/` alone cd's into it        (zsh: AUTO_CD)
shopt -s dirspell cdspell # forgive typos in directory names
shopt -s globstar        # ** recurses
shopt -s no_empty_cmd_completion
# zsh's AUTO_PUSHD: make every cd push onto the dir stack so `popd`/`dirs` work.
if [[ ${BASH_VERSINFO[0]} -ge 4 ]]; then
    cd() { builtin pushd "${@:-$HOME}" >/dev/null || return; }
    back() { builtin popd >/dev/null || return; }
fi

# --- Shared environment + aliases ------------------------------------------
source "$DOTFILES/config/shell/env.sh"
source "$DOTFILES/config/shell/aliases.sh"

# --- Work-specific (untracked) ---------------------------------------------
[ -f ~/.bashrc.work ] && source ~/.bashrc.work

# --- Functions --------------------------------------------------------------
fcd() {  # fuzzy-jump to the directory of a selected file
    local file
    file=$(find . -type f 2>/dev/null | fzf --query="${1:-}" +m) || return
    [ -n "$file" ] && cd "$(dirname "$file")"
}

# --- fzf --------------------------------------------------------------------
# Ctrl-R history search, Ctrl-T file widget, Alt-C dir jump.
if [ -f ~/.fzf/shell/key-bindings.bash ]; then
    source ~/.fzf/shell/key-bindings.bash
    [ -f ~/.fzf/shell/completion.bash ] && source ~/.fzf/shell/completion.bash
elif [ -f /usr/share/doc/fzf/examples/key-bindings.bash ]; then
    source /usr/share/doc/fzf/examples/key-bindings.bash
    [ -f /usr/share/doc/fzf/examples/completion.bash ] && \
        source /usr/share/doc/fzf/examples/completion.bash
fi

# --- Keybindings ------------------------------------------------------------
# readline equivalents of the zsh `zle -N` + `bindkey` widgets.
# \C-x\C-e is left alone (edit-command-line) — we only claim n / g / p.
if [[ $- == *i* ]]; then
    bind -x '"\C-n": nvim .'
    bind -x '"\C-g": opencode'
    bind -x '"\C-p": clear'

    # Prefix-search history with the arrow keys: type `git ch` then Up to walk
    # only through commands starting with that.
    bind '"\e[A": history-search-backward'
    bind '"\e[B": history-search-forward'

    # Completion behaviour.
    #
    # TAB is deliberately left on the DEFAULT `complete` action. Binding it to
    # `menu-complete` (as an earlier version of this file did) replaces bash's
    # normal behaviour with blind cycling: it inserts the first match instead of
    # completing the shared prefix and showing the candidates. With
    # bash-completion loaded that feels like completion is broken.
    #
    # show-all-if-ambiguous: list candidates on the FIRST tab, not the second.
    # menu-complete is still available, just moved off TAB onto Shift-Tab.
    bind 'set completion-ignore-case on'
    bind 'set show-all-if-ambiguous on'
    bind 'set menu-complete-display-prefix on'
    bind 'set colored-stats on'
    bind 'set colored-completion-prefix on'
    bind 'set completion-query-items 200'
    bind 'set page-completions off'
    bind 'set mark-symlinked-directories on'
    bind '"\e[Z": menu-complete'   # Shift-Tab cycles, if you want cycling
fi

# --- Completion -------------------------------------------------------------
if ! shopt -oq posix; then
    if [ -f /usr/share/bash-completion/bash_completion ]; then
        . /usr/share/bash-completion/bash_completion
    elif [ -f /etc/bash_completion ]; then
        . /etc/bash_completion
    fi
fi

# tmux session-name completion for `tkill` (mirrors the zsh compdef).
_tmux_sessions_bash() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    COMPREPLY=($(compgen -W "$(tmux list-sessions -F '#{session_name}' 2>/dev/null)" -- "$cur"))
}
complete -F _tmux_sessions_bash tkill

# --- Lazy loading -----------------------------------------------------------
# nvm: load on first use of node/npm/npx (keeps startup fast).
load_nvm() {
    [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"
}
for _c in node npm npx; do
    eval "$_c() { unset -f node npm npx 2>/dev/null; load_nvm; $_c \"\$@\"; }"
done
unset _c

# kubectl: cache + lazy-load completion on first use.
kubectl() {
    local completion_file="$HOME/.kube/completion.bash.inc"
    if command -v kubectl >/dev/null 2>&1; then
        if [ ! -f "$completion_file" ] || \
           [ "$completion_file" -ot "$(command -v kubectl)" ]; then
            mkdir -p "$HOME/.kube"
            command kubectl completion bash > "$completion_file" 2>/dev/null
        fi
        [ -f "$completion_file" ] && . "$completion_file"
    fi
    unset -f kubectl
    command kubectl "$@"
}

# --- Tools ------------------------------------------------------------------
# zoxide replaces cd entirely. It must come AFTER the autocd/pushd cd() wrapper
# above, otherwise that wrapper would shadow zoxide's.
if command -v zoxide >/dev/null 2>&1; then
    unset -f cd 2>/dev/null
    eval "$(zoxide init bash --cmd cd)"
fi

# Docker helpers (dls, dsh, dkill, drm, ...).
[ -f "$DOTFILES/config/shell/docker_functions.bash" ] && \
    source "$DOTFILES/config/shell/docker_functions.bash"

# --- Prompt (oh-my-posh) ----------------------------------------------------
if command -v oh-my-posh >/dev/null 2>&1; then
    OMP_CONFIG="$HOME/.config/oh-my-posh/current.omp.json"
    [ ! -f "$OMP_CONFIG" ] && OMP_CONFIG="$DOTFILES/config/oh-my-posh/tokyonight_storm.omp.json"
    [ ! -f "$OMP_CONFIG" ] && OMP_CONFIG="$DOTFILES/config/zsh/oh-my-posh.omp.json"
    [ ! -f "$OMP_CONFIG" ] && OMP_CONFIG="$HOME/.cache/oh-my-posh/themes/catppuccin_mocha.omp.json"
    eval "$(oh-my-posh init bash --config "$OMP_CONFIG")"
fi

# --- Local extras (untracked) ----------------------------------------------
[ -f ~/.env ] && source ~/.env

# NOTE: ~/.bun/_bun is a ZSH completion script (`#compdef bun`) — sourcing it
# from bash floods the terminal with "autoload: command not found". Bun has no
# bash completion of its own, so there is deliberately nothing to source here.
