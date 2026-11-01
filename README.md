# Pi-hole Automated Lists Configuration & Deployment

[![Pi-hole v6](https://img.shields.io/badge/Pi--hole-v6.x-red.svg)](https://pi-hole.net/)
[![pihole-updatelists](https://img.shields.io/badge/pihole--updatelists-jacklul-blue.svg)](https://github.com/jacklul/pihole-updatelists)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

An optimized, curated, and automated configuration for [Pi-hole](https://pi-hole.net/) (including **Pi-hole v6**) powered by [pihole-updatelists](https://github.com/jacklul/pihole-updatelists).

This repository automates the synchronization of best-of-breed DNS blocklists, native hardware/OS telemetry blockers, India-specific regional ad & tracker filters, and anti-breakage whitelists.

---

## 📋 Features & Blocklist Architecture

Instead of stacking uncurated lists that create massive database bloat and false positives, this configuration relies on an organized multi-tier strategy:

```
┌────────────────────────────────────────────────────────┐
│               /etc/pihole-updatelists.conf             │
└───────────────────────────┬────────────────────────────┘
                            │
       ┌────────────────────┼───────────────────┐
       ▼                    ▼                   ▼
┌──────────────┐     ┌──────────────┐    ┌──────────────┐
│  BLOCKLISTS  │     │  WHITELISTS  │    │  REGEX RULES │
└──────┬───────┘     └──────┬───────┘    └──────┬───────┘
       │                    │                   │
       ├─ Firebog Ticked    ├─ anudeepND Safe   ├─ mmotti regex
       ├─ Steve Jenkins     └─ HaGeZi Referral  └─ Steve Jenkins
       │  (HaGeZi Pro++,       (Shopping fix)
       │   TIF, OISD Big)
       └─ custom-blocklists.list
          (See breakdown below)
```

### 1. Curated Custom Blocklists (`config/custom-blocklists.list`)

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

### 2. False-Positive Protection & Whitelists

Aggressive ad-blocking can break legitimate services. This configuration protects:
* **UPI & Netbanking:** BHIM, Google Pay, PhonePe, Paytm, and banking portals (SBI, HDFC, ICICI, Axis).
* **Delivery & Quick-Commerce:** Swiggy, Zomato, Blinkit, Zepto, Flipkart.
* **Shopping / Referral Links:** HaGeZi Referral Allowlist ensures Google Shopping, Slickdeals, and affiliate redirects resolve without disabling your blocker.

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
1. Verifies Pi-hole installation.
2. Installs `pihole-updatelists` if missing.
3. Creates a timestamped backup of any existing `/etc/pihole-updatelists.conf`.
4. Deploys `/etc/pihole/custom-blocklists.list` and `/etc/pihole-updatelists.conf`.
5. Runs `pihole-updatelists` to sync and reload gravity.

---

### Option B: Remote Deployment from Windows (PowerShell)

Deploy remotely from your Windows workstation over SSH using the included script:

```powershell
.\deploy.ps1 -Hostname "pi.hole" -User "rpi4b-admin"
```

Or run via standard SSH/SCP commands:

```bash
scp config/custom-blocklists.list rpi4b-admin@pi.hole:/tmp/custom-blocklists.list
scp config/pihole-updatelists.conf rpi4b-admin@pi.hole:/tmp/pihole-updatelists.conf

ssh -t rpi4b-admin@pi.hole "sudo cp /tmp/custom-blocklists.list /etc/pihole/custom-blocklists.list && \
sudo cp /tmp/pihole-updatelists.conf /etc/pihole-updatelists.conf && \
sudo /usr/local/sbin/pihole-updatelists"
```

---

## 📁 Repository Structure

```
.
├── config/
│   ├── pihole-updatelists.conf    # Main configuration for pihole-updatelists
│   └── custom-blocklists.list     # Curated adlist index (HaGeZi, India, Smart TV, etc.)
├── docs/
│   └── pihole-analysis.md         # In-depth analysis of lists, metrics, and comparisons
├── deploy.sh                      # Turnkey deployment script for Linux/Pi
├── deploy.ps1                     # Remote deployment script for Windows PowerShell
├── .gitattributes                 # Enforces Linux LF line-endings for config files
└── README.md                      # Documentation
```

---

## ⏰ Automated Updates (Cron)

`pihole-updatelists` comes with an automated cron job. Verify its schedule at:

```bash
cat /etc/cron.d/pihole-updatelists
```

To run a manual synchronization at any time:

```bash
sudo /usr/local/sbin/pihole-updatelists
```

To update Pi-hole gravity manually:

```bash
sudo pihole -g
```

---

## 📄 License

This repository is licensed under the [MIT License](LICENSE).
Individual blocklists are maintained by their respective authors and projects cited within the configuration.

