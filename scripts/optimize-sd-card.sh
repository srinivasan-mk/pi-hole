#!/usr/bin/env bash
# ==============================================================================
# MicroSD Card & 24/7 Hardware Longevity Optimizer (Forwarder)
# Repository: https://github.com/srinivasan-mk/pi-hole
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_SCRIPT="${SCRIPT_DIR}/optimization/optimize-sd-card.sh"

if [ -f "${TARGET_SCRIPT}" ]; then
    exec bash "${TARGET_SCRIPT}" "$@"
else
    echo "[-] Error: Optimization script not found at ${TARGET_SCRIPT}"
    exit 1
fi
