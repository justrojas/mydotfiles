# CLAUDE.md

Guidance for AI assistants working in this repository.

## Overview

Personal dotfiles for Ubuntu/Debian. Two installation profiles:

- **Terminal Setup** — symlinks configs and installs shell tooling (no sudo needed beyond tool installs)
- **Desktop Setup** — full Ubuntu/Debian bootstrap: packages + terminal config + optional KDE

## Quick Start

```bash
git clone https://github.com/justrojas/mydotfiles.git ~/Documents/my-dotfiles
cd ~/Documents/my-dotfiles
./install.sh
```

Profiles:
- `1` — Terminal Setup (tmux, kitty, neovim, bash/zsh)
- `2` — Desktop Setup (Ubuntu/Debian only, requires sudo)
- `3` — VM / Headless Setup (Ubuntu/Debian only, requires sudo)
- `4` — Top Bar only (Ubuntu/Debian, X11, requires sudo)

## Directory Structure

```
my-dotfiles/
├── install.sh                  # Interactive installer (delegates to profiles/)
├── lib/
│   └── common.sh               # Shared logging, symlink, backup, OS detection utils
├── profiles/
│   ├── terminal-setup.sh       # Symlinks configs; installs tools at pinned versions
│   │                           #   --minimal skips fonts/kitty/herdr (headless)
│   ├── desktop-setup.sh        # install-packages → terminal-setup → kde-setup → bar-setup
│   ├── vm-setup.sh             # Headless: trimmed apt list + terminal-setup --minimal
│   ├── bar-setup.sh            # polybar + playerctl; masks Latte Dock autostart
│   ├── install-packages.sh     # apt packages + eza, glow, zoxide, neovim, TypeScript
│   └── kde-setup.sh            # KDE themes, Touchegg, Ant-Dark, focus outline
├── config/
│   ├── shell/                  # SHARED between bash and zsh — put agnostic code here
│   │   ├── env.sh              # PATH, EDITOR, TERM_PROGRAM, $TERM sanity check
│   │   ├── aliases.sh          # All aliases guarded by `command -v`
│   │   ├── switch.sh           # bash<->zsh preference; sourced early, may exec away
│   │   └── docker_functions.bash
│   ├── bash/
│   │   ├── .bashrc             # DEFAULT shell (lazy NVM/kubectl, fzf, readline binds)
│   │   └── .bash_profile
│   ├── zsh/
│   │   ├── .zshrc              # Kept at parity with bash; reached via shell-toggle
│   │   └── oh-my-posh.omp.json # Legacy prompt theme
│   ├── oh-my-posh/
│   │   ├── tokyonight_storm.omp.json
│   │   └── theme-mappings.conf # kitty theme name -> omp stock theme name
│   ├── polybar/
│   │   ├── config.ini          # Top bar modules + Tokyo Night palette
│   │   ├── launch.sh           # Runtime hw detection; one bar per monitor
│   │   └── scripts/spotify.sh  # MPRIS control via playerctl
│   ├── herdr/config.toml
│   ├── tmux/
│   │   ├── tmux.conf
│   │   └── plugins/            # TPM submodules
│   ├── kitty/
│   │   ├── kitty.conf
│   │   ├── theme.conf          # Active theme (symlink or inline)
│   │   └── kitty-themes/       # 169 theme options
│   └── kde/
│       ├── latte/                  # DEPRECATED (archived upstream 2023, unused)
│       ├── Kvantum/
│       ├── touchegg/
│       ├── applications/firefox/
│       └── shortcuts/
├── scripts/
│   ├── install.sh              # Shim → root install.sh
│   └── utilities/              # kt, drive.sh, ssh_gen.sh, claude_launcher.sh, ...
├── tests/
│   ├── run-docker-tests.sh     # Docker-based test runner
│   ├── test-terminal-setup.sh  # Assertions for terminal-setup.sh
│   ├── test-install-packages.sh
│   ├── test-vm-setup.sh        # Asserts GUI components are ABSENT as well
│   └── docker/Dockerfile
├── assets/
│   └── fonts/
└── docs/
    ├── CLAUDE.md               # This file
    └── README.md
```

## Installation Flow

```
install.sh
├── detect_os()
└── profile menu:
    [1] terminal-setup.sh
        ├── Check/install: tmux, nvim, kitty, zsh, git, curl
        ├── Symlink: ~/.tmux.conf, ~/.config/tmux, ~/.config/kitty, ~/.zshrc
        ├── git submodule update --init (tmux plugins)
        ├── Install: Oh My Zsh, zsh-autosuggestions, zsh-syntax-highlighting
        ├── Install: oh-my-posh
        └── Symlink: scripts/utilities/*.sh → ~/.local/bin/

    [2] desktop-setup.sh
        ├── install-packages.sh  (apt + eza + glow + zoxide + neovim + TypeScript)
        ├── terminal-setup.sh --non-interactive
        ├── kde-setup.sh         (optional, prompted)
        └── bar-setup.sh         (optional, prompted)

    [3] vm-setup.sh
        ├── apt: bash zsh tmux git build-essential bat tree rsync ripgrep
        │        fd-find python3 ncurses-bin ncurses-term
        └── terminal-setup.sh --minimal --non-interactive

    [4] bar-setup.sh
        ├── apt: polybar playerctl pavucontrol wmctrl fonts-noto-color-emoji
        ├── Symlink: ~/.config/polybar, ~/.local/bin/bar
        ├── Autostart entry: ~/.config/autostart/polybar.desktop
        └── Optionally mask Latte Dock autostart
```

### `--minimal` mode

`terminal-setup.sh --minimal` is the headless variant used by `vm-setup.sh`.
It skips 3 of the 11 steps (Nerd fonts, kitty config, herdr) and drops
kitty/imagemagick/wl-clipboard/herdr from the tool-install list. `STEP_TOTAL`
is adjusted to 8 accordingly — **if you add or remove a `log_step` call you
must update both branches of that conditional.**

## Symlink Locations

```bash
~/.bashrc             → config/bash/.bashrc          # default shell
~/.bash_profile       → config/bash/.bash_profile
~/.zshrc              → config/zsh/.zshrc
~/.tmux.conf          → config/tmux/tmux.conf
~/.config/tmux        → config/tmux/
~/.config/kitty       → config/kitty/                # skipped by --minimal
~/.config/herdr/config.toml → config/herdr/config.toml   # skipped by --minimal
~/.config/polybar     → config/polybar/              # bar-setup.sh only
~/.local/bin/bar      → config/polybar/launch.sh     # bar-setup.sh only
~/.local/bin/kt       → scripts/utilities/kt
~/.local/bin/*.sh     → scripts/utilities/*.sh
```

Non-symlinked state:
```bash
~/.config/shell/preferred          # "bash" or "zsh" — decides which shell you get
~/.terminfo/                       # compiled xterm-kitty entry
~/.config/autostart/polybar.desktop
```

Existing files are backed up to `<path>.bak.<timestamp>` before being replaced.

## Pinned Tool Versions

Defined at the top of `profiles/terminal-setup.sh`:

| Tool       | Pinned version |
|------------|----------------|
| tmux       | 3.4 (built from source) |
| neovim     | v0.11.6 |
| kitty      | 0.47.4 (official tarball -> `~/.local/kitty.app`) |
| zsh        | 5.8.1 |
| oh-my-posh | 29.9.2 |
| herdr      | latest |

kitty is deliberately NOT installed from apt: Ubuntu 22.04 ships 0.21.2, whose
Kitty-keyboard-protocol bug double-fires Enter/Tab/Backspace inside herdr
(fixed upstream in 0.33.0). `install_kitty()` pins the tarball and then purges
the apt package so the buggy binary can never win a PATH race.

## Shell Configuration

**bash is the default interactive shell.** zsh is fully configured and kept at
feature parity. Three layers:

| Layer | Files | Loaded by |
|---|---|---|
| shared | `config/shell/{env,aliases,switch}.sh` + `docker_functions.bash` | both |
| bash   | `config/bash/{.bashrc,.bash_profile}` | bash |
| zsh    | `config/zsh/.zshrc` | zsh |

Anything shell-agnostic belongs in `config/shell/` — do not duplicate it into
the two rc files, they will drift.

### Which shell you get

Decided by `~/.config/shell/preferred` (seeded to `bash` by terminal-setup),
NOT by the login shell. `config/shell/switch.sh` is sourced early by both rc
files and re-execs toward the preference, loop-guarded via `SHELL_SWITCH_GUARD`.
This keeps new terminals, tmux panes and herdr panes consistent without `chsh`.

- `shell-toggle` — flip the preference and switch now
- `tobash` / `tozsh` — one-off switch, preference unchanged
- `shell-pref` — print current + preferred

Do NOT add a `chsh`/`usermod` step or an `exec zsh` line to an rc file. The rc
files are symlinks into this repo, so appending to them dirties the working
tree on every install.

### ble.sh (bash only)

`~/.local/share/blesh/ble.sh` — the Bash Line Editor. Provides the two things
readline cannot: autosuggestions (zsh-autosuggestions equivalent) and syntax
highlighting (zsh-syntax-highlighting equivalent).

Load order is load-bearing and easy to break:

1. **Top of `.bashrc`**, right after `switch.sh`:
   `source ~/.local/share/blesh/ble.sh --attach=none`
2. **Very last statement of `.bashrc`**: `ble-attach`, inside `if [[ ${BLE_VERSION-} ]]`

Attaching before oh-my-posh runs makes ble.sh capture a half-built
`PROMPT_COMMAND` and the prompt renders incorrectly. Any `bleopt` / `ble-face`
/ `ble-bind` calls must sit between the two phases.

Built from source by `install_blesh()` in `profiles/terminal-setup.sh`. It is
NOT in the `TOOL_LIST` loop because it is a sourced library, not a binary on
PATH — the loop keys off `command -v`. Requires **gawk** specifically; the
build hard-fails on Ubuntu's default mawk with "Sorry, gawk could not be
found." `gawk` is in the apt lists of both `install-packages.sh` and
`vm-setup.sh`, and `install_blesh()` installs it as a fallback.

Absent ble.sh, `.bashrc` degrades to plain readline with no errors.

### Completion

TAB stays on readline's default `complete`. Do NOT rebind it to
`menu-complete`: that inserts the first match rather than completing the common
prefix, which with bash-completion loaded reads as "completion is broken".
Shift-Tab (`\e[Z`) is bound to `menu-complete` for anyone who wants cycling.

### Performance

Both shells lazy-load:
- **NVM** — loads on first `node`, `npm`, or `npx` call
- **kubectl completion** — generated on first use, cached to
  `~/.kube/completion.{bash,zsh}.inc`
- **Docker functions** — sourced directly in bash; deferred 1s via `zsh/sched` in zsh

Key bindings (identical in both):
- `Ctrl+N` — open nvim in current directory
- `Ctrl+G` — launch opencode
- `Ctrl+P` — clear screen

### Gotchas

- `~/.bun/_bun` is a **zsh** completion (`#compdef bun`). Sourcing it from bash
  emits `autoload: command not found`. There is no bash equivalent.
- `config/shell/aliases.sh` guards every alias behind a `command -v` check so
  the minimal VM profile degrades to stock `ls`/`cat` instead of erroring.
- Everything in `lib/common.sh` runs under `set -u`; use `${VAR:-}` for any
  variable that may be unset (`DISPLAY`, `WAYLAND_DISPLAY`, `OSTYPE`).

Work-specific config goes in `~/.bashrc.work` / `~/.zshrc.work` — gitignored.
Secrets go in `~/.env`, sourced last by both rc files.

## Tmux Configuration

Prefix: `Ctrl+Space`

| Key              | Action                        |
|------------------|-------------------------------|
| `prefix + h`     | Split horizontal              |
| `prefix + v`     | Split vertical                |
| `prefix + j/k`   | Swap pane down/up             |
| `prefix + H/L`   | Swap window left/right        |
| `prefix + r`     | Rename window                 |
| `prefix + x`     | Kill pane                     |
| `prefix + X`     | Kill window                   |
| `prefix + b`     | Toggle status bar             |
| `prefix + I`     | Install plugins               |
| `prefix + U`     | Update plugins                |
| `Alt+H/L`        | Previous/next window          |
| `Alt+1-9`        | Jump to window N              |

Copy mode (vi-style): `prefix+[` to enter, `v` to select, `y` to copy (wl-copy).

Plugins (TPM submodules in `config/tmux/plugins/`):
- `tpm` — plugin manager
- `tmux-sensible` — sensible defaults
- `vim-tmux-navigator` — seamless vim/tmux pane navigation
- `minimal-tmux-status` — status bar theme
- `tmux-yank` — clipboard integration

## Kitty Terminal

- Font: JetBrainsMono Nerd Font Mono 13pt (`assets/fonts/`, Nerd Fonts v3.4.0)
  - The **Mono** variant is required in a terminal — it forces icon glyphs to a
    single cell. The plain / Propo variants overlap the next character.
  - polybar deliberately uses the NON-Mono variant; a status bar is not a grid.
- Default shell: `bash` (`shell bash` in kitty.conf)
- Theme: set via `config/kitty/theme.conf`
- 169 themes in `config/kitty/kitty-themes/themes/`
- Switch themes with `kt` (kitty theme switcher):

```bash
kt list
kt set Dracula
kt interactive   # fzf picker with color preview
kt random
```

## KDE Setup

`profiles/kde-setup.sh` `main()` runs, in order:

| Step | Function | Installs |
|---|---|---|
| 1 | `setup_repositories` | Papirus PPA |
| 2 | `install_packages` | KDE/Qt packages, kwin-bismuth, Kvantum engine, Papirus |
| 3 | `install_binary_packages` | `scripts/packages/*.deb` (touchegg, shapecorners) |
| 4 | `setup_touchegg_config` | `config/kde/touchegg/` → `~/.config/touchegg/` |
| 5 | `setup_kvantum_config` | `config/kde/Kvantum/` → `~/.config/Kvantum/` |
| 6 | `setup_firefox_chrome` | `config/kde/applications/firefox/chrome/` → the default FF profile |
| 7 | `setup_kde_shortcuts` | `config/kde/shortcuts/global-shortcuts.kksrc` (prompted) |
| 8 | `setup_active_window_outline` | shapecorners focus ring |
| 9 | `install_fonts` | JetBrainsMono Nerd Font → `/usr/share/fonts/truetype/` |
| 10 | `install_ant_dark_theme` | Clones EliverLara/Ant, installs plasma/icons/sddm/aurorae |

Steps 5–7 were previously **dead weight**: 748 KB of config that no code path
touched, so a reader reasonably assumed it was installed when it was not.

Gotchas in the newly-wired steps:

* **Kvantum** — `install_packages` apt-installs the *engine*
  (`qt5-style-kvantum`), but the Ant-Dark theme and the `kvantum.kvconfig` that
  selects it live in this repo and must be copied separately. Installing the
  engine alone leaves you on the default theme.
* **Firefox** — two things are required and it is easy to do only one: the CSS
  must land in `<profile>/chrome/`, AND
  `toolkit.legacyUserProfileCustomizations.stylesheets` must be `true` or
  Firefox silently ignores the whole directory. The profile is resolved from
  `profiles.ini`, not by globbing `*.default*`, which picks wrong when several
  profiles exist.
* **Shortcuts** — a `.kksrc` is the same INI format as
  `~/.config/kglobalshortcutsrc`, with `[Component][Global Shortcuts]` headers.
  The import merges key-by-key via `kwriteconfig5` rather than copying the file
  wholesale, so local shortcuts absent from the scheme survive. It **overwrites
  conflicting bindings**, so it is prompted and backs up first. There used to be
  four ambiguous `.kksrc` files with no indication which was current; only
  `global-shortcuts.kksrc` remains.

## Top Bar (polybar)

### Why not waybar / Plasma 6 (decision record)

Current target: **Ubuntu 22.04 + Plasma 5.27 + X11 + polybar.** Deliberate.

* Waybar anchors via `zwlr_layer_shell_v1`, a Wayland protocol. It cannot dock
  on X11 at all. Polybar is the X11 equivalent.
* "Upgrade to Plasma 6 so we can keep polybar" is self-defeating: Plasma 6 is
  Wayland-by-default, and its X11 session is the deprecated path. You would
  take the whole migration and gain nothing.
* There is no upgrade path from 22.04 anyway. Jammy ships Qt 5.15 / KF5;
  Plasma 6 needs Qt6 + KF6. The Kubuntu backports PPA tops out at 5.27.11.
  Reaching Plasma 6 means 22.04 → 24.04 → 24.10 → 25.04 → 25.10, four chained
  release upgrades ending on a 9-month-support release.

If Plasma 6 happens, it should be a **clean install**, and the bar decision is
then Wayland+waybar or a real Hyprland setup — not Plasma 6 + polybar.

Hardware note: this machine is Intel graphics with no NVIDIA, which is the
best case for Wayland. Hardware is not the blocker; the Ubuntu upgrade path is.

> Latte Dock is **deprecated** — archived upstream in 2023, no Plasma 6 support.
> `kde-setup.sh` no longer installs it and `setup_latte_dock_config()` is a
> no-op stub. `config/kde/latte/` is historical reference only. The supported
> options are native Plasma panels or the polybar bar below.


`config/polybar/` — a floating, Waybar-style top bar for **X11**.

Waybar is not usable here: it anchors via the wlroots layer-shell protocol,
which is Wayland-only, and this setup is KDE Plasma on X11. Polybar is the X11
equivalent. Do not "port to waybar" without first migrating the session.

- `config.ini` — modules, Tokyo Night Storm palette, per-module pill styling
- `launch.sh` — detects the network interface, battery and adapter names at
  runtime and exports them as `$NET_IFACE` / `$BATTERY` / `$ADAPTER`, which
  `config.ini` reads via `${env:VAR:fallback}`. Also spawns one bar per
  connected monitor via `$MONITOR`. This is why the config is portable.
- `scripts/spotify.sh` — MPRIS control via `playerctl`

Launch with `bar`. Logs to `~/.cache/polybar.log`.

### Media controls

`scripts/spotify.sh` talks to the **real MPRIS D-Bus interface** via
`playerctl`. It picks the player named `spotify` if present, else the first one
actually playing, else the first available. Subcommands: `status`, `play-pause`,
`next`, `previous`, `focus`, `volume-up`, `volume-down`, `next-icon`,
`prev-icon`. The `*-icon` subcommands print nothing when no player is running,
which collapses the three center pills instead of leaving dead buttons.

A previous `scripts/utilities/spotify_tools/` package used the Spotify **Web
API** (OAuth creds per machine, 5s poll, published a *fake* MPRIS bus). It was
removed during cleanup: no profile installed it, and nothing bound its
`spotify-like` entry point to anything. Saving a track has no MPRIS verb, so
that capability would need the Web API and a dedicated tool if wanted back.

## Terminfo

`TERM=xterm-kitty` only resolves where kitty has been installed. When it does
not resolve, ncurses apps guess escape sequences and you get **doubled
keypresses / double backspaces**, most visibly in herdr.

Handled in three places — keep all three in mind when touching terminal setup:

1. `install_kitty_terminfo()` in `profiles/terminal-setup.sh` compiles the
   entry shipped inside the kitty tarball into `~/.terminfo` via `tic -x`.
   It does NOT depend on the apt `kitty-terminfo` package, which is absent on
   any machine where kitty came only from the tarball.
2. `config/shell/env.sh` validates `$TERM` with `infocmp` at shell startup and
   downgrades to `xterm-256color` (then `xterm`) if it cannot be resolved.
3. `config/shell/aliases.sh` aliases `ssh` to `kitten ssh` under kitty, which
   copies the local terminfo to the remote host.

`tic`/`infocmp` come from `ncurses-bin`; `vm-setup.sh` installs it explicitly.

## Docker Helpers

Sourced from `config/shell/docker_functions.bash` (bash syntax, works in both shells):

```bash
dls                          # List running + stopped containers
dils                         # List images
dsh <container>              # Shell into container (prefers zsh, falls back to bash/sh)
dkill <container>            # Stop container
drm <container>              # Remove container
dcommit <container> <tag>    # Commit container to new image
drunning <container>         # Check if container is running (returns 0/1)
```

## Testing

```bash
# Run all tests (requires Docker)
./tests/run-docker-tests.sh

# Specific suite or version
./tests/run-docker-tests.sh --suite terminal
./tests/run-docker-tests.sh --suite packages --ubuntu 2404
./tests/run-docker-tests.sh --suite vm --ubuntu 2204
./tests/run-docker-tests.sh --keep   # keep containers for debugging
```

The `vm` suite asserts both directions: that the shell/nvim/tmux environment
IS present, and that kitty, herdr and the Nerd fonts were correctly SKIPPED.
A VM profile that quietly drags in GUI components is a failed VM profile.

## Common Operations

```bash
# Reload tmux config
tmux source ~/.tmux.conf

# Reload kitty config
# Ctrl+Shift+F5 inside kitty

# Reload the shell
exec bash        # or: shell-toggle / tozsh

# Update Oh My Zsh + plugins
omz update

# Update tmux plugins (inside tmux)
# prefix + U

# Manually install tmux plugins
~/.config/tmux/plugins/tpm/bin/install_plugins
```

## Sensitive Information

- Secrets (API tokens, JWTs) go in `~/.env` (gitignored), sourced by both rc files
- Work env vars go in `~/.bashrc.work` / `~/.zshrc.work` (gitignored)
- NEVER hardcode a token in `config/bash/.bashrc` or `config/zsh/.zshrc` — those
  are tracked files symlinked into `$HOME`, so the secret lands in git
- The `.gitignore` also excludes: `.env`, `.env.*`, `.zshrc.local`, `*.secret`, `**/secrets.*`
