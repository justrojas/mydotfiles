# Shell-agnostic aliases — sourced by BOTH .zshrc and .bashrc.
#
# Every alias that depends on a non-coreutils binary is guarded, so a minimal
# box (VM profile, fresh container, rescue shell) degrades to the stock tool
# instead of erroring out on every invocation.

# --- File listing (eza, fallback to ls) -------------------------------------
if command -v eza >/dev/null 2>&1; then
    alias l='eza -lh --icons=auto'
    alias ls='eza --icons=auto'
    alias la='eza -lha --icons=auto --sort=name --group-directories-first'
    alias ld='eza -lhD --icons=auto'
else
    alias l='ls -lh --color=auto'
    alias ls='ls --color=auto'
    alias la='ls -lhA --color=auto --group-directories-first'
    alias ld='ls -lhd --color=auto */'
fi

# --- Pager / cat (bat is `batcat` on Debian/Ubuntu, `bat` elsewhere) --------
if command -v batcat >/dev/null 2>&1; then
    alias cat='batcat --paging=never'
elif command -v bat >/dev/null 2>&1; then
    alias cat='bat --paging=never'
fi

# --- Tree ---------------------------------------------------------------------
if command -v tree >/dev/null 2>&1; then
    alias lt='tree -h --du ./'
elif command -v eza >/dev/null 2>&1; then
    alias lt='eza --tree --icons=auto'
fi

# --- Markdown viewer ----------------------------------------------------------
if command -v glow >/dev/null 2>&1; then
    alias re='glow README.md'
else
    alias re='${PAGER:-less} README.md'
fi

# --- Always-available utilities ----------------------------------------------
alias cpr='rsync --recursive --progress'
alias n='nvim'

# --- Desktop-only (NVIDIA PRIME offload) -------------------------------------
if command -v glmark2 >/dev/null 2>&1; then
    alias gpu='__NV_PRIME_RENDER_OFFLOAD=1 __GLX_VENDOR_LIBRARY_NAME=nvidia glmark2'
fi

# --- Tmux ---------------------------------------------------------------------
alias tls='tmux ls'
alias tkill='tmux kill-session -t'

# --- SSH ----------------------------------------------------------------------
# When running inside kitty, use `kitten ssh`, which copies the local terminfo
# to the remote host on connect. Without it, TERM=xterm-kitty arrives on a box
# that has no such entry and every remote TUI misreads key sequences — the same
# root cause as the local herdr double-keypress issue.
if [ "$TERM" = "xterm-kitty" ] && command -v kitten >/dev/null 2>&1; then
    alias ssh='kitten ssh'
fi

