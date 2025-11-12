#!/usr/bin/env bash
# ============================================================
# WordPress Auto Setup Script (for Arch + Nginx + WP-CLI)
# Author: Avijit Sarkar
# Version: 3.0 (Enhanced - No FTP Prompts)
# ============================================================

set -euo pipefail

# ------------------------------------------------------------
# Configuration
# ------------------------------------------------------------
WWW_DIR="$HOME/devS/Www"
SITE_NAME="${1:-}"
SITE_DIR="$WWW_DIR/$SITE_NAME"
DB_NAME="${SITE_NAME//-/_}" # Replace hyphens with underscores for MySQL
DB_USER="${2:-root}"
SITE_URL="http://localhost/$SITE_NAME"
SITE_TITLE="My $SITE_NAME"
ADMIN_USER="${3:-admin}"
ADMIN_PASS="${4:-123}"
ADMIN_EMAIL="${5:-admin@example.com}"

THEME="${6:-astra}"
PLUGINS=("elementor" "classic-editor")

# Script metadata
SCRIPT_VERSION="3.0"

# ------------------------------------------------------------
# Colors & Symbols
# ------------------------------------------------------------
C_RESET="\033[0m"
C_GREEN="\033[32m"
C_RED="\033[31m"
C_YELLOW="\033[33m"
C_BLUE="\033[34m"
C_CYAN="\033[36m"
C_GRAY="\033[90m"
C_BOLD="\033[1m"

# Unicode symbols
S_CHECK="✓"
S_CROSS="✗"
S_WARN="⚠"
S_ARROW="►"
S_SPIN="⟳"

# ------------------------------------------------------------
# Usage & Help
# ------------------------------------------------------------
show_usage() {
    cat << EOF
${C_BOLD}${C_CYAN}WordPress Auto Setup Script v${SCRIPT_VERSION}${C_RESET}

${C_CYAN}${C_BOLD}USAGE:${C_RESET}
  $0 <site_name> [db_user] [admin_user] [admin_pass] [admin_email] [theme]
  $0 --diagnose <site_name>
  $0 --remove <site_name>

${C_CYAN}${C_BOLD}EXAMPLES:${C_RESET}
  ${C_GRAY}# Quick setup with defaults${C_RESET}
  $0 mysite

  ${C_GRAY}# Full custom setup${C_RESET}
  $0 mysite root myadmin mypass123 me@example.com generatepress

  ${C_GRAY}# Diagnose existing site${C_RESET}
  $0 --diagnose mysite

  ${C_GRAY}# Remove a site completely${C_RESET}
  $0 --remove mysite

${C_CYAN}${C_BOLD}ARGUMENTS:${C_RESET}
  ${C_GREEN}site_name${C_RESET}    Required. Name of the WordPress site
  ${C_GREEN}db_user${C_RESET}      Optional. MySQL user (default: root)
  ${C_GREEN}admin_user${C_RESET}   Optional. WP admin username (default: admin)
  ${C_GREEN}admin_pass${C_RESET}   Optional. WP admin password (default: 123)
  ${C_GREEN}admin_email${C_RESET}  Optional. WP admin email (default: admin@example.com)
  ${C_GREEN}theme${C_RESET}        Optional. Theme slug to install (default: astra)

${C_CYAN}${C_BOLD}FEATURES:${C_RESET}
  ${S_ARROW} No FTP prompts - direct file system access
  ${S_ARROW} Automatic dependency installation
  ${S_ARROW} Secure MySQL setup
  ${S_ARROW} Smart Nginx configuration
  ${S_ARROW} Complete error handling & rollback
  ${S_ARROW} Detailed logging

${C_GRAY}Log directory: $WWW_DIR/_logs${C_RESET}
EOF
    exit 0
}

# ------------------------------------------------------------
# Diagnostics
# ------------------------------------------------------------
diagnose_site() {
    local site="$1"
    local site_dir="$WWW_DIR/$site"

    echo -e "${C_CYAN}${C_BOLD}╔═══════════════════════════════════════════╗"
    echo -e "║     Diagnosing Site: ${site}${C_RESET}"
    echo -e "${C_CYAN}${C_BOLD}╚═══════════════════════════════════════════╝${C_RESET}\n"

    # Directory Check
    echo -e "${C_BLUE}${C_BOLD}[1] Directory Structure${C_RESET}"
    if [[ -d "$site_dir" ]]; then
        echo -e "  ${C_GREEN}${S_CHECK}${C_RESET} Site directory exists: ${C_GRAY}$site_dir${C_RESET}"
        local dir_size=$(du -sh "$site_dir" 2>/dev/null | cut -f1)
        echo -e "  ${C_GREEN}${S_ARROW}${C_RESET} Size: $dir_size"
        echo -e "  ${C_GREEN}${S_ARROW}${C_RESET} Permissions: $(ls -ld "$site_dir" | awk '{print $1, $3":"$4}')"
    else
        echo -e "  ${C_RED}${S_CROSS}${C_RESET} Site directory not found"
        return 1
    fi

    # Configuration Check
    echo -e "\n${C_BLUE}${C_BOLD}[2] WordPress Configuration${C_RESET}"
    if [[ -f "$site_dir/wp-config.php" ]]; then
        echo -e "  ${C_GREEN}${S_CHECK}${C_RESET} wp-config.php exists"
        echo -e "\n  ${C_GRAY}Database Settings:${C_RESET}"
        grep -E "DB_NAME|DB_USER|DB_HOST|FS_METHOD" "$site_dir/wp-config.php" | sed 's/^/    /'
    else
        echo -e "  ${C_RED}${S_CROSS}${C_RESET} wp-config.php not found"
    fi

    # Database Check
    echo -e "\n${C_BLUE}${C_BOLD}[3] Database Connection${C_RESET}"
    cd "$site_dir" 2>/dev/null || return 1

    if wp db check --quiet 2>&1; then
        echo -e "  ${C_GREEN}${S_CHECK}${C_RESET} Database connection successful"

        if wp core is-installed 2>/dev/null; then
            echo -e "  ${C_GREEN}${S_CHECK}${C_RESET} WordPress is installed"
            local wp_version=$(wp core version 2>/dev/null)
            echo -e "  ${C_GREEN}${S_ARROW}${C_RESET} Version: $wp_version"
        else
            echo -e "  ${C_YELLOW}${S_WARN}${C_RESET} WordPress not installed in database"
        fi
    else
        echo -e "  ${C_RED}${S_CROSS}${C_RESET} Database connection failed"
    fi

    # Nginx Check
    echo -e "\n${C_BLUE}${C_BOLD}[4] Nginx Configuration${C_RESET}"
    if [[ -f "/etc/nginx/sites-available/$site.conf" ]]; then
        echo -e "  ${C_GREEN}${S_CHECK}${C_RESET} Nginx config exists"
        if [[ -L "/etc/nginx/sites-enabled/$site.conf" ]]; then
            echo -e "  ${C_GREEN}${S_CHECK}${C_RESET} Config is enabled"
        else
            echo -e "  ${C_YELLOW}${S_WARN}${C_RESET} Config not enabled"
        fi
    else
        echo -e "  ${C_RED}${S_CROSS}${C_RESET} Nginx config not found"
    fi

    echo -e "\n${C_GREEN}${C_BOLD}Diagnosis complete!${C_RESET}\n"
}

# ------------------------------------------------------------
# Site Removal
# ------------------------------------------------------------
remove_site() {
    local site="$1"
    local site_dir="$WWW_DIR/$site"
    local db_name="${site//-/_}"

    echo -e "${C_RED}${C_BOLD}⚠  WARNING: Site Removal${C_RESET}\n"
    echo -e "This will permanently delete:"
    echo -e "  ${S_ARROW} Directory: $site_dir"
    echo -e "  ${S_ARROW} Database: $db_name"
    echo -e "  ${S_ARROW} Nginx config\n"

    if ! confirm "Are you absolutely sure?" "n"; then
        warn "Removal cancelled"
        return 0
    fi

    # Remove directory
    if [[ -d "$site_dir" ]]; then
        rm -rf "$site_dir"
        success "Removed site directory"
    fi

    # Drop database
    if mysql -u root -e "USE $db_name;" &>/dev/null 2>&1; then
        mysql -u root -e "DROP DATABASE IF EXISTS $db_name;" &>/dev/null
        success "Dropped database"
    fi

    # Remove Nginx config
    if [[ -f "/etc/nginx/sites-available/$site.conf" ]]; then
        sudo rm -f "/etc/nginx/sites-available/$site.conf"
        sudo rm -f "/etc/nginx/sites-enabled/$site.conf"
        sudo nginx -t &>/dev/null && sudo systemctl reload nginx
        success "Removed Nginx config"
    fi

    success "Site removed completely"
}

# ------------------------------------------------------------
# Argument Parsing
# ------------------------------------------------------------
[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && show_usage
[[ "${1:-}" == "--version" ]] && { echo "WordPress Auto Setup Script v${SCRIPT_VERSION}"; exit 0; }
[[ "${1:-}" == "--diagnose" ]] && { diagnose_site "${2:-wordpress}"; exit 0; }
[[ "${1:-}" == "--remove" ]] && { remove_site "${2:-}"; exit 0; }

# Validate site name
if [[ -z "$SITE_NAME" ]]; then
    echo -e "${C_RED}Error: Site name is required${C_RESET}\n"
    show_usage
fi

if [[ ! "$SITE_NAME" =~ ^[a-zA-Z0-9-]+$ ]]; then
    echo -e "${C_RED}Invalid site name. Use only alphanumeric characters and hyphens.${C_RESET}"
    exit 1
fi

# ------------------------------------------------------------
# Logging Setup
# ------------------------------------------------------------
LOG_DIR="$WWW_DIR/_logs"
mkdir -p "$LOG_DIR" 2>/dev/null || sudo mkdir -p "$LOG_DIR"
sudo chown -R "$USER:$USER" "$LOG_DIR" 2>/dev/null || true
LOG_FILE="$LOG_DIR/${SITE_NAME}-$(date +%Y%m%d-%H%M%S).log"

# ------------------------------------------------------------
# Helper Functions
# ------------------------------------------------------------
log() {
    echo -e "${C_GRAY}[$(date +%H:%M:%S)]${C_RESET} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

success() {
    echo -e "${C_GREEN}${S_CHECK}${C_RESET} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [OK] $1" >> "$LOG_FILE"
}

error() {
    echo -e "${C_RED}${S_CROSS}${C_RESET} $1" >&2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" >> "$LOG_FILE"
}

warn() {
    echo -e "${C_YELLOW}${S_WARN}${C_RESET}  $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $1" >> "$LOG_FILE"
}

run() {
    local cmd="$1"
    local msg="$2"
    log "${S_SPIN} $msg"
    if eval "$cmd" >>"$LOG_FILE" 2>&1; then
        success "$msg"
        return 0
    else
        error "Failed: $msg"
        return 1
    fi
}

confirm() {
    local prompt="$1"
    local default="${2:-n}"
    local response

    if [[ "$default" == "y" ]]; then
        read -rp "$(echo -e "${C_YELLOW}${prompt}${C_RESET} [Y/n]: ")" response
        response="${response:-y}"
    else
        read -rp "$(echo -e "${C_YELLOW}${prompt}${C_RESET} [y/N]: ")" response
        response="${response:-n}"
    fi

    [[ "$response" =~ ^[Yy]$ ]]
}

cleanup_on_error() {
    error "Setup failed. Initiating cleanup..."

    if [[ -d "$SITE_DIR" ]]; then
        warn "Removing site directory: $SITE_DIR"
        rm -rf "$SITE_DIR"
    fi

    if mysql -u "$DB_USER" -p"${DB_PASS:-}" -e "USE $DB_NAME;" &>/dev/null 2>&1; then
        warn "Dropping database: $DB_NAME"
        mysql -u "$DB_USER" -p"${DB_PASS:-}" -e "DROP DATABASE IF EXISTS $DB_NAME;" &>/dev/null
    fi

    if [[ -f "/etc/nginx/sites-available/$SITE_NAME.conf" ]]; then
        warn "Removing Nginx config"
        sudo rm -f "/etc/nginx/sites-available/$SITE_NAME.conf"
        sudo rm -f "/etc/nginx/sites-enabled/$SITE_NAME.conf"
    fi

    error "Cleanup complete. Check log: $LOG_FILE"
    exit 1
}

trap cleanup_on_error ERR

# ------------------------------------------------------------
# System Setup Functions
# ------------------------------------------------------------
prepare_www_dir() {
    echo -e "\n${C_BLUE}${C_BOLD}▶ Preparing Project Environment${C_RESET}"

    if [[ ! -d "$WWW_DIR" ]]; then
        mkdir -p "$WWW_DIR"
        sudo chown -R "$USER:http" "$WWW_DIR"
        sudo chmod -R 775 "$WWW_DIR"
        success "Created $WWW_DIR with proper permissions"
    else
        success "WWW directory exists: $WWW_DIR"
    fi

    if [[ -d "$SITE_DIR" ]]; then
        if confirm "Site directory already exists. Remove and recreate?" "n"; then
            rm -rf "$SITE_DIR"
            mkdir -p "$SITE_DIR"
            success "Recreated site directory"
        else
            error "Cannot proceed with existing directory"
            exit 1
        fi
    else
        mkdir -p "$SITE_DIR"
        success "Created site directory: $SITE_DIR"
    fi
}

check_requirements() {
    echo -e "\n${C_BLUE}${C_BOLD}▶ Checking System Requirements${C_RESET}"

    local packages=("php" "php-fpm" "mariadb" "nginx" "curl" "wget")
    local missing=()

    for pkg in "${packages[@]}"; do
        if ! pacman -Qi "$pkg" &>/dev/null; then
            missing+=("$pkg")
        fi
    done

    if (( ${#missing[@]} > 0 )); then
        warn "Missing packages: ${missing[*]}"
        if confirm "Install missing packages?" "y"; then
            sudo pacman -S --needed --noconfirm "${missing[@]}"
            success "Installed missing packages"
        else
            error "Required packages not installed"
            exit 1
        fi
    else
        success "All required packages installed"
    fi

    # Check PHP extensions
    echo -e "\n${C_BLUE}${C_BOLD}▶ Verifying PHP Extensions${C_RESET}"
    local required_extensions=("mysqli" "pdo_mysql" "curl" "zip" "gd" "mbstring" "xml")
    local missing_extensions=()

    for ext in "${required_extensions[@]}"; do
        if ! php -m 2>/dev/null | grep -qi "^${ext}$"; then
            missing_extensions+=("$ext")
        fi
    done

    if (( ${#missing_extensions[@]} > 0 )); then
        warn "Missing PHP extensions: ${missing_extensions[*]}"

        local php_ini="/etc/php/php.ini"
        local needs_restart=0

        for ext in "${missing_extensions[@]}"; do
            if grep -q "^;extension=${ext}" "$php_ini" 2>/dev/null; then
                sudo sed -i "s/^;extension=${ext}/extension=${ext}/" "$php_ini"
                success "Enabled ${ext} in php.ini"
                needs_restart=1
            elif ! grep -q "^extension=${ext}" "$php_ini" 2>/dev/null; then
                echo "extension=${ext}" | sudo tee -a "$php_ini" >/dev/null
                success "Added ${ext} to php.ini"
                needs_restart=1
            fi
        done

        if (( needs_restart )); then
            sudo systemctl restart php-fpm
            sleep 2
            success "PHP-FPM restarted"
        fi
    else
        success "All PHP extensions available"
    fi
}

check_wp_cli() {
    echo -e "\n${C_BLUE}${C_BOLD}▶ Checking WP-CLI${C_RESET}"

    if ! command -v wp &>/dev/null; then
        warn "WP-CLI not found. Installing..."
        curl -sO https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
        chmod +x wp-cli.phar
        sudo mv wp-cli.phar /usr/local/bin/wp
        success "WP-CLI installed"
    else
        local version=$(wp --version 2>/dev/null | grep -oP '\d+\.\d+\.\d+' || echo "unknown")
        success "WP-CLI ready (version: $version)"
    fi
}

check_services() {
    echo -e "\n${C_BLUE}${C_BOLD}▶ Verifying Services${C_RESET}"

    local services=("nginx" "php-fpm" "mariadb")

    for service in "${services[@]}"; do
        if ! systemctl is-active --quiet "$service"; then
            warn "$service not running. Starting..."
            sudo systemctl enable --now "$service"
            sleep 1
        fi

        if systemctl is-active --quiet "$service"; then
            success "$service running"
        else
            error "$service failed to start"
            exit 1
        fi
    done
}

# ------------------------------------------------------------
# MySQL Setup Functions
# ------------------------------------------------------------
setup_mysql_password() {
    echo -e "\n${C_BLUE}${C_BOLD}▶ MySQL Authentication Setup${C_RESET}"

    if sudo mysql -e "SELECT 1;" &>/dev/null; then
        warn "Detected socket authentication for root"

        if confirm "Set MySQL root password?" "y"; then
            while true; do
                read -rsp "$(echo -e "${C_CYAN}Enter new MySQL root password:${C_RESET} ")" DB_PASS
                echo
                read -rsp "$(echo -e "${C_CYAN}Confirm password:${C_RESET} ")" DB_PASS_CONFIRM
                echo

                if [[ "$DB_PASS" == "$DB_PASS_CONFIRM" ]]; then
                    if [[ ${#DB_PASS} -lt 8 ]]; then
                        warn "Password should be at least 8 characters"
                        if ! confirm "Continue anyway?" "n"; then
                            continue
                        fi
                    fi

                    sudo mysql <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_PASS}';
FLUSH PRIVILEGES;
EOF
                    success "MySQL root password set successfully"
                    return 0
                else
                    error "Passwords don't match. Try again."
                fi
            done
        fi
    fi
}

prompt_mysql_password() {
    echo -e "\n${C_BLUE}${C_BOLD}▶ MySQL Authentication${C_RESET}"

    local tries=0
    while (( tries < 3 )); do
        read -rsp "$(echo -e "${C_CYAN}Enter MySQL password for user '$DB_USER':${C_RESET} ")" DB_PASS
        echo

        if mysql -u "$DB_USER" -p"$DB_PASS" -e "SELECT 1;" &>/dev/null 2>&1; then
            success "MySQL authentication successful"
            return 0
        else
            error "Authentication failed"
            ((tries++))
            [[ $tries -lt 3 ]] && warn "Attempts remaining: $((3 - tries))"
        fi
    done

    error "Too many failed attempts"
    exit 1
}

ensure_database() {
    echo -e "\n${C_BLUE}${C_BOLD}▶ Database Setup${C_RESET}"

    if mysql -u "$DB_USER" -p"$DB_PASS" -e "USE $DB_NAME;" &>/dev/null 2>&1; then
        warn "Database '$DB_NAME' already exists"

        if confirm "Drop and recreate database?" "n"; then
            run "mysql -u $DB_USER -p$DB_PASS -e 'DROP DATABASE $DB_NAME;'" \
                "Drop existing database"
            run "mysql -u $DB_USER -p$DB_PASS -e 'CREATE DATABASE $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;'" \
                "Create database $DB_NAME"
        else
            warn "Using existing database (may cause conflicts)"
        fi
    else
        run "mysql -u $DB_USER -p$DB_PASS -e 'CREATE DATABASE $DB_NAME CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;'" \
            "Create database $DB_NAME"
    fi
}

# ------------------------------------------------------------
# Nginx Configuration
# ------------------------------------------------------------
setup_nginx() {
    echo -e "\n${C_BLUE}${C_BOLD}▶ Configuring Nginx${C_RESET}"

    local nginx_conf="/etc/nginx/sites-available/$SITE_NAME.conf"
    local nginx_enabled="/etc/nginx/sites-enabled/$SITE_NAME.conf"

    # Create directories if they don't exist
    sudo mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled

    # Check if sites-enabled is included in main nginx.conf
    if ! grep -q "sites-enabled" /etc/nginx/nginx.conf; then
        warn "Adding sites-enabled to nginx.conf"
        sudo sed -i '/http {/a \    include /etc/nginx/sites-enabled/*;' /etc/nginx/nginx.conf
    fi

    sudo tee "$nginx_conf" > /dev/null <<EOF
server {
    listen 80;
    server_name localhost;
    root $SITE_DIR;
    index index.php index.html;

    location /$SITE_NAME {
        alias $SITE_DIR;
        try_files \$uri \$uri/ /$SITE_NAME/index.php?\$args;

        location ~ \.php$ {
            include fastcgi_params;
            fastcgi_pass unix:/run/php-fpm/php-fpm.sock;
            fastcgi_param SCRIPT_FILENAME \$request_filename;
            fastcgi_index index.php;
        }
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

    sudo ln -sf "$nginx_conf" "$nginx_enabled"

    if sudo nginx -t &>/dev/null; then
        sudo systemctl reload nginx
        success "Nginx configured and reloaded"
    else
        error "Nginx configuration test failed"
        return 1
    fi
}

# ------------------------------------------------------------
# WordPress Installation
# ------------------------------------------------------------
install_wordpress() {
    echo -e "\n${C_BLUE}${C_BOLD}▶ Installing WordPress${C_RESET}"

    cd "$SITE_DIR"

    run "wp core download --path=$SITE_DIR --quiet" \
        "Download WordPress core" || return 1

    run "wp config create --dbname=$DB_NAME --dbuser=$DB_USER --dbpass=$DB_PASS --skip-check --force --quiet" \
        "Create wp-config.php" || return 1

    # Disable FTP prompts by setting direct file access
    log "Configuring direct file system access (no FTP prompts)..."
    wp config set FS_METHOD 'direct' --quiet
    wp config set FS_CHMOD_DIR 0755 --raw --quiet
    wp config set FS_CHMOD_FILE 0644 --raw --quiet
    success "Disabled FTP prompts (set FS_METHOD to 'direct')"

    # Test database connection
    log "Testing database connection..."
    if ! wp db check --quiet 2>/dev/null; then
        error "Database connection failed"
        wp db check 2>&1 | tee -a "$LOG_FILE"
        return 1
    fi
    success "Database connection verified"

    # Check if WordPress is already installed
    if wp core is-installed 2>/dev/null; then
        warn "WordPress is already installed in the database"
        if confirm "Reinstall WordPress (will erase existing data)?" "n"; then
            run "wp db reset --yes --quiet" "Reset database"
        else
            error "Cannot proceed with existing installation"
            return 1
        fi
    fi

    # Install WordPress
    log "Installing WordPress..."
    if ! wp core install \
        --url="$SITE_URL" \
        --title="$SITE_TITLE" \
        --admin_user="$ADMIN_USER" \
        --admin_password="$ADMIN_PASS" \
        --admin_email="$ADMIN_EMAIL" \
        --skip-email 2>&1 | tee -a "$LOG_FILE"; then
        error "WordPress installation failed"
        return 1
    fi
    success "WordPress installed"

    run "wp rewrite structure '/%postname%/' --hard --quiet" \
        "Set permalink structure" || return 1
}

setup_theme() {
    echo -e "\n${C_BLUE}${C_BOLD}▶ Setting up Theme${C_RESET}"

    if [[ "$THEME" != "default" && -n "$THEME" ]]; then
        if run "wp theme install $THEME --activate --quiet" "Install and activate theme ($THEME)"; then
            # Remove unused default themes
            local inactive_themes
            inactive_themes=$(wp theme list --status=inactive --field=name 2>/dev/null || echo "")
            if [[ -n "$inactive_themes" ]]; then
                run "wp theme delete $inactive_themes --quiet" "Remove unused themes" || warn "Could not remove some themes"
            fi
        else
            warn "Theme installation failed. Using default theme."
        fi
    else
        log "Using default theme"
    fi
}

setup_plugins() {
    echo -e "\n${C_BLUE}${C_BOLD}▶ Setting up Plugins${C_RESET}"

    if (( ${#PLUGINS[@]} > 0 )); then
        for plugin in "${PLUGINS[@]}"; do
            run "wp plugin install $plugin --activate --quiet" \
                "Install plugin ($plugin)" || warn "Plugin $plugin installation failed"
        done

        # Remove default plugins
        run "wp plugin delete hello akismet --quiet" \
            "Remove default plugins" || warn "Could not remove default plugins"
    else
        log "No additional plugins to install"
    fi
}

finalize_setup() {
    echo -e "\n${C_BLUE}${C_BOLD}▶ Finalizing Setup${C_RESET}"

    local plugin_list="${PLUGINS[*]:-none}"
    run "wp option update blogdescription 'Built with WordPress, $THEME & $plugin_list' --quiet" \
        "Update site tagline"

    run "wp option update timezone_string 'Asia/Kolkata' --quiet" \
        "Set timezone"

    # Set proper permissions to avoid FTP prompts
    log "Setting file permissions for direct access..."

    # Set ownership
    sudo chown -R "$USER:http" "$SITE_DIR"

    # Set directory permissions
    sudo chmod -R 755 "$SITE_DIR"

    # Set specific write permissions for wp-content
    sudo chmod -R 775 "$SITE_DIR/wp-content"

    # Ensure subdirectories are writable
    for dir in plugins themes uploads upgrade; do
        if [[ -d "$SITE_DIR/wp-content/$dir" ]]; then
            sudo chmod -R 775 "$SITE_DIR/wp-content/$dir"
        fi
    done

    success "Set proper file permissions (no FTP prompts)"

    # Verify FS_METHOD is set
    local fs_method=$(wp config get FS_METHOD --quiet 2>/dev/null || echo "not set")
    if [[ "$fs_method" == "direct" ]]; then
        success "Direct file system access confirmed"
    else
        warn "FS_METHOD not properly set, adding manually..."
        wp config set FS_METHOD 'direct' --quiet
    fi
}

# ------------------------------------------------------------
# Main Execution
# ------------------------------------------------------------
main() {
    clear
    echo -e "${C_BOLD}${C_CYAN}"
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║      WordPress Auto Setup Script v${SCRIPT_VERSION}            ║"
    echo "║            No FTP Prompts Edition                    ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo -e "${C_RESET}"
    echo -e "${C_BLUE}Site:${C_RESET}  ${C_BOLD}$SITE_NAME${C_RESET}"
    echo -e "${C_BLUE}Path:${C_RESET}  $SITE_DIR"
    echo -e "${C_BLUE}URL:${C_RESET}   $SITE_URL\n"

    log "=== Starting WordPress setup for $SITE_NAME ==="

    check_requirements
    check_wp_cli
    check_services
    prepare_www_dir

    setup_mysql_password
    prompt_mysql_password
    ensure_database

    install_wordpress
    setup_nginx
    setup_theme
    setup_plugins
    finalize_setup

    # Success summary
    echo -e "\n${C_GREEN}${C_BOLD}╔══════════════════════════════════════════════════════╗"
    echo -e "║         Setup Completed Successfully!                ║"
    echo -e "╚══════════════════════════════════════════════════════╝${C_RESET}\n"

    echo -e "${C_CYAN}${C_BOLD}Site Details:${C_RESET}"
    echo -e "  ${C_GREEN}${S_ARROW}${C_RESET} URL:       $SITE_URL"
    echo -e "  ${C_GREEN}${S_ARROW}${C_RESET} Admin:     $SITE_URL/wp-admin"
    echo -e "  ${C_GREEN}${S_ARROW}${C_RESET} Username:  $ADMIN_USER"
    echo -e "  ${C_GREEN}${S_ARROW}${C_RESET} Password:  $ADMIN_PASS"
    echo -e "  ${C_GREEN}${S_ARROW}${C_RESET} Email:     $ADMIN_EMAIL"
    echo -e "  ${C_GREEN}${S_ARROW}${C_RESET} Theme:     ${THEME:-default}"
    [[ ${#PLUGINS[@]} -gt 0 ]] && echo -e "  ${C_GREEN}${S_ARROW}${C_RESET} Plugins:   ${PLUGINS[*]}"
    echo -e "  ${C_GRAY}${S_ARROW}${C_RESET} Log:       $LOG_FILE"

    echo -e "\n${C_YELLOW}${C_BOLD}Next Steps:${C_RESET}"
    echo -e "  ${C_CYAN}1.${C_RESET} Visit $SITE_URL to see your site"
    echo -e "  ${C_CYAN}2.${C_RESET} Login at $SITE_URL/wp-admin"
    echo -e "  ${C_CYAN}3.${C_RESET} Install plugins/themes directly (no FTP prompts!)"
    echo -e "  ${C_CYAN}4.${C_RESET} Start building!\n"

    echo -e "${C_GREEN}${C_BOLD}✓ No FTP credentials required - direct file access enabled!${C_RESET}\n"

    log "Setup completed successfully"
}

# Run main function
main
