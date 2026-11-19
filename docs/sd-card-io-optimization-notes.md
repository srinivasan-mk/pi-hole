# Raspberry Pi 4 MicroSD Card I/O & Longevity Tracking Notes

**Host:** `rpi4b-admin@192.168.31.32`  
**Initial Baseline Date:** 2026-11-19 22:35 IST  
**System Uptime at Baseline:** 3 days, 4 hours  

---

## 1. Executive Summary & Baseline Metrics

To protect the MicroSD card from write wear and ensure 24/7 reliability, all continuous disk write paths (DNS query logging, real-time database updates, and blocklist matching) were redirected to in-memory buffers.

### Baseline Storage Counters (`/proc/diskstats` on `mmcblk0`)
* **Cumulative Reads (since boot):** `178,185` (2.91 GB read)
* **Cumulative Writes (since boot):** `42,594` (8.88 GB written)
* **Lifetime Average:** ~14k writes/day (reflects initial package installations, gravity database generation, and pre-tuning query logging).
* **Live Operational Delta (30-second measurement):**
  ```text
  T0:  178,185 reads | 42,594 writes | 17,350,078 sectors written
  T30: 178,185 reads | 42,594 writes | 17,350,078 sectors written
  Delta: 0 reads, 0 writes (0.00 B/s, wa = 0%)
  ```

---

## 2. Currently Active Optimizations (Phase 1)

1. **Pi-hole Database 24-Hour Write Batching:**
   * `database.DBinterval = 86400`: FTL accumulates all queries in RAM and commits to `/etc/pihole/pihole-FTL.db` only once every 24 hours.
   * `database.forceDisk = false`: Uses in-memory database engine for active history.
   * `database.maxDBdays = 1` and `webserver.api.maxHistory = 86400`: Retains query history for exactly 1 day.
   * Pruned database size down from 79 MB to 13 MB.

2. **In-Memory Logging via Log2Ram:**
   * `/var/log` is mounted on a 256 MB RAM `tmpfs` partition.
   * All DNS queries (`pihole.log`), FTL logs (`FTL.log`), and webserver logs write strictly to RAM.
   * `log2ram-daily.timer` syncs RAM logs to disk only once per day at `23:55:00 GMT`.
   * `/etc/logrotate.d/pihole` configured for daily rotation and `rotate 1` retention.

3. **100% Gravity Domain RAM Locking (`vmtouch`):**
   * Service: `pihole-gravity-ramcache.service`
   * Locked **150,693 / 150,693 pages (588 MB, 100%)** of `/etc/pihole/gravity.db` into physical RAM.
   * Blocklist checks for 9.26 million domains produce **0 disk read lookups**.

4. **DNS Cache Optimization:**
   * `dns.cache.optimizer = 86400` (1 day), `dns.cache.size = 10000`, and `dns.cache.upstreamBlockedTTL = 86400`.
   * Expired cached queries are served instantly from cache while refreshing asynchronously in the background.

5. **Filesystem & Kernel Tuning:**
   * Root partition mounted with `noatime,commit=600` (10-minute journal commits).
   * Kernel writeback centisecs set to 60,000 (10-minute delayed flush).
   * `systemd-journald` set to `Storage=volatile`, `RuntimeMaxUse=64M` (logs stored in RAM).
   * Physical swap disabled; 2.0 GiB zRAM compressed swap in memory (0 B used).

---

## 3. Candidate OS Optimizations to Review After a Few Days (Phase 2)

If monitoring after a few days shows remaining non-Pi-hole background writes, the following system tweaks can be applied:

### A. Disable Non-Essential System Timers
* **`phpsessionclean.timer`**:
  * Runs every 30 minutes (48 times/day) scanning `/var/lib/php/sessions`.
  * Pi-hole v6 uses an embedded `CivetWeb` server without PHP; this timer is unused.
  ```bash
  sudo systemctl disable --now phpsessionclean.timer
  ```
* **`man-db.timer`**:
  * Runs daily rebuilding manual page database cache.
  ```bash
  sudo systemctl disable --now man-db.timer
  ```
* **`apt-daily.timer` & `apt-daily-upgrade.timer`**:
  * Runs twice daily querying Debian repos and touching `/var/lib/apt/daily_lock`.
  ```bash
  sudo systemctl disable --now apt-daily.timer apt-daily-upgrade.timer
  ```

### B. Stop `systemd-timesyncd` Clock File Touching
* `systemd-timesyncd` touches `/var/lib/systemd/timesync/clock` on every sync cycle.
* Pi-hole FTL v6 already has an embedded NTP client (`ntp.sync.active = true`) synchronizing time in memory.
  ```bash
  sudo systemctl disable --now systemd-timesyncd
  ```

### C. Enable `tmpfs` for `/var/tmp`
* Prevent any process from using `/var/tmp` on the SD card:
  ```bash
  sudo sed -i 's/^#tmpfs\s\+\/var\/tmp/tmpfs    \/var\/tmp/' /etc/fstab
  sudo mount -a
  ```

### D. Add `lazytime` to Ext4 Mount
* Keeps file access, modification, and change timestamps in RAM, flushing only when file data is changed:
  ```text
  /dev/mmcblk0p7  /  ext4  defaults,noatime,lazytime,commit=600  0  1
  ```

---

## 4. How to Check Progress After a Few Days

Run these commands via SSH to evaluate new write counts and component health:

```bash
# 1. Check cumulative block device stats:
cat /sys/block/mmcblk0/stat

# 2. Check 30-second live write rate:
sudo bash -c 'cat /sys/block/mmcblk0/stat; sleep 30; cat /sys/block/mmcblk0/stat'

# 3. Check modification timestamp of Pi-hole database (should only be once every 24h):
ls -l --time-style=+"%Y-%m-%d %H:%M:%S" /etc/pihole/pihole-FTL.db*

# 4. Check files touched on the filesystem in the last 24 hours:
sudo find /var/lib /etc -type f -mmin -1440 2>/dev/null | grep -v -E '/etc/pihole|/tmp'

# 5. Check hardware health, voltage, throttling, and temperature:
vcgencmd get_throttled
vcgencmd measure_temp
vcgencmd measure_volts
```

### Formula to Calculate Actual Daily Write Ops:
$$\text{Daily Writes} = \frac{\text{Current Writes} - 42594}{\text{Days Elapsed since Nov 19}}$$

Target is **< 10–50 writes per day** across the entire operating system.
