#!/usr/bin/env bash
# ==============================================================================
# Pi-hole Automated Cloud Lists & Updater Deployment Script
# Repository: https://github.com/srinivasan-mk/pi-hole
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/config"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"
SYSTEMD_DIR="/etc/systemd/system"

echo "============================================================"
echo "  Pi-hole Cloud Lists & Updater Deployment"
echo "============================================================"

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "[-] This script must be run with sudo or as root."
    echo "    Usage: sudo bash $0"
    exit 1
fi

# Check Pi-hole installation
if ! command -v pihole >/dev/null 2>&1; then
    echo "[-] Error: Pi-hole is not installed on this system."
    exit 1
fi

echo "[+] Pi-hole detected:"
pihole -v

# Ensure Python 3 is installed for pihole-cloud-updater
if ! command -v python3 >/dev/null 2>&1; then
    echo "[*] python3 not found. Installing via apt-get..."
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -y && apt-get install -y python3 python3-sqlite3
    fi
fi

# 1. Install pihole-cloud-updater
echo "[*] Installing pihole-cloud-updater..."
mkdir -p /usr/local/share/pihole-cloud-updater
mkdir -p /usr/local/sbin
mkdir -p /var/cache/pihole-cloud-updater

if [ -f "${SCRIPTS_DIR}/pihole-cloud-updater.py" ]; then
    cp "${SCRIPTS_DIR}/pihole-cloud-updater.py" /usr/local/share/pihole-cloud-updater/pihole-cloud-updater.py
    chmod 755 /usr/local/share/pihole-cloud-updater/pihole-cloud-updater.py
fi

if [ -f "${SCRIPTS_DIR}/pihole-cloud-updater" ]; then
    cp "${SCRIPTS_DIR}/pihole-cloud-updater" /usr/local/sbin/pihole-cloud-updater
    chmod 755 /usr/local/sbin/pihole-cloud-updater
fi

# 2. Also keep pihole-updatelists for backward compatibility
if [ ! -f "/usr/local/sbin/pihole-updatelists" ]; then
    echo "[*] Installing classic pihole-updatelists (jacklul)..."
    wget -qO - https://raw.githubusercontent.com/jacklul/pihole-updatelists/master/install.sh | bash || true
fi

# Ensure /etc/pihole directory exists
mkdir -p /etc/pihole

# Backup existing configs if present
if [ -f "/etc/pihole-cloud-updater.conf" ]; then
    cp /etc/pihole-cloud-updater.conf "/etc/pihole-cloud-updater.conf.bak.$(date +%Y%m%d_%H%M%S)"
fi
if [ -f "/etc/pihole-updatelists.conf" ]; then
    cp /etc/pihole-updatelists.conf "/etc/pihole-updatelists.conf.bak.$(date +%Y%m%d_%H%M%S)"
fi

# Deploy custom-blocklists.list
if [ -f "${CONFIG_DIR}/custom-blocklists.list" ]; then
    echo "[*] Installing /etc/pihole/custom-blocklists.list..."
    cp "${CONFIG_DIR}/custom-blocklists.list" /etc/pihole/custom-blocklists.list
    chmod 644 /etc/pihole/custom-blocklists.list
    sed -i 's/\r$//' /etc/pihole/custom-blocklists.list
fi

# Deploy pihole-cloud-updater.conf
if [ -f "${CONFIG_DIR}/pihole-cloud-updater.conf.example" ] && [ ! -f "/etc/pihole-cloud-updater.conf" ]; then
    echo "[*] Installing /etc/pihole-cloud-updater.conf..."
    cp "${CONFIG_DIR}/pihole-cloud-updater.conf.example" /etc/pihole-cloud-updater.conf
    chmod 644 /etc/pihole-cloud-updater.conf
    sed -i 's/\r$//' /etc/pihole-cloud-updater.conf
fi

# Deploy pihole-updatelists.conf
if [ -f "${CONFIG_DIR}/pihole-updatelists.conf" ]; then
    echo "[*] Installing /etc/pihole-updatelists.conf..."
    cp "${CONFIG_DIR}/pihole-updatelists.conf" /etc/pihole-updatelists.conf
    chmod 644 /etc/pihole-updatelists.conf
    sed -i 's/\r$//' /etc/pihole-updatelists.conf
fi

# Install systemd timer if available
if command -v systemctl >/dev/null 2>&1 && [ -d "${SYSTEMD_DIR}" ]; then
    if [ -f "${SCRIPT_DIR}/systemd/pihole-cloud-updater.service" ]; then
        cp "${SCRIPT_DIR}/systemd/pihole-cloud-updater.service" "${SYSTEMD_DIR}/"
        cp "${SCRIPT_DIR}/systemd/pihole-cloud-updater.timer" "${SYSTEMD_DIR}/"
        systemctl daemon-reload
        systemctl enable --now pihole-cloud-updater.timer
        echo "[+] Systemd automated sync timer active (runs daily at 03:30 AM)."
    fi
fi

echo "[+] Configuration files deployed successfully."

# Execute list synchronization
echo "------------------------------------------------------------"
echo "[*] Running pihole-cloud-updater..."
echo "------------------------------------------------------------"
/usr/local/sbin/pihole-cloud-updater

echo "------------------------------------------------------------"
echo "[+] Deployment completed successfully!"
echo "    Cloud sources, Google Sheets & lists synchronized."
echo "============================================================"
