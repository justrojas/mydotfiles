# dotfiles

Personal terminal environment configuration for Ubuntu/Debian.
Clone this repo, run one script, and have a fully configured shell on any machine.

## What's included

| Tool | Config location |
|---|---|
| **bash** (default shell) | `config/bash/.bashrc` |
| **zsh** | `config/zsh/.zshrc` |
| **shared shell layer** | `config/shell/{env,aliases,switch}.sh` |
| **oh-my-posh** | `config/oh-my-posh/tokyonight_storm.omp.json` |
| **tmux** | `config/tmux/tmux.conf` |
| **kitty** | `config/kitty/kitty.conf` |
| **polybar** (top bar) | `config/polybar/config.ini` |
| **rofi** (wifi dropdown) | `config/rofi/config.rasi` |
| **herdr** | `config/herdr/config.toml` |
| **neovim** | NvChad (cloned on install) |
| **KDE Plasma** | `config/kde/` |

`config/shell/` holds everything that is not shell-specific and is sourced by
both `.bashrc` and `.zshrc`, so aliases and `$PATH` never drift between them.

## Quick start

```bash
git clone --recurse-submodules https://github.com/<you>/my-dotfiles.git ~/my-dotfiles
cd ~/my-dotfiles
bash install.sh
```

`--recurse-submodules` is required to pull the tmux plugins.

### Installation profiles

The interactive menu offers four options:

**1 — Terminal Setup** (no sudo required)
- Links all configs via symlinks (`~/.bashrc`, `~/.zshrc`, `~/.config/tmux`, `~/.config/kitty`)
- Installs oh-my-zsh, zsh plugins, oh-my-posh, NvChad
- Assumes packages (bash, zsh, tmux, kitty, nvim) are already installed
- Safe to run on any machine, including restricted work environments

**2 — Desktop Setup** (Ubuntu/Debian, requires sudo)
- Installs all packages via apt + third-party repos (eza, glow, zoxide, neovim)
- Then runs Terminal Setup non-interactively
- Optionally installs KDE Plasma customisations (Kvantum/Ant-Dark theme,
  Touchegg gestures, Firefox userChrome, global shortcuts, bismuth tiling
  gaps, active-window focus ring)
- Optionally installs the polybar top bar

**3 — VM / Headless Setup** (Ubuntu/Debian, requires sudo)
- Shell + neovim + tmux + the CLI tools the shared aliases depend on
- Deliberately skips kitty, Nerd fonts, herdr, KDE and the top bar — none of
  them do anything without a display. Your *client* terminal supplies the font
  and the terminfo entry when you SSH in.
- Equivalent to `terminal-setup.sh --minimal` plus a trimmed apt package list

**4 — Top Bar only** (Ubuntu/Debian, X11)
- Installs polybar, playerctl and rofi, and links `config/polybar/` + `config/rofi/`
- Detects Plasma panels on the top edge and offers to remove or auto-hide them,
  since otherwise two bars fight over the same screen edge and strut

Run a profile directly if you don't want the menu:

```bash
bash profiles/terminal-setup.sh --non-interactive
bash profiles/terminal-setup.sh --minimal      # skip all GUI components
bash profiles/vm-setup.sh --dry-run
bash profiles/bar-setup.sh
bash profiles/desktop-setup.sh --dry-run
```

## After install

**tmux** — start a session, then install plugins:
```
tmux
<Ctrl+Space> + I
```

**neovim** — open it once to trigger NvChad plugin bootstrap:
```
nvim
```

**shell** — open a new terminal. bash is the default; zsh is one command away:
```
shell-toggle    # flip the persistent preference and switch now
tozsh / tobash  # one-off switch, preference unchanged
shell-pref      # show current + preferred
```

## Tmux keybindings

| Action | Key |
|---|---|
| Prefix | `Ctrl+Space` |
| Split horizontal | `prefix + h` |
| Split vertical | `prefix + v` |
| Next/prev window | `Alt+L` / `Alt+H` |
| Jump to window N | `Alt+1`–`9` |
| Move window left/right | `prefix + H` / `prefix + L` |
| Kill pane | `prefix + x` |
| Kill window | `prefix + X` |
| Rename window | `prefix + r` |
| Toggle status bar | `prefix + b` |
| Copy mode | `prefix + [`, then `v` to select, `y` to copy |

## Kitty keybindings

| Action | Key |
|---|---|
| New tab | `Ctrl+Shift+T` |
| Close tab | `Ctrl+Shift+Q` |
| Next/prev tab | `Ctrl+Shift+Right/Left` |
| New window | `Ctrl+Shift+Enter` |
| Close window | `Ctrl+Shift+W` |
| Increase font size | `Ctrl+Shift+=` |
| Decrease font size | `Ctrl+Shift+-` |
| Reset font size | `Ctrl+Shift+Backspace` |

The `kt` utility switches kitty themes interactively:

```bash
kt interactive       # fzf picker with color preview
kt list              # print all available themes
kt set <name>        # apply a theme by name
kt preview <name>    # preview without applying
```

## Shell features

**bash is the default interactive shell.** zsh remains fully configured; the
two are kept at feature parity and share `config/shell/`.

- **Prompt**: oh-my-posh, Tokyo Night Storm — two-line powerline theme
- **Autosuggestions + syntax highlighting**: via [ble.sh](https://github.com/akinomyoga/ble.sh)
  in bash, zsh-autosuggestions/zsh-syntax-highlighting in zsh. Grey ghost text
  from history — press `→` or `Ctrl-F` to accept.
- **Navigation**: zoxide replaces `cd` (learns frequently used directories);
  `cdi` opens an interactive picker
- **File listing**: eza aliases (`l`, `ls`, `la`, `ld`) — these fall back to
  plain `ls` when eza isn't installed, so a minimal box still works
- **Fuzzy find**: `fcd` jumps to the directory of an fzf-selected file;
  `Ctrl+R` / `Ctrl+T` / `Alt+C` are the standard fzf widgets
- **Key bindings** (identical in both shells):
  - `Ctrl+N` — open neovim in current directory
  - `Ctrl+G` — launch opencode
  - `Ctrl+P` — clear screen
- **Lazy loading**: NVM and kubectl completions load on first use (faster start)
- **Docker helpers**: `dls`, `dsh`, `dkill`, `drm`, ... from `config/shell/docker_functions.bash`
- **Work config**: `~/.bashrc.work` / `~/.zshrc.work` for machine-specific config (not tracked)

### Why ble.sh

Bash has no native equivalent of `zsh-autosuggestions` (inline grey completion
from history) or `zsh-syntax-highlighting` (commands coloured as you type).
ble.sh replaces readline outright and provides both, so moving from zsh to bash
does not mean losing them.

It is loaded in two phases in `.bashrc` — sourced with `--attach=none` near the
top, then `ble-attach` as the very last statement. Attaching early would let it
capture `PROMPT_COMMAND` before oh-my-posh sets it, and the prompt renders
wrong. If ble.sh is not installed, bash silently falls back to plain readline.

Building it needs **gawk** (the build rejects Ubuntu's default mawk) and
`make`; `terminal-setup.sh` installs both.

> Tab is deliberately left on readline's default `complete` action. An earlier
> revision bound it to `menu-complete`, which cycles through matches instead of
> completing the shared prefix — that feels like completion is broken. Shift-Tab
> cycles if you want that behaviour.

### Switching shells

The shell you land in is decided by `~/.config/shell/preferred`, **not** by
your login shell. Every interactive shell reads it on startup and re-execs
toward it (loop-guarded). This means new terminals, tmux panes and herdr panes
all agree, without needing `chsh`.

## Top bar

A floating, rounded polybar in a purple-tinted dark palette, sized to 38pt and
detached from the screen edge.

> **Why polybar, not waybar?** Waybar positions itself using the `wlr-layer-shell`
> protocol, which is Wayland-only. This setup is KDE Plasma on **X11**, where
> waybar cannot anchor to a screen edge at all. Polybar is the X11 equivalent
> with the same declarative-config / script-module model.
>
> Note that "upgrade to Plasma 6 to keep polybar" does not work either: Plasma 6
> is Wayland-by-default and its X11 session is deprecated. If Plasma 6 ever
> happens here it should be a clean install, and the bar choice at that point is
> waybar-on-Wayland or a real Hyprland setup. See `docs/CLAUDE.md`.

```bash
bash profiles/bar-setup.sh   # install
bar                          # launch (also autostarts on login)
```

| Region | Modules |
|---|---|
| Left | virtual desktops (as app icons), then media ◀ / ⏯ / ▶ |
| Center | clock |
| Right | volume, temperature, battery, wifi |

The workspace module shows the **icons of the apps on each desktop** rather
than numbers, so you can see what is where at a glance. The active desktop is
marked with an underline rather than a filled block.

Updates are event-driven: `workspaces.sh --watch` follows `xprop -spy` instead
of polling, which took the refresh latency from 1000ms to roughly 2ms.

`config/polybar/launch.sh` detects your network interface, battery and adapter
names at runtime and spawns one bar per connected monitor, so the config file
stays portable across machines.

> **Editing `config.ini` — read this first.** The module icons are Nerd Font
> private-use characters (U+E000–U+F8FF). They are silently stripped if written
> literally by most tooling, leaving modules with blank labels and no error.
> Patch the file with a script that carries the existing bytes across via regex
> capture, rather than retyping the glyphs. `config/polybar/scripts/icons.sh`
> builds its glyphs from `$'\uXXXX'` escapes for the same reason.

### Wifi dropdown

Removing the Plasma panel also removed the systray network applet, and
plasma-nm has no standalone window — it is a systray applet only. So the wifi
icon opens a rofi dropdown anchored under the bar: networks sorted by signal
with the connected one pinned to the top, plus wifi on/off, rescan, and a link
to full network settings.

Selecting a network connects to it, prompting for a password only if
NetworkManager actually asks for one — so saved networks connect in one click.
Falls back to `kdialog` if rofi is missing, then to the full settings windows.

The menu reads NetworkManager's **cache** (`--rescan no`). Letting nmcli decide
to rescan blocks the menu for as long as the scan takes — measured at 3.6s here
against 28ms warm, which presents as random slowness rather than a consistent
delay. NetworkManager rescans on its own schedule, and the menu has an explicit
rescan entry when that isn't enough.

The dropdown is themed to match the bar in `config/rofi/config.rasi`. Note that
polybar writes colours as `#AARRGGBB` and rofi as `#RRGGBBAA`, so the same
colour is spelled `#cc1e1b2e` in one file and `#1e1b2ecc` in the other —
swapping them yields a believable wrong colour rather than an error.

### Spotify / media controls

The center module talks to **MPRIS over D-Bus via `playerctl`** — no OAuth, no
credentials, no network round-trip, and it works with any player (Spotify, mpv,
VLC, Firefox), not just Spotify.

| Interaction | Action |
|---|---|
| Click track | Play / pause |
| Click ◀ / ▶ | Previous / next |
| Scroll over track | Volume down / up |
| Right-click track | Focus the player window |

> A previous `scripts/utilities/spotify_tools/` package did this through the
> Spotify **Web API** — OAuth credentials on every machine, a 5s poll, and a
> *fake* MPRIS bus. It has been removed. The one thing it could do that MPRIS
> cannot is save/like a track; if you want that back, it needs the Web API and
> belongs in its own tool rather than in the bar's hot path.

## Repository structure

```
my-dotfiles/
├── config/
│   ├── shell/                      # shared by BOTH bash and zsh
│   │   ├── env.sh                  # PATH, EDITOR, TERM sanity check
│   │   ├── aliases.sh              # guarded aliases (degrade if tool absent)
│   │   ├── switch.sh               # bash<->zsh preference + toggle
│   │   └── docker_functions.bash   # lazy-loaded docker helpers
│   ├── bash/
│   │   ├── .bashrc                 # symlinked to ~/.bashrc  (default shell)
│   │   └── .bash_profile           # symlinked to ~/.bash_profile
│   ├── zsh/
│   │   ├── .zshrc                  # symlinked to ~/.zshrc
│   │   └── oh-my-posh.omp.json     # legacy prompt theme
│   ├── oh-my-posh/
│   │   ├── tokyonight_storm.omp.json
│   │   └── theme-mappings.conf     # kitty theme -> omp theme
│   ├── polybar/
│   │   ├── config.ini              # top bar: modules, colours, layout
│   │   ├── launch.sh               # detects iface/battery/monitors, spawns bars
│   │   └── scripts/
│   │       ├── workspaces.sh       # virtual desktops as app icons (xprop -spy)
│   │       ├── taskbar.sh          # window list for the focused desktop
│   │       ├── icons.sh            # shared WM_CLASS -> Nerd Font glyph table
│   │       ├── spotify.sh          # MPRIS control via playerctl
│   │       └── network-menu.sh     # rofi wifi dropdown
│   ├── rofi/
│   │   └── config.rasi             # dropdown theme, matched to the bar
│   ├── herdr/config.toml
│   ├── tmux/
│   │   ├── tmux.conf               # symlinked to ~/.config/tmux
│   │   └── plugins/                # git submodules (tpm, sensible, yank, ...)
│   ├── kitty/
│   │   ├── kitty.conf              # symlinked to ~/.config/kitty
│   │   ├── theme.conf              # active theme (symlink into kitty-themes/)
│   │   └── kitty-themes/           # 169 theme files
│   └── kde/
│       ├── latte/                  # DEPRECATED latte-dock layouts (unused)
│       ├── Kvantum/                # Kvantum theme (Ant-Dark)
│       ├── touchegg/               # touchpad gesture config
│       ├── shortcuts/              # KDE keyboard shortcut exports
│       └── applications/firefox/   # Firefox userChrome.css customisations
├── profiles/
│   ├── terminal-setup.sh           # config only, no sudo (--minimal for headless)
│   ├── desktop-setup.sh            # packages + terminal + optional KDE + bar
│   ├── vm-setup.sh                 # headless: shell + nvim + tmux + CLI tools
│   ├── bar-setup.sh                # polybar + playerctl
│   ├── install-packages.sh         # apt installs (called by desktop-setup)
│   └── kde-setup.sh                # KDE themes and desktop customisations
├── lib/
│   └── common.sh                   # shared logging, symlink, and apt helpers
├── scripts/
│   ├── install.sh                  # redirects to root install.sh (legacy)
│   └── utilities/
│       ├── kt                      # kitty theme switcher
│       ├── active-window-border.py # focus ring daemon (X11)
│       └── active-window-border.sh # start/stop/restart the focus ring
├── assets/
│   └── fonts/                      # JetBrainsMono Nerd Font variants
├── tests/
│   ├── docker/
│   │   └── Dockerfile              # parameterised Ubuntu 22.04 / 24.04 image
│   ├── test-terminal-setup.sh      # assertions for terminal-setup.sh
│   ├── test-install-packages.sh    # assertions for install-packages.sh
│   ├── test-vm-setup.sh            # assertions for vm-setup.sh
│   ├── test-kde-setup.sh           # assertions for kde-setup.sh
│   ├── test-rofi-theme.sh          # rofi theme parse check (runs on the host)
│   └── run-docker-tests.sh         # test runner
└── install.sh                      # interactive entry point
```

## Testing

Tests run the install scripts inside a clean Docker container and assert the expected outcome. Docker must be installed and running.

```bash
# Run all tests against all Ubuntu versions
bash tests/run-docker-tests.sh

# Run only the terminal setup suite on Ubuntu 22.04
bash tests/run-docker-tests.sh --suite terminal --ubuntu 2204

# Verify the VM profile installs the shell env AND skips the GUI components
bash tests/run-docker-tests.sh --suite vm --ubuntu 2204

# Keep the container after a failure to inspect it
bash tests/run-docker-tests.sh --suite packages --keep
```

`tests/test-rofi-theme.sh` runs on the **host** rather than in Docker, since it
only needs rofi's parser:

```bash
bash tests/test-rofi-theme.sh
```

It exists because rofi fails a theme parse *silently* — it exits 0, prints
nothing, and renders its stock theme. The only reliable signal from the command
line is that `-dump-theme` emits zero bytes, so the test asserts on dump size
rather than exit status. The specific regression it guards is that a
`configuration {}` block is only legal at the top of `config.rasi`; placing it
after a theme section fails with an error pointing at the closing brace of the
*preceding* block.

> Run these against the host with care: the Docker suites assert things like
> "kitty is not installed", which are false on a real workstation. They are
> written for a clean container and will report spurious failures if invoked
> directly.

On failure the output shows exactly which assertion failed:

```
  FAIL  ~/.config/tmux is not a symlink
  FAIL  command not found: oh-my-posh
Results: 11 passed, 2 failed
```

## Utility scripts

All `scripts/utilities/*.sh` are symlinked into `~/.local/bin` by
`terminal-setup.sh`, so they are on PATH as plain commands.

| Command | What it does |
|---|---|
| `kt` | kitty theme switcher (see above) |
| `active-window-border.sh` | Start/stop the focus ring around the active window (X11) |
| `ssh_gen.sh` | Interactive SSH key generator, copies the pubkey to the clipboard |
| `firefox_fix.sh <url>` | Open a URL in a new Firefox window, optionally fullscreen |
| `claude_launcher.sh` | `firefox_fix.sh https://claude.ai/new` |
| `drive.sh` | Mount OneDrive via rclone. **Requires `rclone`, which no profile installs.** |

### Active window outline

With tiling enabled and a dark decoration, Plasma gives almost no cue as to
which window has focus — it differentiates only by a subtle titlebar shade,
which disappears entirely on tiled or maximised windows where the titlebar is
hidden.

`active-window-border.sh` fixes that by running a small daemon that draws a
coloured ring around whichever window has focus:

```bash
active-window-border.sh start          # purple ring, 3px
active-window-border.sh stop
active-window-border.sh status
AWB_COLOR=f7768e active-window-border.sh restart   # different colour
AWB_WIDTH=5 active-window-border.sh restart        # thicker ring
AWB_MODE=outset active-window-border.sh restart    # ring outside the frame
```

`kde-setup.sh` installs an autostart entry, so it comes back on login.

Configuration is by environment variable: `AWB_COLOR` (RRGGBB), `AWB_WIDTH`,
`AWB_RADIUS`, `AWB_GAP`, `AWB_ALPHA`, `AWB_INTERVAL`, `AWB_MODE`.

**Why a daemon rather than a KWin effect.** This was originally built on
`kwin4_effect_shapecorners`. That effect loads, reports itself enabled, and
logs "shaders loaded" — but never draws anything, verified at 8px in bright
red. The KDE-native alternatives each fail for their own reason: Aurorae SVG
themes such as Ant-Dark paint from their own SVGs and ignore the KDE colour
scheme entirely, so setting `WM/activeBackground` does nothing; Breeze borders
*do* honour it, but only by abandoning the Ant-Dark decoration. Drawing the
ring ourselves — an always-on-top, click-through window tracking the focused
window's frame, the approach `jankyborders` takes on macOS — is the only one
that actually works here.

Two details make it usable rather than infuriating: the window has an **empty
input shape**, so it is completely click-through and never swallows clicks on
window edges or resize handles; and it never accepts focus, which would
otherwise send it into a loop chasing itself.

`inset` mode (the default) draws the ring just inside the window edge, so it
stays fully visible no matter how windows are tiled. `outset` draws it outside
the frame and needs tiling gaps to have somewhere to go — see below.

Inactive windows deliberately get **no** outline — a dim one reads as
"sort of focused" and defeats the purpose. Requires compositing to be enabled.

### Tiling gaps

Bismuth tiles edge-to-edge by default. `kde-setup.sh` sets an 8px gap on both
the screen edges and between tiles, via `[Script-bismuth]` in `kwinrc`.
Override with `BISMUTH_GAP=12 bash profiles/kde-setup.sh --config-only`.

Note that `qdbus org.kde.KWin /KWin reconfigure` alone does **not** make a KWin
*script* re-read its config — the script has to be toggled off and back on,
which `setup_bismuth_tiling()` handles.

## Work / machine-specific config

Machine-specific config (ROS environment, kubeconfig paths) goes in
`~/.bashrc.work` or `~/.zshrc.work`. These are sourced automatically if present
and are excluded from git.

```bash
# ~/.bashrc.work  (example)
export ROS_DOMAIN_ID=42
export KUBECONFIG=~/.kube/work-cluster.yaml
source /opt/ros/humble/setup.bash
```

**Secrets** (API tokens, JWTs) go in `~/.env`, which is sourced at the end of
both rc files. Never hardcode them into a tracked config — the rc files are
symlinked out of this repo and will happily carry a token into git.

```bash
# ~/.env  (example)
export NOCOBASE_TOKEN="..."
```

## Fonts

JetBrainsMono Nerd Font variants are included in `assets/fonts/` and are installed to
`~/.local/share/fonts` by `terminal-setup.sh`. Install manually with:

```bash
cp assets/fonts/*.ttf ~/.local/share/fonts/
fc-cache -f
```

kitty is configured to use **JetBrainsMono Nerd Font Mono** at 13pt
(`config/kitty/kitty.conf`). The polybar config uses the same family, so the
bar renders boxes instead of icons if the fonts are missing.

Nerd Fonts ships three widths and the distinction matters:

| Family | Where |
|---|---|
| `JetBrainsMono Nerd Font Mono` | kitty — icons forced to one cell, which a terminal grid requires |
| `JetBrainsMono Nerd Font` | polybar — icons keep natural width |
| `JetBrainsMono Nerd Font Propo` | proportional, unused |

Using the non-Mono variant in a terminal is the usual cause of powerline
separators and eza icons overlapping the next character.

Verify the families resolve:

```bash
fc-list : family | tr ',' '\n' | grep -i jetbrains | sort -u
```

## Terminal / terminfo

kitty advertises `TERM=xterm-kitty`. That terminfo entry only exists where
kitty has been installed, so on a fresh machine — or the far side of an SSH
hop — full-screen TUIs fall back to guessing escape sequences. The visible
symptom is **doubled keypresses and double backspaces**, most obviously inside
herdr.

Three things address this:

1. `terminal-setup.sh` compiles the entry shipped in the kitty tarball into
   `~/.terminfo` (no root needed), rather than relying on the apt
   `kitty-terminfo` package having been installed at some point.
2. `config/shell/env.sh` validates `$TERM` on startup and downgrades to
   `xterm-256color` if it cannot be resolved.
3. `config/shell/aliases.sh` aliases `ssh` to `kitten ssh` when running under
   kitty, which copies the local terminfo to the remote host on connect.

Check it with:

```bash
infocmp xterm-kitty >/dev/null && echo ok || echo missing
```

Note that apt on Ubuntu 22.04 ships kitty 0.21.2, which has a separate
keyboard-protocol bug that also double-fires keys (fixed upstream in 0.33.0).
`terminal-setup.sh` pins 0.47.4 from the official tarball and purges the apt
package so the buggy binary can never be launched.
