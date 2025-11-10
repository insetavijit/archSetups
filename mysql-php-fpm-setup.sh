#!/usr/bin/env bash
# ============================================================
# PHP + MariaDB setup for Arch Linux (WordPress optimized 2025)
# Author: Avijit Sarkar
# ============================================================

set -euo pipefail

DB_ROOT_PASS="root"
PHP_INI="/etc/php/php.ini"
FPM_POOL="/etc/php/php-fpm.d/www.conf"

echo "▶ Updating system..."
sudo pacman -Syu --noconfirm

echo "▶ Installing PHP (with key extensions) and MariaDB..."
sudo pacman -S --needed --noconfirm \
    php php-fpm php-gd php-intl php-sodium mariadb

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
echo "▶ Configuring PHP for WordPress..."

# --- Core tuning ---
sudo sed -i -E 's/^;?cgi\.fix_pathinfo=.*/cgi.fix_pathinfo=0/' "$PHP_INI"
sudo sed -i -E 's/^;?memory_limit.*/memory_limit = 512M/' "$PHP_INI"
sudo sed -i -E 's/^;?upload_max_filesize.*/upload_max_filesize = 128M/' "$PHP_INI"
sudo sed -i -E 's/^;?post_max_size.*/post_max_size = 128M/' "$PHP_INI"
sudo sed -i -E 's/^;?max_execution_time.*/max_execution_time = 120/' "$PHP_INI"
sudo sed -i -E 's/^;?max_input_vars.*/max_input_vars = 5000/' "$PHP_INI"
sudo sed -i -E 's/^;?expose_php.*/expose_php = Off/' "$PHP_INI"
sudo sed -i -E 's/^;?display_errors.*/display_errors = Off/' "$PHP_INI"
sudo sed -i -E 's/^;?log_errors.*/log_errors = On/' "$PHP_INI"
sudo sed -i -E 's|^;?error_log.*|error_log = /var/log/php/errors.log|' "$PHP_INI"
sudo sed -i -E 's/^;?default_charset.*/default_charset = "UTF-8"/' "$PHP_INI"
sudo sed -i -E 's/^;?allow_url_fopen.*/allow_url_fopen = On/' "$PHP_INI"

# --- OPcache tuning ---
if ! grep -q "opcache.enable" "$PHP_INI"; then
    echo "" | sudo tee -a "$PHP_INI" >/dev/null
    echo "[opcache]" | sudo tee -a "$PHP_INI" >/dev/null
fi

sudo sed -i -E '/\[opcache\]/a \
opcache.enable=1\n\
opcache.enable_cli=0\n\
opcache.memory_consumption=256\n\
opcache.interned_strings_buffer=16\n\
opcache.max_accelerated_files=100000\n\
opcache.validate_timestamps=0\n\
opcache.revalidate_freq=0\n\
opcache.save_comments=1\n\
opcache.jit=0\n' "$PHP_INI"

# --- realpath cache (filesystem speed) ---
if ! grep -q "realpath_cache_size" "$PHP_INI"; then
  echo "realpath_cache_size = 4096k" | sudo tee -a "$PHP_INI" >/dev/null
  echo "realpath_cache_ttl = 600" | sudo tee -a "$PHP_INI" >/dev/null
fi

# ---------------------------
# PHP-FPM Configuration
# ---------------------------
echo "▶ Configuring PHP-FPM pool..."

sudo sed -i 's/^user = .*/user = http/' "$FPM_POOL"
sudo sed -i 's/^group = .*/group = http/' "$FPM_POOL"
sudo sed -i 's~^;?listen = .*~listen = /run/php-fpm/php-fpm.sock~' "$FPM_POOL"

sudo sed -i -E 's/^;?pm = .*/pm = dynamic/' "$FPM_POOL"
sudo sed -i -E 's/^;?pm\.max_children = .*/pm.max_children = 20/' "$FPM_POOL"
sudo sed -i -E 's/^;?pm\.start_servers = .*/pm.start_servers = 4/' "$FPM_POOL"
sudo sed -i -E 's/^;?pm\.min_spare_servers = .*/pm.min_spare_servers = 4/' "$FPM_POOL"
sudo sed -i -E 's/^;?pm\.max_spare_servers = .*/pm.max_spare_servers = 10/' "$FPM_POOL"
sudo sed -i -E 's/^;?pm\.max_requests = .*/pm.max_requests = 500/' "$FPM_POOL"
sudo sed -i -E 's/^;?request_terminate_timeout = .*/request_terminate_timeout = 120s/' "$FPM_POOL"

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
echo "🎉 PHP + MariaDB setup complete! Optimized for WordPress 🚀"
echo "------------------------------------------------------------"
echo "MariaDB root password : ${DB_ROOT_PASS}"
echo "PHP-FPM socket        : /run/php-fpm/php-fpm.sock"
echo "PHP config file       : /etc/php/php.ini"
echo "PHP-FPM pool          : /etc/php/php-fpm.d/www.conf"
echo "MariaDB data dir      : /var/lib/mysql"
echo "Error log             : /var/log/php/errors.log"
echo "------------------------------------------------------------"
