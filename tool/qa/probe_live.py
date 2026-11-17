"""Probe a deployed Liz backend from the outside, as someone with no account.

Every request carries either no credentials or only the public anon key that
ships in the web app, and sends an empty body, so nothing is created, changed
or spent. It checks that:

1. every Edge Function refuses a caller who is not signed in (no 2xx), and
   is deployed (not 404);
2. the anon key reads no rows from any table or view (row-level security,
   migration 0061: the catalog is for signed-in people too).

    SUPABASE_URL=... SUPABASE_ANON_KEY=... python tool/qa/probe_live.py

Exits 1 on any failure. Prints status codes and row counts only, never keys
or row contents.
"""
from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request

FUNCTIONS = [
    "analyze-repo", "ask-liz", "ask-repo", "delete-account", "embed-tools",
    "fetch-news", "fetch-tools", "firebase-session", "logo", "scraper-ingest",
    "send-notification", "summarize-news", "summarize-tools", "tool-updates",
]

# Every table and view in supabase/migrations. A signed-out visitor must see
# none of their rows.
RELATIONS = [
    "app_config", "bookmarks", "categories", "collections", "comments",
    "devices", "error_events", "events", "firebase_accounts", "follows",
    "likes", "news", "news_tools", "notifications", "posts", "profiles",
    "rate_limits", "repo_analyses", "repo_analysis_files", "reports",
    "reviews", "seeded_metrics_backup", "tool_changes",
    "tool_signal_snapshots", "tool_updates_cache", "tools",
    "user_preferences", "drops", "error_summary", "news_needing_summary",
    "tools_needing_embedding", "tools_needing_summary", "tools_rising",
]


def request(url: str, headers: dict[str, str], body: bytes | None) -> tuple[int, bytes]:
    req = urllib.request.Request(url, data=body, headers=headers,
                                 method="POST" if body is not None else "GET")
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


def main() -> int:
    base = os.environ.get("SUPABASE_URL", "").rstrip("/")
    anon = os.environ.get("SUPABASE_ANON_KEY", "")
    if not base or not anon:
        print("Set SUPABASE_URL and SUPABASE_ANON_KEY (public values, see .env.example).")
        return 2
    failures = 0

    print("Edge Functions (no auth / anon key), expect 4xx and not 404:")
    for fn in FUNCTIONS:
        codes = []
        for headers in ({}, {"apikey": anon, "Authorization": f"Bearer {anon}"}):
            status, _ = request(f"{base}/functions/v1/{fn}",
                                {**headers, "Content-Type": "application/json"}, b"{}")
            codes.append(status)
        bad = [c for c in codes if c < 400 or c == 404 or c >= 500]
        failures += bool(bad)
        print(f"  {'FAIL' if bad else 'ok  '} {fn:20} {codes[0]:>4} {codes[1]:>4}")

    print("Tables and views (anon key), expect no rows:")
    for rel in RELATIONS:
        status, body = request(
            f"{base}/rest/v1/{rel}?select=*&limit=1",
            {"apikey": anon, "Authorization": f"Bearer {anon}"}, None)
        rows = None
        if status == 200:
            try:
                rows = len(json.loads(body))
            except ValueError:
                rows = -1
        leaked = status == 200 and rows != 0
        failures += leaked
        shown = f"{rows} rows" if status == 200 else f"refused ({status})"
        print(f"  {'FAIL' if leaked else 'ok  '} {rel:24} {shown}")

    print(f"\n{failures} failure(s)")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
