#!/usr/bin/env bash
# ============================================================
# Clean Reinstall: Zsh + Oh My Zsh (Ubuntu Edition)
# Author: Avijit Sarkar
# Version: 2.2 (Ubuntu-Optimized)
# ============================================================

set -euo pipefail

echo "🧹 Cleaning old Zsh + Oh My Zsh setup..."

# ------------------------------------------------------------
# 🧽 CLEANUP OLD INSTALLS
# ------------------------------------------------------------
rm -rf "$HOME/.oh-my-zsh" \
       "$HOME/.zshrc" \
       "$HOME/.zshrc.pre-oh-my-zsh" \
       "$HOME/.zcompdump"* \
       "$HOME/.p10k.zsh" || true

# ------------------------------------------------------------
# 📦 UPDATE SYSTEM & INSTALL BASICS
# ------------------------------------------------------------
echo "📦 Updating system and installing dependencies..."
sudo apt update -y
sudo apt install -y zsh git curl wget ca-certificates fonts-powerline

# ------------------------------------------------------------
# 🌀 INSTALL OH MY ZSH
# ------------------------------------------------------------
echo "🌀 Installing Oh My Zsh..."
export RUNZSH=no
export CHSH=no
export KEEP_ZSHRC=yes
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

# ------------------------------------------------------------
# ⚙️ CREATE CLEAN .ZSHRC
# ------------------------------------------------------------
echo "🛠️ Creating new .zshrc..."
cat > "$HOME/.zshrc" <<'EOF'
# ============================================================
# Avijit's Clean Zsh + Oh My Zsh Setup (Ubuntu)
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

# Powerlevel10k instant prompt
if [[ -r ~/.p10k.zsh ]]; then
  source ~/.p10k.zsh
fi
EOF

# ------------------------------------------------------------
# 🌈 INSTALL PLUGINS
# ------------------------------------------------------------
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
echo "⚙️ Installing plugins..."
git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions" || true
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" || true

# ------------------------------------------------------------
# 💎 INSTALL POWERLEVEL10K THEME
# ------------------------------------------------------------
echo "💎 Installing Powerlevel10k theme..."
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git \
  "$ZSH_CUSTOM/themes/powerlevel10k" || true

# ------------------------------------------------------------
# 🧩 FIX DEFAULT SHELL
# ------------------------------------------------------------
ZSH_PATH="$(command -v zsh)"
if ! grep -q "$ZSH_PATH" /etc/shells; then
  echo "🧩 Adding $ZSH_PATH to /etc/shells..."
  echo "$ZSH_PATH" | sudo tee -a /etc/shells >/dev/null
fi

echo "🔁 Setting default shell to $ZSH_PATH..."
chsh -s "$ZSH_PATH"

# ------------------------------------------------------------
# ✅ DONE
# ------------------------------------------------------------
echo ""
echo "🎉 Clean reinstall complete!"
echo "👉 Restart your terminal or run: exec zsh"
echo "✨ Configure Powerlevel10k when prompted for your prompt style."
echo ""
echo "💡 Tip: Run 'p10k configure' anytime to reconfigure your prompt."
