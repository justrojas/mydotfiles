# dotfiles

Personal terminal environment configuration for Ubuntu/Debian.
Clone this repo, run one script, and have a fully configured shell on any machine.

## What's included

| Tool | Config location |
|---|---|
| **zsh** | `config/zsh/.zshrc` |
| **oh-my-posh** | `config/zsh/oh-my-posh.omp.json` |
| **tmux** | `config/tmux/tmux.conf` |
| **kitty** | `config/kitty/kitty.conf` |
| **neovim** | NvChad (cloned on install) |
| **KDE Plasma** | `config/kde/` |

## Quick start

```bash
git clone --recurse-submodules https://github.com/<you>/my-dotfiles.git ~/my-dotfiles
cd ~/my-dotfiles
bash install.sh
```

`--recurse-submodules` is required to pull the tmux plugins.

### Installation profiles

The interactive menu offers two options:

**1 — Terminal Setup** (no sudo required)
- Links all configs via symlinks (`~/.zshrc`, `~/.config/tmux`, `~/.config/kitty`)
- Installs oh-my-zsh, zsh plugins, oh-my-posh, NvChad
- Assumes packages (zsh, tmux, kitty, nvim) are already installed
- Safe to run on any machine, including restricted work environments

**2 — Desktop Setup** (Ubuntu/Debian, requires sudo)
- Installs all packages via apt + third-party repos (eza, glow, zoxide, neovim)
- Then runs Terminal Setup non-interactively
- Optionally installs KDE Plasma customisations (themes, latte-dock, Ant-Dark)

Run a profile directly if you don't want the menu:

```bash
bash profiles/terminal-setup.sh --non-interactive
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

**zsh** — reload your shell:
```
exec zsh
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

## Zsh features

- **Prompt**: oh-my-posh with atomic layout — muted two-line powerline theme
- **Plugins**: zsh-autosuggestions, zsh-syntax-highlighting, fzf, git, sudo
- **Navigation**: zoxide replaces `cd` (learns frequently used directories)
- **File listing**: eza aliases (`l`, `ls`, `la`, `ld`)
- **Key bindings**:
  - `Ctrl+N` — open neovim in current directory
  - `Ctrl+G` — launch opencode
  - `Ctrl+P` — clear screen
- **Lazy loading**: NVM and kubectl completions load on first use (faster shell start)
- **Work config**: create `~/.zshrc.work` for machine-specific config (not tracked)

## Repository structure

```
my-dotfiles/
├── config/
│   ├── zsh/
│   │   ├── .zshrc                  # symlinked to ~/.zshrc
│   │   ├── oh-my-posh.omp.json     # prompt theme
│   │   └── docker_functions.bash   # lazy-loaded docker helpers
│   ├── tmux/
│   │   ├── tmux.conf               # symlinked to ~/.config/tmux
│   │   └── plugins/                # git submodules (tpm, sensible, yank, ...)
│   ├── kitty/
│   │   ├── kitty.conf              # symlinked to ~/.config/kitty
│   │   ├── theme.conf              # active theme (symlink into kitty-themes/)
│   │   └── kitty-themes/           # 200+ theme files
│   └── kde/
│       ├── latte/                  # latte-dock layouts
│       ├── Kvantum/                # Kvantum theme (Ant-Dark)
│       ├── touchegg/               # touchpad gesture config
│       ├── shortcuts/              # KDE keyboard shortcut exports
│       └── applications/firefox/   # Firefox userChrome.css customisations
├── profiles/
│   ├── terminal-setup.sh           # config only, no sudo
│   ├── desktop-setup.sh            # packages + terminal + optional KDE
│   ├── install-packages.sh         # apt installs (called by desktop-setup)
│   └── kde-setup.sh                # KDE themes and desktop customisations
├── lib/
│   └── common.sh                   # shared logging, symlink, and apt helpers
├── scripts/
│   ├── install.sh                  # redirects to root install.sh (legacy)
│   └── utilities/
│       └── kt                      # kitty theme switcher
├── assets/
│   └── fonts/                      # Hack Nerd Font variants
├── tests/
│   ├── docker/
│   │   └── Dockerfile              # parameterised Ubuntu 22.04 / 24.04 image
│   ├── test-terminal-setup.sh      # assertions for terminal-setup.sh
│   ├── test-install-packages.sh    # assertions for install-packages.sh
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

# Keep the container after a failure to inspect it
bash tests/run-docker-tests.sh --suite packages --keep
```

On failure the output shows exactly which assertion failed:

```
  FAIL  ~/.config/tmux is not a symlink
  FAIL  command not found: oh-my-posh
Results: 11 passed, 2 failed
```

## Work / machine-specific config

Anything that should not be committed (employer tokens, ROS environment variables, machine-specific paths) goes in `~/.zshrc.work`. This file is sourced automatically if it exists and is excluded from git.

```bash
# ~/.zshrc.work  (example)
export ROS_DOMAIN_ID=42
export KUBECONFIG=~/.kube/work-cluster.yaml
source /opt/ros/humble/setup.zsh
```

## Fonts

Hack Nerd Font variants are included in `assets/fonts/`. The KDE setup script installs them system-wide. Install manually with:

```bash
sudo cp assets/fonts/*.ttf /usr/share/fonts/
sudo fc-cache -fv
```

Set **JetBrains Mono** as the kitty font (configured in `config/kitty/kitty.conf`).
