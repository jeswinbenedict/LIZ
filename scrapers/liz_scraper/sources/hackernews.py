"""Hacker News "Show HN" discovery via the free Algolia search API.

Show HN posts are where builders launch, so this catches tools days before they
reach the bigger directories — the "rising early" signal the app is built around.
"""

from __future__ import annotations

import logging
from urllib.parse import urlsplit

from ..http_client import PoliteSession
from ..normalize import clean_text
from .producthunt import Candidate

log = logging.getLogger(__name__)

API_URL = (
    "https://hn.algolia.com/api/v1/search_by_date"
    "?tags=show_hn&query=AI&hitsPerPage={limit}"
)

# Repos have their own pipeline (the fetch-tools Edge Function), and store
# listings only yield the platform's boilerplate copy rather than the product's
# own description — in both cases we want the tool's real homepage instead.
_SKIP_HOSTS = {
    "github.com",
    "gitlab.com",
    "news.ycombinator.com",
    "medium.com",
    "substack.com",
    "apps.apple.com",
    "itunes.apple.com",
    "play.google.com",
    "x.com",
    "twitter.com",
    "youtube.com",
    "reddit.com",
}


def discover(session: PoliteSession, *, limit: int = 30) -> list[Candidate]:
    response = session.get(API_URL.format(limit=limit))
    if response is None:
        log.warning("Hacker News API unavailable")
        return []

    try:
        hits = response.json().get("hits", [])
    except ValueError:
        log.warning("Hacker News returned non-JSON")
        return []

    candidates: list[Candidate] = []
    for hit in hits:
        url = clean_text(hit.get("url") or "")
        title = clean_text(hit.get("title") or "")
        if not url or not title:
            continue

        host = urlsplit(url).netloc.lower().removeprefix("www.")
        if host in _SKIP_HOSTS:
            continue

        # A Show HN title is one sentence that both names and describes the
        # product, so it serves as the tagline as-is. Extracting the name from
        # it (or from the product's own site) is the pipeline's job.
        stripped = title.removeprefix("Show HN:").strip()

        candidates.append(
            Candidate(
                name=stripped,
                url=url,
                tagline=clean_text(stripped),
                published_at=hit.get("created_at"),
                source="hackernews",
            )
        )

    log.info("Hacker News: %d candidates", len(candidates))
    return candidates
