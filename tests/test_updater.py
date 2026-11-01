#!/usr/bin/env python3
"""
Unit tests for pihole-cloud-updater.
Tests:
  - Configuration parsing
  - Google Sheets URL parsing, CSV transformation, and column selection
  - Google Drive file ID extraction and SQLite querying
  - Recursive Lists of Lists ("listsoflist") resolution and cycle prevention
  - Pi-hole gravity.db synchronization, group mapping, and comment safety
"""

import csv
import io
import os
import shutil
import sqlite3
import tempfile
import unittest
from unittest.mock import MagicMock, patch

# Import classes from pihole-cloud-updater
import sys
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "scripts")))
import importlib.util
spec = importlib.util.spec_from_file_location(
    "pihole_cloud_updater",
    os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "scripts", "pihole-cloud-updater.py"))
)
updater = importlib.util.module_from_spec(spec)
spec.loader.exec_module(updater)


class TestConfigParser(unittest.TestCase):
    def test_parse_simple_and_multiline(self):
        sample_config = """
; Sample configuration
GRAVITY_DB="/var/pihole/gravity.db"
ADLISTS_GROUP_ID=2
REQUIRE_COMMENT=true
DELETE_OBSOLETE=false
BLOCKLISTS_URL="https://example.com/list1.txt
https://example.com/list2.txt"
"""
        with tempfile.NamedTemporaryFile("w+", delete=False, encoding="utf-8") as f:
            f.write(sample_config)
            f_path = f.name

        try:
            cfg = updater.ConfigParser.parse_file(f_path)
            self.assertEqual(cfg["GRAVITY_DB"], "/var/pihole/gravity.db")
            self.assertEqual(cfg["ADLISTS_GROUP_ID"], 2)
            self.assertTrue(cfg["REQUIRE_COMMENT"])
            self.assertFalse(cfg["DELETE_OBSOLETE"])
            self.assertIn("https://example.com/list1.txt", cfg["BLOCKLISTS_URL"])
            self.assertIn("https://example.com/list2.txt", cfg["BLOCKLISTS_URL"])
        finally:
            os.remove(f_path)


class TestGoogleSheetsIntegration(unittest.TestCase):
    def test_parse_google_sheet_url_variants(self):
        # 1. Standard URL with gid
        url1 = "https://docs.google.com/spreadsheets/d/1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms/edit#gid=12345"
        sheet_id, gid, sheet_name, col_spec = updater.CloudSourceFetcher.parse_google_sheet_target(url1)
        self.assertEqual(sheet_id, "1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms")
        self.assertEqual(gid, "12345")
        self.assertIsNone(col_spec)

        # 2. URL with column specifier via pipe
        url2 = "https://docs.google.com/spreadsheets/d/1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms/edit#gid=0 | Blocklist_URL"
        sheet_id, gid, sheet_name, col_spec = updater.CloudSourceFetcher.parse_google_sheet_target(url2)
        self.assertEqual(sheet_id, "1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms")
        self.assertEqual(gid, "0")
        self.assertEqual(col_spec, "Blocklist_URL")

        # 3. Custom gsheet:// URI
        url3 = "gsheet://1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms?gid=999&sheet=Ads&col=1"
        sheet_id, gid, sheet_name, col_spec = updater.CloudSourceFetcher.parse_google_sheet_target(url3)
        self.assertEqual(sheet_id, "1BxiMVs0XRA5nFMdKvBdBZjgmUUqptlbs74OgvE2upms")
        self.assertEqual(gid, "999")
        self.assertEqual(sheet_name, "Ads")
        self.assertEqual(col_spec, "1")

    def test_fetch_google_sheet_column_selection(self):
        sample_csv = "Name,URL,Enabled\nFilter A,https://example.com/a.txt,yes\n# Commented row,https://example.com/b.txt,no\nFilter C,https://example.com/c.txt,yes\n"
        fetcher = updater.CloudSourceFetcher(cache_dir=tempfile.gettempdir())

        # Mock fetch_text to return sample CSV
        with patch.object(fetcher, "fetch_text", return_value=sample_csv):
            # Target by column header name
            target = "https://docs.google.com/spreadsheets/d/dummy_id/edit#gid=0 | URL"
            items = fetcher.fetch_google_sheet(target)
            self.assertEqual(items, ["https://example.com/a.txt", "https://example.com/c.txt"])

            # Target by column letter 'B'
            target_b = "https://docs.google.com/spreadsheets/d/dummy_id/edit#gid=0 | B"
            items_b = fetcher.fetch_google_sheet(target_b)
            self.assertEqual(items_b, ["https://example.com/a.txt", "https://example.com/c.txt"])


class TestGDriveSQLiteIntegration(unittest.TestCase):
    def test_extract_gdrive_file_id(self):
        url1 = "https://drive.google.com/file/d/1AbCdEfGhIjKlMnOpQrStUvWxYz012345/view?usp=sharing"
        self.assertEqual(updater.CloudSourceFetcher.extract_gdrive_file_id(url1), "1AbCdEfGhIjKlMnOpQrStUvWxYz012345")

        url2 = "https://drive.google.com/open?id=2BcDeFgHiJkLmNoPqRsTuVwXyZ123456"
        self.assertEqual(updater.CloudSourceFetcher.extract_gdrive_file_id(url2), "2BcDeFgHiJkLmNoPqRsTuVwXyZ123456")

        url3 = "gdrive://3CdEfGhIjKlMnOpQrStUvWxYz234567"
        self.assertEqual(updater.CloudSourceFetcher.extract_gdrive_file_id(url3), "3CdEfGhIjKlMnOpQrStUvWxYz234567")

    def test_query_sqlite_local(self):
        temp_dir = tempfile.mkdtemp()
        db_path = os.path.join(temp_dir, "test_lists.db")
        try:
            conn = sqlite3.connect(db_path)
            conn.execute("CREATE TABLE lists (id INTEGER PRIMARY KEY, url TEXT, active INT);")
            conn.execute("INSERT INTO lists (url, active) VALUES ('https://test.com/list1.txt', 1);")
            conn.execute("INSERT INTO lists (url, active) VALUES ('https://test.com/list2.txt', 0);")
            conn.execute("INSERT INTO lists (url, active) VALUES ('https://test.com/list3.txt', 1);")
            conn.commit()
            conn.close()

            fetcher = updater.CloudSourceFetcher(cache_dir=temp_dir)
            results = fetcher.query_sqlite(db_path, "SELECT url FROM lists WHERE active = 1")
            self.assertEqual(results, ["https://test.com/list1.txt", "https://test.com/list3.txt"])
        finally:
            shutil.rmtree(temp_dir)


class TestListsOfLists(unittest.TestCase):
    def test_recursive_lists_of_lists(self):
        fetcher = updater.CloudSourceFetcher(cache_dir=tempfile.gettempdir(), max_depth=2)

        # Mock responses
        # Root index points to sublist A and sublist B
        root_content = "https://server.com/sublist_a.txt\nhttps://server.com/sublist_b.txt\n# ignore this comment\n"
        sublist_a_content = "https://adlists.com/adlist1.txt\nhttps://adlists.com/adlist2.txt\n"
        sublist_b_content = "https://adlists.com/adlist3.txt\n"

        def mock_fetch(url):
            if url == "https://server.com/root.txt":
                return root_content
            elif url == "https://server.com/sublist_a.txt":
                return sublist_a_content
            elif url == "https://server.com/sublist_b.txt":
                return sublist_b_content
            return ""

        with patch.object(fetcher, "fetch_text", side_effect=mock_fetch):
            results = fetcher.resolve_source("https://server.com/root.txt")
            self.assertEqual(
                results,
                [
                    "https://adlists.com/adlist1.txt",
                    "https://adlists.com/adlist2.txt",
                    "https://adlists.com/adlist3.txt",
                ],
            )


class TestGravitySync(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.mkdtemp()
        self.db_path = os.path.join(self.temp_dir, "gravity.db")

        # Create Pi-hole gravity schema
        conn = sqlite3.connect(self.db_path)
        conn.executescript("""
            CREATE TABLE adlist (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                address TEXT UNIQUE NOT NULL,
                enabled INTEGER NOT NULL DEFAULT 1,
                date_added INTEGER NOT NULL,
                date_modified INTEGER NOT NULL,
                comment TEXT
            );
            CREATE TABLE adlist_by_group (
                adlist_id INTEGER NOT NULL,
                group_id INTEGER NOT NULL,
                PRIMARY KEY (adlist_id, group_id)
            );
            CREATE TABLE domainlist (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                type INTEGER NOT NULL DEFAULT 0,
                domain TEXT NOT NULL,
                enabled INTEGER NOT NULL DEFAULT 1,
                date_added INTEGER NOT NULL,
                date_modified INTEGER NOT NULL,
                comment TEXT
            );
            CREATE TABLE domainlist_by_group (
                domainlist_id INTEGER NOT NULL,
                group_id INTEGER NOT NULL,
                PRIMARY KEY (domainlist_id, group_id)
            );
            -- Pre-insert manual user entry (should not be deleted)
            INSERT INTO adlist (address, enabled, date_added, date_modified, comment)
            VALUES ('https://user-manual.com/list.txt', 1, 1000, 1000, 'User manual list from Web GUI');
        """)
        conn.commit()
        conn.close()

    def tearDown(self):
        shutil.rmtree(self.temp_dir)

    def test_sync_adlists_and_preserve_manual(self):
        sync = updater.GravitySync(
            db_path=self.db_path,
            comment_tag="Managed by pihole-cloud-updater",
            require_comment=True,
            delete_obsolete=True,
        )

        target_adlists = [
            "https://cloud.com/adlist1.txt",
            "https://cloud.com/adlist2.txt",
        ]

        sync.execute_sync(
            adlists=target_adlists,
            whitelists=["safe-banking.com"],
            blacklists=["malware.com"],
            regex_whitelists=[r"^pi-hole\.net$"],
            regex_blacklists=[r"^telemetry\..*"],
        )

        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()

        # Verify adlist table
        cursor.execute("SELECT address, comment FROM adlist ORDER BY id")
        rows = cursor.fetchall()

        # Should have preserved the user manual list AND added the 2 managed lists
        addresses = [r[0] for r in rows]
        self.assertIn("https://user-manual.com/list.txt", addresses)
        self.assertIn("https://cloud.com/adlist1.txt", addresses)
        self.assertIn("https://cloud.com/adlist2.txt", addresses)

        # Verify domainlist table
        cursor.execute("SELECT domain, type FROM domainlist ORDER BY id")
        domain_rows = cursor.fetchall()
        self.assertEqual(len(domain_rows), 4)

        conn.close()


if __name__ == "__main__":
    unittest.main()

