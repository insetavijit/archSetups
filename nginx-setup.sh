#!/usr/bin/env bash
# ============================================================
# Modular Nginx setup for Arch Linux (with directory listing)
# Author: Avijit Sarkar
# Version: 1.1
# ============================================================

set -euo pipefail

echo "▶ Installing Nginx..."
sudo pacman -S --needed --noconfirm nginx

echo "▶ Creating modular directory structure..."
sudo mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled
sudo mkdir -p /srv/http

# ------------------------------------------------------------
# Barebone nginx.conf
# ------------------------------------------------------------
echo "▶ Writing barebone /etc/nginx/nginx.conf"
sudo tee /etc/nginx/nginx.conf >/dev/null <<'EOF'
# ============================================================
# Barebone modular Nginx config for Arch Linux + PHP-FPM
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
# Default site configuration
# ------------------------------------------------------------
echo "▶ Creating default site config with directory listing..."
sudo tee /etc/nginx/sites-available/default.conf >/dev/null <<'EOF'
# ============================================================
# Default Nginx site for Arch Linux (with directory listing)
# ============================================================

server {
    listen 80 default_server;
    server_name _ localhost;

    root /srv/http;
    index index.php index.html;

    access_log /var/log/nginx/default_access.log;
    error_log  /var/log/nginx/default_error.log;

    # Directory listing (autoindex)
    location / {
        autoindex on;
        autoindex_exact_size off;
        autoindex_localtime on;
        try_files $uri $uri/ =404;
    }

    # PHP-FPM integration
    location ~ \.php$ {
        include fastcgi_params;
        fastcgi_pass unix:/run/php-fpm/php-fpm.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
        fastcgi_param DOCUMENT_ROOT $realpath_root;
    }

    # Security
    location ~ /\.ht {
        deny all;
    }

    location ~ /\.(git|svn|hg) {
        deny all;
    }
}
EOF

# Enable default site
sudo ln -sf /etc/nginx/sites-available/default.conf /etc/nginx/sites-enabled/default.conf

# ------------------------------------------------------------
# Default index and sample directories
# ------------------------------------------------------------
echo "▶ Creating sample directories..."
sudo mkdir -p /srv/http/dir1 /srv/http/dir2
echo "This is dir1" | sudo tee /srv/http/dir1/index.html >/dev/null
echo "This is dir2" | sudo tee /srv/http/dir2/index.html >/dev/null

echo "<?php phpinfo(); ?>" | sudo tee /srv/http/index.php >/dev/null
sudo chown -R http:http /srv/http

# ------------------------------------------------------------
# Start / Enable Service
# ------------------------------------------------------------
echo "▶ Enabling and starting Nginx..."
sudo systemctl enable --now nginx

# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------
echo ""
echo "🎉 Modular Nginx setup (with directory listing) complete!"
echo "------------------------------------------------------------"
echo "Main config:      /etc/nginx/nginx.conf"
echo "Sites available:  /etc/nginx/sites-available/"
echo "Sites enabled:    /etc/nginx/sites-enabled/"
echo "Root directory:   /srv/http/"
echo "Sample dirs:      /srv/http/dir1, /srv/http/dir2"
echo "Test URL:         http://localhost/"
echo "------------------------------------------------------------"
