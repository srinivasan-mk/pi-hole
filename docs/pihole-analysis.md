# Pi-hole Lists Analysis & Updated Configuration (with India Regional Feeds)

## System Info
- **Pi-hole Version:** Core v6.5, Web v6.6.1, FTL v6.8
- **pihole-updatelists:** Installed at `/usr/local/sbin/pihole-updatelists` (up to date)
- **Gravity DB:** `/etc/pihole/gravity.db`

---

## India-Specific Ads, Trackers & Telemetry Lists

Websites, streaming platforms, and smartphone ecosystems in India present specific tracking and ad challenges (heavy regional ad networks, MIUI/ColorOS/Funtouch telemetry, OTT video app analytics).

The following regional blocklists have been added:

| Category | List | Purpose | URL |
|---|---|---|---|
| **Regional Ads & News Portals** | EasyList IndianList | Official regional ABP/DNS filter for Indian news portals (Times of India, NDTV, regional language presses) and domestic ad networks | `https://easylist-downloads.adblockplus.org/indianlist.txt` |
| **Mobile Apps & In-App Ads** | GoodbyeAds (jerryn70) | Created by Indian developer Jerryn, extensively blocks ad SDKs, analytics, and app bloat common in Indian Android apps | `https://raw.githubusercontent.com/jerryn70/GoodbyeAds/master/Hosts/GoodbyeAds.txt` |
| **Mi TV & Xiaomi Telemetry** | GoodbyeAds Xiaomi Extension | Mitigates aggressive ads and telemetry on Xiaomi / Redmi / POCO devices and Mi TV / PatchWall | `https://raw.githubusercontent.com/jerryn70/GoodbyeAds/master/Extension/GoodbyeAds-Xiaomi-Extension.txt` |
| **Xiaomi Hardware Telemetry** | HaGeZi Native Xiaomi | Blocks background phone/smart TV metric beacons back to Xiaomi servers | `https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/adblock/native.xiaomi.txt` |
| **Realme & Oppo Telemetry** | HaGeZi Native Oppo/Realme | Blocks ColorOS / RealmeUI background telemetry endpoints | `https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/adblock/native.oppo-realme.txt` |
| **Vivo Telemetry** | HaGeZi Native Vivo | Blocks FuntouchOS / OriginOS diagnostics and advertising trackers | `https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/adblock/native.vivo.txt` |

### Important Note on Indian Video Ads (JioHotstar, JioCinema, SonyLIV, Zee5):
> [!NOTE]
> Indian streaming apps (like JioHotstar, JioCinema, and Zee5) deliver advertisements using **Server-Side Ad Insertion (SSAI)** and dynamic CDN tokens via the same hostnames as the actual video streams. Blocking those domains at the DNS level often causes video streams to freeze or throw playback errors. The network-level blocklists above focus on stripping **app telemetry, tracker beacons, and static banner/interstitial ads**, while in-stream video ads are best handled by browser extensions like uBlock Origin on web clients.

---

### False-Positive Protection for Indian Services

Aggressive filtering can occasionally disrupt crucial Indian services. Our whitelist configuration explicitly protects:
1. **UPI & Payments:** PhonePe, Google Pay (Tez), Paytm, BHIM, and banking authentication gateways (SBI, HDFC, ICICI, Axis).
2. **E-Commerce & Quick-Commerce:** Flipkart, Amazon IN, Blinkit, Zepto, Swiggy, and Zomato asset CDNs.
3. **Shopping / Referral Links:** Protected via `https://raw.githubusercontent.com/hagezi/dns-blocklists/main/domains/whitelist-referral.txt`.

---

## SuperAdBlockTest Handcrafted Blacklist (`/etc/pihole/custom-blacklist.list`)

The following ad servers, cryptojacking scripts, and telemetry endpoints identified by tests such as superadblocktest.com have been added directly to `custom-blacklist.list`:

| Domain | Category | Threat / Function |
|---|---|---|
| `adservice.google.com` | Google Ads | Direct ad serving & conversion tracking |
| `ad.doubleclick.net` | Google / DoubleClick | Web advertising and cross-site tracker |
| `s.youtube.com` | YouTube Telemetry | Video watch telemetry and beacon tracking |
| `coinimp.com` | Cryptojacking | In-browser cryptocurrency mining script |
| `www.coinimp.com` | Cryptojacking | In-browser crypto miner host domain |
| `track.customer.io` | Telemetry / Tracking | Customer analytics and behavioral event tracking (`/events`) |
| `dai.google.com` | Google Dynamic Ads | Video ad insertion & stream stitching |
| `ssl.p.jwpcdn.com` | Video Ad Analytics | JW Player CDN ad and tracking beacon |

> [!NOTE]
> Pi-hole operates at the DNS resolution layer (FQDN). Blacklisting `track.customer.io` blocks all network requests destined for that domain, including HTTP paths like `/events`, before any connection can be initiated.

---

## Excluded / Purged Defunct Adlists

The following upstream adlists have been shut down or deprecated and are excluded/purged so `pihole -g` does not fail:

| Defunct Adlist Target | Status | Resolution |
|---|---|---|
| `https://urlhaus.abuse.ch/downloads/hostfile/` | HTTP 410 Gone (Unreachable) | Filtered via `ADLISTS_EXCLUDE` and purged from `gravity.db` |

---

## Deployment Status on Pi-hole

The updated configuration files and lists include:
- `config/custom-blocklists.list` -> `/etc/pihole/custom-blocklists.list`
- `config/custom-blacklist.list` -> `/etc/pihole/custom-blacklist.list`
- `config/pihole-updatelists.conf` -> `/etc/pihole-updatelists.conf`
- `config/pihole-cloud-updater.conf.example` -> `/etc/pihole-cloud-updater.conf`

To apply the changes remotely from Windows:
```powershell
.\deploy.ps1
```

Or apply directly on the Pi-hole host:
```bash
sudo cp config/custom-blacklist.list /etc/pihole/custom-blacklist.list
sudo cp config/pihole-updatelists.conf /etc/pihole-updatelists.conf
sudo /usr/local/sbin/pihole-updatelists
# Or if using pihole-cloud-updater:
sudo /usr/local/sbin/pihole-cloud-updater
```

Or add directly via Pi-hole CLI for immediate effect:
```bash
sudo pihole -b adservice.google.com ad.doubleclick.net s.youtube.com coinimp.com www.coinimp.com track.customer.io dai.google.com ssl.p.jwpcdn.com
```
