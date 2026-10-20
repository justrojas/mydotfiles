# ~/.bash_profile — login bash shells read this, NOT .bashrc.
#
# Two jobs:
#  1. Read ~/.profile. bash skips it whenever .bash_profile exists, and on
#     Ubuntu it is what puts ~/.local/bin on PATH. The KDE session is started
#     from a login bash (SDDM's Xsession), so without this, polybar click
#     actions and autostart apps cannot find tools installed in ~/.local/bin.
#  2. Make login and non-login interactive shells behave the same by loading
#     .bashrc. Ubuntu's ~/.profile already sources it, so only do it here when
#     .profile did not (DOTFILES is exported by .bashrc).
[ -f ~/.profile ] && . ~/.profile
[ -z "${DOTFILES:-}" ] && [ -f ~/.bashrc ] && . ~/.bashrc
