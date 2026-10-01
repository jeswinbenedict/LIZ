"""Hide products that were published twice.

    python -m liz_scraper.dedupe_tools            # report, change nothing
    python -m liz_scraper.dedupe_tools --apply    # hide the copies

Two published rows are one product when they share a site (tools.site_key,
migration 0049), or have the same name on the same host — the same launch
seen once at its home page and once at a deeper link. The oldest row is kept:
it is the one people may already have saved or shared. Anything the copy
knows that the original does not (its Hacker News story, GitHub repository,
preview image) is moved across before the copy is hidden, with a hold reason
that names the row it duplicates. Nothing is deleted.

The scraper now checks site_key before writing, so this is for rows from
before that check.
"""

from __future__ import annotations

import argparse
import collections
import json
import sys
from urllib.parse import urlsplit

import requests

from .config import REQUEST_TIMEOUT, load_settings

CARRY = ("hn_id", "hn_points", "hn_comments", "hn_posted_at", "gh_repo",
         "gh_stars", "image_url")


def group_duplicates(rows: list[dict]) -> list[list[dict]]:
    """Groups of rows that are one product, oldest first. Union-find over the
    two rules, so a chain (A shares a site with B, B a name and host with C)
    becomes one group."""
    parent = {r["id"]: r["id"] for r in rows}

    def find(x: str) -> str:
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    def union(a: str, b: str) -> None:
        parent[find(a)] = find(b)

    by_key: dict[tuple, str] = {}
    for r in rows:
        host = urlsplit(r.get("website_url") or "").netloc.lower().removeprefix("www.")
        keys = []
        if r.get("site_key"):
            keys.append(("site", r["site_key"]))
        if host:
            keys.append(("name", r["name"].strip().lower(), host))
        for k in keys:
            if k in by_key:
                union(r["id"], by_key[k])
            else:
                by_key[k] = r["id"]

    groups: dict[str, list[dict]] = collections.defaultdict(list)
    for r in rows:
        groups[find(r["id"])].append(r)
    return [sorted(g, key=lambda r: r["created_at"]) for g in groups.values() if len(g) > 1]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="liz_scraper.dedupe_tools")
    parser.add_argument("--apply", action="store_true", help="Hide the copies.")
    args = parser.parse_args(argv)

    settings = load_settings()
    if not settings.configured:
        print("error: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set", file=sys.stderr)
        return 2
    headers = {"apikey": settings.service_role_key,
               "Authorization": f"Bearer {settings.service_role_key}",
               "Content-Type": "application/json", "Prefer": "return=minimal"}
    rows = requests.get(
        f"{settings.rest_url}/tools",
        params={"select": "id,name,slug,website_url,site_key,created_at," + ",".join(CARRY),
                "status": "eq.published", "limit": 5000},
        headers=headers, timeout=REQUEST_TIMEOUT,
    ).json()

    groups = group_duplicates(rows)
    hidden = 0
    for group in groups:
        keep, copies = group[0], group[1:]
        print(json.dumps({"keep": keep["slug"], "hide": [c["slug"] for c in copies]}))
        if not args.apply:
            continue
        carried = {}
        for field in CARRY:
            if keep.get(field) is None:
                value = next((c[field] for c in copies if c.get(field) is not None), None)
                if value is not None:
                    carried[field] = value
        if carried:
            requests.patch(f"{settings.rest_url}/tools", params={"id": f"eq.{keep['id']}"},
                           headers=headers, json=carried, timeout=REQUEST_TIMEOUT)
        for c in copies:
            requests.patch(
                f"{settings.rest_url}/tools", params={"id": f"eq.{c['id']}"},
                headers=headers, timeout=REQUEST_TIMEOUT,
                json={"status": "hidden", "hold_reason": f"duplicate of /tools/{keep['slug']}"},
            )
            hidden += 1

    print(f"\n{len(groups)} products listed more than once; "
          f"{hidden if args.apply else sum(len(g) - 1 for g in groups)} copies "
          f"{'hidden' if args.apply else 'would be hidden'}.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
