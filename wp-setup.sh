#!/usr/bin/env bash
# ============================================================
# WordPress Auto Setup Script (for Arch + Nginx + WP-CLI)
# Author: Avijit Sarkar
# Version: 1.3
# ============================================================

set -euo pipefail

# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------
WWW_DIR="$HOME/devS/Www"
SITE_NAME="${1:-wordpress}"
SITE_DIR="$WWW_DIR/$SITE_NAME"
DB_NAME="$SITE_NAME"
SITE_URL="http://localhost/$SITE_NAME"
SITE_TITLE="My $SITE_NAME"
ADMIN_USER="admin"
ADMIN_PASS="123"
ADMIN_EMAIL="admin@example.com"

THEME="astra"
PLUGINS=("elementor" "classic-editor")

# ------------------------------------------------------------
# Colors
# ------------------------------------------------------------
C_RESET="\033[0m"
C_GREEN="\033[32m"
C_RED="\033[31m"
C_YELLOW="\033[33m"
C_BLUE="\033[34m"
C_GRAY="\033[90m"

# ------------------------------------------------------------
# Logging Setup (safe & sudo-aware)
# ------------------------------------------------------------
LOG_DIR="$WWW_DIR/_logs"
{
    mkdir -p "$LOG_DIR" 2>/dev/null || sudo mkdir -p "$LOG_DIR"
} &>/dev/null
sudo chown -R "$USER:$USER" "$LOG_DIR" 2>/dev/null || true
LOG_FILE="$LOG_DIR/${SITE_NAME}-$(date +%s).log"

# ------------------------------------------------------------
# Helper functions
# ------------------------------------------------------------
log() { echo -e "${C_GRAY}[$(date +%H:%M:%S)]${C_RESET} $1"; echo "[$(date)] $1" >> "$LOG_FILE"; }
success() { echo -e "${C_GREEN}✓${C_RESET} $1"; echo "[$(date)] [OK] $1" >> "$LOG_FILE"; }
error() { echo -e "${C_RED}✗${C_RESET} $1" >&2; echo "[$(date)] [ERROR] $1" >> "$LOG_FILE"; }

run() {
    local cmd="$1"
    local msg="$2"
    log "⟳ $msg"
    if eval "$cmd" >>"$LOG_FILE" 2>&1; then
        success "$msg"
    else
        error "Failed: $msg"
        echo "Check log: $LOG_FILE"
        exit 1
    fi
}

# ------------------------------------------------------------
# System Checks
# ------------------------------------------------------------
check_requirements() {
    echo -e "${C_BLUE}▶ Checking system requirements...${C_RESET}"
    for cmd in php mysql nginx; do
        if ! command -v "$cmd" &>/dev/null; then
            echo -e "${C_YELLOW}→ Installing $cmd...${C_RESET}"
            sudo pacman -S --needed --noconfirm "$cmd"
        fi
        success "$cmd is installed"
    done
}

check_wp_cli() {
    if ! command -v wp &>/dev/null; then
        echo -e "${C_YELLOW}⚙️  WP-CLI not found. Installing...${C_RESET}"
        sudo pacman -S --needed --noconfirm php curl wget
        curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
        chmod +x wp-cli.phar
        sudo mv wp-cli.phar /usr/local/bin/wp
    fi
    success "WP-CLI ready"
}

check_services() {
    echo -e "${C_BLUE}▶ Verifying services...${C_RESET}"
    for service in nginx php-fpm mariadb; do
        if ! systemctl is-active --quiet "$service"; then
            sudo systemctl enable --now "$service"
        fi
        success "$service running"
    done
}

# ------------------------------------------------------------
# Secure MySQL Setup / Password Prompt
# ------------------------------------------------------------
setup_mysql_password() {
    echo -e "${C_BLUE}▶ Checking MySQL authentication...${C_RESET}"

    if sudo mysql -e "SELECT 1;" &>/dev/null; then
        echo -e "${C_YELLOW}⚙️  Detected socket authentication for root.${C_RESET}"
        read -rsp "Enter new MySQL root password: " DB_PASS
        echo
        sudo mysql <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_PASS}';
FLUSH PRIVILEGES;
EOF
        success "MySQL root password set successfully."
    fi
}

prompt_mysql_password() {
    local tries=0
    while (( tries < 3 )); do
        read -rsp "Enter MySQL root password: " DB_PASS
        echo
        if mysql -u root -p"$DB_PASS" -e "SELECT 1;" &>/dev/null; then
            success "MySQL root password verified."
            return 0
        else
            echo -e "${C_RED}✗ Incorrect password. Try again.${C_RESET}"
            ((tries++))
        fi
    done
    error "Too many failed attempts. Exiting."
    exit 1
}

# ------------------------------------------------------------
# Database handling
# ------------------------------------------------------------
ensure_database() {
    echo -e "${C_BLUE}▶ Checking database...${C_RESET}"

    if mysql -u root -p"$DB_PASS" -e "USE $DB_NAME;" &>/dev/null; then
        echo -e "${C_YELLOW}⚠️  Database '$DB_NAME' already exists. Skipping creation.${C_RESET}"
    else
        run "mysql -u root -p$DB_PASS -e 'CREATE DATABASE $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;'" \
            "Create database $DB_NAME"
    fi
}

# ------------------------------------------------------------
# Main Setup
# ------------------------------------------------------------
clear
echo -e "${C_BLUE}▶ WordPress Setup${C_RESET} → ${C_YELLOW}$SITE_NAME${C_RESET}\n"
log "=== Starting WordPress setup for $SITE_NAME ==="

check_requirements
check_wp_cli
check_services

# Secure MySQL (if using socket auth)
setup_mysql_password
# Ask for MySQL password (always verifies)
prompt_mysql_password
ensure_database

mkdir -p "$SITE_DIR"
cd "$SITE_DIR"

run "wp core download --quiet" "Download WordPress core"
run "wp config create --dbname=$DB_NAME --dbuser=root --dbpass=$DB_PASS --skip-check --force --quiet" "Create wp-config.php"
run "wp core install --url=$SITE_URL --title='$SITE_TITLE' --admin_user=$ADMIN_USER --admin_password=$ADMIN_PASS --admin_email=$ADMIN_EMAIL --skip-email --quiet" "Install WordPress"
run "wp rewrite structure '/%postname%/' --hard --quiet" "Set permalink structure"

if [[ "$THEME" != "default" && -n "$THEME" ]]; then
    run "wp theme install $THEME --activate --quiet" "Install and activate theme ($THEME)"
    run "wp theme delete $(wp theme list --status=inactive --field=name)" "Remove unused themes"
else
    log "Using default theme"
fi

if (( ${#PLUGINS[@]} > 0 )); then
    for plugin in "${PLUGINS[@]}"; do
        run "wp plugin install $plugin --activate --quiet" "Install plugin ($plugin)"
    done
    run "wp plugin delete hello akismet --quiet" "Remove default plugins"
else
    log "No plugins to install"
fi

run "wp option update blogdescription 'Built with WordPress, $THEME & ${PLUGINS[*]}' --quiet" "Update site tagline"
run "wp option update timezone_string 'Asia/Kolkata' --quiet" "Set timezone"

success "WordPress setup complete!"
echo -e "\n${C_GREEN}Site:${C_RESET}     $SITE_URL"
echo -e "${C_GREEN}Admin:${C_RESET}    $SITE_URL/wp-admin"
echo -e "${C_GREEN}User:${C_RESET}     $ADMIN_USER"
echo -e "${C_GREEN}Pass:${C_RESET}     $ADMIN_PASS"
echo -e "${C_GREEN}Theme:${C_RESET}    ${THEME:-default}"
[[ ${#PLUGINS[@]} -gt 0 ]] && echo -e "${C_GREEN}Plugins:${C_RESET}  ${PLUGINS[*]}"
echo -e "${C_GRAY}Log:${C_RESET}      $LOG_FILE\n"

log "Setup completed successfully"
