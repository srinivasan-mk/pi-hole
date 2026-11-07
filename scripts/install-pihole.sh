#!/usr/bin/env bash
# ==============================================================================
# Pi-hole Automated / Unattended Installation Script
# Supports: Debian, Raspberry Pi OS (Bullseye, Bookworm, Trixie), Ubuntu
# Repository: https://github.com/srinivasan-mk/pi-hole
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default settings (can be overridden by environment variables or CLI flags)
UNATTENDED=false
PIHOLE_PASSWORD="${PIHOLE_PASSWORD:-}"
DNS_1="${DNS_1:-1.1.1.1}"      # Cloudflare primary
DNS_2="${DNS_2:-1.0.0.1}"      # Cloudflare secondary
DNS_3="${DNS_3:-9.9.9.9}"      # Quad9 fallback
INTERFACE="${PIHOLE_INTERFACE:-}"
STATIC_IP="${PIHOLE_STATIC_IP:-}"
GATEWAY="${PIHOLE_GATEWAY:-}"
ENABLE_CF="${PIHOLE_CONDITIONAL_FORWARDING:-false}"
ROUTER_IP="${PIHOLE_ROUTER_IP:-}"
LOCAL_SUBNET="${PIHOLE_LOCAL_SUBNET:-}"
LOCAL_DOMAIN="${PIHOLE_LOCAL_DOMAIN:-lan}"

# Parse command line options
while [[ $# -gt 0 ]]; do
    case "$1" in
        -y|--unattended|--non-interactive)
            UNATTENDED=true
            shift
            ;;
        -p|--password)
            PIHOLE_PASSWORD="$2"
            shift 2
            ;;
        -i|--interface)
            INTERFACE="$2"
            shift 2
            ;;
        --dns1)
            DNS_1="$2"
            shift 2
            ;;
        --dns2)
            DNS_2="$2"
            shift 2
            ;;
        --cf|--conditional-forwarding)
            ENABLE_CF=true
            shift
            ;;
        --router-ip)
            ROUTER_IP="$2"
            ENABLE_CF=true
            shift 2
            ;;
        --local-subnet)
            LOCAL_SUBNET="$2"
            ENABLE_CF=true
            shift 2
            ;;
        --local-domain)
            LOCAL_DOMAIN="$2"
            ENABLE_CF=true
            shift 2
            ;;
        -h|--help)
            echo "Usage: sudo bash $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  -y, --unattended         Run completely unattended with auto-detected network settings"
            echo "  -p, --password PWD       Set custom admin Web GUI password"
            echo "  -i, --interface IF       Network interface (e.g. eth0, wlan0) [auto-detected if omitted]"
            echo "  --dns1 IP                Primary upstream DNS server (default: 1.1.1.1)"
            echo "  --dns2 IP                Secondary upstream DNS server (default: 1.0.0.1)"
            echo "  --cf                     Enable Conditional Forwarding to reveal client names"
            echo "  --router-ip IP           Router IP for Conditional Forwarding (default: auto-detected)"
            echo "  --local-subnet CIDR      Local subnet in CIDR notation (default: auto-detected)"
            echo "  --local-domain DOMAIN    Local domain name (default: lan)"
            echo "  -h, --help               Show this help message"
            exit 0
            ;;
        *)
            echo "[-] Unknown option: $1" >&2
            echo "    Use --help for usage information." >&2
            exit 1
            ;;
    esac
done

echo "============================================================"
echo "  Pi-hole Automated Installer"
echo "============================================================"

# --- Preflight Checks ---
if [ "$(id -u)" -ne 0 ]; then
    echo "[-] Error: This installer must be run with sudo or as root." >&2
    echo "    Usage: sudo bash $0 [options]" >&2
    exit 1
fi

# Check if Pi-hole is already installed
if command -v pihole >/dev/null 2>&1; then
    echo "[+] Pi-hole is already installed on this system:"
    pihole -v
    echo ""
    read -r -p "Do you want to update Pi-hole to the latest version? [Y/n]: " update_choice || update_choice="Y"
    if [[ "$update_choice" =~ ^[Yy]?$ ]]; then
        echo "[*] Updating Pi-hole..."
        pihole -up
    fi

    if [ -n "${PIHOLE_PASSWORD}" ]; then
        echo "[*] Setting Pi-hole admin password..."
        pihole -a -p "${PIHOLE_PASSWORD}"
    fi

    if [ "${ENABLE_CF}" = true ] && [ -f "${SCRIPT_DIR}/configure-conditional-forwarding.sh" ]; then
        echo "[*] Configuring Conditional Forwarding..."
        bash "${SCRIPT_DIR}/configure-conditional-forwarding.sh" -y \
            ${ROUTER_IP:+-r "$ROUTER_IP"} \
            ${LOCAL_SUBNET:+-s "$LOCAL_SUBNET"} \
            ${LOCAL_DOMAIN:+-d "$LOCAL_DOMAIN"}
    fi

    echo "[+] Pi-hole setup complete."
    exit 0
fi

# Ensure basic utilities are present
echo "[*] Updating package index and verifying prerequisites..."
if command -v apt-get >/dev/null 2>&1; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y --no-install-recommends \
        curl \
        wget \
        git \
        dnsutils \
        iproute2 \
        ca-certificates \
        whiptail
fi

# Detect primary network interface and IP
if [ -z "${INTERFACE}" ]; then
    INTERFACE=$(ip route show default 2>/dev/null | awk '/default/ {print $5}' | head -n1 || true)
    if [ -z "${INTERFACE}" ]; then
        INTERFACE=$(ip -4 -o addr show scope global | awk '{print $2}' | head -n1 || echo "eth0")
    fi
fi

if [ -z "${STATIC_IP}" ]; then
    STATIC_IP=$(ip -4 -o addr show dev "${INTERFACE}" scope global | awk '{print $4}' | head -n1 || true)
fi

if [ -z "${GATEWAY}" ]; then
    GATEWAY=$(ip route show default dev "${INTERFACE}" 2>/dev/null | awk '/default/ {print $3}' | head -n1 || true)
fi

# Compute subnet if conditional forwarding requested
if [ -z "${ROUTER_IP}" ]; then
    ROUTER_IP="${GATEWAY}"
fi

if [ -z "${LOCAL_SUBNET}" ]; then
    LOCAL_SUBNET=$(ip -4 route show dev "${INTERFACE}" scope link 2>/dev/null | awk '{print $1}' | head -n1 || true)
    if [ -z "${LOCAL_SUBNET}" ] || [[ ! "${LOCAL_SUBNET}" =~ / ]]; then
        IP_BASE=$(echo "${STATIC_IP}" | cut -d'/' -f1 | awk -F. '{print $1"."$2"."$3".0"}')
        MASK=$(echo "${STATIC_IP}" | cut -d'/' -f2)
        LOCAL_SUBNET="${IP_BASE}/${MASK}"
    fi
fi

echo "[*] Network configuration detected:"
echo "    Interface : ${INTERFACE}"
echo "    IPv4/CIDR : ${STATIC_IP:-unknown}"
echo "    Gateway   : ${GATEWAY:-unknown}"
echo "    Upstream  : ${DNS_1}, ${DNS_2}"
if [ "${ENABLE_CF}" = true ]; then
    echo "    Cond. Fwd : Enabled -> Router: ${ROUTER_IP}, Subnet: ${LOCAL_SUBNET}, Domain: ${LOCAL_DOMAIN}"
fi

# Prepare automated setupVars.conf if unattended mode is requested
mkdir -p /etc/pihole

if [ "${UNATTENDED}" = true ]; then
    echo "[*] Configuring unattended installation (/etc/pihole/setupVars.conf)..."
    cat > /etc/pihole/setupVars.conf << EOF
PIHOLE_INTERFACE=${INTERFACE}
IPV4_ADDRESS=${STATIC_IP}
IPV6_ADDRESS=
PIHOLE_DNS_1=${DNS_1}
PIHOLE_DNS_2=${DNS_2}
PIHOLE_DNS_3=${DNS_3}
QUERY_LOGGING=true
INSTALL_WEB_SERVER=true
INSTALL_WEB_INTERFACE=true
LIGHTTPD_ENABLED=true
CACHE_SIZE=10000
BLOCKING_ENABLED=true
EOF
    if [ "${ENABLE_CF}" = true ]; then
        cat >> /etc/pihole/setupVars.conf << EOF
CONDITIONAL_FORWARDING=true
CONDITIONAL_FORWARDING_IP=${ROUTER_IP}
CONDITIONAL_FORWARDING_DOMAIN=${LOCAL_DOMAIN}
CONDITIONAL_FORWARDING_REVERSE=${LOCAL_SUBNET}
EOF
    fi
    chmod 644 /etc/pihole/setupVars.conf

    echo "[*] Running official Pi-hole unattended installer..."
    curl -sSL https://install.pi-hole.net | bash --unattended
else
    echo "[*] Launching standard Pi-hole guided installer..."
    curl -sSL https://install.pi-hole.net | bash
fi

# --- Post-Installation Configuration ---
echo "------------------------------------------------------------"
echo "[*] Configuring Pi-hole services and security..."

# Set custom or generated admin password
if [ -n "${PIHOLE_PASSWORD}" ]; then
    echo "[*] Setting Web GUI password..."
    pihole -a -p "${PIHOLE_PASSWORD}"
    echo "[+] Admin password set successfully."
else
    if [ "${UNATTENDED}" = true ]; then
        GEN_PWD=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 12 ; echo '')
        pihole -a -p "${GEN_PWD}"
        echo "[+] Admin password automatically generated: ${GEN_PWD}"
        echo "    (You can change it later using: sudo pihole -a -p)"
    fi
fi

# Configure Conditional Forwarding drop-in if requested
if [ "${ENABLE_CF}" = true ]; then
    echo "[*] Setting up Conditional Forwarding in /etc/dnsmasq.d/02-conditional-forwarding.conf..."
    mkdir -p /etc/dnsmasq.d
    cat > /etc/dnsmasq.d/02-conditional-forwarding.conf << EOF
# Conditional Forwarding for local reverse PTR and local domain queries
rev-server=${LOCAL_SUBNET},${ROUTER_IP}
server=/${LOCAL_DOMAIN}/${ROUTER_IP}
EOF
    chmod 644 /etc/dnsmasq.d/02-conditional-forwarding.conf
    pihole restartdns
    echo "[+] Conditional Forwarding configured."
fi

# Configure firewall rules if UFW is active
if command -v ufw >/dev/null 2>&1 && ufw status | grep -q "Status: active"; then
    echo "[*] Configuring UFW firewall rules for Pi-hole..."
    ufw allow 53/tcp comment "Pi-hole DNS"
    ufw allow 53/udp comment "Pi-hole DNS"
    ufw allow 80/tcp comment "Pi-hole Web GUI"
    ufw allow 443/tcp comment "Pi-hole Web GUI SSL"
fi

# Configure firewall rules if firewalld is active
if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
    echo "[*] Configuring Firewalld rules for Pi-hole..."
    firewall-cmd --permanent --add-service=dns || true
    firewall-cmd --permanent --add-service=http || true
    firewall-cmd --permanent --add-service=https || true
    firewall-cmd --reload || true
fi

# Verify Pi-hole status
echo "------------------------------------------------------------"
echo "[+] Pi-hole installation verification:"
pihole status || true

HOST_IP=$(echo "${STATIC_IP}" | cut -d'/' -f1)
echo "============================================================"
echo "[+] Pi-hole installed successfully!"
echo "    Web Admin Dashboard: http://${HOST_IP:-$(hostname -I | awk '{print $1}')}/admin"
echo "    DNS Server IP      : ${HOST_IP:-$(hostname -I | awk '{print $1}')}"
if [ "${ENABLE_CF}" = true ]; then
    echo "    Conditional Fwd    : Active -> Router (${ROUTER_IP}) for *.${LOCAL_DOMAIN} & ${LOCAL_SUBNET}"
fi
echo "============================================================"
