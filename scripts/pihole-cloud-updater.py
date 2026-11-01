#!/usr/bin/env python3
"""
pihole-cloud-updater - Pi-hole Lists & Gravity Updater with Cloud Sources Support
Supports:
  - Standard Pi-hole adlists, whitelists, blacklists, and regex rules
  - Lists of Lists ("listsoflist" / LoL) with recursive resolution
  - Google Sheets (public or shared links, CSV export, specific tabs/columns)
  - SQLite databases stored in Google Drive (direct download link or synced local path)
  - Atomic transactions with backup & rollback safety
  - Pi-hole v5 and Pi-hole v6 compatibility

Author: Srinivasan MK & Community
License: MIT
"""

import argparse
import csv
import datetime
import http.cookiejar
import io
import json
import logging
import os
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Dict, List, Optional, Set, Tuple

VERSION = "1.0.0"

# Default configuration values
DEFAULT_CONFIG = {
    "GRAVITY_DB": "/etc/pihole/gravity.db",
    "DOMAINS_GROUP_ID": 0,
    "ADLISTS_GROUP_ID": 0,
    "BLOCKLISTS_URL": "",
    "ALLOWLISTS_URL": "",
    "WHITELIST_URL": "",
    "BLACKLIST_URL": "",
    "REGEX_WHITELIST_URL": "",
    "REGEX_BLACKLIST_URL": "",
    "COMMENT": "Managed by pihole-cloud-updater",
    "REQUIRE_COMMENT": True,
    "DELETE_OBSOLETE": True,
    "UPDATE_GRAVITY": True,
    "VACUUM_DATABASE": False,
    "VERBOSE": False,
    "DEBUG": False,
    "IGNORE_DOWNLOAD_FAILURE": False,
    "CACHE_DIR": "/var/cache/pihole-cloud-updater",
    "MAX_RECURSION_DEPTH": 2,
    "REQUEST_TIMEOUT": 30,
    "USER_AGENT": "Mozilla/5.0 (compatible; pihole-cloud-updater/1.0; +https://github.com/srinivasan-mk/pi-hole)",
    # Google Sheets sources (can also be included directly in *_URL)
    "GSHEET_BLOCKLISTS": "",
    "GSHEET_WHITELISTS": "",
    "GSHEET_BLACKLISTS": "",
    "GSHEET_REGEX_WHITELISTS": "",
    "GSHEET_REGEX_BLACKLISTS": "",
    # Google Drive SQLite database settings
    "GDRIVE_SQLITE_FILE": "",
    "GDRIVE_SQLITE_QUERY_BLOCKLISTS": "",
    "GDRIVE_SQLITE_QUERY_WHITELISTS": "",
    "GDRIVE_SQLITE_QUERY_BLACKLISTS": "",
    "GDRIVE_SQLITE_QUERY_REGEX_WHITELISTS": "",
    "GDRIVE_SQLITE_QUERY_REGEX_BLACKLISTS": "",
}

# Domainlist types in gravity.db
TYPE_WHITELIST = 0
TYPE_BLACKLIST = 1
TYPE_REGEX_WHITELIST = 2
TYPE_REGEX_BLACKLIST = 3

logger = logging.getLogger("pihole-cloud-updater")


class ConfigParser:
    """Parses shell/INI-like configuration files compatible with pihole-updatelists."""

    @staticmethod
    def parse_file(path: str) -> dict:
        config = {}
        if not os.path.exists(path):
            return config

        with open(path, "r", encoding="utf-8", errors="replace") as f:
            content = f.read()

        # Handle multiline quoted strings and simple key=value pairs
        pattern = re.compile(
            r'^\s*([A-Za-z0-9_]+)\s*=\s*(?:"([^"]*)"|\'([^\']*)\'|([^#;\n]+))',
            re.MULTILINE | re.DOTALL,
        )

        for match in pattern.finditer(content):
            key = match.group(1).strip()
            # Val can be from group 2 (double quotes), 3 (single quotes), or 4 (unquoted)
            val = match.group(2) if match.group(2) is not None else (
                match.group(3) if match.group(3) is not None else match.group(4)
            )
            if val is not None:
                val = val.strip()
                # Cast booleans and ints where appropriate
                if val.lower() in ("true", "yes", "1"):
                    config[key] = True
                elif val.lower() in ("false", "no", "0"):
                    config[key] = False
                elif val.isdigit():
                    config[key] = int(val)
                else:
                    config[key] = val

        return config


class CloudSourceFetcher:
    """Fetches and parses URLs, Google Sheets, Lists-of-Lists, and Google Drive SQLite databases."""

    def __init__(
        self,
        cache_dir: str = "/tmp/pihole-cloud-cache",
        timeout: int = 30,
        user_agent: str = DEFAULT_CONFIG["USER_AGENT"],
        ignore_failures: bool = False,
        max_depth: int = 2,
    ):
        self.cache_dir = cache_dir
        self.timeout = timeout
        self.user_agent = user_agent
        self.ignore_failures = ignore_failures
        self.max_depth = max_depth
        os.makedirs(self.cache_dir, exist_ok=True)

        # Cookie jar for Google Drive / Google Sheets downloads
        self.cookie_jar = http.cookiejar.CookieJar()
        self.opener = urllib.request.build_opener(
            urllib.request.HTTPCookieProcessor(self.cookie_jar)
        )

    def fetch_text(self, url: str) -> str:
        """Fetches raw text content from HTTP/HTTPS URL or local file path."""
        url = url.strip()
        if not url:
            return ""

        # Local file path
        if os.path.exists(url) or url.startswith("file://"):
            local_path = url[7:] if url.startswith("file://") else url
            try:
                with open(local_path, "r", encoding="utf-8", errors="replace") as f:
                    return f.read()
            except Exception as e:
                logger.error("Failed to read local file '%s': %s", local_path, e)
                if not self.ignore_failures:
                    raise
                return ""

        # Remote URL
        req = urllib.request.Request(
            url,
            headers={
                "User-Agent": self.user_agent,
                "Accept": "*/*",
            },
        )

        try:
            with self.opener.open(req, timeout=self.timeout) as resp:
                raw_bytes = resp.read()
                return raw_bytes.decode("utf-8", errors="replace")
        except Exception as e:
            logger.error("Failed to fetch URL '%s': %s", url, e)
            if not self.ignore_failures:
                raise
            return ""

    # --------------------------------------------------------------------------
    # Google Sheets Parser & Fetcher
    # --------------------------------------------------------------------------

    @staticmethod
    def is_google_sheet(url: str) -> bool:
        """Detects whether a URL is a Google Sheets reference."""
        return (
            "docs.google.com/spreadsheets" in url
            or "drive.google.com/spreadsheets" in url
            or url.startswith("gsheet://")
        )

    @classmethod
    def parse_google_sheet_target(cls, url: str) -> Tuple[str, Optional[str], Optional[str], Optional[str]]:
        """
        Parses Google Sheet targets into: (spreadsheet_id, gid, sheet_name, column_name_or_index).
        Accepts:
          - Standard URL: https://docs.google.com/spreadsheets/d/{ID}/edit#gid={GID}
          - With pipe: "https://docs.google.com/spreadsheets/d/{ID}/edit#gid=0 | ColumnA"
          - URI scheme: gsheet://{ID}?gid={GID}&col=1
        """
        col_spec = None
        if "|" in url:
            parts = url.split("|", 1)
            url = parts[0].strip()
            col_spec = parts[1].strip()

        # Handle custom gsheet:// scheme
        if url.startswith("gsheet://"):
            parsed = urllib.parse.urlparse(url)
            sheet_id = parsed.netloc
            qs = urllib.parse.parse_qs(parsed.query)
            gid = qs.get("gid", [None])[0]
            sheet_name = qs.get("sheet", [None])[0]
            if not col_spec and "col" in qs:
                col_spec = qs["col"][0]
            return sheet_id, gid, sheet_name, col_spec

        # Extract Sheet ID using regex
        match = re.search(r"/spreadsheets/d/([a-zA-Z0-9-_]+)", url)
        if not match:
            raise ValueError(f"Invalid Google Sheets URL format: {url}")
        sheet_id = match.group(1)

        # Extract gid from URL fragment or query parameter
        gid = None
        sheet_name = None
        if "#gid=" in url:
            gid = url.split("#gid=")[1].split("&")[0].split("?")[0]
        elif "gid=" in url:
            match_gid = re.search(r"[?&]gid=([0-9]+)", url)
            if match_gid:
                gid = match_gid.group(1)

        # Extract sheet name if present
        if "sheet=" in url:
            match_sheet = re.search(r"[?&]sheet=([^&#]+)", url)
            if match_sheet:
                sheet_name = urllib.parse.unquote(match_sheet.group(1))

        return sheet_id, gid, sheet_name, col_spec

    def fetch_google_sheet(self, url: str) -> List[str]:
        """Fetches and extracts a list of entries from a Google Sheet via CSV export."""
        sheet_id, gid, sheet_name, col_spec = self.parse_google_sheet_target(url)

        # Build direct CSV export URL
        if sheet_name:
            # Using Google Visualization API for named sheet tab
            export_url = (
                f"https://docs.google.com/spreadsheets/d/{sheet_id}/gviz/tq?"
                f"tqx=out:csv&sheet={urllib.parse.quote(sheet_name)}"
            )
        else:
            gid_param = f"&gid={gid}" if gid else ""
            export_url = f"https://docs.google.com/spreadsheets/d/{sheet_id}/export?format=csv{gid_param}"

        logger.info("Fetching Google Sheet [ID: %s, GID: %s, Col: %s]", sheet_id, gid or "0", col_spec or "auto")
        csv_text = self.fetch_text(export_url)
        if not csv_text:
            return []

        entries = []
        reader = csv.reader(io.StringIO(csv_text))
        rows = list(reader)
        if not rows:
            return []

        # Determine target column index
        target_col_idx = 0
        header = [h.strip().lower() for h in rows[0]]

        if col_spec is not None:
            col_spec_str = str(col_spec).strip()
            # If specified as numeric index
            if col_spec_str.isdigit():
                target_col_idx = int(col_spec_str)
            # If specified as single column letter (A, B, C...)
            elif len(col_spec_str) == 1 and col_spec_str.upper() in "ABCDEFGHIJKLMNOPQRSTUVWXYZ":
                target_col_idx = ord(col_spec_str.upper()) - ord("A")
            # If specified as column header name
            elif col_spec_str.lower() in header:
                target_col_idx = header.index(col_spec_str.lower())
            else:
                logger.warning(
                    "Column specifier '%s' not found in header %s, using column 0.",
                    col_spec,
                    header,
                )
                target_col_idx = 0
        else:
            # Smart discovery: look for known column header names
            candidates = ["url", "link", "list", "blocklist", "whitelist", "domain", "regex", "address", "entry"]
            found = False
            for cand in candidates:
                if cand in header:
                    target_col_idx = header.index(cand)
                    found = True
                    break
            if not found:
                target_col_idx = 0

        # Skip header if it is not a URL or domain
        start_row = 1 if len(rows) > 1 and not (rows[0][target_col_idx].startswith("http") or "." in rows[0][target_col_idx]) else 0

        for row in rows[start_row:]:
            if len(row) > target_col_idx:
                val = row[target_col_idx].strip()
                if val and not val.startswith(("#", "//", ";")):
                    # Support multiple space/comma separated items within a single cell
                    for item in re.split(r"[\s,]+", val):
                        clean_item = item.strip()
                        if clean_item and not clean_item.startswith(("#", "//", ";")):
                            entries.append(clean_item)

        logger.info("Extracted %d entries from Google Sheet.", len(entries))
        return entries

    # --------------------------------------------------------------------------
    # Google Drive SQLite Fetcher & Querier
    # --------------------------------------------------------------------------

    @staticmethod
    def is_gdrive_file(target: str) -> bool:
        """Detects if target is a Google Drive file link or gdrive:// scheme."""
        return (
            "drive.google.com/file/d/" in target
            or "drive.google.com/open?id=" in target
            or target.startswith("gdrive://")
        )

    @classmethod
    def extract_gdrive_file_id(cls, target: str) -> str:
        """Extracts Google Drive file ID from URLs or schemes."""
        if target.startswith("gdrive://"):
            return target[9:].split("?")[0].split("/")[0]

        match = re.search(r"/file/d/([a-zA-Z0-9-_]+)", target)
        if match:
            return match.group(1)

        match_id = re.search(r"[?&]id=([a-zA-Z0-9-_]+)", target)
        if match_id:
            return match_id.group(1)

        # Fallback if raw ID passed
        if re.match(r"^[a-zA-Z0-9-_]{20,}$", target):
            return target

        raise ValueError(f"Could not extract Google Drive file ID from: {target}")

    def download_gdrive_file(self, file_id: str) -> str:
        """Downloads a file from Google Drive handling virus scan confirmation tokens for large files."""
        dest_path = os.path.join(self.cache_dir, f"gdrive_{file_id}.sqlite")

        # Initial download URL
        base_url = f"https://drive.google.com/uc?export=download&id={file_id}"
        req = urllib.request.Request(base_url, headers={"User-Agent": self.user_agent})

        try:
            with self.opener.open(req, timeout=self.timeout) as resp:
                content = resp.read()

                # Check if Google Drive returned a virus scan warning page with confirm token
                text_content = content[:4096].decode("utf-8", errors="replace")
                if "confirm=" in text_content or "download_warning" in text_content:
                    confirm_match = re.search(r"confirm=([0-9A-Za-z_]+)", text_content)
                    if confirm_match:
                        confirm_token = confirm_match.group(1)
                        confirm_url = f"https://drive.google.com/uc?export=download&confirm={confirm_token}&id={file_id}"
                        req2 = urllib.request.Request(confirm_url, headers={"User-Agent": self.user_agent})
                        with self.opener.open(req2, timeout=self.timeout) as resp2:
                            content = resp2.read()

                with open(dest_path, "wb") as f:
                    f.write(content)

            logger.info("Downloaded Google Drive SQLite file [ID: %s] -> %s", file_id, dest_path)
            return dest_path
        except Exception as e:
            logger.error("Failed to download SQLite file from Google Drive [ID: %s]: %s", file_id, e)
            if not self.ignore_failures:
                raise
            return ""

    def query_sqlite(self, db_target: str, query: str) -> List[str]:
        """
        Executes a SQL query against an SQLite database (either local path, synced Google Drive folder,
        or downloaded from Google Drive).
        """
        if not db_target or not query:
            return []

        # If it's a remote Google Drive file, download it first
        if self.is_gdrive_file(db_target):
            file_id = self.extract_gdrive_file_id(db_target)
            db_path = self.download_gdrive_file(file_id)
        else:
            db_path = db_target

        if not os.path.exists(db_path):
            logger.error("SQLite database file not found: %s", db_path)
            return []

        results = []
        try:
            # Read-only SQLite connection
            conn = sqlite3.connect(f"file:{os.path.abspath(db_path)}?mode=ro", uri=True)
            cursor = conn.cursor()
            cursor.execute(query)
            for row in cursor.fetchall():
                if row and row[0] is not None:
                    val = str(row[0]).strip()
                    if val and not val.startswith(("#", "//", ";")):
                        results.append(val)
            conn.close()
            logger.info("SQLite query returned %d items from %s", len(results), db_path)
        except Exception as e:
            logger.error("Error executing query '%s' on %s: %s", query, db_path, e)
            if not self.ignore_failures:
                raise

        return results

    # --------------------------------------------------------------------------
    # Lists of Lists ("listsoflist") & Standard List Resolution
    # --------------------------------------------------------------------------

    def resolve_source(self, source: str, depth: int = 0, visited: Optional[Set[str]] = None) -> List[str]:
        """
        Resolves a single source (URL, Google Sheet, local file, or SQLite query) into a list of strings.
        Recursively expands Lists of Lists ("listsoflist") up to max_depth.
        """
        source = source.strip()
        if not source or source.startswith(("#", ";", "//")):
            return []

        if visited is None:
            visited = set()

        if source in visited:
            logger.debug("Skipping already visited source: %s", source)
            return []
        visited.add(source)

        # Case 1: Google Sheet
        if self.is_google_sheet(source):
            return self.fetch_google_sheet(source)

        # Case 2: Direct text fetch (URL or local file)
        text = self.fetch_text(source)
        if not text:
            return []

        lines = [line.strip() for line in text.splitlines()]
        entries = []

        # Detect if this text file is a "List of Lists" (contains URLs to other lists)
        url_count = sum(1 for line in lines if line.startswith(("http://", "https://", "gsheet://", "gdrive://")))
        is_list_of_lists = url_count > 0 and (url_count / max(1, len([l for l in lines if l and not l.startswith("#")])) > 0.4)

        if is_list_of_lists and depth < self.max_depth:
            logger.info("Detected List of Lists (LoL) at '%s' (depth %d). Expanding...", source, depth)
            for line in lines:
                if line and not line.startswith(("#", ";", "//")):
                    # Recursively resolve nested list
                    sub_entries = self.resolve_source(line, depth=depth + 1, visited=visited)
                    entries.extend(sub_entries)
        else:
            # Raw entries (domains, regex patterns, or adlist URLs)
            for line in lines:
                if line and not line.startswith(("#", ";", "//")):
                    # Remove trailing inline comments
                    line = re.split(r"\s+[#;]", line, maxsplit=1)[0].strip()
                    if line:
                        entries.append(line)

        return entries

    def resolve_all(self, raw_sources: str) -> List[str]:
        """Parses multiline or space-separated source specifications and resolves all entries."""
        if not raw_sources:
            return []

        results = []
        visited: Set[str] = set()

        # Split on newlines and spaces (while respecting quotes if any)
        lines = [line.strip() for line in raw_sources.splitlines() if line.strip()]
        for line in lines:
            # Allow multiple URLs on a single line separated by whitespace
            tokens = [t.strip() for t in re.split(r"\s+", line) if t.strip()]
            for token in tokens:
                if not token.startswith(("#", ";", "//")):
                    items = self.resolve_source(token, depth=0, visited=visited)
                    results.extend(items)

        # Return deduplicated while preserving order
        seen = set()
        deduped = []
        for item in results:
            if item not in seen:
                seen.add(item)
                deduped.append(item)
        return deduped


class GravitySync:
    """Synchronizes adlists and domainlists into Pi-hole gravity.db with full group support."""

    def __init__(
        self,
        db_path: str = "/etc/pihole/gravity.db",
        comment_tag: str = DEFAULT_CONFIG["COMMENT"],
        require_comment: bool = True,
        delete_obsolete: bool = True,
        adlists_group_id: int = 0,
        domains_group_id: int = 0,
        dry_run: bool = False,
    ):
        self.db_path = db_path
        self.comment_tag = comment_tag
        self.require_comment = require_comment
        self.delete_obsolete = delete_obsolete
        self.adlists_group_id = adlists_group_id
        self.domains_group_id = domains_group_id
        self.dry_run = dry_run
        self.changes_made = {
            "adlist_added": 0,
            "adlist_removed": 0,
            "domain_added": 0,
            "domain_removed": 0,
        }

    def backup_database(self) -> Optional[str]:
        """Creates a timestamped backup of gravity.db."""
        if not os.path.exists(self.db_path):
            return None
        timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
        backup_path = f"{self.db_path}.bak.{timestamp}"
        try:
            shutil.copy2(self.db_path, backup_path)
            logger.info("Created gravity backup: %s", backup_path)
            return backup_path
        except Exception as e:
            logger.error("Failed to create database backup: %s", e)
            return None

    def sync_adlists(self, conn: sqlite3.Connection, target_urls: List[str]):
        """Synchronizes target URLs into the adlist table and adlist_by_group."""
        cursor = conn.cursor()
        now = int(time.time())

        # Retrieve existing adlists
        cursor.execute("SELECT id, address, comment, enabled FROM adlist")
        existing_rows = cursor.fetchall()
        existing_by_url = {row[1]: {"id": row[0], "comment": row[2] or "", "enabled": row[3]} for row in existing_rows}

        target_set = set(target_urls)
        to_add = []
        to_remove_ids = []

        # Find new adlists to insert
        for url in target_urls:
            if url not in existing_by_url:
                to_add.append(url)

        # Find obsolete managed adlists
        for url, data in existing_by_url.items():
            if url not in target_set:
                # Check comment tag if require_comment is enabled
                is_managed = (self.comment_tag in data["comment"]) if self.require_comment else True
                if is_managed:
                    to_remove_ids.append(data["id"])

        logger.info(
            "Adlists sync: %d target, %d currently existing, %d to add, %d to remove",
            len(target_set),
            len(existing_rows),
            len(to_add),
            len(to_remove_ids),
        )

        if self.dry_run:
            logger.info("[DRY-RUN] Would add %d adlists and remove %d obsolete adlists.", len(to_add), len(to_remove_ids))
            self.changes_made["adlist_added"] = len(to_add)
            self.changes_made["adlist_removed"] = len(to_remove_ids)
            return

        # Insert new adlists
        for url in to_add:
            cursor.execute(
                """
                INSERT INTO adlist (address, enabled, date_added, date_modified, comment)
                VALUES (?, 1, ?, ?, ?)
                """,
                (url, now, now, self.comment_tag),
            )
            adlist_id = cursor.lastrowid
            # Assign to group
            cursor.execute(
                "INSERT OR IGNORE INTO adlist_by_group (adlist_id, group_id) VALUES (?, ?)",
                (adlist_id, self.adlists_group_id),
            )

        # Handle obsolete adlists
        if to_remove_ids:
            if self.delete_obsolete:
                for ad_id in to_remove_ids:
                    cursor.execute("DELETE FROM adlist_by_group WHERE adlist_id = ?", (ad_id,))
                    cursor.execute("DELETE FROM adlist WHERE id = ?", (ad_id,))
            else:
                for ad_id in to_remove_ids:
                    cursor.execute("UPDATE adlist SET enabled = 0, date_modified = ? WHERE id = ?", (now, ad_id))

        self.changes_made["adlist_added"] = len(to_add)
        self.changes_made["adlist_removed"] = len(to_remove_ids)

    def sync_domains(self, conn: sqlite3.Connection, target_domains: List[str], domain_type: int, type_label: str):
        """Synchronizes domains or regex rules into domainlist table and domainlist_by_group."""
        cursor = conn.cursor()
        now = int(time.time())

        # Retrieve existing entries for this type
        cursor.execute("SELECT id, domain, comment, enabled FROM domainlist WHERE type = ?", (domain_type,))
        existing_rows = cursor.fetchall()
        existing_by_domain = {row[1]: {"id": row[0], "comment": row[2] or "", "enabled": row[3]} for row in existing_rows}

        target_set = set(target_domains)
        to_add = []
        to_remove_ids = []

        for d in target_domains:
            if d not in existing_by_domain:
                to_add.append(d)

        for d, data in existing_by_domain.items():
            if d not in target_set:
                is_managed = (self.comment_tag in data["comment"]) if self.require_comment else True
                if is_managed:
                    to_remove_ids.append(data["id"])

        logger.info(
            "%s sync: %d target, %d currently existing, %d to add, %d to remove",
            type_label,
            len(target_set),
            len(existing_rows),
            len(to_add),
            len(to_remove_ids),
        )

        if self.dry_run:
            logger.info("[DRY-RUN] Would add %d and remove %d %s entries.", len(to_add), len(to_remove_ids), type_label)
            self.changes_made["domain_added"] += len(to_add)
            self.changes_made["domain_removed"] += len(to_remove_ids)
            return

        # Insert new domains
        for d in to_add:
            cursor.execute(
                """
                INSERT INTO domainlist (type, domain, enabled, date_added, date_modified, comment)
                VALUES (?, ?, 1, ?, ?, ?)
                """,
                (domain_type, d, now, now, self.comment_tag),
            )
            domain_id = cursor.lastrowid
            cursor.execute(
                "INSERT OR IGNORE INTO domainlist_by_group (domainlist_id, group_id) VALUES (?, ?)",
                (domain_id, self.domains_group_id),
            )

        # Remove obsolete
        if to_remove_ids:
            if self.delete_obsolete:
                for d_id in to_remove_ids:
                    cursor.execute("DELETE FROM domainlist_by_group WHERE domainlist_id = ?", (d_id,))
                    cursor.execute("DELETE FROM domainlist WHERE id = ?", (d_id,))
            else:
                for d_id in to_remove_ids:
                    cursor.execute("UPDATE domainlist SET enabled = 0, date_modified = ? WHERE id = ?", (now, d_id))

        self.changes_made["domain_added"] += len(to_add)
        self.changes_made["domain_removed"] += len(to_remove_ids)

    def execute_sync(
        self,
        adlists: List[str],
        whitelists: List[str],
        blacklists: List[str],
        regex_whitelists: List[str],
        regex_blacklists: List[str],
        vacuum: bool = False,
    ):
        """Executes full synchronization within an atomic SQLite transaction."""
        if not os.path.exists(self.db_path):
            raise FileNotFoundError(f"Pi-hole gravity database not found at: {self.db_path}")

        if not self.dry_run:
            self.backup_database()

        conn = sqlite3.connect(self.db_path)
        try:
            conn.execute("PRAGMA foreign_keys = ON;")
            conn.execute("BEGIN TRANSACTION;")

            self.sync_adlists(conn, adlists)
            self.sync_domains(conn, whitelists, TYPE_WHITELIST, "Whitelist")
            self.sync_domains(conn, blacklists, TYPE_BLACKLIST, "Blacklist")
            self.sync_domains(conn, regex_whitelists, TYPE_REGEX_WHITELIST, "Regex Whitelist")
            self.sync_domains(conn, regex_blacklists, TYPE_REGEX_BLACKLIST, "Regex Blacklist")

            if self.dry_run:
                conn.rollback()
                logger.info("[DRY-RUN] Transaction rolled back safely. Database unmodified.")
            else:
                conn.commit()
                logger.info("Database transaction committed successfully.")

                if vacuum:
                    logger.info("Vacuuming database...")
                    conn.execute("VACUUM;")

        except Exception as e:
            conn.rollback()
            logger.error("Transaction failed and was rolled back: %s", e)
            raise
        finally:
            conn.close()


def detect_pihole_version() -> Tuple[int, str]:
    """Detects Pi-hole major version (5 or 6)."""
    try:
        res = subprocess.run(["pihole", "-v"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=10)
        output = res.stdout + res.stderr
        match = re.search(r"Pi-hole\s+v(\d+)\.", output, re.IGNORECASE)
        if match:
            major = int(match.group(1))
            return major, output.strip().splitlines()[0]
    except Exception:
        pass
    return 6, "Pi-hole (assumed v6)"


def trigger_pihole_reload(changes: dict, force_gravity: bool = False):
    """Triggers appropriate Pi-hole reload command based on changes and version."""
    major_ver, ver_str = detect_pihole_version()
    logger.info("Detected %s", ver_str)

    adlists_changed = changes.get("adlist_added", 0) > 0 or changes.get("adlist_removed", 0) > 0
    domains_changed = changes.get("domain_added", 0) > 0 or changes.get("domain_removed", 0) > 0

    if adlists_changed or force_gravity:
        logger.info("Adlists changed (or forced). Updating gravity via 'pihole -g'...")
        subprocess.run(["pihole", "-g"], check=False)
    elif domains_changed:
        logger.info("Domains changed. Reloading Pi-hole DNS lists...")
        if major_ver >= 6:
            # Pi-hole v6 supports reload-lists without rebuilding full gravity
            subprocess.run(["pihole", "restartdns", "reload-lists"], check=False)
        else:
            # Pi-hole v5 reload
            subprocess.run(["pihole", "restartdns", "reload"], check=False)
    else:
        logger.info("No gravity or DNS reload needed (no modifications detected).")


def main():
    parser = argparse.ArgumentParser(
        description="pihole-cloud-updater - Sync Pi-hole lists from Cloud Sources, Google Sheets, GDrive SQLite, and Lists-of-Lists."
    )
    parser.add_argument("-c", "--config", default="/etc/pihole-cloud-updater.conf", help="Path to configuration file")
    parser.add_argument("--dry-run", action="store_true", help="Simulate updates without modifying gravity.db")
    parser.add_argument("--no-gravity", action="store_true", help="Skip running 'pihole -g' or DNS reload after sync")
    parser.add_argument("--gravity", action="store_true", help="Force running 'pihole -g' even if no adlists changed")
    parser.add_argument("--vacuum", action="store_true", help="Vacuum gravity.db after update")
    parser.add_argument("-v", "--verbose", action="store_true", help="Enable verbose logging")
    parser.add_argument("--debug", action="store_true", help="Enable debug logging")
    parser.add_argument("--version", action="version", version=f"%(prog)s {VERSION}")
    parser.add_argument("--test-source", metavar="TARGET", help="Test fetch a single source and print extracted items")
    args = parser.parse_args()

    # Logging setup
    log_level = logging.DEBUG if args.debug else (logging.INFO if args.verbose else logging.INFO)
    logging.basicConfig(
        level=log_level,
        format="%(asctime)s [%(levelname)s] %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )

    # If --test-source is invoked, simply test fetch and exit
    if args.test_source:
        fetcher = CloudSourceFetcher(timeout=30)
        print(f"Testing extraction from: {args.test_source}")
        items = fetcher.resolve_source(args.test_source)
        print(f"Extracted {len(items)} items:")
        for idx, item in enumerate(items[:50], 1):
            print(f"  {idx}. {item}")
        if len(items) > 50:
            print(f"  ... and {len(items) - 50} more.")
        sys.exit(0)

    # Load configuration
    cfg = DEFAULT_CONFIG.copy()

    # Look for fallback config file if default not found
    config_file = args.config
    if not os.path.exists(config_file):
        for candidate in ["/etc/pihole-updatelists.conf", "config/pihole-cloud-updater.conf", "config/pihole-updatelists.conf"]:
            if os.path.exists(candidate):
                config_file = candidate
                logger.info("Using configuration file: %s", config_file)
                break

    parsed_cfg = ConfigParser.parse_file(config_file)
    cfg.update(parsed_cfg)

    # CLI flags override config
    if args.verbose:
        cfg["VERBOSE"] = True
    if args.debug:
        cfg["DEBUG"] = True
    if args.vacuum:
        cfg["VACUUM_DATABASE"] = True

    fetcher = CloudSourceFetcher(
        cache_dir=cfg.get("CACHE_DIR", "/var/cache/pihole-cloud-updater"),
        timeout=int(cfg.get("REQUEST_TIMEOUT", 30)),
        user_agent=str(cfg.get("USER_AGENT", DEFAULT_CONFIG["USER_AGENT"])),
        ignore_failures=bool(cfg.get("IGNORE_DOWNLOAD_FAILURE", False)),
        max_depth=int(cfg.get("MAX_RECURSION_DEPTH", 2)),
    )

    logger.info("pihole-cloud-updater v%s starting", VERSION)

    # 1. Collect Adlists (Blocklists / Allowlist URLs / Lists of Lists)
    adlist_sources = [cfg.get("BLOCKLISTS_URL", ""), cfg.get("GSHEET_BLOCKLISTS", "")]
    all_adlists = fetcher.resolve_all("\n".join(filter(None, adlist_sources)))

    # Add results from Google Drive SQLite query if configured
    gdrive_db = cfg.get("GDRIVE_SQLITE_FILE", "")
    if gdrive_db and cfg.get("GDRIVE_SQLITE_QUERY_BLOCKLISTS"):
        sqlite_adlists = fetcher.query_sqlite(gdrive_db, cfg["GDRIVE_SQLITE_QUERY_BLOCKLISTS"])
        all_adlists.extend(sqlite_adlists)

    # Filter invalid URLs for adlists (adlists must be http/https/file)
    valid_adlists = []
    for item in all_adlists:
        if item.startswith(("http://", "https://", "file://", "/")):
            valid_adlists.append(item)
        else:
            logger.warning("Skipping entry '%s' from blocklists: adlists must be a URL or local file path.", item)

    # 2. Collect Whitelists (exact domains)
    whitelist_sources = [cfg.get("WHITELIST_URL", ""), cfg.get("GSHEET_WHITELISTS", "")]
    all_whitelists = fetcher.resolve_all("\n".join(filter(None, whitelist_sources)))
    if gdrive_db and cfg.get("GDRIVE_SQLITE_QUERY_WHITELISTS"):
        all_whitelists.extend(fetcher.query_sqlite(gdrive_db, cfg["GDRIVE_SQLITE_QUERY_WHITELISTS"]))

    # 3. Collect Blacklists (exact domains)
    blacklist_sources = [cfg.get("BLACKLIST_URL", ""), cfg.get("GSHEET_BLACKLISTS", "")]
    all_blacklists = fetcher.resolve_all("\n".join(filter(None, blacklist_sources)))
    if gdrive_db and cfg.get("GDRIVE_SQLITE_QUERY_BLACKLISTS"):
        all_blacklists.extend(fetcher.query_sqlite(gdrive_db, cfg["GDRIVE_SQLITE_QUERY_BLACKLISTS"]))

    # 4. Collect Regex Whitelists
    regex_whitelist_sources = [cfg.get("REGEX_WHITELIST_URL", ""), cfg.get("GSHEET_REGEX_WHITELISTS", "")]
    all_regex_whitelists = fetcher.resolve_all("\n".join(filter(None, regex_whitelist_sources)))
    if gdrive_db and cfg.get("GDRIVE_SQLITE_QUERY_REGEX_WHITELISTS"):
        all_regex_whitelists.extend(fetcher.query_sqlite(gdrive_db, cfg["GDRIVE_SQLITE_QUERY_REGEX_WHITELISTS"]))

    # 5. Collect Regex Blacklists
    regex_blacklist_sources = [cfg.get("REGEX_BLACKLIST_URL", ""), cfg.get("GSHEET_REGEX_BLACKLISTS", "")]
    all_regex_blacklists = fetcher.resolve_all("\n".join(filter(None, regex_blacklist_sources)))
    if gdrive_db and cfg.get("GDRIVE_SQLITE_QUERY_REGEX_BLACKLISTS"):
        all_regex_blacklists.extend(fetcher.query_sqlite(gdrive_db, cfg["GDRIVE_SQLITE_QUERY_REGEX_BLACKLISTS"]))

    logger.info("Summary of resolved targets:")
    logger.info("  Blocklists (Adlists) : %d", len(valid_adlists))
    logger.info("  Exact Whitelists     : %d", len(all_whitelists))
    logger.info("  Exact Blacklists     : %d", len(all_blacklists))
    logger.info("  Regex Whitelists     : %d", len(all_regex_whitelists))
    logger.info("  Regex Blacklists     : %d", len(all_regex_blacklists))

    # Synchronize into Pi-hole gravity.db
    gravity_db_path = cfg.get("GRAVITY_DB", "/etc/pihole/gravity.db")
    sync = GravitySync(
        db_path=gravity_db_path,
        comment_tag=cfg.get("COMMENT", DEFAULT_CONFIG["COMMENT"]),
        require_comment=bool(cfg.get("REQUIRE_COMMENT", True)),
        delete_obsolete=bool(cfg.get("DELETE_OBSOLETE", True)),
        adlists_group_id=int(cfg.get("ADLISTS_GROUP_ID", 0)),
        domains_group_id=int(cfg.get("DOMAINS_GROUP_ID", 0)),
        dry_run=args.dry_run,
    )

    try:
        sync.execute_sync(
            adlists=valid_adlists,
            whitelists=all_whitelists,
            blacklists=all_blacklists,
            regex_whitelists=all_regex_whitelists,
            regex_blacklists=all_regex_blacklists,
            vacuum=bool(cfg.get("VACUUM_DATABASE", False)),
        )
    except Exception as e:
        logger.error("Gravity sync encountered an error: %s", e)
        sys.exit(1)

    # Post-sync reload
    if not args.dry_run and not args.no_gravity and cfg.get("UPDATE_GRAVITY", True):
        trigger_pihole_reload(sync.changes_made, force_gravity=args.gravity)

    logger.info("pihole-cloud-updater completed successfully.")


if __name__ == "__main__":
    main()

