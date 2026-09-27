"""Apply the quality gate to rows already in the catalog.

The gate runs at ingest, but 423 rows were written before it existed and would
otherwise sit pending forever. This re-judges them by exactly the same rule, so
there is no second definition of "good enough" to drift from the first.

    python -m liz_scraper.review                 # report, change nothing
    python -m liz_scraper.review --apply         # publish what passes
    python -m liz_scraper.review --published     # re-judge what is live

When the rule gets stricter, rows published under the old one do not fail it
by themselves. --published re-judges the live catalog by the current rule and,
with --apply, moves what now fails back to pending with the reason recorded —
held, not deleted, so a moderator can still restore one.

Held rows keep their status. They are not deleted: most are held because
enrichment could not reach the product page from a cloud IP, and a run from a
different host may resolve them later.
"""

from __future__ import annotations

import argparse
import json
import logging
import sys

import requests

from .config import REQUEST_TIMEOUT, load_settings
from .quality import assess, summarise

log = logging.getLogger(__name__)

PAGE = 500


def _headers(key: str) -> dict[str, str]:
    return {
        "apikey": key,
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
    }


def fetch_pending(
    settings, session: requests.Session, status: str = "pending"
) -> list[dict]:
    """Every row with `status`, paged — there are more than one request returns."""
    rows: list[dict] = []
    offset = 0
    while True:
        resp = session.get(
            f"{settings.rest_url}/tools",
            params={
                "select": "id,name,tagline,description,website_url,source",
                "status": f"eq.{status}",
                "order": "created_at.asc",
                "offset": offset,
                "limit": PAGE,
            },
            headers=_headers(settings.service_role_key),
            timeout=REQUEST_TIMEOUT,
        )
        resp.raise_for_status()
        page = resp.json()
        rows.extend(page)
        if len(page) < PAGE:
            return rows
        offset += PAGE


def publish(settings, session: requests.Session, ids: list[str]) -> int:
    """Publish rows by id, in chunks small enough for a URL."""
    done = 0
    for start in range(0, len(ids), 50):
        chunk = ids[start : start + 50]
        quoted = ",".join(f'"{i}"' for i in chunk)
        resp = session.patch(
            f"{settings.rest_url}/tools",
            params={"id": f"in.({quoted})"},
            headers={**_headers(settings.service_role_key), "Prefer": "return=minimal"},
            json={"status": "published"},
            timeout=REQUEST_TIMEOUT,
        )
        resp.raise_for_status()
        done += len(chunk)
        log.info("published %d/%d", done, len(ids))
    return done


def note_hold(settings, session: requests.Session, ids: list[str], reason: str) -> None:
    """Write the gate's reason onto rows it held back."""
    for start in range(0, len(ids), 50):
        chunk = ids[start : start + 50]
        quoted = ",".join(f'"{i}"' for i in chunk)
        resp = session.patch(
            f"{settings.rest_url}/tools",
            params={"id": f"in.({quoted})"},
            headers={**_headers(settings.service_role_key), "Prefer": "return=minimal"},
            json={"hold_reason": reason},
            timeout=REQUEST_TIMEOUT,
        )
        resp.raise_for_status()


def unpublish(settings, session: requests.Session, rows: list[dict]) -> None:
    """Move rows that now fail the gate back to pending, each with its reason."""
    held: dict[str, list[str]] = {}
    for row in rows:
        held.setdefault(assess(row).reasons[0], []).append(row["id"])
    for reason, ids in held.items():
        for start in range(0, len(ids), 50):
            quoted = ",".join(f'"{i}"' for i in ids[start : start + 50])
            resp = session.patch(
                f"{settings.rest_url}/tools",
                params={"id": f"in.({quoted})", "status": "eq.published"},
                headers={**_headers(settings.service_role_key),
                         "Prefer": "return=minimal"},
                json={"status": "pending", "hold_reason": reason},
                timeout=REQUEST_TIMEOUT,
            )
            resp.raise_for_status()


# The sources this gate governs. GitHub rows come from the fetch-tools Edge
# Function, where the repository *is* the product, and curated rows were chosen
# by hand; judging either by a rule written for launch links would pull a
# hundred genuine open-source tools for "linking to GitHub".
GATED_SOURCES = {"hackernews", "producthunt", "scraper"}


def judge_published(rows: list[dict]) -> list[dict]:
    """Published rows from gated sources that the current rule would hold."""
    return [
        r for r in rows
        if r.get("source") in GATED_SOURCES and not assess(r).publish
    ]


def review_published(settings, session: requests.Session, apply: bool) -> dict:
    rows = fetch_pending(settings, session, status="published")
    failing = judge_published(rows)
    if apply and failing:
        unpublish(settings, session, failing)
    return {
        "published": len(rows),
        "held_back" if apply else "would_hold_back": len(failing),
        "rows": [
            {"name": r["name"], "website_url": r["website_url"],
             "reason": assess(r).reasons[0]}
            for r in failing
        ],
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Actually publish. Without it, nothing is written.",
    )
    parser.add_argument(
        "--published",
        action="store_true",
        help="Re-judge the live catalog instead of the pending backlog.",
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

    session = requests.Session()
    if args.published:
        report = review_published(settings, session, args.apply)
        print(json.dumps(report, indent=2, ensure_ascii=False))
        return 0

    rows = fetch_pending(settings, session)
    passing = [r for r in rows if assess(r).publish]

    report = {
        "pending": len(rows),
        "would_publish" if not args.apply else "published": len(passing),
        "breakdown": summarise(rows),
    }

    if args.apply:
        if passing:
            publish(settings, session, [r["id"] for r in passing])
        # Record why the rest stay behind, so the admin queue can group them
        # and the health check can tell them from an unreviewed backlog.
        held: dict[str, list[str]] = {}
        for row in rows:
            verdict = assess(row)
            if verdict.publish:
                continue
            held.setdefault(verdict.reasons[0], []).append(row["id"])
        for reason, ids in held.items():
            note_hold(settings, session, ids, reason)

    print(json.dumps(report, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
