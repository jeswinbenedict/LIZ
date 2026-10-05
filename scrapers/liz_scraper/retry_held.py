"""Give held rows another go at reaching their product page.

Every Product Hunt row in the backlog is held for the same reason: the scraper
ran on a GitHub Actions runner, Product Hunt's edge returns 403 to datacenter
IPs, and enrichment fell back to the listing URL. The quality gate then refused
it, correctly — a tool whose Visit button goes back to Product Hunt is not a
catalog entry.

Nothing about those rows is wrong except where they were fetched from. Run from
a connection that is not blocked — the machine n8n runs on — the same code
resolves them: a dry run of six current launches from a home connection
reached every product page and all six passed the gate.

Normal scraping cannot recover them, because it only sees what is on the feed
today and these launches have rolled off it. This re-reads the stored listing
URL for each held row instead.

    python -m liz_scraper.retry_held                 # report, change nothing
    python -m liz_scraper.retry_held --apply         # write what now resolves
    python -m liz_scraper.retry_held --apply --limit 50

Polite by construction: it goes through the same PoliteSession as every other
fetch, so robots.txt and crawl delays apply. Product Hunt's robots.txt allows
/products/*.
"""

from __future__ import annotations

import argparse
import json
import logging
import sys

import requests

from .config import REQUEST_TIMEOUT, load_settings
from .enrich import PageFacts, is_aggregator, resolve_and_enrich
from .http_client import PoliteSession
from .ingest_client import IngestClient
from .normalize import build_tool_row, choose_name
from .quality import assess

log = logging.getLogger(__name__)

# The held reason written by the quality gate for an unresolved listing. Only
# these are worth a network round trip; a row held for a missing description
# will not be fixed by fetching it again.
_LISTING_MARKER = "listing, not the product"


def _headers(key: str) -> dict[str, str]:
    return {
        "apikey": key,
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
    }


def fetch_held(settings, session: requests.Session, limit: int) -> list[dict]:
    """Pending rows held because their website is still a listing page."""
    if settings.uses_ingest:
        return IngestClient(settings, session).held(_LISTING_MARKER, limit)
    resp = session.get(
        f"{settings.rest_url}/tools",
        params={
            "select": "id,name,tagline,description,website_url,source,source_url,"
            "logo_url,category,platforms,pricing_type,hold_reason",
            "status": "eq.pending",
            "hold_reason": f"like.*{_LISTING_MARKER}*",
            # Newest first: a launch from this week is worth more to a reader
            # than one from a month ago, and a partial run should favour it.
            "order": "created_at.desc",
            "limit": limit,
        },
        headers=_headers(settings.service_role_key),
        timeout=REQUEST_TIMEOUT,
    )
    resp.raise_for_status()
    return resp.json()


def rebuild(row: dict, site_url: str, facts: PageFacts | None) -> dict | None:
    """The update to write for `row`, or None when nothing resolved.

    Pure, so the decision about what changes can be tested without a network.
    The content hash is deliberately left alone: it is keyed on the listing
    URL, and keeping it means a future feed run recognises the row instead of
    creating a duplicate.
    """
    if facts is None or is_aggregator(site_url):
        return None

    rebuilt = build_tool_row(
        name=choose_name(row.get("name") or "", facts.title, url=site_url),
        website_url=site_url,
        tagline=row.get("tagline") or facts.description,
        # The stored description is usually the tagline repeated, because the
        # listing page was all enrichment could see. The product's own page is
        # the better source now that it is reachable.
        description=facts.description or row.get("description") or "",
        logo_url=facts.logo_url or row.get("logo_url"),
        category=facts.category or row.get("category"),
        platforms=facts.platforms or row.get("platforms"),
        pricing_type=facts.pricing_type
        if facts.pricing_type != "unknown"
        else (row.get("pricing_type") or "unknown"),
        source=row.get("source") or "scraper",
        source_url=row.get("source_url"),
    )

    verdict = assess(rebuilt)
    update = {
        key: rebuilt[key]
        for key in (
            "name",
            "tagline",
            "description",
            "website_url",
            "logo_url",
            "category",
            "platforms",
            "pricing_type",
        )
    }
    update["status"] = verdict.status
    update["hold_reason"] = None if verdict.publish else verdict.reasons[0]
    return update


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="Write the results.")
    parser.add_argument("--limit", type=int, default=25)
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args(argv)

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(levelname)s %(name)s: %(message)s",
    )

    try:
        settings = load_settings()
    except ValueError as err:
        print(f"error: {err}", file=sys.stderr)
        return 2

    rest = requests.Session()
    polite = PoliteSession()
    held = fetch_held(settings, rest, args.limit)

    report = {"held_listings_tried": len(held), "published": 0, "still_held": 0,
              "unreachable": 0, "applied": args.apply}

    for row in held:
        listing = row.get("source_url") or row.get("website_url") or ""
        site_url, facts = resolve_and_enrich(polite, listing)
        update = rebuild(row, site_url, facts)

        if update is None:
            report["unreachable"] += 1
            continue
        if update["status"] == "published":
            report["published"] += 1
        else:
            report["still_held"] += 1

        if args.apply and settings.uses_ingest:
            try:
                IngestClient(settings, rest).update_held(row["id"], update)
            except requests.RequestException as err:
                log.warning("could not update %s: %s", row["id"], err)
        elif args.apply:
            resp = rest.patch(
                f"{settings.rest_url}/tools",
                params={"id": f"eq.{row['id']}"},
                headers={**_headers(settings.service_role_key),
                         "Prefer": "return=minimal"},
                json=update,
                timeout=REQUEST_TIMEOUT,
            )
            if resp.status_code >= 400:
                # One bad row (a slug collision, say) should not end the run.
                log.warning("could not update %s: %s", row["id"], resp.text[:200])

    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
