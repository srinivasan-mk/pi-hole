#!/usr/bin/env bash
# ==============================================================================
# Pi-hole & pihole-updatelists automated deployment script
# Repository: https://github.com/srinivasan-mk/pi-hole
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/config"

echo "============================================================"
echo "  Pi-hole & pihole-updatelists Deployment"
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

# Check/Install pihole-updatelists
if [ ! -f "/usr/local/sbin/pihole-updatelists" ]; then
    echo "[*] pihole-updatelists not found. Installing from github.com/jacklul/pihole-updatelists..."
    wget -qO - https://raw.githubusercontent.com/jacklul/pihole-updatelists/master/install.sh | bash
else
    echo "[+] pihole-updatelists is already installed."
fi

# Backup existing config if present
if [ -f "/etc/pihole-updatelists.conf" ]; then
    BACKUP_NAME="/etc/pihole-updatelists.conf.bak.$(date +%Y%m%d_%H%M%S)"
    echo "[*] Backing up existing config to ${BACKUP_NAME}"
    cp /etc/pihole-updatelists.conf "${BACKUP_NAME}"
fi

# Ensure /etc/pihole directory exists
mkdir -p /etc/pihole

# Deploy custom-blocklists.list
if [ -f "${CONFIG_DIR}/custom-blocklists.list" ]; then
    echo "[*] Installing /etc/pihole/custom-blocklists.list..."
    cp "${CONFIG_DIR}/custom-blocklists.list" /etc/pihole/custom-blocklists.list
    chmod 644 /etc/pihole/custom-blocklists.list
    sed -i 's/\r$//' /etc/pihole/custom-blocklists.list
fi

# Deploy pihole-updatelists.conf
if [ -f "${CONFIG_DIR}/pihole-updatelists.conf" ]; then
    echo "[*] Installing /etc/pihole-updatelists.conf..."
    cp "${CONFIG_DIR}/pihole-updatelists.conf" /etc/pihole-updatelists.conf
    chmod 644 /etc/pihole-updatelists.conf
    sed -i 's/\r$//' /etc/pihole-updatelists.conf
fi

echo "[+] Configuration files deployed successfully."

# Execute list synchronization
echo "------------------------------------------------------------"
echo "[*] Running pihole-updatelists..."
echo "------------------------------------------------------------"
/usr/local/sbin/pihole-updatelists

echo "------------------------------------------------------------"
echo "[+] Deployment completed successfully!"
echo "    Lists have been synchronized and Pi-hole gravity updated."
echo "============================================================"

