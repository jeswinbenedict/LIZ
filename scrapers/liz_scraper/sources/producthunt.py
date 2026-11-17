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

# Feed content ends with navigation links back to the thread ("Discussion",
# "Link"), which are not part of the product's tagline.
# One word at a time from the end, rather than one regular expression: a
# repeated group with optional whitespace on both sides backtracks
# polynomially on long runs of spaces, and this text comes from a third party.
_FEED_NAV_WORDS = ("discussion", "link")


def strip_feed_nav(text: str) -> str:
    """Drop trailing "Discussion | Link" navigation from a feed tagline."""
    while True:
        trimmed = text.rstrip().rstrip("|").rstrip()
        for word in _FEED_NAV_WORDS:
            if trimmed.lower().endswith(word) and (
                len(trimmed) == len(word) or not trimmed[-len(word) - 1].isalnum()
            ):
                trimmed = trimmed[: -len(word)]
                break
        else:
            return trimmed
        text = trimmed


@dataclass
class Candidate:
    name: str
    url: str
    tagline: str
    published_at: str | None
    source: str = "producthunt"
    # The source's own id and score, where it has them (Hacker News).
    external_id: str | None = None
    points: int | None = None


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
            tagline = strip_feed_nav(tagline).strip()

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
