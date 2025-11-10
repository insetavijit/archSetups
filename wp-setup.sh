#!/usr/bin/env bash
# ============================================================
# WordPress Auto Setup Script (for Arch + Nginx + WP-CLI)
# Author: Avijit Sarkar
# Version: 2.0 (Enhanced with better error handling & features)
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

# ------------------------------------------------------------
# Colors
# ------------------------------------------------------------
C_RESET="\033[0m"
C_GREEN="\033[32m"
C_RED="\033[31m"
C_YELLOW="\033[33m"
C_BLUE="\033[34m"
C_CYAN="\033[36m"
C_GRAY="\033[90m"
C_BOLD="\033[1m"

# ------------------------------------------------------------
# Usage
# ------------------------------------------------------------
show_usage() {
    cat << EOF
${C_BOLD}WordPress Auto Setup Script${C_RESET}

${C_CYAN}Usage:${C_RESET}
  $0 <site_name> [db_user] [admin_user] [admin_pass] [admin_email] [theme]
  $0 --diagnose <site_name>

${C_CYAN}Examples:${C_RESET}
  $0 mysite
  $0 mysite root myadmin mypass123 me@example.com generatepress
  $0 --diagnose mysite

${C_CYAN}Arguments:${C_RESET}
  site_name    - Required. Name of the WordPress site
  db_user      - Optional. MySQL user (default: root)
  admin_user   - Optional. WP admin username (default: admin)
  admin_pass   - Optional. WP admin password (default: 123)
  admin_email  - Optional. WP admin email (default: admin@example.com)
  theme        - Optional. Theme to install (default: astra)

${C_CYAN}Options:${C_RESET}
  --diagnose   - Run diagnostics on an existing installation
  -h, --help   - Show this help message

${C_CYAN}Features:${C_RESET}
  • Automatic dependency installation
  • MySQL setup with secure password handling
  • Nginx configuration generation
  • Detailed logging
  • Rollback on failure

${C_GRAY}Log directory: $WWW_DIR/_logs${C_RESET}
EOF
    exit 0
}

diagnose_site() {
    local site="$1"
    local site_dir="$WWW_DIR/$site"

    echo -e "${C_CYAN}${C_BOLD}Diagnosing site: $site${C_RESET}\n"

    # Check directory
    echo -e "${C_BLUE}Directory Check:${C_RESET}"
    if [[ -d "$site_dir" ]]; then
        echo -e "  ${C_GREEN}✓${C_RESET} Site directory exists: $site_dir"
        ls -lah "$site_dir" | head -10
    else
        echo -e "  ${C_RED}✗${C_RESET} Site directory not found: $site_dir"
        return 1
    fi

    # Check wp-config.php
    echo -e "\n${C_BLUE}Configuration Check:${C_RESET}"
    if [[ -f "$site_dir/wp-config.php" ]]; then
        echo -e "  ${C_GREEN}✓${C_RESET} wp-config.php exists"
        echo -e "\n  Database settings:"
        grep -E "DB_NAME|DB_USER|DB_HOST|table_prefix" "$site_dir/wp-config.php"
    else
        echo -e "  ${C_RED}✗${C_RESET} wp-config.php not found"
    fi

    # Check database
    echo -e "\n${C_BLUE}Database Check:${C_RESET}"
    cd "$site_dir"
    if wp db check 2>&1; then
        echo -e "  ${C_GREEN}✓${C_RESET} Database connection successful"

        # Check if installed
        if wp core is-installed 2>/dev/null; then
            echo -e "  ${C_GREEN}✓${C_RESET} WordPress is installed"
            wp core version
        else
            echo -e "  ${C_YELLOW}⚠${C_RESET}  WordPress not installed in database"
        fi
    else
        echo -e "  ${C_RED}✗${C_RESET} Database connection failed"
    fi

    # Check Nginx
    echo -e "\n${C_BLUE}Nginx Check:${C_RESET}"
    if [[ -f "/etc/nginx/sites-available/$site.conf" ]]; then
        echo -e "  ${C_GREEN}✓${C_RESET} Nginx config exists"
        if [[ -L "/etc/nginx/sites-enabled/$site.conf" ]]; then
            echo -e "  ${C_GREEN}✓${C_RESET} Nginx config enabled"
        else
            echo -e "  ${C_YELLOW}⚠${C_RESET}  Nginx config not enabled"
        fi
    else
        echo -e "  ${C_RED}✗${C_RESET} Nginx config not found"
    fi

    # Check permissions
    echo -e "\n${C_BLUE}Permission Check:${C_RESET}"
    ls -ld "$site_dir"

    echo -e "\n${C_CYAN}Latest log file:${C_RESET}"
    local latest_log=$(ls -t "$WWW_DIR/_logs/$site"*.log 2>/dev/null | head -1)
    if [[ -n "$latest_log" ]]; then
        echo "$latest_log"
        echo -e "\nLast 20 lines:"
        tail -20 "$latest_log"
    else
        echo "No log files found"
    fi
}

[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && show_usage
[[ "${1:-}" == "--diagnose" ]] && { diagnose_site "${2:-wordpress}"; exit 0; }
[[ -z "$SITE_NAME" ]] && { echo -e "${C_RED}Error: Site name is required${C_RESET}\n"; show_usage; }

# ------------------------------------------------------------
# Logging Setup
# ------------------------------------------------------------
LOG_DIR="$WWW_DIR/_logs"
mkdir -p "$LOG_DIR" 2>/dev/null || sudo mkdir -p "$LOG_DIR"
sudo chown -R "$USER:$USER" "$LOG_DIR" 2>/dev/null || true
LOG_FILE="$LOG_DIR/${SITE_NAME}-$(date +%Y%m%d-%H%M%S).log"

# ------------------------------------------------------------
# Helper functions
# ------------------------------------------------------------
log() {
    echo -e "${C_GRAY}[$(date +%H:%M:%S)]${C_RESET} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

success() {
    echo -e "${C_GREEN}✓${C_RESET} $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [OK] $1" >> "$LOG_FILE"
}

error() {
    echo -e "${C_RED}✗${C_RESET} $1" >&2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" >> "$LOG_FILE"
}

warn() {
    echo -e "${C_YELLOW}⚠${C_RESET}  $1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $1" >> "$LOG_FILE"
}

run() {
    local cmd="$1"
    local msg="$2"
    log "⟳ $msg"
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
        read -rp "$prompt [Y/n]: " response
        response="${response:-y}"
    else
        read -rp "$prompt [y/N]: " response
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

    if mysql -u "$DB_USER" -p"$DB_PASS" -e "USE $DB_NAME;" &>/dev/null 2>&1; then
        warn "Dropping database: $DB_NAME"
        mysql -u "$DB_USER" -p"$DB_PASS" -e "DROP DATABASE IF EXISTS $DB_NAME;" &>/dev/null
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
# Environment Setup
# ------------------------------------------------------------
prepare_www_dir() {
    echo -e "\n${C_BLUE}${C_BOLD}▶ Preparing project root...${C_RESET}"

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
            success "Recreated site directory: $SITE_DIR"
        else
            error "Cannot proceed with existing directory"
            exit 1
        fi
    else
        mkdir -p "$SITE_DIR"
        success "Created site directory: $SITE_DIR"
    fi
}

# ------------------------------------------------------------
# System Checks
# ------------------------------------------------------------
check_requirements() {
    echo -e "\n${C_BLUE}${C_BOLD}▶ Checking system requirements...${C_RESET}"

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

    # Check PHP MySQL extensions
    echo -e "\n${C_BLUE}${C_BOLD}▶ Checking PHP extensions...${C_RESET}"
    local required_extensions=("mysqli" "pdo_mysql")
    local missing_extensions=()

    for ext in "${required_extensions[@]}"; do
        if ! php -m 2>/dev/null | grep -q "^${ext}$"; then
            missing_extensions+=("$ext")
        fi
    done

    if (( ${#missing_extensions[@]} > 0 )); then
        warn "Missing PHP extensions: ${missing_extensions[*]}"
        warn "Attempting to enable extensions in php.ini..."

        local php_ini="/etc/php/php.ini"
        local needs_restart=0

        for ext in "${missing_extensions[@]}"; do
            if grep -q "^;extension=${ext}" "$php_ini" 2>/dev/null; then
                sudo sed -i "s/^;extension=${ext}/extension=${ext}/" "$php_ini"
                success "Enabled ${ext} in php.ini"
                needs_restart=1
            elif grep -q "^extension=${ext}" "$php_ini" 2>/dev/null; then
                warn "${ext} already enabled in php.ini but not loaded"
                needs_restart=1
            else
                warn "${ext} not found in php.ini, adding it..."
                echo "extension=${ext}" | sudo tee -a "$php_ini" >/dev/null
                success "Added ${ext} to php.ini"
                needs_restart=1
            fi
        done

        if (( needs_restart )); then
            warn "Restarting PHP-FPM to load extensions..."
            sudo systemctl restart php-fpm
            sleep 2

            # Verify extensions are now loaded
            local still_missing=()
            for ext in "${missing_extensions[@]}"; do
                if ! php -m 2>/dev/null | grep -q "^${ext}$"; then
                    still_missing+=("$ext")
                fi
            done

            if (( ${#still_missing[@]} > 0 )); then
                error "Failed to load extensions: ${still_missing[*]}"
                warn "Please manually enable these extensions in $php_ini"
                exit 1
            else
                success "All PHP extensions loaded successfully"
            fi
        fi
    else
        success "All required PHP extensions available"
    fi
}

check_wp_cli() {
    echo -e "\n${C_BLUE}${C_BOLD}▶ Checking WP-CLI...${C_RESET}"

    if ! command -v wp &>/dev/null; then
        warn "WP-CLI not found. Installing..."
        curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
        chmod +x wp-cli.phar
        sudo mv wp-cli.phar /usr/local/bin/wp
        success "WP-CLI installed"
    else
        local version
        version=$(wp --version | grep -oP '\d+\.\d+\.\d+' || echo "unknown")
        success "WP-CLI ready (version: $version)"
    fi
}

check_services() {
    echo -e "\n${C_BLUE}${C_BOLD}▶ Verifying services...${C_RESET}"

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
# MySQL Setup
# ------------------------------------------------------------
setup_mysql_password() {
    echo -e "\n${C_BLUE}${C_BOLD}▶ Checking MySQL authentication...${C_RESET}"

    if sudo mysql -e "SELECT 1;" &>/dev/null; then
        warn "Detected socket authentication for root."

        if confirm "Set MySQL root password?" "y"; then
            while true; do
                read -rsp "Enter new MySQL root password: " DB_PASS
                echo
                read -rsp "Confirm password: " DB_PASS_CONFIRM
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
    echo -e "\n${C_BLUE}${C_BOLD}▶ MySQL Authentication...${C_RESET}"

    local tries=0
    while (( tries < 3 )); do
        read -rsp "Enter MySQL password for user '$DB_USER': " DB_PASS
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
    echo -e "\n${C_BLUE}${C_BOLD}▶ Database Setup...${C_RESET}"

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
    echo -e "\n${C_BLUE}${C_BOLD}▶ Configuring Nginx...${C_RESET}"

    local nginx_conf="/etc/nginx/sites-available/$SITE_NAME.conf"
    local nginx_enabled="/etc/nginx/sites-enabled/$SITE_NAME.conf"

    # Create sites-available and sites-enabled directories if they don't exist
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
    echo -e "\n${C_BLUE}${C_BOLD}▶ Installing WordPress...${C_RESET}"

    cd "$SITE_DIR"

    run "wp core download --path=$SITE_DIR --quiet" \
        "Download WordPress core" || return 1

    run "wp config create --dbname=$DB_NAME --dbuser=$DB_USER --dbpass=$DB_PASS --skip-check --force --quiet" \
        "Create wp-config.php" || return 1

    # Test database connection before installation
    log "Testing database connection..."
    if ! wp db check --quiet 2>/dev/null; then
        error "Database connection failed"
        log "Trying to diagnose the issue..."

        # Show detailed error
        wp db check 2>&1 | tee -a "$LOG_FILE"

        # Try manual connection test
        if ! mysql -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" -e "SELECT 1;" &>/dev/null; then
            error "Cannot connect to database $DB_NAME with user $DB_USER"
            return 1
        fi

        warn "Database exists but WP-CLI cannot connect. Checking wp-config.php..."
        grep -E "DB_NAME|DB_USER|DB_PASSWORD|DB_HOST" "$SITE_DIR/wp-config.php" | tee -a "$LOG_FILE"
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

    # Install with verbose error output on failure
    log "Installing WordPress (this may take a moment)..."
    if ! wp core install \
        --url="$SITE_URL" \
        --title="$SITE_TITLE" \
        --admin_user="$ADMIN_USER" \
        --admin_password="$ADMIN_PASS" \
        --admin_email="$ADMIN_EMAIL" \
        --skip-email 2>&1 | tee -a "$LOG_FILE"; then

        error "WordPress installation failed"
        log "Debugging information:"
        echo "Site URL: $SITE_URL" | tee -a "$LOG_FILE"
        echo "Site Dir: $SITE_DIR" | tee -a "$LOG_FILE"
        echo "DB Name: $DB_NAME" | tee -a "$LOG_FILE"
        echo "Checking wp-config.php..." | tee -a "$LOG_FILE"

        if [[ -f "$SITE_DIR/wp-config.php" ]]; then
            grep -E "table_prefix|DB_" "$SITE_DIR/wp-config.php" | tee -a "$LOG_FILE"
        fi

        return 1
    fi
    success "Install WordPress"

    run "wp rewrite structure '/%postname%/' --hard --quiet" \
        "Set permalink structure" || return 1
}

setup_theme() {
    echo -e "\n${C_BLUE}${C_BOLD}▶ Setting up theme...${C_RESET}"

    if [[ "$THEME" != "default" && -n "$THEME" ]]; then
        if run "wp theme install $THEME --activate --quiet" "Install and activate theme ($THEME)"; then
            # Remove unused default themes
            local inactive_themes
            inactive_themes=$(wp theme list --status=inactive --field=name 2>/dev/null || echo "")
            if [[ -n "$inactive_themes" ]]; then
                run "wp theme delete $inactive_themes" "Remove unused themes" || warn "Could not remove some themes"
            fi
        else
            warn "Theme installation failed. Using default theme."
        fi
    else
        log "Using default theme"
    fi
}

setup_plugins() {
    echo -e "\n${C_BLUE}${C_BOLD}▶ Setting up plugins...${C_RESET}"

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
    echo -e "\n${C_BLUE}${C_BOLD}▶ Finalizing setup...${C_RESET}"

    local plugin_list="${PLUGINS[*]:-none}"
    run "wp option update blogdescription 'Built with WordPress, $THEME & $plugin_list' --quiet" \
        "Update site tagline"

    run "wp option update timezone_string 'Asia/Kolkata' --quiet" \
        "Set timezone"

    # Set proper permissions
    sudo chown -R "$USER:http" "$SITE_DIR"
    sudo chmod -R 775 "$SITE_DIR"
    success "Set proper file permissions"
}

# ------------------------------------------------------------
# Main Execution
# ------------------------------------------------------------
main() {
    clear
    echo -e "${C_BOLD}${C_CYAN}"
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║         WordPress Auto Setup Script v2.0            ║"
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
    echo -e "║              Setup Completed Successfully!           ║"
    echo -e "╚══════════════════════════════════════════════════════╝${C_RESET}\n"

    echo -e "${C_CYAN}Site Details:${C_RESET}"
    echo -e "  ${C_GREEN}►${C_RESET} URL:       $SITE_URL"
    echo -e "  ${C_GREEN}►${C_RESET} Admin:     $SITE_URL/wp-admin"
    echo -e "  ${C_GREEN}►${C_RESET} Username:  $ADMIN_USER"
    echo -e "  ${C_GREEN}►${C_RESET} Password:  $ADMIN_PASS"
    echo -e "  ${C_GREEN}►${C_RESET} Email:     $ADMIN_EMAIL"
    echo -e "  ${C_GREEN}►${C_RESET} Theme:     ${THEME:-default}"
    [[ ${#PLUGINS[@]} -gt 0 ]] && echo -e "  ${C_GREEN}►${C_RESET} Plugins:   ${PLUGINS[*]}"
    echo -e "  ${C_GRAY}►${C_RESET} Log:       $LOG_FILE"

    echo -e "\n${C_YELLOW}Next Steps:${C_RESET}"
    echo -e "  1. Visit $SITE_URL to see your site"
    echo -e "  2. Login at $SITE_URL/wp-admin"
    echo -e "  3. Start building!\n"

    log "Setup completed successfully"
}

# Run main function
main
