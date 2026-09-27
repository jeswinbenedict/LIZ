"""Fill in the price of published tools the catalog does not know yet.

A third of the catalog was published with pricing "unknown", which makes the
price filter hide a third of the catalog under every choice but "Any price".
Most of those sites do say what they cost — on a pricing page the scraper never
used to open. Enrichment now follows that link for new tools; this applies the
same read to the tools already published.

    python -m liz_scraper.backfill_pricing              # report, change nothing
    python -m liz_scraper.backfill_pricing --apply      # write what was learned

Only pricing_type is written, and only when the answer is known. Moving from
"unknown" to a price does not alert followers (migration 0021): the product
did not change, the catalog caught up.
"""

from __future__ import annotations

import argparse
import collections
import json
import logging
import sys

import requests

from .config import REQUEST_TIMEOUT, load_settings
from .enrich import enrich_url, is_aggregator
from .http_client import PoliteSession

log = logging.getLogger(__name__)


def _headers(key: str) -> dict[str, str]:
    return {
        "apikey": key,
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
    }


def fetch_unknown(settings, session: requests.Session, limit: int) -> list[dict]:
    resp = session.get(
        f"{settings.rest_url}/tools",
        params={
            "select": "id,name,website_url",
            "status": "eq.published",
            "pricing_type": "eq.unknown",
            "order": "trend_score.desc",
            "limit": limit,
        },
        headers=_headers(settings.service_role_key),
        timeout=REQUEST_TIMEOUT,
    )
    resp.raise_for_status()
    return resp.json()


def learned_pricing(session: PoliteSession, row: dict) -> str:
    """The row's pricing as its site states it now, or "unknown"."""
    url = row.get("website_url") or ""
    if not url or is_aggregator(url):
        return "unknown"
    facts = enrich_url(session, url)
    return facts.pricing_type if facts else "unknown"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="Write the results.")
    parser.add_argument("--limit", type=int, default=500)
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
    rows = fetch_unknown(settings, rest, args.limit)
    learned: collections.Counter[str] = collections.Counter()

    for row in rows:
        pricing = learned_pricing(polite, row)
        learned[pricing] += 1
        log.info("%-8s %s", pricing, row.get("name"))
        if pricing == "unknown" or not args.apply:
            continue
        resp = rest.patch(
            f"{settings.rest_url}/tools",
            params={"id": f"eq.{row['id']}", "pricing_type": "eq.unknown"},
            headers={**_headers(settings.service_role_key),
                     "Prefer": "return=minimal"},
            json={"pricing_type": pricing},
            timeout=REQUEST_TIMEOUT,
        )
        if resp.status_code >= 400:
            log.warning("could not update %s: %s", row["id"], resp.text[:200])

    report = {"tried": len(rows), "learned": dict(learned), "applied": args.apply}
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
