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
- `1` — Terminal Setup (tmux, kitty, neovim, zsh)
- `2` — Desktop Setup (Ubuntu/Debian only, requires sudo)

## Directory Structure

```
my-dotfiles/
├── install.sh                  # Interactive installer (delegates to profiles/)
├── lib/
│   └── common.sh               # Shared logging, symlink, backup, OS detection utils
├── profiles/
│   ├── terminal-setup.sh       # Symlinks configs; installs missing tools at pinned versions
│   ├── desktop-setup.sh        # Orchestrates: install-packages → terminal-setup → kde-setup
│   ├── install-packages.sh     # apt packages + eza, glow, zoxide, neovim, TypeScript
│   └── kde-setup.sh            # KDE Plasma themes, Latte dock, Touchegg, Ant-Dark
├── config/
│   ├── zsh/
│   │   ├── .zshrc              # Main zsh config (lazy-loads NVM, kubectl, docker functions)
│   │   ├── docker_functions.bash
│   │   └── oh-my-posh.omp.json # Prompt theme
│   ├── tmux/
│   │   ├── tmux.conf
│   │   └── plugins/            # TPM submodules
│   ├── kitty/
│   │   ├── kitty.conf
│   │   ├── theme.conf          # Active theme (symlink or inline)
│   │   └── kitty-themes/       # 100+ theme options
│   └── kde/
│       ├── latte/
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
        └── kde-setup.sh         (optional, prompted)
```

## Symlink Locations

```bash
~/.zshrc              → config/zsh/.zshrc
~/.tmux.conf          → config/tmux/tmux.conf
~/.config/tmux        → config/tmux/
~/.config/kitty       → config/kitty/
~/.local/bin/kt       → scripts/utilities/kt
~/.local/bin/*.sh     → scripts/utilities/*.sh
```

Existing files are backed up to `<path>.bak.<timestamp>` before being replaced.

## Pinned Tool Versions

Defined at the top of `profiles/terminal-setup.sh`:

| Tool       | Pinned version |
|------------|----------------|
| tmux       | 3.4 (built from source) |
| neovim     | v0.11.6 |
| kitty      | 0.21.2 |
| zsh        | 5.8.1 |
| oh-my-posh | 29.9.2 |

## Shell Configuration (Zsh)

`config/zsh/.zshrc` is performance-optimized with lazy loading:

- **NVM** — loads on first `node`, `npm`, or `npx` call
- **kubectl completion** — generated on first use, cached to `~/.kube/completion.zsh.inc`
- **Docker functions** — deferred 1 second via `zsh/sched`

Key bindings:
- `Ctrl+N` — open nvim in current directory
- `Ctrl+G` — launch opencode
- `Ctrl+P` — clear screen

Work-specific config (tokens, env vars) goes in `~/.zshrc.work` — gitignored.

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

- Font: JetBrains Mono 16pt
- Theme: set via `config/kitty/theme.conf`
- 100+ themes in `config/kitty/kitty-themes/themes/`
- Switch themes with `kt` (kitty theme switcher):

```bash
kt list
kt set Dracula
kt interactive   # fzf picker with color preview
kt random
```

## Docker Helpers

Sourced from `config/zsh/docker_functions.bash`:

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
./tests/run-docker-tests.sh --keep   # keep containers for debugging
```

## Common Operations

```bash
# Reload tmux config
tmux source ~/.tmux.conf

# Reload kitty config
# Ctrl+Shift+F5 inside kitty

# Reload zsh
exec zsh

# Update Oh My Zsh + plugins
omz update

# Update tmux plugins (inside tmux)
# prefix + U

# Manually install tmux plugins
~/.config/tmux/plugins/tpm/bin/install_plugins
```

## Sensitive Information

- Work tokens, API keys, and env vars go in `~/.zshrc.work` (gitignored, never committed)
- The `.gitignore` also excludes: `.env`, `.env.*`, `.zshrc.local`, `*.secret`, `**/secrets.*`
