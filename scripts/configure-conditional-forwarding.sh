#!/usr/bin/env bash
# ==============================================================================
# Pi-hole Conditional Forwarding Automated Configuration
# Forwards local reverse DNS (PTR) and domain lookups to the router DHCP server
# to reveal friendly client/device hostnames in the Pi-hole Query Log & Dashboard.
# Repository: https://github.com/srinivasan-mk/pi-hole
# ==============================================================================

set -euo pipefail

AUTO_YES=false
ROUTER_IP=""
LOCAL_SUBNET=""
LOCAL_DOMAIN="lan"
INTERFACE=""
DISABLE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -y|--yes|--unattended)
            AUTO_YES=true
            shift
            ;;
        -r|--router|--router-ip)
            ROUTER_IP="$2"
            shift 2
            ;;
        -s|--subnet|--local-subnet)
            LOCAL_SUBNET="$2"
            shift 2
            ;;
        -d|--domain|--local-domain)
            LOCAL_DOMAIN="$2"
            shift 2
            ;;
        -i|--interface)
            INTERFACE="$2"
            shift 2
            ;;
        --disable)
            DISABLE=true
            shift
            ;;
        -h|--help)
            echo "Usage: sudo bash $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -y, --yes            Apply auto-detected settings without prompting"
            echo "  -r, --router-ip IP   Router / DHCP server IP (default: auto-detected gateway)"
            echo "  -s, --subnet CIDR    Local network in CIDR notation (e.g. 192.168.1.0/24)"
            echo "  -d, --domain NAME    Local domain name (default: lan)"
            echo "  --disable            Disable conditional forwarding"
            echo "  -h, --help           Show this help message"
            exit 0
            ;;
        *)
            echo "[-] Unknown option: $1" >&2
            echo "    Use --help for usage details." >&2
            exit 1
            ;;
    esac
done

echo "============================================================"
echo "  Pi-hole Conditional Forwarding Setup"
echo "============================================================"

# Preflight check: must be root
if [ "$(id -u)" -ne 0 ]; then
    echo "[-] Error: This script must be run with sudo or as root." >&2
    exit 1
fi

# Check Pi-hole installation
if ! command -v pihole >/dev/null 2>&1; then
    echo "[-] Error: Pi-hole is not installed on this system." >&2
    exit 1
fi

DNSMASQ_CONF="/etc/dnsmasq.d/02-conditional-forwarding.conf"
SETUP_VARS="/etc/pihole/setupVars.conf"

# Handle disabling
if [ "${DISABLE}" = true ]; then
    echo "[*] Disabling conditional forwarding..."
    rm -f "${DNSMASQ_CONF}"
    if [ -f "${SETUP_VARS}" ]; then
        sed -i '/CONDITIONAL_FORWARDING/d' "${SETUP_VARS}"
    fi
    # If Pi-hole v6 FTL
    if command -v pihole-FTL >/dev/null 2>&1; then
        pihole-FTL --config dns.revServers "[]" 2>/dev/null || true
    fi
    echo "[*] Restarting Pi-hole DNS..."
    pihole restartdns
    echo "[+] Conditional forwarding has been disabled."
    exit 0
fi

# Auto-detect interface
if [ -z "${INTERFACE}" ]; then
    INTERFACE=$(ip route show default 2>/dev/null | awk '/default/ {print $5}' | head -n1 || true)
    if [ -z "${INTERFACE}" ]; then
        INTERFACE=$(ip -4 -o addr show scope global | awk '{print $2}' | head -n1 || echo "eth0")
    fi
fi

# Auto-detect default router IP (gateway)
if [ -z "${ROUTER_IP}" ]; then
    ROUTER_IP=$(ip route show default dev "${INTERFACE}" 2>/dev/null | awk '/default/ {print $3}' | head -n1 || true)
    if [ -z "${ROUTER_IP}" ]; then
        ROUTER_IP=$(ip route show default 2>/dev/null | awk '/default/ {print $3}' | head -n1 || echo "192.168.1.1")
    fi
fi

# Auto-detect local subnet in CIDR notation (e.g. 192.168.1.0/24 or 192.168.31.0/24)
if [ -z "${LOCAL_SUBNET}" ]; then
    # Look for link subnet route on primary interface
    LOCAL_SUBNET=$(ip -4 route show dev "${INTERFACE}" scope link 2>/dev/null | awk '{print $1}' | head -n1 || true)
    if [ -z "${LOCAL_SUBNET}" ] || [[ ! "${LOCAL_SUBNET}" =~ / ]]; then
        # Fallback to computing from IP address
        RAW_IP=$(ip -4 -o addr show dev "${INTERFACE}" scope global | awk '{print $4}' | head -n1 || true)
        if [ -n "${RAW_IP}" ]; then
            # Extract network and mask
            IP_BASE=$(echo "${RAW_IP}" | cut -d'/' -f1 | awk -F. '{print $1"."$2"."$3".0"}')
            MASK=$(echo "${RAW_IP}" | cut -d'/' -f2)
            LOCAL_SUBNET="${IP_BASE}/${MASK}"
        else
            LOCAL_SUBNET="192.168.1.0/24"
        fi
    fi
fi

# Check /etc/resolv.conf for search domain if default 'lan'
if [ "${LOCAL_DOMAIN}" = "lan" ]; then
    DETECTED_SEARCH=$(awk '/^search/ {print $2}' /etc/resolv.conf 2>/dev/null || true)
    if [ -n "${DETECTED_SEARCH}" ] && [ "${DETECTED_SEARCH}" != "lan" ] && [ "${DETECTED_SEARCH}" != "." ]; then
        LOCAL_DOMAIN="${DETECTED_SEARCH}"
    fi
fi

echo "[*] Network parameters detected for Conditional Forwarding:"
echo "    Router / Local DNS IP : ${ROUTER_IP}"
echo "    Local Subnet (CIDR)   : ${LOCAL_SUBNET}"
echo "    Local Domain Name     : ${LOCAL_DOMAIN}"
echo ""

if [ "${AUTO_YES}" != true ]; then
    read -r -p "Use detected Router IP [${ROUTER_IP}] (or enter custom IP): " input_router
    if [ -n "${input_router}" ]; then ROUTER_IP="${input_router}"; fi

    read -r -p "Use detected Subnet [${LOCAL_SUBNET}] (or enter custom CIDR): " input_subnet
    if [ -n "${input_subnet}" ]; then LOCAL_SUBNET="${input_subnet}"; fi

    read -r -p "Use Local Domain [${LOCAL_DOMAIN}] (or enter custom domain): " input_domain
    if [ -n "${input_domain}" ]; then LOCAL_DOMAIN="${input_domain}"; fi
fi

echo ""
echo "[*] Applying configuration..."

# 1. Create dnsmasq drop-in configuration (Universal for Pi-hole v5 and v6)
mkdir -p /etc/dnsmasq.d
cat > "${DNSMASQ_CONF}" << EOF
# ==============================================================================
# Pi-hole Conditional Forwarding Configuration
# Managed by pi-hole scripts (scripts/configure-conditional-forwarding.sh)
# ==============================================================================
# Forward reverse lookups (PTR queries) for the local network to the router:
rev-server=${LOCAL_SUBNET},${ROUTER_IP}

# Forward queries for the local domain to the router:
server=/${LOCAL_DOMAIN}/${ROUTER_IP}
EOF
chmod 644 "${DNSMASQ_CONF}"
echo "[+] Created ${DNSMASQ_CONF}"

# 2. Update /etc/pihole/setupVars.conf so Pi-hole Web Admin UI reflects it
if [ -f "${SETUP_VARS}" ]; then
    sed -i '/CONDITIONAL_FORWARDING/d' "${SETUP_VARS}"
    cat >> "${SETUP_VARS}" << EOF
CONDITIONAL_FORWARDING=true
CONDITIONAL_FORWARDING_IP=${ROUTER_IP}
CONDITIONAL_FORWARDING_DOMAIN=${LOCAL_DOMAIN}
CONDITIONAL_FORWARDING_REVERSE=${LOCAL_SUBNET}
EOF
    echo "[+] Updated ${SETUP_VARS}"
fi

# 3. If Pi-hole v6 FTL is active, sync into FTL config
if command -v pihole-FTL >/dev/null 2>&1; then
    pihole-FTL --config dns.revServers "[\"${LOCAL_SUBNET},${ROUTER_IP},${LOCAL_DOMAIN}\"]" 2>/dev/null || true
fi

# 4. Restart Pi-hole DNS engine to activate changes
echo "[*] Reloading Pi-hole DNS engine..."
pihole restartdns

echo "============================================================"
echo "[+] Conditional Forwarding enabled successfully!"
echo "    - Reverse PTR queries for ${LOCAL_SUBNET} -> ${ROUTER_IP}"
echo "    - Local domain '*.${LOCAL_DOMAIN}' queries -> ${ROUTER_IP}"
echo ""
echo "Device names will now start appearing in the Pi-hole Query Log,"
echo "Top Clients list, and Dashboard as DHCP leases resolve!"
echo "============================================================"
