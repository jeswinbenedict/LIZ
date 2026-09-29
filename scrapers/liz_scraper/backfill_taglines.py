"""Replace launch-post taglines on published tools with what the tool does.

Two kinds are fixed. Taglines that repeat the tool's name ("Koi.rest – watch
some fish") lose the repeat, since a card prints the name right above. And
launch-post copy written about the maker is replaced, as below.

Show HN titles went into the catalog as taglines, so seventeen tools were
introduced by their maker's story instead of the product: "I couldn't deal
with another Claude Code tab", "I pointed 11 cold AI agents at my own
product". The pipeline now prefers the site's own description for new rows
(normalize.choose_tagline); this fixes the ones already published.

    python -m liz_scraper.backfill_taglines            # report, change nothing
    python -m liz_scraper.backfill_taglines --apply    # write the new taglines

The replacement is the first line of the tool's summary, which the summariser
writes as a plain statement of what the product does, and failing that the
first sentence of its description. A tool with neither keeps its tagline.
"""

from __future__ import annotations

import argparse
import json
import re
import sys

import requests

from .config import REQUEST_TIMEOUT, load_settings
from .normalize import clean_text, is_first_person, strip_name_prefix

_SENTENCE_END = re.compile(r"(?<=[.!?])\s")


def replacement_for(tool: dict) -> str | None:
    """A product-first tagline, or None when there is nothing better."""
    summary = tool.get("ai_summary")
    candidates: list[str] = []
    if isinstance(summary, list) and summary:
        candidates.append(str(summary[0]))
    description = clean_text(tool.get("description") or "")
    if description:
        candidates.append(_SENTENCE_END.split(description, maxsplit=1)[0])

    for text in candidates:
        text = clean_text(text).rstrip(".")
        if text and not is_first_person(text):
            if len(text) > 140:
                text = text[:137].rsplit(" ", 1)[0] + "…"
            return text
    return None


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="liz_scraper.backfill_taglines")
    parser.add_argument("--apply", action="store_true", help="Write the new taglines.")
    args = parser.parse_args(argv)

    settings = load_settings()
    if not settings.configured:
        print("error: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set", file=sys.stderr)
        return 2
    headers = {
        "apikey": settings.service_role_key,
        "Authorization": f"Bearer {settings.service_role_key}",
        "Content-Type": "application/json",
    }

    resp = requests.get(
        f"{settings.rest_url}/tools",
        params={
            "select": "id,name,tagline,description,ai_summary",
            "status": "eq.published",
            "limit": 5000,
        },
        headers=headers,
        timeout=REQUEST_TIMEOUT,
    )
    resp.raise_for_status()

    changes = []
    for tool in resp.json():
        old = tool["tagline"] or ""
        if is_first_person(old):
            new = replacement_for(tool)
        else:
            new = strip_name_prefix(old, tool["name"])
            if new == old:
                continue
        changes.append({"id": tool["id"], "name": tool["name"],
                        "old": old, "new": new})

    for change in changes:
        print(json.dumps(change, ensure_ascii=False))

    if not args.apply:
        print(f"\n{len(changes)} found. Re-run with --apply to write.")
        return 0

    written = 0
    for change in changes:
        if not change["new"]:
            continue
        r = requests.patch(
            f"{settings.rest_url}/tools",
            params={"id": f"eq.{change['id']}"},
            headers=headers,
            json={"tagline": change["new"]},
            timeout=REQUEST_TIMEOUT,
        )
        if r.status_code < 400:
            written += 1
    print(f"\n{written} of {len(changes)} taglines rewritten.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
