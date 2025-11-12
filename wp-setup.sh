#!/usr/bin/env bash
# ============================================================
# WordPress Auto Setup Script (for Arch + Nginx + WP-CLI)
# Author: Avijit Sarkar
# Version: 3.0 (Enhanced with better structure & modern features)
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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
C_MAGENTA="\033[35m"

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
  $0 --backup <site_name> [backup_name]
  $0 --restore <site_name> <backup_name>
  $0 --remove <site_name>

${C_CYAN}${C_BOLD}EXAMPLES:${C_RESET}
  ${C_GRAY}# Quick setup with defaults${C_RESET}
  $0 mysite

  ${C_GRAY}# Full custom setup${C_RESET}
  $0 mysite root myadmin mypass123 me@example.com generatepress

  ${C_GRAY}# Diagnose existing site${C_RESET}
  $0 --diagnose mysite

  ${C_GRAY}# Backup a site${C_RESET}
  $0 --backup mysite backup-20241112

  ${C_GRAY}# Remove a site completely${C_RESET}
  $0 --remove mysite

${C_CYAN}${C_BOLD}ARGUMENTS:${C_RESET}
  ${C_GREEN}site_name${C_RESET}    Required. Name of the WordPress site (alphanumeric, hyphens)
  ${C_GREEN}db_user${C_RESET}      Optional. MySQL user (default: root)
  ${C_GREEN}admin_user${C_RESET}   Optional. WP admin username (default: admin)
  ${C_GREEN}admin_pass${C_RESET}   Optional. WP admin password (default: 123)
  ${C_GREEN}admin_email${C_RESET}  Optional. WP admin email (default: admin@example.com)
  ${C_GREEN}theme${C_RESET}        Optional. Theme slug to install (default: astra)

${C_CYAN}${C_BOLD}OPTIONS:${C_RESET}
  ${C_GREEN}--diagnose${C_RESET}   Run comprehensive diagnostics on existing site
  ${C_GREEN}--backup${C_RESET}     Create complete backup (files + database)
  ${C_GREEN}--restore${C_RESET}    Restore site from backup
  ${C_GREEN}--remove${C_RESET}     Remove site completely (with confirmation)
  ${C_GREEN}-h, --help${C_RESET}   Show this help message
  ${C_GREEN}--version${C_RESET}    Show script version

${C_CYAN}${C_BOLD}FEATURES:${C_RESET}
  ${S_ARROW} Automatic dependency checking & installation
  ${S_ARROW} Secure MySQL setup with validation
  ${S_ARROW} Smart Nginx configuration with PHP-FPM
  ${S_ARROW} Complete backup & restore functionality
  ${S_ARROW} Comprehensive error handling & rollback
  ${S_ARROW} Detailed logging with timestamps
  ${S_ARROW} Site health diagnostics
  ${S_ARROW} Clean site removal

${C_GRAY}Log directory: $WWW_DIR/_logs
Backup directory: $WWW_DIR/_backups${C_RESET}
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

        # Check key WordPress files
        local key_files=("wp-config.php" "wp-load.php" "wp-settings.php" "index.php")
        for file in "${key_files[@]}"; do
            if [[ -f "$site_dir/$file" ]]; then
                echo -e "  ${C_GREEN}${S_CHECK}${C_RESET} $file"
            else
                echo -e "  ${C_RED}${S_CROSS}${C_RESET} $file ${C_GRAY}(missing)${C_RESET}"
            fi
        done
    else
        echo -e "  ${C_RED}${S_CROSS}${C_RESET} Site directory not found"
        return 1
    fi

    # Configuration Check
    echo -e "\n${C_BLUE}${C_BOLD}[2] WordPress Configuration${C_RESET}"
    if [[ -f "$site_dir/wp-config.php" ]]; then
        echo -e "  ${C_GREEN}${S_CHECK}${C_RESET} wp-config.php exists"
        echo -e "\n  ${C_GRAY}Database Settings:${C_RESET}"
        grep -E "DB_NAME|DB_USER|DB_HOST|table_prefix" "$site_dir/wp-config.php" | \
            sed 's/^/    /' | sed "s/define/  ${C_CYAN}define${C_RESET}/"
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

            # Get site info
            local site_url=$(wp option get siteurl 2>/dev/null)
            local site_title=$(wp option get blogname 2>/dev/null)
            echo -e "  ${C_GREEN}${S_ARROW}${C_RESET} URL: $site_url"
            echo -e "  ${C_GREEN}${S_ARROW}${C_RESET} Title: $site_title"

            # Count posts
            local post_count=$(wp post list --post_type=post --format=count 2>/dev/null || echo "0")
            local page_count=$(wp post list --post_type=page --format=count 2>/dev/null || echo "0")
            echo -e "  ${C_GREEN}${S_ARROW}${C_RESET} Posts: $post_count | Pages: $page_count"
        else
            echo -e "  ${C_YELLOW}${S_WARN}${C_RESET} WordPress not installed in database"
        fi
    else
        echo -e "  ${C_RED}${S_CROSS}${C_RESET} Database connection failed"
    fi

    # Theme & Plugins
    echo -e "\n${C_BLUE}${C_BOLD}[4] Theme & Plugins${C_RESET}"
    local active_theme=$(wp theme list --status=active --field=name 2>/dev/null || echo "Unknown")
    echo -e "  ${C_GREEN}${S_ARROW}${C_RESET} Active Theme: $active_theme"

    local plugin_count=$(wp plugin list --status=active --format=count 2>/dev/null || echo "0")
    echo -e "  ${C_GREEN}${S_ARROW}${C_RESET} Active Plugins: $plugin_count"

    if [[ $plugin_count -gt 0 ]]; then
        wp plugin list --status=active --fields=name,version --format=table 2>/dev/null | \
            tail -n +2 | sed 's/^/    /'
    fi

    # Nginx Check
    echo -e "\n${C_BLUE}${C_BOLD}[5] Nginx Configuration${C_RESET}"
    if [[ -f "/etc/nginx/sites-available/$site.conf" ]]; then
        echo -e "  ${C_GREEN}${S_CHECK}${C_RESET} Nginx config exists"
        if [[ -L "/etc/nginx/sites-enabled/$site.conf" ]]; then
            echo -e "  ${C_GREEN}${S_CHECK}${C_RESET} Config is enabled"

            # Test nginx config
            if sudo nginx -t &>/dev/null; then
                echo -e "  ${C_GREEN}${S_CHECK}${C_RESET} Nginx config valid"
            else
                echo -e "  ${C_RED}${S_CROSS}${C_RESET} Nginx config has errors"
            fi
        else
            echo -e "  ${C_YELLOW}${S_WARN}${C_RESET} Config not enabled"
        fi
    else
        echo -e "  ${C_RED}${S_CROSS}${C_RESET} Nginx config not found"
    fi

    # Health Check
    echo -e "\n${C_BLUE}${C_BOLD}[6] Site Health${C_RESET}"
    if command -v curl &>/dev/null; then
        local http_code=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost/$site" 2>/dev/null || echo "000")
        if [[ "$http_code" == "200" ]]; then
            echo -e "  ${C_GREEN}${S_CHECK}${C_RESET} Site is accessible (HTTP $http_code)"
        else
            echo -e "  ${C_RED}${S_CROSS}${C_RESET} Site returned HTTP $http_code"
        fi
    fi

    # Latest log
    echo -e "\n${C_BLUE}${C_BOLD}[7] Recent Logs${C_RESET}"
    local latest_log=$(ls -t "$WWW_DIR/_logs/$site"*.log 2>/dev/null | head -1)
    if [[ -n "$latest_log" ]]; then
        echo -e "  ${C_GREEN}${S_ARROW}${C_RESET} Latest: ${C_GRAY}$(basename "$latest_log")${C_RESET}"
        echo -e "\n  ${C_GRAY}Last 10 lines:${C_RESET}"
        tail -10 "$latest_log" | sed 's/^/    /'
    else
        echo -e "  ${C_GRAY}No log files found${C_RESET}"
    fi

    echo -e "\n${C_GREEN}${C_BOLD}Diagnosis complete!${C_RESET}\n"
}

# ------------------------------------------------------------
# Backup & Restore
# ------------------------------------------------------------
backup_site() {
    local site="$1"
    local backup_name="${2:-backup-$(date +%Y%m%d-%H%M%S)}"
    local site_dir="$WWW_DIR/$site"
    local backup_dir="$WWW_DIR/_backups/$site"
    local backup_path="$backup_dir/$backup_name"

    echo -e "${C_CYAN}${C_BOLD}Creating backup for: $site${C_RESET}\n"

    if [[ ! -d "$site_dir" ]]; then
        error "Site directory not found: $site_dir"
        return 1
    fi

    mkdir -p "$backup_path"

    # Backup files
    echo -e "${C_BLUE}${S_SPIN}${C_RESET} Backing up files..."
    tar -czf "$backup_path/files.tar.gz" -C "$WWW_DIR" "$site" 2>/dev/null
    success "Files backed up"

    # Backup database
    echo -e "${C_BLUE}${S_SPIN}${C_RESET} Backing up database..."
    cd "$site_dir"
    wp db export "$backup_path/database.sql" --quiet 2>/dev/null
    success "Database backed up"

    # Save metadata
    cat > "$backup_path/metadata.txt" << EOF
Site: $site
Backup Date: $(date '+%Y-%m-%d %H:%M:%S')
WordPress Version: $(wp core version 2>/dev/null || echo "Unknown")
Theme: $(wp theme list --status=active --field=name 2>/dev/null || echo "Unknown")
Site URL: $(wp option get siteurl 2>/dev/null || echo "Unknown")
EOF

    local backup_size=$(du -sh "$backup_path" | cut -f1)
    success "Backup created: $backup_path (Size: $backup_size)"
}

restore_site() {
    local site="$1"
    local backup_name="$2"
    local backup_path="$WWW_DIR/_backups/$site/$backup_name"

    echo -e "${C_CYAN}${C_BOLD}Restoring site: $site${C_RESET}\n"

    if [[ ! -d "$backup_path" ]]; then
        error "Backup not found: $backup_path"
        return 1
    fi

    if ! confirm "This will overwrite current site. Continue?" "n"; then
        warn "Restore cancelled"
        return 0
    fi

    # Restore files
    echo -e "${C_BLUE}${S_SPIN}${C_RESET} Restoring files..."
    tar -xzf "$backup_path/files.tar.gz" -C "$WWW_DIR" 2>/dev/null
    success "Files restored"

    # Restore database
    echo -e "${C_BLUE}${S_SPIN}${C_RESET} Restoring database..."
    cd "$WWW_DIR/$site"
    wp db import "$backup_path/database.sql" --quiet 2>/dev/null
    success "Database restored"

    success "Site restored successfully!"
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
    echo -e "  ${S_ARROW} Nginx config: /etc/nginx/sites-available/$site.conf\n"

    if ! confirm "Are you absolutely sure?" "n"; then
        warn "Removal cancelled"
        return 0
    fi

    # Create backup first
    if confirm "Create backup before removal?" "y"; then
        backup_site "$site" "pre-removal-$(date +%Y%m%d-%H%M%S)"
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
[[ "${1:-}" == "--backup" ]] && { backup_site "${2:-}" "${3:-}"; exit 0; }
[[ "${1:-}" == "--restore" ]] && { restore_site "${2:-}" "${3:-}"; exit 0; }
[[ "${1:-}" == "--remove" ]] && { remove_site "${2:-}"; exit 0; }

# Validate site name
if [[ -z "$SITE_NAME" ]]; then
    echo -e "${C_RED}Error: Site name is required${C_RESET}\n"
    show_usage
fi

if [[ ! "$SITE_NAME" =~ ^[a-zA-Z0-9-]+$ ]]; then
    error "Invalid site name. Use only alphanumeric characters and hyphens."
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

    # Create backup directory
    mkdir -p "$WWW_DIR/_backups"
    success "Backup directory ready"

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

    local packages=("php" "php-fpm" "mariadb" "nginx" "curl" "wget" "tar" "gzip")
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

    # Verify WP-CLI works
    if ! wp --info &>/dev/null; then
        error "WP-CLI is not working correctly"
        exit 1
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
            sudo systemctl status "$service" --no-pager
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
            run "mysql -u $DB_USER -p$DB_PASS -e 'DROP DATABASE $DB_NAME;'" \dumy
