#!/usr/bin/env bash
# ==============================================================================
# Pi-hole FTL Database Write Batching Optimizer (v5 and v6)
# Profiles:
#   balanced : DBinterval = 900s  (15 mins)
#   ultra    : DBinterval = 1800s (30 mins)
#   extreme  : DBinterval = 3600s (60 mins)
# ==============================================================================

set -euo pipefail

PROFILE="${1:-extreme}"

if [ "$(id -u)" -ne 0 ]; then
    echo "[-] This script must be run as root or with sudo."
    exit 1
fi

case "${PROFILE}" in
    balanced)
        INTERVAL_SEC=900
        INTERVAL_MIN=15.0
        ;;
    ultra)
        INTERVAL_SEC=1800
        INTERVAL_MIN=30.0
        ;;
    extreme|zero-churn)
        INTERVAL_SEC=3600
        INTERVAL_MIN=60.0
        ;;
    [0-9]*)
        INTERVAL_SEC="${PROFILE}"
        INTERVAL_MIN=$(awk "BEGIN {printf \"%.1f\", ${INTERVAL_SEC}/60}")
        ;;
    *)
        echo "[-] Unknown profile: ${PROFILE}. Use 'balanced', 'ultra', or 'extreme'."
        exit 1
        ;;
esac

echo "[*] Configuring Pi-hole query database write batching (${INTERVAL_SEC}s / ${INTERVAL_MIN}m)..."

# 1. Pi-hole v6 (pihole.toml)
if [ -f "/etc/pihole/pihole.toml" ]; then
    echo "[*] Updating Pi-hole v6 configuration..."
    if command -v pihole-FTL >/dev/null 2>&1 && pihole-FTL --help 2>&1 | grep -q -- '--config'; then
        pihole-FTL --config database.DBinterval "${INTERVAL_SEC}" 2>/dev/null || true
        pihole-FTL --config database.maxDBdays 14 2>/dev/null || true
    else
        sed -i -E "s/^[[:space:]]*DBinterval[[:space:]]*=[[:space:]]*[0-9]+/  DBinterval = ${INTERVAL_SEC}/" /etc/pihole/pihole.toml
        sed -i -E "s/^[[:space:]]*maxDBdays[[:space:]]*=[[:space:]]*[0-9]+/  maxDBdays = 14/" /etc/pihole/pihole.toml
    fi
    echo "[+] Pi-hole v6 configured with DBinterval = ${INTERVAL_SEC}s and maxDBdays = 14."
fi

# 2. Pi-hole v5 / FTL conf fallback (/etc/pihole/pihole-FTL.conf)
FTL_CONF="/etc/pihole/pihole-FTL.conf"
if [ -f "${FTL_CONF}" ] || [ ! -f "/etc/pihole/pihole.toml" ]; then
    mkdir -p /etc/pihole
    touch "${FTL_CONF}"
    if grep -q "^DBINTERVAL=" "${FTL_CONF}"; then
        sed -i "s/^DBINTERVAL=.*/DBINTERVAL=${INTERVAL_MIN}/" "${FTL_CONF}"
    else
        echo "DBINTERVAL=${INTERVAL_MIN}" >> "${FTL_CONF}"
    fi

    if grep -q "^MAXDBDAYS=" "${FTL_CONF}"; then
        sed -i 's/^MAXDBDAYS=.*/MAXDBDAYS=14/' "${FTL_CONF}"
    else
        echo "MAXDBDAYS=14" >> "${FTL_CONF}"
    fi
    echo "[+] Pi-hole v5/FTL configured with DBINTERVAL=${INTERVAL_MIN}m."
fi

# Restart pihole-FTL
if systemctl is-active --quiet pihole-FTL 2>/dev/null; then
    systemctl restart pihole-FTL
    echo "[+] Restarted pihole-FTL service."
fi
