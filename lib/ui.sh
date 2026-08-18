#!/usr/bin/env bash
# lib/ui.sh — presentation layer: cats, status faces, verification output.
#
# Split out from lib/common.sh, which had grown to mix logging with filesystem
# helpers, and duplicated across profiles (terminal-setup and bar-setup each
# had their own _vok/_vfail with slightly different formatting).
#
# THREE TIERS, AUTO-DETECTED
# --------------------------
# There is a hard constraint here that shapes everything: install.sh runs on a
# fresh Ubuntu box BEFORE any fonts are installed. So the fancy art cannot be
# the default — on the machine you most want it to look right, it would be a
# grid of tofu boxes.
#
#   plain    no art, no colour. Auto-selected when stdout is not a terminal
#            (pipes, CI, `tee` to a log) or when DOTFILES_UI=plain.
#   ascii    ASCII cats. Renders identically in a bare VGA console, over
#            `ssh -T`, under LANG=C, in any font. The default.
#   braille  the art in assets/cats/. Needs a UTF-8 locale and a font with the
#            braille block (U+2800-U+28FF) — see install_braille_font() in
#            lib/installers.sh, since JetBrainsMono Nerd Font does NOT cover it
#            and the fallback is a proportional face that skews the columns.
#
# Override with DOTFILES_UI=plain|ascii|braille.

# ----------------------------------------------------------------------------
# Tier detection
# ----------------------------------------------------------------------------
_detect_ui_tier() {
    # Explicit wins.
    case "${DOTFILES_UI:-}" in
        plain|ascii|braille) echo "${DOTFILES_UI}"; return ;;
    esac

    # Not a terminal: being piped, redirected, or run by CI. Art in a log file
    # is noise, and colour codes make it unreadable.
    [[ -t 1 ]] || { echo plain; return; }

    # Braille needs a UTF-8 locale. A bare console (TERM=linux) has a 256-glyph
    # font and cannot render it regardless of locale.
    local enc="${LC_ALL:-${LC_CTYPE:-${LANG:-}}}"
    if [[ "$enc" == *[Uu][Tt][Ff]* && "${TERM:-}" != "linux" && "${TERM:-}" != "dumb" ]]; then
        echo braille
        return
    fi

    echo ascii
}

UI_TIER="$(_detect_ui_tier)"
export UI_TIER

CATS_DIR="${CATS_DIR:-${DOTFILES_DIR:-.}/assets/cats}"

# ----------------------------------------------------------------------------
# The cast
# ----------------------------------------------------------------------------
# ASCII cats are three lines so they can carry an expression. The eyes are the
# state: 0_0 working, -_- idle/dry-run, ^_^ happy, x_x broken.
_ascii_cat() {
    local eyes="${1:-0_0}"
    printf ' /\\_/\\\n( %s )\n > ^ <\n' "$eyes"
}

# Braille art, keyed by mood. Falls back to the ASCII cat when the file is
# missing so a bad install never breaks output.
_braille_cat() {
    local name="$1" file="$CATS_DIR/$1.txt"
    if [[ -r "$file" ]]; then
        cat "$file"
    else
        case "$name" in
            sit)     _ascii_cat "^_^" ;;
            loaf)    _ascii_cat "-_-" ;;
            stretch) _ascii_cat "^_^" ;;
            *)       _ascii_cat "0_0" ;;
        esac
    fi
}

# cat_art <mood>   moods: peek (header), sit (done), loaf (idle/dry-run),
#                         stretch (greeting)
cat_art() {
    local mood="${1:-peek}"
    case "$UI_TIER" in
        plain)   return 0 ;;
        braille) _braille_cat "$mood" ;;
        *)
            case "$mood" in
                sit)     _ascii_cat "^_^" ;;
                loaf)    _ascii_cat "-_-" ;;
                stretch) _ascii_cat "^_^" ;;
                *)       _ascii_cat "0_0" ;;
            esac
            ;;
    esac
}

# One-line faces for individual log lines. Always ASCII: these sit inline in
# padded columns, and printf's %-Ns padding counts characters, not display
# columns — so a double-width glyph here would silently misalign every row.
ui_face() {
    [[ "$UI_TIER" == plain ]] && { echo ""; return; }
    case "$1" in
        ok)    echo '(^_^)b' ;;
        work)  echo '(0_0) ' ;;
        warn)  echo '(0.o)?' ;;
        err)   echo '(x_x) ' ;;
        idle)  echo '(-_-)z' ;;
        *)     echo '(0_0) ' ;;
    esac
}

# ----------------------------------------------------------------------------
# Verification output
# ----------------------------------------------------------------------------
# Promoted from terminal-setup.sh (_vok/_vfail) and bar-setup.sh (_ok/_bad),
# which formatted the same information two different ways.
VERIFY_PASS=0
VERIFY_FAIL=0

verify_ok() {
    local face; face="$(ui_face ok)"
    printf "  ${GREEN}%s${NC}  %-38s ${GREEN}%s${NC}\n" "${face:-ok}" "$1" "${2:-ok}"
    (( VERIFY_PASS++ )) || true
}

verify_fail() {
    local face; face="$(ui_face err)"
    printf "  ${RED}%s${NC}  %-38s ${RED}%s${NC}\n" "${face:-FAIL}" "$1" "${2:-MISSING}"
    (( VERIFY_FAIL++ )) || true
}

# verify_cmd <label> <command>  — assert a command resolves on PATH
#
# Argument order is (label, command), matching the existing call sites in
# terminal-setup.sh. Reversing it would have been marginally more natural but
# would silently mislabel two dozen assertions.
verify_cmd() {
    local label="$1" cmd="${2:-$1}" path
    if path="$(command -v "$cmd" 2>/dev/null)"; then
        verify_ok "$label" "$path"
    else
        verify_fail "$label" "not found"
    fi
}

# verify_symlink <label> <path>  — assert a path is a symlink that resolves
verify_symlink() {
    local label="$1" path="$2"
    if [[ -L "$path" && -e "$path" ]]; then
        verify_ok "$label" "ok"
    elif [[ -L "$path" ]]; then
        verify_fail "$label" "broken -> $(readlink "$path")"
    else
        verify_fail "$label" "not a symlink"
    fi
}

# verify_summary [label]  — print the tally with a cat, return non-zero on fail
verify_summary() {
    local label="${1:-checks}" total=$((VERIFY_PASS + VERIFY_FAIL))
    echo ""
    if [[ $VERIFY_FAIL -eq 0 ]]; then
        cat_art sit
        log_success "All $label passed ($VERIFY_PASS/$total)"
        return 0
    fi
    cat_art loaf
    log_warning "$VERIFY_FAIL of $total $label failed — see above"
    return 1
}
