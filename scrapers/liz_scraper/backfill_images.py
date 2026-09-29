"""Fill in the preview image of published tools that have none.

    python -m liz_scraper.backfill_images              # report, change nothing
    python -m liz_scraper.backfill_images --apply      # write what was found

Reads each tool's own home page, politely (robots.txt, crawl delay), for the
image it declares for link sharing — og:image or twitter:image — and stores it
in tools.image_url (migration 0045). New tools get theirs at ingest; this is
for the ones already published. A site that declares none keeps none: Liz does
not take screenshots of other people's sites.
"""

from __future__ import annotations

import argparse
import collections
import json
import logging
import sys

import requests
from bs4 import BeautifulSoup

from .config import REQUEST_TIMEOUT, load_settings
from .enrich import extract_preview_image, is_aggregator
from .http_client import PoliteSession

log = logging.getLogger(__name__)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="liz_scraper.backfill_images")
    parser.add_argument("--apply", action="store_true", help="Write the results.")
    parser.add_argument("--limit", type=int, default=2000)
    args = parser.parse_args(argv)
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s: %(message)s")

    settings = load_settings()
    if not settings.configured:
        print("error: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set", file=sys.stderr)
        return 2
    headers = {
        "apikey": settings.service_role_key,
        "Authorization": f"Bearer {settings.service_role_key}",
        "Content-Type": "application/json",
        "Prefer": "return=minimal",
    }
    rows = requests.get(
        f"{settings.rest_url}/tools",
        params={"select": "id,name,website_url", "status": "eq.published",
                "image_url": "is.null", "order": "momentum.desc", "limit": args.limit},
        headers=headers, timeout=REQUEST_TIMEOUT,
    ).json()

    polite = PoliteSession()
    outcome: collections.Counter[str] = collections.Counter()
    for row in rows:
        url = row.get("website_url") or ""
        if not url or is_aggregator(url):
            outcome["no site"] += 1
            continue
        resp = polite.get(url)
        if resp is None:
            outcome["unreachable"] += 1
            continue
        image = extract_preview_image(BeautifulSoup(resp.content, "lxml"), resp.url)
        if not image:
            outcome["none declared"] += 1
            continue
        outcome["found"] += 1
        log.info("%s -> %s", row["name"], image)
        if args.apply:
            requests.patch(
                f"{settings.rest_url}/tools",
                params={"id": f"eq.{row['id']}", "image_url": "is.null"},
                headers=headers, json={"image_url": image}, timeout=REQUEST_TIMEOUT,
            )

    print(json.dumps({"tried": len(rows), **outcome, "applied": args.apply}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
