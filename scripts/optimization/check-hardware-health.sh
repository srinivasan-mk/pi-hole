#!/usr/bin/env bash
# ==============================================================================
# Hardware Health & Storage Diagnostics for Raspberry Pi
# Repository: https://github.com/srinivasan-mk/pi-hole
# ==============================================================================

set -euo pipefail

echo "============================================================"
echo "  Raspberry Pi Hardware & Storage Diagnostics"
echo "============================================================"

# 1. Temperature
if [ -f "/sys/class/thermal/thermal_zone0/temp" ]; then
    RAW_TEMP=$(cat /sys/class/thermal/thermal_zone0/temp)
    TEMP_C=$(awk "BEGIN {printf \"%.1f\", ${RAW_TEMP}/1000}")
    echo "  [✓] SoC Temperature          : ${TEMP_C}°C"
else
    echo "  [-] SoC Temperature          : N/A"
fi

# 2. Power & Throttling
if command -v vcgencmd >/dev/null 2>&1; then
    THROTTLED=$(vcgencmd get_throttled 2>/dev/null || echo "N/A")
    echo "  [✓] Power / Throttle State   : ${THROTTLED}"
    if [ "${THROTTLED}" = "throttled=0x0" ]; then
        echo "      (Power supply voltage is solid, no under-voltage detected)"
    elif [ "${THROTTLED}" != "N/A" ]; then
        echo "      [!] Warning: Undervoltage or frequency throttling has occurred!"
    fi
fi

# 3. Memory & Dirty Page Buffer
TOTAL_MEM=$(free -h | awk '/^Mem:/{print $2}')
USED_MEM=$(free -h | awk '/^Mem:/{print $3}')
AVAIL_MEM=$(free -h | awk '/^Mem:/{print $7}')
DIRTY_PAGES=$(grep -i '^Dirty:' /proc/meminfo 2>/dev/null | awk '{print $2 " " $3}' || echo "N/A")
WRITEBACK_PAGES=$(grep -i '^Writeback:' /proc/meminfo 2>/dev/null | awk '{print $2 " " $3}' || echo "N/A")

echo ""
echo "--- Memory & Buffer Status ---"
echo "  * Total RAM                  : ${TOTAL_MEM}"
echo "  * Used RAM                   : ${USED_MEM}"
echo "  * Available RAM              : ${AVAIL_MEM}"
echo "  * Currently Dirty in Buffer  : ${DIRTY_PAGES}"
echo "  * Active Writeback in Prog   : ${WRITEBACK_PAGES}"

# 4. Storage & Filesystem Mounts
echo ""
echo "--- Storage & Commit Interval ---"
df -h / | awk 'NR>1 {print "  * Root Partition Usage       : " $3 " used / " $2 " total (" $5 " full)"}'
ROOT_MOUNT=$(grep -E '\s+/\s+ext4\s+' /etc/fstab 2>/dev/null || echo "N/A")
echo "  * Root Mount in /etc/fstab   : ${ROOT_MOUNT}"
if echo "${ROOT_MOUNT}" | grep -q "commit="; then
    COMMIT_VAL=$(echo "${ROOT_MOUNT}" | grep -o 'commit=[0-9]\+' | cut -d= -f2)
    echo "    -> Commit interval: ${COMMIT_VAL}s ($(( COMMIT_VAL / 60 )) min)"
fi

# 5. Kernel Writeback sysctl values
echo ""
echo "--- Kernel Delayed Writeback Configuration ---"
echo "  * vm.dirty_ratio             : $(cat /proc/sys/vm/dirty_ratio 2>/dev/null || echo 'N/A')%"
echo "  * vm.dirty_background_ratio  : $(cat /proc/sys/vm/dirty_background_ratio 2>/dev/null || echo 'N/A')%"
WB_CS=$(cat /proc/sys/vm/dirty_writeback_centisecs 2>/dev/null || echo 0)
EX_CS=$(cat /proc/sys/vm/dirty_expire_centisecs 2>/dev/null || echo 0)
echo "  * vm.dirty_writeback_centisecs: ${WB_CS} (flush check every $(( WB_CS / 100 ))s / $(( WB_CS / 6000 ))m)"
echo "  * vm.dirty_expire_centisecs  : ${EX_CS} (buffer page max age $(( EX_CS / 100 ))s / $(( EX_CS / 6000 ))m)"
echo "  * vm.vfs_cache_pressure      : $(cat /proc/sys/vm/vfs_cache_pressure 2>/dev/null || echo 'N/A')"

# 6. Pi-hole Database Write Interval
echo ""
echo "--- Pi-hole Database Write Interval ---"
if [ -f "/etc/pihole/pihole.toml" ]; then
    DB_INT=$(grep -E '^[[:space:]]*DBinterval[[:space:]]*=' /etc/pihole/pihole.toml 2>/dev/null | awk -F= '{print $2}' | awk '{print $1}' | tr -d ' ' || echo "N/A")
    MAX_DAYS=$(grep -E '^[[:space:]]*maxDBdays[[:space:]]*=' /etc/pihole/pihole.toml 2>/dev/null | awk -F= '{print $2}' | awk '{print $1}' | tr -d ' ' || echo "N/A")
    if [[ "${DB_INT}" =~ ^[0-9]+$ ]]; then
        echo "  * Pi-hole v6 DBinterval      : ${DB_INT}s ($(( DB_INT / 60 )) min)"
    else
        echo "  * Pi-hole v6 DBinterval      : ${DB_INT}"
    fi
    echo "  * Pi-hole v6 maxDBdays       : ${MAX_DAYS} days"
elif [ -f "/etc/pihole/pihole-FTL.conf" ]; then
    DB_INT=$(grep '^DBINTERVAL=' /etc/pihole/pihole-FTL.conf 2>/dev/null | cut -d= -f2 || echo "1.0 (default)")
    echo "  * Pi-hole v5 DBINTERVAL      : ${DB_INT} min"
fi

# 7. Swap Status
echo ""
echo "--- Swap & Wear Protection ---"
SWAP_LINE=$(awk 'NR>1 {printf "%s (%s, size %s) ", $1, $2, $3}' /proc/swaps 2>/dev/null || echo "None")
echo "  * Active Swap                : ${SWAP_LINE:-None}"

echo "============================================================"
