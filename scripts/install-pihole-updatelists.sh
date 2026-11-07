#!/usr/bin/env bash
# ==============================================================================
# pihole-updatelists Automated Installation & Configuration Script
# Installs jacklul's pihole-updatelists, PHP dependencies, and deploys configs
# Repository: https://github.com/srinivasan-mk/pi-hole
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_DIR="${PARENT_DIR}/config"

echo "============================================================"
echo "  pihole-updatelists Installation & Configuration"
echo "============================================================"

# --- Preflight Checks ---
if [ "$(id -u)" -ne 0 ]; then
    echo "[-] Error: This installer must be run with sudo or as root." >&2
    echo "    Usage: sudo bash $0" >&2
    exit 1
fi

# Check Pi-hole installation
if ! command -v pihole >/dev/null 2>&1; then
    echo "[-] Warning: Pi-hole is not currently installed on this system." >&2
    if [ -f "${SCRIPT_DIR}/install-pihole.sh" ]; then
        read -r -p "Do you want to install Pi-hole now? [Y/n]: " install_pihole_choice || install_pihole_choice="Y"
        if [[ "$install_pihole_choice" =~ ^[Yy]?$ ]]; then
            echo "[*] Installing Pi-hole first..."
            bash "${SCRIPT_DIR}/install-pihole.sh" -y
        else
            echo "[-] Error: pihole-updatelists requires Pi-hole to be installed. Aborting." >&2
            exit 1
        fi
    else
        echo "[-] Error: Please install Pi-hole first before configuring lists." >&2
        exit 1
    fi
fi

echo "[+] Pi-hole detected:"
pihole -v

# --- Install PHP & Required Dependencies ---
echo "[*] Verifying PHP runtime and dependencies..."
if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y --no-install-recommends \
        php-cli \
        php-sqlite3 \
        php-intl \
        php-curl \
        wget \
        curl \
        ca-certificates
elif command -v apk >/dev/null 2>&1; then
    apk add --no-cache php-cli php-sqlite3 php-intl php-curl wget curl
elif command -v dnf >/dev/null 2>&1; then
    dnf install -y php-cli php-pdo php-intl php-curl wget curl
fi

# Verify PHP installation
if ! command -v php >/dev/null 2>&1; then
    echo "[-] Error: PHP is required for pihole-updatelists but could not be installed." >&2
    exit 1
fi

echo "[+] PHP installed: $(php -v | head -n1)"

# --- Install pihole-updatelists Utility ---
echo "[*] Installing/Updating pihole-updatelists from upstream repository..."
# Use jacklul's official installer script
wget -qO - https://raw.githubusercontent.com/jacklul/pihole-updatelists/master/install.sh | bash

if [ ! -f "/usr/local/sbin/pihole-updatelists" ]; then
    echo "[-] Error: pihole-updatelists executable not found after installation." >&2
    exit 1
fi

chmod +x /usr/local/sbin/pihole-updatelists
echo "[+] pihole-updatelists installed at /usr/local/sbin/pihole-updatelists"

# --- Deploy Curated Configurations ---
mkdir -p /etc/pihole

# Backup existing config if present
if [ -f "/etc/pihole-updatelists.conf" ]; then
    BACKUP_FILE="/etc/pihole-updatelists.conf.bak.$(date +%Y%m%d_%H%M%S)"
    echo "[*] Backing up existing /etc/pihole-updatelists.conf -> ${BACKUP_FILE}"
    cp /etc/pihole-updatelists.conf "${BACKUP_FILE}"
fi

# 1. Deploy custom-blocklists.list
if [ -f "${CONFIG_DIR}/custom-blocklists.list" ]; then
    echo "[*] Deploying curated /etc/pihole/custom-blocklists.list..."
    cp "${CONFIG_DIR}/custom-blocklists.list" /etc/pihole/custom-blocklists.list
    chmod 644 /etc/pihole/custom-blocklists.list
    sed -i 's/\r$//' /etc/pihole/custom-blocklists.list
fi

# 2. Deploy pihole-updatelists.conf
if [ -f "${CONFIG_DIR}/pihole-updatelists.conf" ]; then
    echo "[*] Deploying /etc/pihole-updatelists.conf..."
    cp "${CONFIG_DIR}/pihole-updatelists.conf" /etc/pihole-updatelists.conf
    chmod 644 /etc/pihole-updatelists.conf
    sed -i 's/\r$//' /etc/pihole-updatelists.conf
fi

echo "[+] Configurations deployed successfully."

# --- Verify Cron / Automation Schedule ---
if [ -f "/etc/cron.d/pihole-updatelists" ]; then
    echo "[+] Scheduled cron job detected at /etc/cron.d/pihole-updatelists"
else
    echo "[*] Setting up daily cron job for pihole-updatelists..."
    cat > /etc/cron.d/pihole-updatelists << 'CRON'
# /etc/cron.d/pihole-updatelists
# Update Pi-hole lists daily at 03:00 AM with randomized sleep
0 3 * * *   root    sleep $((RANDOM % 900)) && /usr/local/sbin/pihole-updatelists >/dev/null 2>&1
CRON
    chmod 644 /etc/cron.d/pihole-updatelists
fi

# --- Run Initial Synchronization ---
echo "------------------------------------------------------------"
echo "[*] Executing initial synchronization via pihole-updatelists..."
echo "------------------------------------------------------------"
/usr/local/sbin/pihole-updatelists

echo "------------------------------------------------------------"
echo "[+] pihole-updatelists installation and synchronization completed!"
echo "    Config file : /etc/pihole-updatelists.conf"
echo "    Custom list : /etc/pihole/custom-blocklists.list"
echo "    Run manually: sudo /usr/local/sbin/pihole-updatelists"
echo "============================================================"

