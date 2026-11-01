# Pi-hole Automated Lists Configuration & Cloud Updater

[![Pi-hole v6](https://img.shields.io/badge/Pi--hole-v6.x-red.svg)](https://pi-hole.net/)
[![Python 3](https://img.shields.io/badge/Python-3.7+-blue.svg)](https://www.python.org/)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

An optimized, curated, and automated configuration for [Pi-hole](https://pi-hole.net/) (including **Pi-hole v6**) featuring:
- **`pihole-cloud-updater`**: A modern Python 3 list updater supporting **Lists of Lists ("listsoflist")**, **Google Sheets**, and **SQLite databases stored in Google Drive or cloud sync**.
- Curated regional DNS blocklists (India-specific apps, news portals, and domestic ad networks).
- Native hardware/OS telemetry blockers (Apple, Windows 10/11, Mi TV, Samsung TV, Realme/Oppo/Vivo, IoT).
- Anti-breakage whitelists for UPI, Netbanking, Quick-Commerce, and Google Shopping redirects.

---

## 🌟 Key Capabilities of `pihole-cloud-updater`

| Feature | Description |
| :--- | :--- |
| **Lists of Lists ("listsoflist")** | Recursively resolves index lists (e.g. Firebog, Steve Jenkins, custom files) to fetch underlying adlists with loop protection. |
| **Google Sheets Integration** | Directly sync adlists, whitelists, blacklists, or regex from public/shared Google Sheets with automatic CSV export, tab/gid selection, and column targeting. |
| **Google Drive SQLite Databases** | Downloads and executes custom SQL queries against SQLite databases (`.db` / `.sqlite`) hosted on Google Drive or local rclone mounts. |
| **Zero Dependencies** | Pure Python 3 standard library (`sqlite3`, `urllib`, `csv`). No PHP or external pip packages required. |
| **Pi-hole v5 & v6 Ready** | Detects Pi-hole major version, handles group mappings, and triggers atomic gravity rebuilds or DNS list reloads. |
| **Safe Database Transactions** | Automatic `gravity.db` backups before writing, atomic `BEGIN TRANSACTION ... COMMIT`, and automatic rollback on errors. |
| **Automated Systemd Timer** | Daily automated sync timer (`pihole-cloud-updater.timer`) with randomized delay. |

For full documentation and advanced options, see [docs/pihole-cloud-updater.md](docs/pihole-cloud-updater.md).

---

## 📋 Blocklist Architecture

```
┌────────────────────────────────────────────────────────┐
│             /etc/pihole-cloud-updater.conf             │
└───────────────────────────┬────────────────────────────┘
                            │
       ┌────────────────────┼───────────────────┐
       ▼                    ▼                   ▼
┌──────────────┐     ┌──────────────┐    ┌──────────────┐
│  BLOCKLISTS  │     │  WHITELISTS  │    │  REGEX RULES │
└──────┬───────┘     └──────┬───────┘    └──────┬───────┘
       │                    │                   │
       ├─ Google Sheets     ├─ Google Sheets    ├─ mmotti regex
       ├─ GDrive SQLite     ├─ anudeepND Safe   └─ Steve Jenkins
       ├─ Firebog LoL       └─ HaGeZi Referral
       ├─ Steve Jenkins        (Shopping fix)
       └─ custom-blocklists.list
```

### Curated Custom Blocklists (`config/custom-blocklists.list`)

* **🇮🇳 India Regional Ads & Trackers:**
  * **EasyList IndianList:** Official regional filter for Indian news portals (Times of India, NDTV, Dainik Bhaskar, etc.) and domestic ad networks.
  * **GoodbyeAds (jerryn70):** In-app ad SDK and analytics blockers heavily used in Indian Android apps.
  * **Xiaomi / Mi TV Telemetry & Ads:** Mitigates aggressive PatchWall and MIUI ad injection.
  * **Realme, Oppo & Vivo Telemetry:** Targets ColorOS, RealmeUI, and FuntouchOS tracking endpoints.
* **🛡️ Security & Malware:**
  * **HaGeZi DynDNS:** Blocks abuse of dynamic DNS providers for Command & Control (C2) and phishing.
  * **HaGeZi Anti-Piracy:** Blocks rogue streaming portals and torrent trackers.
* **📱 Native OS & Hardware Telemetry:**
  * Standalone blockers for **Apple**, **Amazon Echo/FireTV**, **Windows 10/11 & Office**, and **TikTok**.
* **📺 Smart TV & IoT Telemetry:**
  * **Perflyst SmartTV:** Multi-vendor Smart TV ad and telemetry blocker (Sony, Roku, Philips, etc.).
  * **mboutolleau Samsung Telemetry:** Targets ACR (Automatic Content Recognition) tracking on Samsung TVs.
* **⚡ Modern Tracking & Optimization:**
  * **Developer Dan Extended:** Extended trackers and Google AMP redirect stripper.
  * **1Hosts Lite:** Lightweight, actively maintained modern tracking filter.
  * **Dandelion Sprout Game Console AdBlock:** Blocks ads on PlayStation, Xbox, and Nintendo Switch.

---

## 🚀 Quickstart Deployment

### Option A: Local Deployment (Directly on Pi-hole / Raspberry Pi)

Clone the repository and run the automated deployment script:

```bash
git clone https://github.com/srinivasan-mk/pi-hole.git
cd pi-hole
sudo bash deploy.sh
```

`deploy.sh` automatically:
1. Verifies Pi-hole installation and Python 3.
2. Installs `pihole-cloud-updater` to `/usr/local/sbin/pihole-cloud-updater`.
3. Sets up automated systemd timer (`pihole-cloud-updater.timer`).
4. Creates backups and deploys configuration files.
5. Runs `pihole-cloud-updater` to synchronize all lists and reload gravity.

---

### Option B: Remote Deployment from Windows (PowerShell)

Deploy remotely from your Windows workstation over SSH using the included script:

```powershell
.\deploy.ps1 -Hostname "pi.hole" -User "rpi4b-admin"
```

---

## ☁️ Cloud Sources Configuration Examples

In `/etc/pihole-cloud-updater.conf`:

### 1. Google Sheets Sources
```ini
; Format: URL [| column_name_or_index]
GSHEET_BLOCKLISTS="https://docs.google.com/spreadsheets/d/1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms/edit#gid=0 | URL"
GSHEET_WHITELISTS="https://docs.google.com/spreadsheets/d/1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms/edit#gid=123456 | Domains"
```

### 2. Google Drive SQLite Database
```ini
; Google Drive file link or local sync path
GDRIVE_SQLITE_FILE="https://drive.google.com/file/d/1AbCdEfGhIjKlMnOpQrStUvWxYz012345/view?usp=sharing"

; Queries to execute
GDRIVE_SQLITE_QUERY_BLOCKLISTS="SELECT url FROM sources WHERE type = 'adlist' AND enabled = 1"
GDRIVE_SQLITE_QUERY_WHITELISTS="SELECT domain FROM whitelist WHERE active = 1"
```

---

## 📁 Repository Structure

```
.
├── config/
│   ├── custom-blocklists.list              # Curated adlist index (HaGeZi, India, Smart TV, etc.)
│   ├── pihole-cloud-updater.conf.example   # Example config with Google Sheets, GDrive SQLite, and LoL
│   └── pihole-updatelists.conf             # Backward-compatible pihole-updatelists configuration
├── docs/
│   ├── pihole-cloud-updater.md             # Comprehensive cloud updater & configuration manual
│   └── pihole-analysis.md                  # In-depth analysis of lists, metrics, and comparisons
├── scripts/
│   ├── pihole-cloud-updater.py             # Python 3 engine for cloud list parsing & gravity sync
│   ├── pihole-cloud-updater                # CLI launcher executable
│   └── install.sh                          # Standalone installer for the cloud updater
├── systemd/
│   ├── pihole-cloud-updater.service        # Systemd service unit
│   └── pihole-cloud-updater.timer          # Systemd daily automation timer (03:30 AM)
├── deploy.sh                               # Turnkey deployment script for Linux/Pi
├── deploy.ps1                              # Remote deployment script for Windows PowerShell
├── .gitattributes                          # Enforces Linux LF line-endings for config files
└── README.md                               # Project documentation
```

---

## ⏰ Automated Updates & Testing

To test list resolution without applying changes:
```bash
sudo pihole-cloud-updater --dry-run
```

To test fetching a single Google Sheet or list:
```bash
pihole-cloud-updater --test-source "https://docs.google.com/spreadsheets/d/1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms/edit#gid=0 | URL"
```

To force a full gravity rebuild:
```bash
sudo pihole-cloud-updater --gravity
```

---

## 📄 License

This repository is licensed under the [MIT License](LICENSE).
Individual blocklists are maintained by their respective authors and projects cited within the configuration.
