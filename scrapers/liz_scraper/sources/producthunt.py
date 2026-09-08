"""Product Hunt discovery via their public RSS feed.

The feed is the sanctioned way in — no API token, no scraping of the site's
HTML, and it already carries the launch date we want.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass

from bs4 import BeautifulSoup

from ..http_client import PoliteSession
from ..normalize import clean_text

log = logging.getLogger(__name__)

FEED_URL = "https://www.producthunt.com/feed?category=artificial-intelligence"


@dataclass
class Candidate:
    name: str
    url: str
    tagline: str
    published_at: str | None
    source: str = "producthunt"


def discover(session: PoliteSession, *, limit: int = 30) -> list[Candidate]:
    response = session.get(FEED_URL)
    if response is None:
        log.warning("Product Hunt feed unavailable")
        return []

    soup = BeautifulSoup(response.text, "xml")
    candidates: list[Candidate] = []

    for item in soup.find_all("item")[:limit]:
        title = clean_text(item.title.get_text() if item.title else "")
        link = clean_text(item.link.get_text() if item.link else "")
        if not title or not link:
            continue

        # PH titles read "Name — tagline"; split so each field lands correctly.
        name, _, tagline = title.partition(" — ")
        if not tagline:
            name, _, tagline = title.partition(" - ")

        published = item.find("pubDate")
        candidates.append(
            Candidate(
                name=clean_text(name) or title,
                url=link,
                tagline=clean_text(tagline),
                published_at=clean_text(published.get_text()) if published else None,
            )
        )

    log.info("Product Hunt: %d candidates", len(candidates))
    return candidates
