#!/usr/bin/env bash
# Shared WM_CLASS -> Nerd Font glyph mapping.
#
# Sourced by scripts/workspaces.sh (per-desktop app icons) and
# scripts/taskbar.sh (window list), so the two can never drift and show
# different glyphs for the same application.
#
# GLYPHS ARE WRITTEN AS $'\uXXXX' ESCAPES, DELIBERATELY.
# Nerd Font icons live in the Unicode Private Use Area. Pasting them literally
# into a source file is fragile — they are invisible in most editors and diffs,
# trivially stripped by any tool in the chain, and when that happens the
# failure is silent: icon_for() just returns an empty string and every app
# renders as blank. Escapes are plain ASCII, survive anything, and are
# greppable. Codepoints: nerdfonts.com/cheat-sheet
#
# polybar can only draw glyphs from its configured fonts — it cannot render an
# application's real .desktop icon the way Plasma's task manager does. Unknown
# apps fall back to a generic window glyph.
#
# To add an app: run `wmctrl -lx`, take the WM_CLASS, add a case below.

icon_for() {
    case "${1,,}" in
        *firefox*|*navigator*)                                  printf '%s' $'\uf269' ;;  # fa-firefox
        *chrome*|*chromium*|*brave*)                            printf '%s' $'\uf268' ;;  # fa-chrome
        *kitty*|*konsole*|*alacritty*|*gnome-terminal*|*xterm*) printf '%s' $'\uf120' ;;  # fa-terminal
        *code*|*vscodium*|*cursor*)                             printf '%s' $'\uf121' ;;  # fa-code
        *dolphin*|*nautilus*|*thunar*|*nemo*)                   printf '%s' $'\uf07b' ;;  # fa-folder
        *spotify*)                                              printf '%s' $'\uf1bc' ;;  # fa-spotify
        *slack*)                                                printf '%s' $'\uf198' ;;  # fa-slack
        *discord*)                                              printf '%s' $'\uf075' ;;  # fa-comment
        *telegram*)                                             printf '%s' $'\uf2c6' ;;  # fa-telegram
        *thunderbird*|*mail*|*evolution*)                       printf '%s' $'\uf0e0' ;;  # fa-envelope
        *libreoffice*|*writer*|*calc*)                          printf '%s' $'\uf0f6' ;;  # fa-file-text
        *gimp*|*inkscape*|*krita*)                              printf '%s' $'\uf03e' ;;  # fa-image
        *vlc*|*mpv*|*celluloid*)                                printf '%s' $'\uf008' ;;  # fa-film
        *steam*|*lutris*)                                       printf '%s' $'\uf1b6' ;;  # fa-steam
        *systemsettings*|*settings*)                            printf '%s' $'\uf013' ;;  # fa-cog
        *nvim*|*vim*)                                           printf '%s' $'\ue62b' ;;  # custom-vim
        *obsidian*|*notion*)                                    printf '%s' $'\uf02d' ;;  # fa-book
        *zoom*|*teams*|*meet*)                                  printf '%s' $'\uf03d' ;;  # fa-video-camera
        *virtualbox*|*virt-manager*)                            printf '%s' $'\uf109' ;;  # fa-laptop
        *pavucontrol*)                                          printf '%s' $'\uf028' ;;  # fa-volume-up
        *okular*|*evince*|*pdf*)                                printf '%s' $'\uf1c1' ;;  # fa-file-pdf
        *)                                                      printf '%s' $'\uf2d0' ;;  # fa-window-maximize
    esac
}

# Windows that are never real applications: the desktop shell, our own bar,
# the launcher overlay.
is_ignorable_class() {
    case "${1,,}" in
        *plasmashell*|*polybar*|*latte-dock*|*krunner*|*plasma-desktop*) return 0 ;;
        *) return 1 ;;
    esac
}
