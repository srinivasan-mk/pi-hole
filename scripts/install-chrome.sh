#!/usr/bin/env bash
# ==============================================================================
# Minimal Chromium Browser installer for Raspberry Pi OS Lite (Debian Trixie)
# Installs Chromium + cage (Wayland kiosk compositor) + wayvnc for remote access
# https://github.com/srinivasan-mk/pi-hole
# ==============================================================================

set -euo pipefail

CHROME_USER="${SUDO_USER:-$(logname 2>/dev/null || echo pi)}"
CHROME_USER_HOME=$(eval echo "~${CHROME_USER}")

echo "============================================================"
echo "  Minimal Chromium Installer for Raspberry Pi OS Lite"
echo "============================================================"

# --- Preflight checks --------------------------------------------------------

if [ "$(id -u)" -ne 0 ]; then
    echo "[-] This installer must be run with sudo or as root." >&2
    exit 1
fi

if ! command -v apt-get >/dev/null 2>&1; then
    echo "[-] apt-get not found. This script requires Debian/Raspberry Pi OS." >&2
    exit 1
fi

# --- Install packages ---------------------------------------------------------

echo "[*] Updating package lists..."
apt-get update -y

echo "[*] Installing Chromium (minimal, no recommends)..."
apt-get install -y --no-install-recommends chromium

echo "[*] Installing cage (minimal Wayland kiosk compositor)..."
apt-get install -y --no-install-recommends cage

echo "[*] Installing wayvnc (remote VNC access)..."
apt-get install -y --no-install-recommends wayvnc

# --- Create launcher scripts -------------------------------------------------

echo "[*] Creating launcher scripts..."

# chrome - local display (attached monitor)
cat > /usr/local/bin/chrome << 'LAUNCHER'
#!/usr/bin/env bash
# Launch Chromium fullscreen on the attached monitor via cage (Wayland kiosk)
# Close Chromium to return to the terminal — all UI memory is released.
exec cage -- chromium --no-sandbox --disable-gpu-compositing "$@"
LAUNCHER
chmod 755 /usr/local/bin/chrome

# chrome-vnc - local display + VNC server on port 5900
cat > /usr/local/bin/chrome-vnc << 'LAUNCHER'
#!/usr/bin/env bash
# Launch Chromium on attached monitor with VNC server on port 5900.
# Connect from any VNC client to <pi-ip>:5900
# Close Chromium to stop everything.
VNC_PORT="${1:-5900}"
echo "[*] Starting Chromium with VNC on port ${VNC_PORT}..."
echo "[*] Connect with a VNC client to $(hostname -I | awk '{print $1}'):${VNC_PORT}"
exec cage -- sh -c "wayvnc 0.0.0.0 ${VNC_PORT} & exec chromium --no-sandbox --disable-gpu-compositing"
LAUNCHER
chmod 755 /usr/local/bin/chrome-vnc

# chrome-remote - headless VNC only (no monitor required)
cat > /usr/local/bin/chrome-remote << 'LAUNCHER'
#!/usr/bin/env bash
# Launch Chromium headless with VNC only (no physical monitor needed).
# Connect from any VNC client to <pi-ip>:5900
# Close Chromium to stop everything.
VNC_PORT="${1:-5900}"
echo "[*] Starting headless Chromium with VNC on port ${VNC_PORT}..."
echo "[*] Connect with a VNC client to $(hostname -I | awk '{print $1}'):${VNC_PORT}"
WLR_BACKENDS=headless exec cage -- sh -c "wayvnc 0.0.0.0 ${VNC_PORT} & exec chromium --no-sandbox --disable-gpu-compositing"
LAUNCHER
chmod 755 /usr/local/bin/chrome-remote

# --- Summary ------------------------------------------------------------------

echo ""
echo "============================================================"
echo "[+] Minimal Chromium installed successfully!"
echo "============================================================"
echo ""
echo "  Available commands (run as ${CHROME_USER}):"
echo ""
echo "    chrome          - Launch on attached monitor (fullscreen)"
echo "    chrome-vnc      - Launch on monitor + VNC on port 5900"
echo "    chrome-remote   - Headless VNC only (no monitor needed)"
echo ""
echo "  Connect via VNC:  $(hostname -I | awk '{print $1}'):5900"
echo ""
echo "  All UI memory is released when Chromium is closed."
echo "============================================================"

