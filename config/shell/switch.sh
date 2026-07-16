# Persistent bash <-> zsh preference with instant toggle.
# Sourced EARLY by both .bashrc and .zshrc — may exec() into the other shell.
#
# Model:
#   ~/.config/shell/preferred  holds "zsh" or "bash".
#   Every interactive shell checks it on startup and re-exec's toward the
#   preferred shell (guarded against loops). So new terminals always land in
#   your preferred shell regardless of the system login shell.
#
# Commands:
#   shell-toggle   flip the saved preference and switch now (use at work)
#   tobash / tozsh one-off switch WITHOUT changing the saved preference
#   shell-pref     print current + preferred

_shell_pref_file="${XDG_CONFIG_HOME:-$HOME/.config}/shell/preferred"

# Which shell is running this file right now?
if [ -n "${ZSH_VERSION:-}" ]; then
    _shell_current=zsh
elif [ -n "${BASH_VERSION:-}" ]; then
    _shell_current=bash
else
    _shell_current=sh
fi

# Flip the persistent preference and switch immediately.
shell-toggle() {
    local target
    if [ "$_shell_current" = zsh ]; then target=bash; else target=zsh; fi
    if ! command -v "$target" >/dev/null 2>&1; then
        printf 'shell-toggle: %s is not installed\n' "$target" >&2
        return 1
    fi
    mkdir -p "$(dirname "$_shell_pref_file")"
    printf '%s\n' "$target" > "$_shell_pref_file"
    printf 'Preferred shell -> %s (switching now)\n' "$target"
    unset SHELL_SWITCH_GUARD
    exec "$target" -l
}

# One-off switches that do NOT change the saved preference.
tobash() { exec bash -l; }
tozsh()  { exec zsh -l; }

# Show current + preferred.
shell-pref() {
    printf 'current: %s | preferred: %s\n' "$_shell_current" \
        "$(cat "$_shell_pref_file" 2>/dev/null || echo '(unset -> uses login shell)')"
}

# --- Auto-switch toward the saved preference (interactive shells only) ------
case $- in
    *i*)
        if [ -z "${SHELL_SWITCH_GUARD:-}" ] && [ -r "$_shell_pref_file" ]; then
            _shell_pref="$(cat "$_shell_pref_file" 2>/dev/null)"
            if [ -n "$_shell_pref" ] && [ "$_shell_pref" != "$_shell_current" ] \
               && command -v "$_shell_pref" >/dev/null 2>&1; then
                export SHELL_SWITCH_GUARD=1
                exec "$_shell_pref" -l
            fi
        fi
        ;;
esac
