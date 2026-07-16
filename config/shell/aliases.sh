# Shell-agnostic aliases — sourced by BOTH .zshrc and .bashrc.

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
