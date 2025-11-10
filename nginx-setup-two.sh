#!/usr/bin/env bash
# ============================================================
# Modular Nginx setup for Arch Linux (with /home/avijit/devS/Www as root)
# Author: Avijit Sarkar
# Version: 1.2
# ============================================================

set -euo pipefail

# ------------------------------------------------------------
# Variables
# ------------------------------------------------------------
DEV_WWW="/home/avijit/devS/Www"
HTTP_ROOT="/srv/http"
NGINX_AVAILABLE="/etc/nginx/sites-available"
NGINX_ENABLED="/etc/nginx/sites-enabled"

echo "▶ Installing Nginx..."
sudo pacman -S --needed --noconfirm nginx

echo "▶ Creating modular directory structure..."
sudo mkdir -p "$NGINX_AVAILABLE" "$NGINX_ENABLED" "$HTTP_ROOT"

# ------------------------------------------------------------
# 🧩 Create /home/avijit/devS/Www and symlink to /srv/http/Www
# ------------------------------------------------------------
echo "▶ Setting up Www symlink..."
mkdir -p "$DEV_WWW"

# Ensure proper permissions for Nginx access
sudo chmod o+rx /home /home/avijit /home/avijit/devS "$DEV_WWW"

# Create symlink
if [ ! -L "$HTTP_ROOT/Www" ]; then
  sudo ln -s "$DEV_WWW" "$HTTP_ROOT/Www"
fi

# ------------------------------------------------------------
# 🧠 Barebone nginx.conf
# ------------------------------------------------------------
echo "▶ Writing /etc/nginx/nginx.conf ..."
sudo tee /etc/nginx/nginx.conf >/dev/null <<'EOF'
# ============================================================
# Barebone modular Nginx config for Arch Linux
# ============================================================

user http;
worker_processes auto;
pid /run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include       mime.types;
    default_type  application/octet-stream;

    sendfile        on;
    tcp_nopush      on;
    tcp_nodelay     on;
    keepalive_timeout 65;
    types_hash_max_size 4096;

    server_tokens off;

    access_log /var/log/nginx/access.log;
    error_log  /var/log/nginx/error.log;

    gzip on;
    gzip_types text/plain text/css application/json application/javascript application/xml image/svg+xml;

    # Modular site includes
    include /etc/nginx/sites-enabled/*.conf;
}
EOF

# ------------------------------------------------------------
# 🌐 Default site configuration
# ------------------------------------------------------------
echo "▶ Creating default site config with directory listing..."
sudo tee "$NGINX_AVAILABLE/default.conf" >/dev/null <<'EOF'
# ============================================================
# Default Nginx site (Directory listing for ~/devS/Www)
# ============================================================

server {
    listen 80 default_server;
    server_name _ localhost;

    root /srv/http/Www;
    index index.php index.html index.htm;

    access_log /var/log/nginx/default_access.log;
    error_log  /var/log/nginx/default_error.log;

    # -------------------------------------------------
    # 📂 Directory listing
    # -------------------------------------------------
    location / {
        autoindex on;
        autoindex_exact_size off;
        autoindex_localtime on;
        try_files $uri $uri/ =404;
    }

    # -------------------------------------------------
    # ⚙️ PHP-FPM integration (optional for WordPress)
    # -------------------------------------------------
    location ~ \.php$ {
        include fastcgi_params;
        fastcgi_pass unix:/run/php-fpm/php-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
        fastcgi_param DOCUMENT_ROOT $realpath_root;
    }

    # -------------------------------------------------
    # 🔒 Security
    # -------------------------------------------------
    location ~ /\.ht {
        deny all;
    }

    location ~ /\.(git|svn|hg) {
        deny all;
    }

    add_header Cache-Control "no-store";
}
EOF

# ------------------------------------------------------------
# Enable default site
# ------------------------------------------------------------
sudo ln -sf "$NGINX_AVAILABLE/default.conf" "$NGINX_ENABLED/default.conf"

# ------------------------------------------------------------
# 🧱 Create sample dirs and index file for test
# ------------------------------------------------------------
echo "▶ Creating sample directories..."
sudo mkdir -p "$DEV_WWW/test1" "$DEV_WWW/test2"
echo "This is test1" | sudo tee "$DEV_WWW/test1/index.html" >/dev/null
echo "This is test2" | sudo tee "$DEV_WWW/test2/index.html" >/dev/null
echo "<?php phpinfo(); ?>" | sudo tee "$DEV_WWW/index.php" >/dev/null
sudo chown -R http:http "$DEV_WWW"

# ------------------------------------------------------------
# 🚀 Start and enable Nginx
# ------------------------------------------------------------
echo "▶ Enabling and starting Nginx..."
sudo systemctl enable --now nginx

# ------------------------------------------------------------
# ✅ Summary
# ------------------------------------------------------------
echo ""
echo "🎉 Modular Nginx setup (with directory listing) complete!"
echo "------------------------------------------------------------"
echo "Main config:      /etc/nginx/nginx.conf"
echo "Sites available:  $NGINX_AVAILABLE"
echo "Sites enabled:    $NGINX_ENABLED"
echo "Root directory:   $HTTP_ROOT/Www → $DEV_WWW"
echo "Sample dirs:      $DEV_WWW/test1, $DEV_WWW/test2"
echo "Test URL:         http://localhost/"
echo "------------------------------------------------------------"
