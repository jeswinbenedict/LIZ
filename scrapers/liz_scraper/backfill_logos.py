"""Fill in the logo of published tools that were stored without one.

A tool with no logo_url shows a letter tile. On 28 September 41 published tools
had none, and re-reading their sites found 11 whose page now declares an icon
(it changed, or ingest only ever saw a listing) and 4 that serve /favicon.ico
without declaring it — which enrichment did not check until then.

    python -m liz_scraper.backfill_logos              # report, change nothing
    python -m liz_scraper.backfill_logos --apply      # write what was found
    python -m liz_scraper.backfill_logos --svg        # tools whose logo is SVG

Only logo_url is written, and only where it is still what was read — empty,
or the SVG being replaced.

--svg: Flutter cannot draw SVG, and 84 published tools had stored one. The logo
proxy now refuses SVG and falls back to the site's favicon, which rescued 65 of
them; this replaces the stored SVG with the site's own raster icon where it
declares one, usually a sharper apple-touch-icon.
"""

from __future__ import annotations

import argparse
import collections
import json
import logging
import sys

import requests
from bs4 import BeautifulSoup

from .backfill_pricing import _headers
from .config import REQUEST_TIMEOUT, load_settings
from .enrich import extract_logo, favicon_at_root, is_aggregator
from .http_client import PoliteSession

log = logging.getLogger(__name__)


def fetch_logoless(
    settings, session: requests.Session, limit: int, svg: bool = False
) -> list[dict]:
    resp = session.get(
        f"{settings.rest_url}/tools",
        params={
            "select": "id,name,website_url,logo_url",
            "status": "eq.published",
            # No logo yet, or one store_logos marked as not found ("").
            **({"logo_url": "ilike.*.svg*"} if svg
               else {"or": "(logo_url.is.null,logo_url.eq.)"}),
            "order": "trend_score.desc",
            "limit": limit,
        },
        headers=_headers(settings.service_role_key),
        timeout=REQUEST_TIMEOUT,
    )
    resp.raise_for_status()
    return resp.json()


def logo_for(session: PoliteSession, url: str) -> str | None:
    """The icon the site declares, else an undeclared /favicon.ico, else None."""
    if not url or is_aggregator(url):
        return None
    response = session.get(url)
    if response is None:
        return None
    if "html" in response.headers.get("Content-Type", "").lower():
        declared = extract_logo(BeautifulSoup(response.content, "lxml"), url)
        if declared:
            return declared
    return favicon_at_root(session, url)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="Write the results.")
    parser.add_argument("--limit", type=int, default=200)
    parser.add_argument(
        "--svg", action="store_true", help="Replace stored SVG logos instead."
    )
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
    rows = fetch_logoless(settings, rest, args.limit, svg=args.svg)
    outcome: collections.Counter[str] = collections.Counter()

    for row in rows:
        logo = logo_for(polite, row.get("website_url") or "")
        outcome["found" if logo else "none"] += 1
        log.info("%-5s %s %s", "found" if logo else "none", row.get("name"), logo or "")
        if not logo or not args.apply:
            continue
        resp = rest.patch(
            f"{settings.rest_url}/tools",
            # Only if it is still what was read: never overwrite a logo that
            # something else set in the meantime.
            params={
                "id": f"eq.{row['id']}",
                "logo_url": "is.null" if row.get("logo_url") is None
                else f"eq.{row['logo_url']}",
            },
            headers={**_headers(settings.service_role_key), "Prefer": "return=minimal"},
            json={"logo_url": logo},
            timeout=REQUEST_TIMEOUT,
        )
        if resp.status_code >= 400:
            log.warning("could not update %s: %s", row["id"], resp.text[:200])

    report = {"tried": len(rows), **outcome, "applied": args.apply}
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
