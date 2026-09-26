"""Command line entry point.

    python -m liz_scraper --dry-run              # print rows, write nothing
    python -m liz_scraper --source hackernews    # one source only
    python -m liz_scraper --status published     # skip admin review
"""

from __future__ import annotations

import argparse
import json
import logging
import sys

from .pipeline import run
from .sources import ALL_SOURCES


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="liz_scraper")
    parser.add_argument(
        "--source",
        action="append",
        choices=sorted(ALL_SOURCES),
        help="Limit to one source (repeatable). Defaults to all.",
    )
    parser.add_argument("--limit", type=int, default=30, help="Candidates per source.")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Run discovery and enrichment but write nothing to Supabase.",
    )
    parser.add_argument(
        "--status",
        choices=["pending", "published"],
        default=None,
        help="Force every row to this status. Omit to let the quality gate "
             "decide per row, which is what a scheduled run wants.",
    )
    parser.add_argument(
        "--out",
        metavar="PATH",
        help="Write every normalized row to PATH as JSON. Useful with "
             "--dry-run to inspect or post-process a full run.",
    )
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args(argv)

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(levelname)s %(name)s: %(message)s",
    )

    try:
        result = run(
            sources=args.source,
            limit=args.limit,
            dry_run=args.dry_run,
            status=args.status,
        )
    except ValueError as err:
        print(f"error: {err}", file=sys.stderr)
        return 2

    if args.out and result.rows is not None:
        with open(args.out, "w", encoding="utf-8") as fh:
            json.dump(result.rows, fh, indent=2, ensure_ascii=False)

    summary = {
        "discovered": result.discovered,
        "skipped_existing": result.skipped_existing,
        "enriched": result.enriched,
        "written": result.written,
        "published": result.published,
        # Why the rest were held, so a run that publishes nothing says why in
        # the log instead of looking like it did nothing.
        "held": result.held,
    }
    print(json.dumps(summary, indent=2))

    if args.dry_run and result.rows:
        print(json.dumps(result.rows[:5], indent=2, default=str))

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
