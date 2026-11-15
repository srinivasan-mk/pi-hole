#!/usr/bin/env bash
# ==============================================================================
# ext4 Filesystem Commit Interval & tmpfs Optimizer
# Profiles:
#   balanced : commit=60  (1 min)
#   ultra    : commit=300 (5 min)
#   extreme  : commit=600 (10 min)
# ==============================================================================

set -euo pipefail

PROFILE="${1:-extreme}"
FSTAB="/etc/fstab"

if [ "$(id -u)" -ne 0 ]; then
    echo "[-] This script must be run as root or with sudo."
    exit 1
fi

case "${PROFILE}" in
    balanced)
        COMMIT=60
        ;;
    ultra)
        COMMIT=300
        ;;
    extreme|zero-churn)
        COMMIT=600
        ;;
    [0-9]*)
        COMMIT="${PROFILE}"
        ;;
    *)
        echo "[-] Unknown profile: ${PROFILE}. Use 'balanced', 'ultra', or 'extreme'."
        exit 1
        ;;
esac

echo "[*] Configuring /etc/fstab with commit=${COMMIT}s ($(( COMMIT / 60 )) min)..."

if [ -f "${FSTAB}" ]; then
    FSTAB_BAK="${FSTAB}.bak.$(date +%Y%m%d_%H%M%S)"
    cp "${FSTAB}" "${FSTAB_BAK}"

    # Replace existing commit= if present, or add commit=
    if grep -E '\s+/\s+ext4\s+' "${FSTAB}" | grep -q 'commit='; then
        sed -i -E "s/commit=[0-9]+/commit=${COMMIT}/" "${FSTAB}"
    else
        sed -i -E "s|(\s+/\s+ext4\s+defaults)(,[a-zA-Z0-9_=]+)*|\1,noatime,commit=${COMMIT}|" "${FSTAB}" || true
        if ! grep -E '\s+/\s+ext4\s+' "${FSTAB}" | grep -q "commit=${COMMIT}"; then
            sed -i -E "s|(\s+/\s+ext4\s+)(\S+)|\1\2,noatime,commit=${COMMIT}|" "${FSTAB}" || true
        fi
    fi

    # Add /var/tmp tmpfs mount if not already present
    if ! grep -q '\s+/var/tmp\s+tmpfs' "${FSTAB}"; then
        echo "tmpfs    /var/tmp    tmpfs    defaults,noatime,nosuid,size=256m    0    0" >> "${FSTAB}"
    fi

    mount -o remount / 2>/dev/null || true
    mount -a 2>/dev/null || true
    echo "[+] Root ext4 remounted with commit=${COMMIT}s."
fi
