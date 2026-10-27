"""Keep sites known to serve malware or phishing out of the catalog.

    python -m liz_scraper.threats              # report published tools on a list
    python -m liz_scraper.threats --apply      # hold them, with the reason

Liz links people to sites it found by scraping, and a link from Liz reads as
an endorsement. A launch post can point anywhere, so every new tool's site is
checked against two lists, and so is the published catalog once a day, since
a site can be compromised after it was listed:

* malware: abuse.ch URLhaus's hosts serving malware;
* phishing: the hosts on OpenPhish, PhishTank and PhishStats.

Both are fetched fresh each run from the malware-filter project, which
republishes those sources every 12 hours as plain domain lists, free and
without a key, and leaves out popular domains so a big host is never caught
by one bad page on it. abuse.ch's own downloads, which this read until
October 2026, now answer 410 Gone.

A listed tool is not deleted: it is set back to pending with a hold reason
naming the list, so an admin can see why and restore it once the host is
cleaned.

A list that cannot be fetched is skipped rather than failing the scrape, but
never silently: the daily check exits 1 when no list could be read at all, so
the screening being off shows as a red run.
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import sys
from dataclasses import dataclass, field
from urllib.parse import urlsplit

import requests

from .config import REQUEST_TIMEOUT, USER_AGENT, load_settings

log = logging.getLogger(__name__)

_MIRROR = "https://malware-filter.gitlab.io/malware-filter"


@dataclass(frozen=True)
class ThreatList:
    name: str
    url: str
    reason: str


LISTS = (
    ThreatList(
        "malware",
        f"{_MIRROR}/urlhaus-filter-domains.txt",
        "site listed by URLhaus as serving malware",
    ),
    ThreatList(
        "phishing",
        f"{_MIRROR}/phishing-filter-domains.txt",
        "site listed as phishing (OpenPhish, PhishTank, PhishStats)",
    ),
)

# The reason a malware hold carries; kept for callers that name one reason.
REASON = LISTS[0].reason

# Fewer entries than this is an error page or a truncated download, not a
# list: each has carried thousands since they began.
MIN_ENTRIES = 1000


def parse_domains(text: str) -> set[str]:
    """One host per line, `#` comments ignored. Also reads hosts-file lines
    ("0.0.0.0 example.com"), the format the old URLhaus download used."""
    hosts = set()
    for line in text.splitlines():
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        parts = line.split()
        host = parts[1] if len(parts) >= 2 else parts[0]
        hosts.add(host.lower().rstrip("."))
    return hosts


# The old name, for anything still reading a hosts file.
parse_hostfile = parse_domains


@dataclass
class Fetched:
    """The lists that were read, by name, and the ones that could not be."""

    hosts: dict[str, set[str]] = field(default_factory=dict)
    missing: list[str] = field(default_factory=list)

    @property
    def all_hosts(self) -> set[str]:
        return set().union(*self.hosts.values()) if self.hosts else set()


def fetch_lists(session: requests.Session | None = None) -> Fetched:
    """Every list that can be read now. One that is down is left out — a check
    that failed closed would stop every scrape whenever a mirror is down — and
    named in `missing`, so the caller can say so."""
    out = Fetched()
    for threat in LISTS:
        try:
            resp = (session or requests).get(
                threat.url, timeout=REQUEST_TIMEOUT, headers={"User-Agent": USER_AGENT}
            )
            resp.raise_for_status()
            hosts = parse_domains(resp.text)
        except requests.RequestException as err:
            log.warning("%s list unavailable: %s", threat.name, err)
            out.missing.append(threat.name)
            continue
        if len(hosts) < MIN_ENTRIES:
            log.warning("%s list looks broken: %d entries", threat.name, len(hosts))
            out.missing.append(threat.name)
            continue
        out.hosts[threat.name] = hosts
    return out


def fetch_hosts(session: requests.Session | None = None) -> set[str]:
    """Every listed host, from whichever lists could be read."""
    return fetch_lists(session).all_hosts


def is_listed(url: str | None, hosts: set[str]) -> bool:
    host = urlsplit(url or "").netloc.lower().split(":")[0]
    if not host:
        return False
    host = host.removeprefix("www.")
    # A listed parent domain covers its subdomains.
    parts = host.split(".")
    return any(".".join(parts[i:]) in hosts for i in range(len(parts) - 1)) or host in hosts


def reason_for(url: str | None, fetched: Fetched) -> str | None:
    """The hold reason for the first list that names [url]'s host, or None."""
    for threat in LISTS:
        hosts = fetched.hosts.get(threat.name)
        if hosts and is_listed(url, hosts):
            return threat.reason
    return None


def _annotate(level: str, message: str) -> None:
    """A GitHub Actions annotation when running there, so a skipped list shows
    on the run's summary, not only in its log."""
    if os.environ.get("GITHUB_ACTIONS") == "true":
        print(f"::{level}::{message}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="liz_scraper.threats")
    parser.add_argument("--apply", action="store_true", help="Hold listed tools.")
    args = parser.parse_args(argv)
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s: %(message)s")

    settings = load_settings()
    if not settings.configured:
        print("error: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set", file=sys.stderr)
        return 2
    fetched = fetch_lists()
    if not fetched.hosts:
        _annotate("error", "No threat list could be fetched; sites were not screened.")
        print("error: no threat list could be fetched; nothing was screened", file=sys.stderr)
        return 1
    for name in fetched.missing:
        _annotate("warning", f"The {name} list could not be fetched; screened without it.")

    headers = {"apikey": settings.service_role_key,
               "Authorization": f"Bearer {settings.service_role_key}",
               "Content-Type": "application/json", "Prefer": "return=minimal"}
    rows = requests.get(f"{settings.rest_url}/tools",
                        params={"select": "id,name,website_url", "status": "eq.published",
                                "limit": 10000},
                        headers=headers, timeout=REQUEST_TIMEOUT).json()
    listed = []
    for r in rows:
        reason = reason_for(r.get("website_url"), fetched)
        if reason is None:
            continue
        listed.append(r)
        print(json.dumps({"name": r["name"], "site": r["website_url"], "reason": reason}))
        if args.apply:
            requests.patch(f"{settings.rest_url}/tools", params={"id": f"eq.{r['id']}"},
                           headers=headers, json={"status": "pending", "hold_reason": reason},
                           timeout=REQUEST_TIMEOUT)
    print(json.dumps({
        "lists": {name: len(hosts) for name, hosts in fetched.hosts.items()},
        "missing": fetched.missing,
        "checked": len(rows),
        "listed": len(listed),
        "applied": args.apply,
    }))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
