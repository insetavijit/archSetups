#!/usr/bin/env bash
# ============================================================
# PHP Configuration Script for WordPress on Arch Linux
# Author: Avijit Sarkar
# Version: 1.0
# Description: Automatically configures PHP for optimal WordPress performance
# ============================================================

set -euo pipefail

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
# Configuration
# ------------------------------------------------------------
PHP_INI="/etc/php/php.ini"
PHP_INI_BACKUP="/etc/php/php.ini.backup-$(date +%Y%m%d-%H%M%S)"
PHP_FPM_CONF="/etc/php/php-fpm.conf"
PHP_FPM_WWW_CONF="/etc/php/php-fpm.d/www.conf"
LOG_FILE="/tmp/php-wordpress-config-$(date +%Y%m%d-%H%M%S).log"

# WordPress recommended PHP settings
MEMORY_LIMIT="256M"
UPLOAD_MAX_FILESIZE="64M"
POST_MAX_SIZE="64M"
MAX_EXECUTION_TIME="300"
MAX_INPUT_TIME="300"
MAX_INPUT_VARS="3000"

# Required PHP extensions for WordPress
REQUIRED_EXTENSIONS=(
    "mysqli"
    "pdo_mysql"
    "curl"
    "gd"
    "imagick"
    "zip"
    "mbstring"
    "xml"
    "xmlwriter"
    "openssl"
    "fileinfo"
    "intl"
    "exif"
)

# Optional but recommended extensions
OPTIONAL_EXTENSIONS=(
    "opcache"
    "redis"
    "imagick"
)

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

info() {
    echo -e "${C_CYAN}ℹ${C_RESET}  $1"
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

# ------------------------------------------------------------
# Header
# ------------------------------------------------------------
show_header() {
    clear
    echo -e "${C_BOLD}${C_CYAN}"
    echo "╔══════════════════════════════════════════════════════╗"
    echo "║     PHP WordPress Configuration Script v1.0         ║"
    echo "║              for Arch Linux                          ║"
    echo "╚══════════════════════════════════════════════════════╝"
    echo -e "${C_RESET}\n"
}

show_usage() {
    cat << EOF
${C_BOLD}PHP WordPress Configuration Script${C_RESET}

${C_CYAN}Usage:${C_RESET}
  $0 [OPTIONS]

${C_CYAN}Options:${C_RESET}
  --check      Check current PHP configuration
  --backup     Backup current php.ini only
  --restore    Restore from latest backup
  --info       Show PHP info
  -h, --help   Show this help message

${C_CYAN}What this script does:${C_RESET}
  • Installs required PHP packages
  • Enables all WordPress-required PHP extensions
  • Optimizes php.ini settings for WordPress
  • Configures PHP-FPM for better performance
  • Enables OPcache for faster PHP execution
  • Creates automatic backup before changes

${C_CYAN}Recommended Settings:${C_RESET}
  • Memory Limit:        ${MEMORY_LIMIT}
  • Upload Max:          ${UPLOAD_MAX_FILESIZE}
  • Post Max Size:       ${POST_MAX_SIZE}
  • Max Execution Time:  ${MAX_EXECUTION_TIME}s
  • Max Input Vars:      ${MAX_INPUT_VARS}

${C_GRAY}Log file: ${LOG_FILE}${C_RESET}
EOF
    exit 0
}

# ------------------------------------------------------------
# Check current configuration
# ------------------------------------------------------------
check_php_config() {
    echo -e "${C_BLUE}${C_BOLD}▶ Current PHP Configuration${C_RESET}\n"

    if ! command -v php &>/dev/null; then
        error "PHP is not installed"
        return 1
    fi

    local php_version=$(php -v | head -n1)
    echo -e "${C_CYAN}PHP Version:${C_RESET}"
    echo "  $php_version"

    echo -e "\n${C_CYAN}Critical Settings:${C_RESET}"
    php -i 2>/dev/null | grep -E "memory_limit|upload_max_filesize|post_max_size|max_execution_time|max_input_vars" | while read -r line; do
        echo "  $line"
    done

    echo -e "\n${C_CYAN}Loaded Extensions:${C_RESET}"
    local loaded=()
    local missing=()

    for ext in "${REQUIRED_EXTENSIONS[@]}"; do
        if php -m 2>/dev/null | grep -q "^${ext}$"; then
            loaded+=("$ext")
        else
            missing+=("$ext")
        fi
    done

    if (( ${#loaded[@]} > 0 )); then
        echo -e "  ${C_GREEN}Loaded:${C_RESET} ${loaded[*]}"
    fi

    if (( ${#missing[@]} > 0 )); then
        echo -e "  ${C_RED}Missing:${C_RESET} ${missing[*]}"
    else
        success "All required extensions are loaded!"
    fi

    echo -e "\n${C_CYAN}PHP-FPM Status:${C_RESET}"
    if systemctl is-active --quiet php-fpm; then
        echo -e "  ${C_GREEN}✓${C_RESET} Running"
    else
        echo -e "  ${C_RED}✗${C_RESET} Not running"
    fi

    echo -e "\n${C_CYAN}Configuration Files:${C_RESET}"
    echo "  php.ini:          $PHP_INI"
    echo "  php-fpm.conf:     $PHP_FPM_CONF"
    echo "  www.conf:         $PHP_FPM_WWW_CONF"

    echo ""
}

# ------------------------------------------------------------
# Backup configuration
# ------------------------------------------------------------
backup_config() {
    echo -e "${C_BLUE}${C_BOLD}▶ Backing up configuration...${C_RESET}"

    if [[ ! -f "$PHP_INI" ]]; then
        error "php.ini not found at $PHP_INI"
        return 1
    fi

    sudo cp "$PHP_INI" "$PHP_INI_BACKUP"
    success "Backup created: $PHP_INI_BACKUP"

    # Keep only last 5 backups
    local backup_count=$(ls -1 /etc/php/php.ini.backup-* 2>/dev/null | wc -l)
    if (( backup_count > 5 )); then
        log "Cleaning old backups (keeping last 5)..."
        ls -1t /etc/php/php.ini.backup-* | tail -n +6 | xargs sudo rm -f
    fi
}

# ------------------------------------------------------------
# Restore from backup
# ------------------------------------------------------------
restore_config() {
    echo -e "${C_BLUE}${C_BOLD}▶ Available backups:${C_RESET}\n"

    local backups=($(ls -1t /etc/php/php.ini.backup-* 2>/dev/null || true))

    if (( ${#backups[@]} == 0 )); then
        error "No backups found"
        return 1
    fi

    local i=1
    for backup in "${backups[@]}"; do
        local timestamp=$(stat -c %y "$backup" | cut -d'.' -f1)
        echo "  $i) $(basename "$backup") - $timestamp"
        ((i++))
    done

    echo ""
    read -rp "Select backup to restore (1-${#backups[@]}): " choice

    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#backups[@]} )); then
        local selected="${backups[$((choice-1))]}"
        warn "This will replace current php.ini with: $(basename "$selected")"

        if confirm "Continue?" "n"; then
            sudo cp "$selected" "$PHP_INI"
            success "Configuration restored from $(basename "$selected")"

            if confirm "Restart PHP-FPM?" "y"; then
                sudo systemctl restart php-fpm
                success "PHP-FPM restarted"
            fi
        fi
    else
        error "Invalid selection"
        return 1
    fi
}

# ------------------------------------------------------------
# Install PHP packages
# ------------------------------------------------------------
install_php_packages() {
    echo -e "${C_BLUE}${C_BOLD}▶ Installing PHP packages...${C_RESET}"

    local packages=(
        "php"
        "php-fpm"
        "php-gd"
        "php-imagick"
        "php-intl"
        "php-redis"
    )

    local to_install=()

    for pkg in "${packages[@]}"; do
        if ! pacman -Qi "$pkg" &>/dev/null; then
            to_install+=("$pkg")
        fi
    done

    if (( ${#to_install[@]} > 0 )); then
        log "Installing: ${to_install[*]}"
        if sudo pacman -S --needed --noconfirm "${to_install[@]}" >> "$LOG_FILE" 2>&1; then
            success "Installed PHP packages"
        else
            error "Failed to install some packages"
            return 1
        fi
    else
        success "All PHP packages already installed"
    fi
}

# ------------------------------------------------------------
# Enable PHP extensions
# ------------------------------------------------------------
enable_php_extensions() {
    echo -e "\n${C_BLUE}${C_BOLD}▶ Enabling PHP extensions...${C_RESET}"

    local enabled_count=0
    local already_enabled=0

    for ext in "${REQUIRED_EXTENSIONS[@]}"; do
        # Check if already loaded
        if php -m 2>/dev/null | grep -q "^${ext}$"; then
            log "✓ ${ext} - already enabled"
            ((already_enabled++))
            continue
        fi

        # Try to enable in php.ini
        if grep -q "^;extension=${ext}" "$PHP_INI" 2>/dev/null; then
            sudo sed -i "s/^;extension=${ext}/extension=${ext}/" "$PHP_INI"
            success "Enabled ${ext}"
            ((enabled_count++))
        elif grep -q "^extension=${ext}" "$PHP_INI" 2>/dev/null; then
            log "✓ ${ext} - already uncommented"
            ((already_enabled++))
        else
            # Add extension if not found
            echo "extension=${ext}" | sudo tee -a "$PHP_INI" >/dev/null
            success "Added ${ext}"
            ((enabled_count++))
        fi
    done

    if (( enabled_count > 0 )); then
        success "Enabled $enabled_count new extension(s)"
    fi

    if (( already_enabled > 0 )); then
        info "$already_enabled extension(s) were already enabled"
    fi
}

# ------------------------------------------------------------
# Configure php.ini settings
# ------------------------------------------------------------
configure_php_ini() {
    echo -e "\n${C_BLUE}${C_BOLD}▶ Configuring php.ini settings...${C_RESET}"

    local settings=(
        "memory_limit|$MEMORY_LIMIT"
        "upload_max_filesize|$UPLOAD_MAX_FILESIZE"
        "post_max_size|$POST_MAX_SIZE"
        "max_execution_time|$MAX_EXECUTION_TIME"
        "max_input_time|$MAX_INPUT_TIME"
        "max_input_vars|$MAX_INPUT_VARS"
    )

    for setting_pair in "${settings[@]}"; do
        IFS='|' read -r setting value <<< "$setting_pair"

        # Check current value
        local current_value=$(php -i 2>/dev/null | grep "^${setting} =>" | awk '{print $3}' || echo "not set")

        # Update or add setting
        if grep -q "^${setting} =" "$PHP_INI" 2>/dev/null; then
            sudo sed -i "s/^${setting} =.*/${setting} = ${value}/" "$PHP_INI"
            log "Updated: ${setting} = ${value} (was: ${current_value})"
        elif grep -q "^;${setting} =" "$PHP_INI" 2>/dev/null; then
            sudo sed -i "s/^;${setting} =.*/${setting} = ${value}/" "$PHP_INI"
            log "Enabled: ${setting} = ${value}"
        else
            echo "${setting} = ${value}" | sudo tee -a "$PHP_INI" >/dev/null
            log "Added: ${setting} = ${value}"
        fi
    done

    success "PHP settings configured for WordPress"
}

# ------------------------------------------------------------
# Configure OPcache
# ------------------------------------------------------------
configure_opcache() {
    echo -e "\n${C_BLUE}${C_BOLD}▶ Configuring OPcache...${C_RESET}"

    # Enable OPcache extension
    if ! php -m 2>/dev/null | grep -q "^Zend OPcache$"; then
        if grep -q "^;zend_extension=opcache" "$PHP_INI" 2>/dev/null; then
            sudo sed -i "s/^;zend_extension=opcache/zend_extension=opcache/" "$PHP_INI"
            success "Enabled OPcache extension"
        else
            echo "zend_extension=opcache" | sudo tee -a "$PHP_INI" >/dev/null
            success "Added OPcache extension"
        fi
    else
        log "OPcache already enabled"
    fi

    # OPcache settings for WordPress
    local opcache_settings=(
        "opcache.enable|1"
        "opcache.memory_consumption|128"
        "opcache.interned_strings_buffer|8"
        "opcache.max_accelerated_files|10000"
        "opcache.revalidate_freq|2"
        "opcache.fast_shutdown|1"
    )

    # Add [opcache] section if not exists
    if ! grep -q "^\[opcache\]" "$PHP_INI" 2>/dev/null; then
        echo -e "\n[opcache]" | sudo tee -a "$PHP_INI" >/dev/null
    fi

    for setting_pair in "${opcache_settings[@]}"; do
        IFS='|' read -r setting value <<< "$setting_pair"

        if grep -q "^${setting}=" "$PHP_INI" 2>/dev/null; then
            sudo sed -i "s/^${setting}=.*/${setting}=${value}/" "$PHP_INI"
        elif grep -q "^;${setting}=" "$PHP_INI" 2>/dev/null; then
            sudo sed -i "s/^;${setting}=.*/${setting}=${value}/" "$PHP_INI"
        else
            echo "${setting}=${value}" | sudo tee -a "$PHP_INI" >/dev/null
        fi
    done

    success "OPcache configured for optimal performance"
}

# ------------------------------------------------------------
# Configure PHP-FPM
# ------------------------------------------------------------
configure_php_fpm() {
    echo -e "\n${C_BLUE}${C_BOLD}▶ Configuring PHP-FPM...${C_RESET}"

    if [[ ! -f "$PHP_FPM_WWW_CONF" ]]; then
        warn "PHP-FPM www.conf not found, skipping"
        return 0
    fi

    # Backup PHP-FPM config
    sudo cp "$PHP_FPM_WWW_CONF" "${PHP_FPM_WWW_CONF}.backup-$(date +%Y%m%d-%H%M%S)"

    # Configure PM settings for better performance
    local fpm_settings=(
        "pm.max_children|50"
        "pm.start_servers|5"
        "pm.min_spare_servers|5"
        "pm.max_spare_servers|35"
    )

    for setting_pair in "${fpm_settings[@]}"; do
        IFS='|' read -r setting value <<< "$setting_pair"

        if grep -q "^${setting} =" "$PHP_FPM_WWW_CONF" 2>/dev/null; then
            sudo sed -i "s/^${setting} =.*/${setting} = ${value}/" "$PHP_FPM_WWW_CONF"
        elif grep -q "^;${setting} =" "$PHP_FPM_WWW_CONF" 2>/dev/null; then
            sudo sed -i "s/^;${setting} =.*/${setting} = ${value}/" "$PHP_FPM_WWW_CONF"
        fi
    done

    success "PHP-FPM configured"
}

# ------------------------------------------------------------
# Verify configuration
# ------------------------------------------------------------
verify_configuration() {
    echo -e "\n${C_BLUE}${C_BOLD}▶ Verifying configuration...${C_RESET}"

    # Restart PHP-FPM
    log "Restarting PHP-FPM..."
    if sudo systemctl restart php-fpm; then
        success "PHP-FPM restarted successfully"
    else
        error "Failed to restart PHP-FPM"
        return 1
    fi

    sleep 2

    # Check if PHP-FPM is running
    if systemctl is-active --quiet php-fpm; then
        success "PHP-FPM is running"
    else
        error "PHP-FPM is not running"
        return 1
    fi

    # Verify extensions
    echo -e "\n${C_CYAN}Verifying extensions:${C_RESET}"
    local missing_extensions=()

    for ext in "${REQUIRED_EXTENSIONS[@]}"; do
        if php -m 2>/dev/null | grep -q "^${ext}$"; then
            log "✓ ${ext}"
        else
            missing_extensions+=("$ext")
            warn "✗ ${ext} - not loaded"
        fi
    done

    if (( ${#missing_extensions[@]} > 0 )); then
        error "Some extensions failed to load: ${missing_extensions[*]}"
        return 1
    else
        success "All required extensions loaded successfully!"
    fi

    # Show new settings
    echo -e "\n${C_CYAN}Updated Settings:${C_RESET}"
    php -i 2>/dev/null | grep -E "memory_limit|upload_max_filesize|post_max_size|max_execution_time|max_input_vars" | while read -r line; do
        echo "  $line"
    done
}

# ------------------------------------------------------------
# Show summary
# ------------------------------------------------------------
show_summary() {
    echo -e "\n${C_GREEN}${C_BOLD}╔══════════════════════════════════════════════════════╗"
    echo -e "║         Configuration Completed Successfully!       ║"
    echo -e "╚══════════════════════════════════════════════════════╝${C_RESET}\n"

    echo -e "${C_CYAN}What was configured:${C_RESET}"
    echo -e "  ${C_GREEN}✓${C_RESET} PHP packages installed"
    echo -e "  ${C_GREEN}✓${C_RESET} WordPress-required extensions enabled"
    echo -e "  ${C_GREEN}✓${C_RESET} Memory and upload limits increased"
    echo -e "  ${C_GREEN}✓${C_RESET} OPcache enabled for performance"
    echo -e "  ${C_GREEN}✓${C_RESET} PHP-FPM optimized"

    echo -e "\n${C_CYAN}Configuration backup:${C_RESET}"
    echo -e "  $PHP_INI_BACKUP"

    echo -e "\n${C_CYAN}Log file:${C_RESET}"
    echo -e "  $LOG_FILE"

    echo -e "\n${C_YELLOW}Next steps:${C_RESET}"
    echo -e "  1. Run: ${C_BOLD}php -v${C_RESET} to verify PHP version"
    echo -e "  2. Run: ${C_BOLD}php -m | grep -E 'mysqli|gd'${C_RESET} to check extensions"
    echo -e "  3. Your WordPress setup script will now work perfectly!"

    echo -e "\n${C_GRAY}To restore previous configuration: $0 --restore${C_RESET}\n"
}

# ------------------------------------------------------------
# Main execution
# ------------------------------------------------------------
main() {
    show_header

    log "=== Starting PHP configuration for WordPress ==="

    # Check if running as root
    if [[ $EUID -eq 0 ]]; then
        error "Don't run this script as root. It will ask for sudo when needed."
        exit 1
    fi

    # Run configuration steps
    install_php_packages
    backup_config
    enable_php_extensions
    configure_php_ini
    configure_opcache
    configure_php_fpm
    verify_configuration
    show_summary

    log "=== Configuration completed ==="
}

# Parse arguments
case "${1:-}" in
    --check)
        check_php_config
        exit 0
        ;;
    --backup)
        backup_config
        exit 0
        ;;
    --restore)
        restore_config
        exit 0
        ;;
    --info)
        php -i
        exit 0
        ;;
    -h|--help)
        show_usage
        ;;
    *)
        main
        ;;
esac
