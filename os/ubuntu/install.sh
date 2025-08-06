#!/bin/bash

set -e # Exit immediately if a command exits with a non-zero status.

# Function to run apt commands with sudo
apt_install() {
	sudo apt update
	sudo apt install -y "$@"
}

# Function to run commands with error handling
run_cmd() {
	if ! "$@"; then
		echo "Error: Command failed: $*" >&2
		return 1
	fi
}

# Install initial packages
apt_install git wget

# Setup eza repository
sudo mkdir -p /etc/apt/keyrings
run_cmd wget -qO- https://raw.githubusercontent.com/eza-community/eza/main/deb.asc | sudo gpg --dearmor -o /etc/apt/keyrings/gierens.gpg
echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" | sudo tee /etc/apt/sources.list.d/gierens.list
sudo chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list

# Install main packages
apt_install neofetch xclip vim tldr fuse libfuse2 python3 python3-venv npm zsh curl autojump fzf gpg p7zip-full nodejs eza unzip autoconf automake libtool build-essential libevent-dev libncurses5-dev libncursesw5-dev btop nvtop bat

# Install TypeScript
sudo npm install -g typescript

# Update tldr database
tldr -u

# Install oh-my-zsh
run_cmd sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

# Install zoxide
run_cmd curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh

# Setup nvim
(
	cd ~/Downloads
	wget https://github.com/neovim/neovim/releases/download/stable/nvim.appimage
	chmod +x nvim.appimage
	sudo mv nvim.appimage /usr/local/bin/nvim
	# Test nvim installation
	if ! nvim --version >/dev/null 2>&1; then
		echo "AppImage failed, trying alternative installation..."
		sudo apt install -y neovim
	fi
)

# Setup .zshrc config
if [ -f ~/Documents/my-dotfiles/config/shell/zsh/.zshrc ]; then
	ln -sf ~/Documents/my-dotfiles/config/shell/zsh/.zshrc ~/.zshrc
elif [ -f ~/Documents/my-dotfiles/os/ubuntu/.zshrc ]; then
	ln -sf ~/Documents/my-dotfiles/os/ubuntu/.zshrc ~/.zshrc
else
	echo "No .zshrc config found, keeping default oh-my-zsh config"
fi

# Install tmux from package manager (tmux compilation removed)
# Note: If you need a specific tmux version, add compilation steps here

# Glow Setup
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg
echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list
sudo apt install -y glow

# Setup tpm and tmux config
mkdir -p ~/.config/tmux/plugins
if [ ! -d ~/.config/tmux/plugins/tpm ]; then
	git clone https://github.com/tmux-plugins/tpm ~/.config/tmux/plugins/tpm/
fi
if [ -f ~/Documents/my-dotfiles/.config/tmux/tmux.conf ]; then
	ln -sf ~/Documents/my-dotfiles/.config/tmux/tmux.conf ~/.config/tmux/tmux.conf
else
	echo "Tmux config not found, skipping tmux configuration..."
fi

# Install zsh plugins
ZSH_CUSTOM=${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}
git clone https://github.com/zsh-users/zsh-autosuggestions $ZSH_CUSTOM/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git $ZSH_CUSTOM/plugins/zsh-syntax-highlighting
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git $ZSH_CUSTOM/themes/powerlevel10k
git clone https://github.com/chrissicool/zsh-256color $ZSH_CUSTOM/plugins/zsh-256color

# Setup personal nvim config
if [ ! -d ~/.config/nvim ]; then
	git clone https://github.com/lsantos7654/NvChad.git ~/.config/nvim
else
	echo "Nvim config already exists, skipping..."
fi

exec zsh
