#!/usr/bin/env bash
# ============================================================
# Clean Reinstall: Zsh + Oh My Zsh
# Author: Avijit Sarkar
# Version: 2.1 (No fonts, Arch-optimized)
# ============================================================

set -euo pipefail

echo "🧹 Cleaning old Zsh + Oh My Zsh setup..."

# Detect the package manager
if command -v pacman &>/dev/null; then
  PM="sudo pacman -S --noconfirm --needed"
elif command -v apt &>/dev/null; then
  PM="sudo apt install -y"
elif command -v dnf &>/dev/null; then
  PM="sudo dnf install -y"
else
  echo "❌ Unsupported distribution."
  exit 1
fi

# ------------------------------------------------------------
# 🧽 CLEANUP OLD INSTALLS
# ------------------------------------------------------------
rm -rf "$HOME/.oh-my-zsh" \
       "$HOME/.zshrc" \
       "$HOME/.zshrc.pre-oh-my-zsh" \
       "$HOME/.zcompdump*" \
       "$HOME/.p10k.zsh" || true

# ------------------------------------------------------------
# 📦 INSTALL ZSH + GIT
# ------------------------------------------------------------
echo "📦 Installing Zsh and Git..."
$PM zsh git curl wget

# ------------------------------------------------------------
# 🌀 INSTALL OH MY ZSH
# ------------------------------------------------------------
echo "🌀 Installing Oh My Zsh..."
RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

# ------------------------------------------------------------
# ⚙️ CONFIGURE ZSHRC
# ------------------------------------------------------------
echo "🛠️ Creating new .zshrc..."
cat > "$HOME/.zshrc" <<'EOF'
# ============================================================
# Avijit's Clean Zsh + Oh My Zsh Setup
# ============================================================

export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"

plugins=(
  git
  z
  sudo
  colored-man-pages
  zsh-autosuggestions
  zsh-syntax-highlighting
)

source $ZSH/oh-my-zsh.sh

# Aliases
alias ll='ls -lh'
alias la='ls -lha'
alias gs='git status'
alias gc='git commit -m'

export PATH="$HOME/.local/bin:$PATH"
EOF

# ------------------------------------------------------------
# 🌈 INSTALL PLUGINS
# ------------------------------------------------------------
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
echo "⚙️ Installing plugins..."
git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"

# ------------------------------------------------------------
# 💎 INSTALL POWERLEVEL10K THEME
# ------------------------------------------------------------
echo "💎 Installing Powerlevel10k theme..."
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \
  "$ZSH_CUSTOM/themes/powerlevel10k"

# ------------------------------------------------------------
# 🧩 FIX DEFAULT SHELL
# ------------------------------------------------------------
ZSH_PATH="/usr/bin/zsh"
if [ ! -x "$ZSH_PATH" ]; then
  ZSH_PATH="$(command -v zsh)"
fi

if ! grep -q "$ZSH_PATH" /etc/shells; then
  echo "🧩 Adding $ZSH_PATH to /etc/shells..."
  echo "$ZSH_PATH" | sudo tee -a /etc/shells >/dev/null
fi

echo "🔁 Setting default shell to $ZSH_PATH..."
chsh -s "$ZSH_PATH"

# ------------------------------------------------------------
# ✅ DONE
# ------------------------------------------------------------
echo "🎉 Clean reinstall complete!"
echo "👉 Restart your terminal or run: exec zsh"
echo "✨ Configure Powerlevel10k when prompted for your prompt style."
