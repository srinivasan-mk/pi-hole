# Pi-hole Project Rules

## Project Overview
- Raspberry Pi 4B running Raspbian Lite (Debian Trixie, aarch64)
- Hostname: pi.hole / 192.168.31.32
- SSH user: rpi4b-admin (key-based auth via id_ed25519)
- SSH config is at ~/.ssh/config

## Repository Structure
- `scripts/` — Bash scripts deployed to the Pi
- `config/` — Configuration files
- `systemd/` — Systemd service/timer units
- `docs/` — Documentation
- `tests/` — Python tests

## Deployment
- PowerShell deploy scripts (deploy.ps1, deploy-chrome.ps1) SCP files and run via SSH
- Remote scripts need `sudo` (password required, no NOPASSWD)
- Always use `set -euo pipefail` in bash scripts
- Use `--no-install-recommends` for apt installs on the Pi

## Preferences
- Keep Raspbian Lite minimal — avoid pulling in desktop environment packages
- Shell scripts use `/usr/bin/env bash` shebang
- Prefer concise responses

