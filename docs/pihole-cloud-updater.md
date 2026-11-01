# Pi-hole Cloud Updater (`pihole-cloud-updater`)

A modern, standalone lists and gravity synchronizer for **Pi-hole (v5.x and v6.x)**. Built to expand beyond traditional list updaters with native support for **Lists of Lists ("listsoflist")**, **Google Sheets**, and **SQLite databases stored in Google Drive or cloud-synced folders**.

---

## 🌟 Features & Comparison

| Capability | Standard `pihole-updatelists` | `pihole-cloud-updater` |
| :--- | :---: | :---: |
| **Pi-hole v5 & v6 Support** | ✅ | ✅ |
| **Standard Remote Lists & Files** | ✅ | ✅ |
| **Lists of Lists ("listsoflist")** | Limited | ✅ **Recursive resolution with loop detection** |
| **Google Sheets Direct Import** | ❌ | ✅ **Native (Public, shared, tab/gid & column selection)** |
| **Google Drive SQLite DB Import** | ❌ | ✅ **Native (Downloads/caches & runs custom SQL queries)** |
| **Local Synced Cloud DBs (rclone/gdrive)** | ❌ | ✅ **Native SQLite query support** |
| **Zero External Runtime Dependencies** | ❌ (Requires PHP & extensions) | ✅ **Pure Python 3 standard library** |
| **Atomic Gravity Transactions & Auto-Backup** | Basic | ✅ **Automated backup, atomic commit & rollback** |
| **Systemd Timer & Service** | Manual | ✅ **Included with randomized jitter** |

---

## 🚀 Quick Installation

Run the automated installer on your Pi-hole host (Raspberry Pi, Debian, Ubuntu, etc.):

```bash
git clone https://github.com/srinivasan-mk/pi-hole.git
cd pi-hole
sudo bash scripts/install.sh
```

Or deploy everything with the master deployment script:

```bash
sudo bash deploy.sh
```

The installer:
1. Copies `pihole-cloud-updater.py` to `/usr/local/share/pihole-cloud-updater/`.
2. Creates the CLI command `/usr/local/sbin/pihole-cloud-updater`.
3. Installs `/etc/pihole-cloud-updater.conf` if not present.
4. Enables the `pihole-cloud-updater.timer` systemd service to run daily at 03:30 AM.

---

## 📋 Source Integrations

### 1. Lists of Lists ("listsoflist" / LoL)

A "List of Lists" is an endpoint or file that doesn't list individual domains, but lists **URLs pointing to other adlists**.

`pihole-cloud-updater` automatically detects whether a source is a list of URLs or raw host entries and recursively fetches nested lists up to `MAX_RECURSION_DEPTH=2` (configurable).

```ini
BLOCKLISTS_URL="https://v.firebog.net/hosts/lists.php?type=tick
https://raw.githubusercontent.com/stevejenkins/pi-hole-lists/main/blocklists.txt
/etc/pihole/custom-blocklists.list"
```

---

### 2. Google Sheets Integration

You can maintain your adlists, whitelist domains, or regex rules in Google Sheets. Anyone with edit/read permissions on the sheet can collaborate, and your Pi-hole will sync the changes automatically!

#### How to Configure:
1. Open your Google Sheet.
2. Ensure the sheet is shared so your Pi-hole can read it (e.g. **"Anyone with the link can view"**).
3. Copy the URL from your browser address bar:
   `https://docs.google.com/spreadsheets/d/1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms/edit#gid=0`
4. Add it to your config:

```ini
; Format: URL [| column_name_or_index]

; Method A: In GSHEET_BLOCKLISTS with column selector
GSHEET_BLOCKLISTS="https://docs.google.com/spreadsheets/d/1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms/edit#gid=0 | URL"

; Method B: In WHITELIST_URL or GSHEET_WHITELISTS
GSHEET_WHITELISTS="https://docs.google.com/spreadsheets/d/1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms/edit#gid=123456 | Domains"

; Method C: Shorthand gsheet:// URI
GSHEET_BLACKLISTS="gsheet://1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms?gid=0&col=Blacklist"
```

#### Smart Column Detection:
- If a column name (e.g. `| URL` or `| Domain`) is specified, that column is used.
- If a column index (e.g. `| 0` or `| A`) is specified, that index is used.
- If no column is specified, `pihole-cloud-updater` automatically inspects header rows for: `url`, `link`, `list`, `blocklist`, `whitelist`, `domain`, `regex`, `address`, falling back to column `0`.
- Empty rows, inline comments (`#`, `;`, `//`), and header titles are automatically skipped.

---

### 3. SQLite Database Stored in Google Drive (or Local Cloud Mount)

If you keep your lists in a custom SQLite database (e.g., `sources.db` or `lists.sqlite`) uploaded to Google Drive or mounted locally via `rclone`, `pihole-cloud-updater` can download/query it directly.

#### A. Direct Google Drive Link:
1. Upload your `.sqlite` / `.db` database to Google Drive.
2. Right click -> **Share** -> **Anyone with link: Viewer**.
3. Copy the file URL:
   `https://drive.google.com/file/d/1AbCdEfGhIjKlMnOpQrStUvWxYz012345/view?usp=sharing`

In `/etc/pihole-cloud-updater.conf`:

```ini
; Google Drive file link or file ID
GDRIVE_SQLITE_FILE="https://drive.google.com/file/d/1AbCdEfGhIjKlMnOpQrStUvWxYz012345/view?usp=sharing"

; Queries to retrieve items from your database
GDRIVE_SQLITE_QUERY_BLOCKLISTS="SELECT url FROM sources WHERE type = 'adlist' AND enabled = 1"
GDRIVE_SQLITE_QUERY_WHITELISTS="SELECT domain FROM whitelist WHERE active = 1"
GDRIVE_SQLITE_QUERY_BLACKLISTS="SELECT domain FROM blacklist WHERE active = 1"
GDRIVE_SQLITE_QUERY_REGEX_WHITELISTS="SELECT pattern FROM regex_rules WHERE type = 'allow' AND active = 1"
GDRIVE_SQLITE_QUERY_REGEX_BLACKLISTS="SELECT pattern FROM regex_rules WHERE type = 'block' AND active = 1"
```

#### B. Local / Synced Path (e.g. Rclone or Google Drive for Desktop):
If your Google Drive is synced or mounted locally:

```ini
GDRIVE_SQLITE_FILE="/mnt/gdrive/pihole/lists.sqlite"
GDRIVE_SQLITE_QUERY_BLOCKLISTS="SELECT url FROM blocklists WHERE enabled = 1"
```

---

## 🛠️ CLI Options

```
usage: pihole-cloud-updater [-h] [-c CONFIG] [--dry-run] [--no-gravity]
                            [--gravity] [--vacuum] [-v] [--debug] [--version]
                            [--test-source TARGET]

pihole-cloud-updater - Sync Pi-hole lists from Cloud Sources, Google Sheets,
GDrive SQLite, and Lists-of-Lists.

optional arguments:
  -h, --help            show this help message and exit
  -c CONFIG, --config CONFIG
                        Path to configuration file (default: /etc/pihole-cloud-updater.conf)
  --dry-run             Simulate updates without modifying gravity.db
  --no-gravity          Skip running 'pihole -g' or DNS reload after sync
  --gravity             Force running 'pihole -g' even if no adlists changed
  --vacuum              Vacuum gravity.db after update
  -v, --verbose         Enable verbose logging
  --debug               Enable debug logging
  --version             show program's version number and exit
  --test-source TARGET  Test fetch a single source (Google Sheet, GDrive, URL)
                        and print extracted items
```

### Useful CLI Examples:

1. **Test fetch a Google Sheet without modifying Pi-hole:**
   ```bash
   pihole-cloud-updater --test-source "https://docs.google.com/spreadsheets/d/1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms/edit#gid=0 | URL"
   ```

2. **Simulate sync (Dry Run):**
   ```bash
   pihole-cloud-updater --dry-run
   ```

3. **Force update gravity:**
   ```bash
   pihole-cloud-updater --gravity
   ```

---

## 🛡️ Safety & Manual Entries

- **Comment Tagging:** Managed entries are tagged with `COMMENT="Managed by pihole-cloud-updater"`.
- **Manual Entry Protection:** When `REQUIRE_COMMENT=true` (default), only entries created by the updater are touched or removed. Any domains or adlists you manually added via the Pi-hole Web Admin GUI are preserved.
- **Automatic Backups:** Before making database changes, `gravity.db` is backed up to `/etc/pihole/gravity.db.bak.<timestamp>`.
- **Rollback Safety:** All updates execute inside an atomic SQLite transaction (`BEGIN TRANSACTION ... COMMIT`). If an error occurs, the transaction automatically rolls back.

