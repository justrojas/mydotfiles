# ~/.bash_profile — login bash shells read this, NOT .bashrc.
# Delegate to .bashrc so login and non-login bash behave identically
# (and so the bash<->zsh auto-switch runs for login shells too).
[ -f ~/.bashrc ] && . ~/.bashrc
