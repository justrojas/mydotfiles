# Nerd Fonts

Archived from the Nerd Fonts release **v3.4.0**.

* https://github.com/ryanoasis/nerd-fonts/
* https://github.com/ryanoasis/nerd-fonts/releases/latest/

# JetBrains Mono

A typeface designed for developers, patched by Nerd Fonts to add the icon
glyphs used by the prompt (oh-my-posh), the tmux status bar, eza's `--icons`,
and the polybar top bar.

* https://www.jetbrains.com/lp/mono/

## Variants

Three widths ship here, each in Regular / Bold / Italic / BoldItalic:

| File prefix | Family name | Use |
|---|---|---|
| `JetBrainsMonoNerdFontMono-` | `JetBrainsMono Nerd Font Mono` | Terminals. Icons forced to single-cell width — this is what kitty uses. |
| `JetBrainsMonoNerdFont-` | `JetBrainsMono Nerd Font` | Icons keep their natural width. Used by polybar. |
| `JetBrainsMonoNerdFontPropo-` | `JetBrainsMono Nerd Font Propo` | Proportional. Not currently referenced. |

Getting this distinction wrong is the usual cause of misaligned or clipped
icons: a terminal needs the **Mono** variant, a status bar generally does not.

## Installation

`profiles/terminal-setup.sh` copies these to `~/.local/share/fonts` and runs
`fc-cache`. Manually:

```bash
cp assets/fonts/*.ttf ~/.local/share/fonts/
fc-cache -f
```

Verify the family names resolve:

```bash
fc-list : family | tr ',' '\n' | grep -i jetbrains | sort -u
```

## Licence

JetBrains Mono is licensed under the SIL Open Font License 1.1 — see
`LICENSE.md`.
