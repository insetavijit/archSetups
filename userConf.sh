#!/usr/bin/env bash
set -e

echo "=========================================="
echo " 🧑‍💻 Arch Linux Initial User Setup Script"
echo "=========================================="

# --- Ensure running as root ---
if [ "$(id -u)" -ne 0 ]; then
  echo "❌ Please run as root (use: sudo bash setup-user.sh)"
  exit 1
fi

# --- Set root password ---
echo "🔐 Setting password for root user..."
passwd root

# --- Install essential packages ---
echo "📦 Installing sudo and vim..."
pacman -Syu --noconfirm
pacman -S --noconfirm sudo vim

# --- Create new user ---
USERNAME="avijit"

if id "$USERNAME" &>/dev/null; then
  echo "⚠️ User '$USERNAME' already exists. Skipping creation."
else
  echo "👤 Creating new user: $USERNAME"
  useradd -m -G wheel -s /bin/bash "$USERNAME"
  echo "🔐 Set password for $USERNAME:"
  passwd "$USERNAME"
fi

# --- Configure sudo access ---
echo "🧩 Enabling sudo for wheel group..."
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers

# --- Confirmation ---
echo "✅ User '$USERNAME' created and added to sudoers."
echo "=========================================="

# --- Switch to user automatically ---
echo "🔄 Switching to user '$USERNAME'..."
su - "$USERNAME"
