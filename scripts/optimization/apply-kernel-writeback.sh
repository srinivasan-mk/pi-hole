#!/usr/bin/env bash
# ==============================================================================
# Linux Kernel Dirty Buffer & Delayed Writeback Tuner
# Profiles:
#   balanced : 1 min flush check, 2 min page age (dirty 20/40)
#   ultra    : 5 min flush check, 5 min page age (dirty 25/50)
#   extreme  : 10 min flush check, 10 min page age (dirty 30/60)
# ==============================================================================

set -euo pipefail

PROFILE="${1:-extreme}"
SYSCTL_CONF="/etc/sysctl.d/99-sdcard-longevity.conf"

if [ "$(id -u)" -ne 0 ]; then
    echo "[-] This script must be run as root or with sudo."
    exit 1
fi

case "${PROFILE}" in
    balanced)
        DIRTY_BG=20
        DIRTY=40
        EXPIRE=12000   # 120s (2m)
        WRITEBACK=6000 # 60s (1m)
        ;;
    ultra)
        DIRTY_BG=25
        DIRTY=50
        EXPIRE=30000   # 300s (5m)
        WRITEBACK=30000 # 300s (5m)
        ;;
    extreme|zero-churn)
        DIRTY_BG=30
        DIRTY=60
        EXPIRE=60000   # 600s (10m)
        WRITEBACK=60000 # 600s (10m)
        ;;
    *)
        echo "[-] Unknown profile: ${PROFILE}. Use 'balanced', 'ultra', or 'extreme'."
        exit 1
        ;;
esac

echo "[*] Applying '${PROFILE}' profile to kernel delayed writeback..."

cat << EOF > "${SYSCTL_CONF}"
# SD Card Longevity: Batch writes in RAM instead of frequent flash trickle writes
# Profile: ${PROFILE}

# Start flushing in background only when dirty memory reaches this percentage of RAM
vm.dirty_background_ratio = ${DIRTY_BG}

# Force processes to pause and flush when dirty memory hits this ratio
vm.dirty_ratio = ${DIRTY}

# Keep dirty pages in RAM buffer up to ${EXPIRE} centisecs ($(( EXPIRE / 6000 )) mins) before committing
vm.dirty_expire_centisecs = ${EXPIRE}

# Kernel background flusher wakes every ${WRITEBACK} centisecs ($(( WRITEBACK / 6000 )) mins)
vm.dirty_writeback_centisecs = ${WRITEBACK}

# Retain directory and inode metadata in RAM to minimize repeated disk reads
vm.vfs_cache_pressure = 50
EOF

if command -v sysctl >/dev/null 2>&1; then
    sysctl --system >/dev/null 2>&1 || sysctl -p "${SYSCTL_CONF}" >/dev/null 2>&1
    echo "[+] Kernel parameters applied successfully from ${SYSCTL_CONF}."
    echo "    - Dirty ratios: ${DIRTY_BG}% background / ${DIRTY}% hard threshold"
    echo "    - Buffer flush interval: $(( WRITEBACK / 100 )) seconds ($(( WRITEBACK / 6000 )) minutes)"
fi
