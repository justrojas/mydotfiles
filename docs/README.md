# My Dotfiles

Personal configuration files and setup scripts for Ubuntu/Debian.

## Quick Start

```bash
git clone https://github.com/justrojas/mydotfiles.git ~/Documents/my-dotfiles
cd ~/Documents/my-dotfiles
./install.sh
```

Select a profile:
1. **Terminal Setup** — links tmux, kitty, neovim, zsh configs. Installs missing tools at pinned versions. No sudo required beyond tool installs.
2. **Desktop Setup** — full Ubuntu/Debian bootstrap: installs packages, configures terminal, optional KDE Plasma customization. Requires sudo.

## Directory Structure

```
my-dotfiles/
├── install.sh              # Interactive installer
├── lib/common.sh           # Shared utilities (logging, symlinks, OS detection)
├── profiles/
│   ├── terminal-setup.sh   # Config symlinks + tool installs
│   ├── desktop-setup.sh    # Full system bootstrap
│   ├── install-packages.sh # apt packages + eza, glow, zoxide, neovim
│   └── kde-setup.sh        # KDE Plasma themes and customization
├── config/
│   ├── zsh/                # .zshrc, oh-my-posh theme, docker helpers
│   ├── tmux/               # tmux.conf + TPM plugin submodules
│   ├── kitty/              # kitty.conf, theme.conf, 100+ themes
│   └── kde/                # Latte, Kvantum, Touchegg, Firefox, shortcuts
├── scripts/
│   └── utilities/          # kt (theme switcher), drive, ssh_gen, ...
├── tests/                  # Docker-based integration tests
├── assets/fonts/           # Nerd Fonts
└── docs/                   # Documentation
```

## What Gets Configured

### Terminal Setup (Profile 1)

| Tool       | Config location            | Symlink target         |
|------------|----------------------------|------------------------|
| zsh        | `config/zsh/.zshrc`        | `~/.zshrc`             |
| tmux       | `config/tmux/tmux.conf`    | `~/.tmux.conf`         |
| kitty      | `config/kitty/`            | `~/.config/kitty/`     |
| neovim     | NvChad (cloned on install) | `~/.config/nvim/`      |
| utilities  | `scripts/utilities/`       | `~/.local/bin/`        |

Existing configs are backed up with a timestamp before being replaced.

### Packages Installed (Profile 2)

Core: `git wget curl zsh tmux kitty fzf bat btop vim python3 nodejs`

Third-party:
- `eza` — modern `ls` replacement
- `glow` — markdown renderer
- `zoxide` — smart `cd`
- `neovim` — latest stable

### KDE Plasma (optional, Profile 2)

- Ant-Dark theme + Kvantum styling
- Papirus icon theme
- Latte dock with custom layout
- Touchegg gesture control
- Rounded corners KWin effect

## Utility Scripts

Available in `~/.local/bin/` after install:

- `kt` — kitty theme switcher with fzf preview (`kt list`, `kt set Dracula`, `kt interactive`)
- `drive.sh` — mount OneDrive via rclone
- `ssh_gen.sh` — interactive SSH key generator
- `claude_launcher.sh` — open Claude in a new Firefox window
- `firefox_fix.sh` — open a URL in Firefox with optional fullscreen

## Tmux

Prefix: `Ctrl+Space`

```
prefix + h/v        Split horizontal / vertical
prefix + j/k        Swap pane down / up
prefix + H/L        Swap window left / right
prefix + I/U        Install / update plugins
Alt + H/L           Previous / next window
Alt + 1-9           Jump to window N
```

## Zsh

- Oh My Zsh + oh-my-posh prompt
- Lazy-loaded: NVM, kubectl completion, docker functions
- Plugins: zsh-autosuggestions, zsh-syntax-highlighting, fzf
- Work-specific config in `~/.zshrc.work` (gitignored)

## Testing

Requires Docker:

```bash
./tests/run-docker-tests.sh                          # all suites, Ubuntu 22.04 + 24.04
./tests/run-docker-tests.sh --suite terminal         # terminal-setup only
./tests/run-docker-tests.sh --suite packages --ubuntu 2404
```

## Requirements

- Ubuntu 22.04+ or Debian (Desktop Setup requires Ubuntu/Debian)
- `git`, `curl` or `wget`
- Sudo access for Desktop Setup

## License

MIT
