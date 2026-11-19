#!/usr/bin/env bash
# ==============================================================================
# MicroSD Card & 24/7 Hardware Longevity Master Optimizer
# Repository: https://github.com/srinivasan-mk/pi-hole
#
# Profiles:
#   balanced : 1 min writeback flush, 60s commit, 15m Pi-hole DBinterval
#   ultra    : 5 min writeback flush, 300s commit, 30m Pi-hole DBinterval
#   extreme  : 10 min writeback flush, 600s commit, 60m Pi-hole DBinterval (Zero-Churn)
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROFILE="extreme"
ACTION="all"
AUTO_YES=false

show_help() {
    cat << EOF
Usage: sudo bash $0 [OPTIONS]

Profiles:
  -p, --profile PROFILE   Optimization intensity profile:
                            extreme  : (Default) 10m kernel flush, 600s ext4 commit, 60m Pi-hole DBinterval (Zero-Churn)
                            ultra    : 5m kernel flush, 300s ext4 commit, 30m Pi-hole DBinterval
                            balanced : 1m kernel flush, 60s ext4 commit, 15m Pi-hole DBinterval

Selective Actions (Omit to run full optimization):
  --kernel-only           Only tune Linux kernel dirty page writeback buffers
  --fstab-only            Only tune /etc/fstab commit intervals and tmpfs
  --pihole-only           Only tune Pi-hole database write intervals
  --journal-only          Only configure volatile RAM systemd journaling
  --swap-only             Only eliminate SD card swap thrashing
  --prune-gravity         Only prune redundant gravity.db backup files
  --status, --diagnostics Check current hardware and buffer status without modifying

General Options:
  -y, --yes               Run non-interactively
  -h, --help              Show this help message
EOF
}

# Parse flags
while [[ $# -gt 0 ]]; do
    case "$1" in
        -p|--profile)
            PROFILE="$2"
            shift 2
            ;;
        --kernel-only)
            ACTION="kernel"
            shift
            ;;
        --fstab-only)
            ACTION="fstab"
            shift
            ;;
        --pihole-only)
            ACTION="pihole"
            shift
            ;;
        --journal-only)
            ACTION="journal"
            shift
            ;;
        --swap-only)
            ACTION="swap"
            shift
            ;;
        --prune-gravity)
            ACTION="prune"
            shift
            ;;
        --status|--diagnostics|--check)
            ACTION="status"
            shift
            ;;
        -y|--yes|--unattended)
            AUTO_YES=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            shift
            ;;
    esac
done

# If action is status, just run the diagnostics script
if [ "${ACTION}" = "status" ]; then
    if [ -f "${SCRIPT_DIR}/check-hardware-health.sh" ]; then
        bash "${SCRIPT_DIR}/check-hardware-health.sh"
    fi
    exit 0
fi

# Ensure running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "[-] This script must be run with sudo or as root."
    echo "    Usage: sudo bash $0 [-p extreme] [-y]"
    exit 1
fi

echo "============================================================"
echo "  Raspberry Pi 24/7 SD Card & Hardware Longevity Optimizer"
echo "  Target Profile: ${PROFILE^^}"
echo "============================================================"
echo ""

TOTAL_RAM_MB=$(free -m | awk '/^Mem:/{print $2}')
echo "[*] Detected System RAM: ${TOTAL_RAM_MB} MB"

# 1. Kernel Delayed Batch Writeback
if [ "${ACTION}" = "all" ] || [ "${ACTION}" = "kernel" ]; then
    echo ""
    echo "[*] Step: Kernel Page Cache Delayed Batch Writeback..."
    if [ -f "${SCRIPT_DIR}/apply-kernel-writeback.sh" ]; then
        bash "${SCRIPT_DIR}/apply-kernel-writeback.sh" "${PROFILE}"
    fi
fi

# 2. Filesystem Mounts & Commit Interval
if [ "${ACTION}" = "all" ] || [ "${ACTION}" = "fstab" ]; then
    echo ""
    echo "[*] Step: ext4 Delayed Journal Commit & tmpfs Mounts..."
    if [ -f "${SCRIPT_DIR}/apply-fstab-commit.sh" ]; then
        bash "${SCRIPT_DIR}/apply-fstab-commit.sh" "${PROFILE}"
    fi
fi

# 3. MicroSD Swap Thrashing Elimination
if [ "${ACTION}" = "all" ] || [ "${ACTION}" = "swap" ]; then
    echo ""
    echo "[*] Step: MicroSD Swap Thrashing Check..."
    if systemctl is-active --quiet dphys-swapfile 2>/dev/null || [ -f /etc/init.d/dphys-swapfile ]; then
        echo "[*] Disabling and removing SD card dphys-swapfile..."
        systemctl stop dphys-swapfile 2>/dev/null || true
        systemctl disable dphys-swapfile 2>/dev/null || true
        if command -v dphys-swapfile >/dev/null 2>&1; then
            dphys-swapfile swapoff 2>/dev/null || true
            dphys-swapfile uninstall 2>/dev/null || true
        fi
        rm -f /var/swap 2>/dev/null || true
        echo "[+] SD card swap file eliminated."
    else
        echo "[+] No active dphys-swapfile on SD card detected."
    fi

    if grep -q "zram" /proc/swaps 2>/dev/null; then
        echo "[+] Active RAM swap (zram) detected. Safe zero-flash-wear memory expansion is active."
    fi
fi

# 4. Volatile RAM Systemd Journal
if [ "${ACTION}" = "all" ] || [ "${ACTION}" = "journal" ]; then
    echo ""
    echo "[*] Step: Volatile RAM Systemd Journal..."
    JOURNAL_CONF_DIR="/etc/systemd/journald.conf.d"
    mkdir -p "${JOURNAL_CONF_DIR}"
    cat << 'EOF' > "${JOURNAL_CONF_DIR}/volatile-storage.conf"
[Journal]
Storage=volatile
RuntimeMaxUse=64M
EOF
    if systemctl is-active --quiet systemd-journald 2>/dev/null; then
        systemctl restart systemd-journald 2>/dev/null || true
        echo "[+] Configured volatile RAM storage for systemd-journald."
    fi
fi

# 5. Pi-hole FTL Database Write Batching
if [ "${ACTION}" = "all" ] || [ "${ACTION}" = "pihole" ]; then
    echo ""
    echo "[*] Step: Pi-hole Database Write Batching..."
    if [ -f "${SCRIPT_DIR}/apply-pihole-batching.sh" ]; then
        bash "${SCRIPT_DIR}/apply-pihole-batching.sh" "${PROFILE}"
    fi
fi

# 6. Prune Redundant Gravity Backups
if [ "${ACTION}" = "all" ] || [ "${ACTION}" = "prune" ]; then
    echo ""
    echo "[*] Step: Pruning redundant gravity.db backup copies..."
    if [ -d "/etc/pihole" ]; then
        BACKUP_COUNT=$(ls -1 /etc/pihole/gravity.db.bak.* 2>/dev/null | wc -l || echo 0)
        if [ "${BACKUP_COUNT}" -gt 1 ]; then
            echo "[*] Found ${BACKUP_COUNT} old gravity.db backup copies. Pruning to retain only the latest 1..."
            ls -1t /etc/pihole/gravity.db.bak.* | tail -n +2 | xargs -r rm -f
            REMAINING=$(ls -1 /etc/pihole/gravity.db.bak.* 2>/dev/null | wc -l || echo 0)
            echo "[+] Reclaimed SD card space! Retained ${REMAINING} latest backup."
        else
            echo "[+] No redundant gravity.db backup files found."
        fi
    fi
fi

# 7. Final Health Diagnostics
echo ""
if [ -f "${SCRIPT_DIR}/check-hardware-health.sh" ]; then
    bash "${SCRIPT_DIR}/check-hardware-health.sh"
fi

echo ""
echo "[+] Profile '${PROFILE^^}' applied successfully!"
