"""Keep sites known to serve malware out of the catalog.

    python -m liz_scraper.threats              # report published tools on the list
    python -m liz_scraper.threats --apply      # hold them, with the reason

Liz links people to sites it found by scraping, and a link from Liz reads as
an endorsement. A launch post can point anywhere, so every new tool's site is
checked against abuse.ch URLhaus's list of hosts currently serving malware —
free, maintained, and fetched fresh each run — and so is the published
catalog once a day, since a site can be compromised after it was listed.

A listed tool is not deleted: it is set back to pending with a hold reason, so
an admin can see why and restore it once the host is cleaned.
"""

from __future__ import annotations

import argparse
import json
import logging
import sys
from urllib.parse import urlsplit

import requests

from .config import REQUEST_TIMEOUT, USER_AGENT, load_settings

log = logging.getLogger(__name__)

HOSTFILE = "https://urlhaus.abuse.ch/downloads/hostfile/"
REASON = "site listed by URLhaus as serving malware"


def parse_hostfile(text: str) -> set[str]:
    hosts = set()
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) >= 2:
            hosts.add(parts[1].lower())
    return hosts


def fetch_hosts(session: requests.Session | None = None) -> set[str]:
    """The current list, or an empty set when it cannot be fetched — a check
    that fails closed would stop every scrape whenever abuse.ch is down."""
    try:
        resp = (session or requests).get(HOSTFILE, timeout=REQUEST_TIMEOUT,
                                         headers={"User-Agent": USER_AGENT})
        resp.raise_for_status()
    except requests.RequestException as err:
        log.warning("URLhaus list unavailable: %s", err)
        return set()
    return parse_hostfile(resp.text)


def is_listed(url: str | None, hosts: set[str]) -> bool:
    host = urlsplit(url or "").netloc.lower().split(":")[0]
    if not host:
        return False
    host = host.removeprefix("www.")
    # A listed parent domain covers its subdomains.
    parts = host.split(".")
    return any(".".join(parts[i:]) in hosts for i in range(len(parts) - 1)) or host in hosts


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="liz_scraper.threats")
    parser.add_argument("--apply", action="store_true", help="Hold listed tools.")
    args = parser.parse_args(argv)
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s: %(message)s")

    settings = load_settings()
    if not settings.configured:
        print("error: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set", file=sys.stderr)
        return 2
    hosts = fetch_hosts()
    headers = {"apikey": settings.service_role_key,
               "Authorization": f"Bearer {settings.service_role_key}",
               "Content-Type": "application/json", "Prefer": "return=minimal"}
    rows = requests.get(f"{settings.rest_url}/tools",
                        params={"select": "id,name,website_url", "status": "eq.published",
                                "limit": 10000},
                        headers=headers, timeout=REQUEST_TIMEOUT).json()
    listed = [r for r in rows if is_listed(r.get("website_url"), hosts)]
    for r in listed:
        print(json.dumps({"name": r["name"], "site": r["website_url"]}))
        if args.apply:
            requests.patch(f"{settings.rest_url}/tools", params={"id": f"eq.{r['id']}"},
                           headers=headers, json={"status": "pending", "hold_reason": REASON},
                           timeout=REQUEST_TIMEOUT)
    print(json.dumps({"hosts_on_list": len(hosts), "checked": len(rows),
                      "listed": len(listed), "applied": args.apply}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
