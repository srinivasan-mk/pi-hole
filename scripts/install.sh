#!/usr/bin/env bash
# ==============================================================================
# pihole-cloud-updater installation script
# https://github.com/srinivasan-mk/pi-hole
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "============================================================"
echo "  Pi-hole Cloud Updater Installer"
echo "============================================================"

if [ "$(id -u)" -ne 0 ]; then
    echo "[-] This installer must be run with sudo or as root." >&2
    exit 1
fi

# Ensure Python 3 is installed
if ! command -v python3 >/dev/null 2>&1; then
    echo "[*] python3 not found. Attempting to install via package manager..."
    if command -v apt-get >/dev/null 2>&1; then
        apt-get update -y && apt-get install -y python3 python3-sqlite3
    elif command -v apk >/dev/null 2>&1; then
        apk add --no-cache python3 py3-sqlite3
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y python3 python3-sqlite3
    else
        echo "[-] Error: Unsupported package manager. Please install python3 manually." >&2
        exit 1
    fi
fi

# Target directories
INSTALL_DIR="/usr/local/share/pihole-cloud-updater"
BIN_DIR="/usr/local/sbin"
CONFIG_DIR="/etc"
SYSTEMD_DIR="/etc/systemd/system"

mkdir -p "${INSTALL_DIR}"
mkdir -p "${BIN_DIR}"
mkdir -p /var/cache/pihole-cloud-updater

# Copy files
echo "[*] Installing updater files to ${INSTALL_DIR}..."
cp "${SCRIPT_DIR}/pihole-cloud-updater.py" "${INSTALL_DIR}/pihole-cloud-updater.py"
chmod 755 "${INSTALL_DIR}/pihole-cloud-updater.py"

echo "[*] Installing CLI launcher to ${BIN_DIR}/pihole-cloud-updater..."
cp "${SCRIPT_DIR}/pihole-cloud-updater" "${BIN_DIR}/pihole-cloud-updater"
chmod 755 "${BIN_DIR}/pihole-cloud-updater"

# Copy default config if none exists
if [ ! -f "${CONFIG_DIR}/pihole-cloud-updater.conf" ]; then
    if [ -f "${PARENT_DIR}/config/pihole-cloud-updater.conf.example" ]; then
        echo "[*] Installing default configuration to ${CONFIG_DIR}/pihole-cloud-updater.conf..."
        cp "${PARENT_DIR}/config/pihole-cloud-updater.conf.example" "${CONFIG_DIR}/pihole-cloud-updater.conf"
        chmod 644 "${CONFIG_DIR}/pihole-cloud-updater.conf"
    fi
fi

# Install systemd timer if systemd is available
if command -v systemctl >/dev/null 2>&1 && [ -d "${SYSTEMD_DIR}" ]; then
    echo "[*] Installing systemd units..."
    cp "${PARENT_DIR}/systemd/pihole-cloud-updater.service" "${SYSTEMD_DIR}/"
    cp "${PARENT_DIR}/systemd/pihole-cloud-updater.timer" "${SYSTEMD_DIR}/"
    systemctl daemon-reload
    systemctl enable --now pihole-cloud-updater.timer
    echo "[+] Enabled pihole-cloud-updater.timer (runs daily at 03:30 AM)."
fi

echo "============================================================"
echo "[+] pihole-cloud-updater successfully installed!"
echo "    Run manually: sudo pihole-cloud-updater"
echo "    Dry run test: sudo pihole-cloud-updater --dry-run"
echo "    Config file : /etc/pihole-cloud-updater.conf"
echo "============================================================"

