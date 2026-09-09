"""Product Hunt discovery via their public RSS feed.

The feed is the sanctioned way in — no API token, no scraping of the site's
HTML, and it already carries the launch date we want.
"""

from __future__ import annotations

import logging
import re
from dataclasses import dataclass

from bs4 import BeautifulSoup

from ..http_client import PoliteSession
from ..normalize import clean_text

log = logging.getLogger(__name__)

FEED_URL = "https://www.producthunt.com/feed?category=artificial-intelligence"

# Feed content ends with navigation links back to the thread ("Discussion",
# "Link"), which are not part of the product's tagline.
_FEED_NAV_SUFFIX = re.compile(r"\s*(?:(?:Discussion|Link)\s*\|?\s*)+$", re.IGNORECASE)


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

    # The feed is Atom, not RSS: <entry> rather than <item>, <link href="..">
    # rather than link text, and <published> rather than <pubDate>.
    for entry in soup.find_all("entry")[:limit]:
        name = clean_text(entry.title.get_text() if entry.title else "")
        link_tag = entry.find("link")
        url = clean_text(link_tag.get("href", "")) if link_tag else ""
        if not name or not url:
            continue

        # <content> is HTML holding the tagline plus a "Discussion" link back
        # to the thread, which is navigation rather than description.
        content = entry.find("content")
        tagline = ""
        if content is not None:
            tagline = clean_text(
                BeautifulSoup(content.get_text(), "lxml").get_text(" ")
            )
            tagline = _FEED_NAV_SUFFIX.sub("", tagline).strip()

        published = entry.find("published") or entry.find("updated")
        candidates.append(
            Candidate(
                name=name,
                url=url,
                tagline=tagline,
                published_at=clean_text(published.get_text()) if published else None,
            )
        )

    log.info("Product Hunt: %d candidates", len(candidates))
    return candidates
