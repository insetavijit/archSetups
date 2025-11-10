#!/usr/bin/env bash
# ============================================================
# PHP + MariaDB setup for Arch Linux (2025 compatible)
# Author: Avijit Sarkar
# ============================================================

set -euo pipefail

DB_ROOT_PASS="root"

echo "▶ Updating system..."
sudo pacman -Syu --noconfirm

echo "▶ Installing PHP and MariaDB..."
sudo pacman -S --needed --noconfirm php php-fpm mariadb

# ---------------------------
# MariaDB Setup
# ---------------------------
if [ ! -d /var/lib/mysql/mysql ]; then
    echo "▶ Initializing MariaDB data directory..."
    sudo mariadb-install-db --user=mysql --basedir=/usr --datadir=/var/lib/mysql
else
    echo "ℹ️  MariaDB already initialized — skipping."
fi

echo "▶ Enabling and starting MariaDB..."
sudo systemctl enable --now mariadb

echo "▶ Securing MariaDB..."
sudo mysql --user=root <<EOF || true
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASS}';
DELETE FROM mysql.user WHERE User='';
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF

echo "✅ MariaDB root password set to '${DB_ROOT_PASS}'"

# ---------------------------
# PHP Setup
# ---------------------------
echo "▶ Configuring PHP-FPM..."

# Disable pathinfo for security
sudo sed -i -E 's/^;?cgi\.fix_pathinfo=.*/cgi.fix_pathinfo=0/' /etc/php/php.ini

# Ensure correct PHP-FPM pool user/group/socket
sudo sed -i 's/^user = .*/user = http/' /etc/php/php-fpm.d/www.conf
sudo sed -i 's/^group = .*/group = http/' /etc/php/php-fpm.d/www.conf
sudo sed -i 's~^;?listen = .*~listen = /run/php-fpm/php-fpm.sock~' /etc/php/php-fpm.d/www.conf

echo "▶ Enabling and starting PHP-FPM..."
sudo systemctl enable --now php-fpm

# ---------------------------
# Verification
# ---------------------------
echo ""
echo "▶ Checking service status..."
systemctl is-active --quiet mariadb && echo "✅ MariaDB is running." || echo "❌ MariaDB failed to start."
systemctl is-active --quiet php-fpm && echo "✅ PHP-FPM is running." || echo "❌ PHP-FPM failed to start."

# ---------------------------
# Summary
# ---------------------------
echo ""
echo "🎉 PHP + MariaDB setup complete!"
echo "------------------------------------------------------------"
echo "MariaDB root password : ${DB_ROOT_PASS}"
echo "PHP-FPM socket        : /run/php-fpm/php-fpm.sock"
echo "PHP config file       : /etc/php/php.ini"
echo "MariaDB data dir      : /var/lib/mysql"
echo "------------------------------------------------------------"
