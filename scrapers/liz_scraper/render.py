"""Read pages that only exist after JavaScript runs.

Most of the tools Liz could not price were single-page apps: their HTML is an
empty shell ("<div id=root>") with fewer than a hundred characters of text, so
BeautifulSoup, which reads HTML as served, sees nothing to price. This renders
the page in headless Chromium (Playwright, open source) and hands back the HTML
as a visitor's browser would have it.

It is slow — a second or more per page and a browser process — so it is only
the fallback, used by `backfill_pricing --render` from the machine at home,
never on every scrape. Playwright is optional: install it with
`pip install playwright && python -m playwright install chromium`.

Everything PoliteSession promises still holds: robots.txt is asked first, and
the same user agent identifies Liz.
"""

from __future__ import annotations

import logging
from collections.abc import Iterator
from contextlib import contextmanager

from .config import USER_AGENT
from .http_client import PoliteSession

log = logging.getLogger(__name__)

# How long to let a page settle. Long enough for an app shell to fetch and draw
# its content; short enough that a page that never goes idle is abandoned.
NAVIGATION_TIMEOUT_MS = 20000
SETTLE_MS = 1500


class Renderer:
    def __init__(self, browser, polite: PoliteSession) -> None:
        self._browser = browser
        self._polite = polite

    def html(self, url: str) -> str | None:
        """The rendered page, or None when robots.txt says no or it fails."""
        if not self._polite.allowed(url):
            log.info("robots.txt disallows %s — not rendering", url)
            return None
        page = self._browser.new_page(user_agent=USER_AGENT)
        try:
            page.goto(url, timeout=NAVIGATION_TIMEOUT_MS, wait_until="domcontentloaded")
            try:
                page.wait_for_load_state("networkidle", timeout=NAVIGATION_TIMEOUT_MS)
            except Exception:  # noqa: BLE001 - a page that never idles still rendered
                pass
            page.wait_for_timeout(SETTLE_MS)
            return page.content()
        except Exception as err:  # noqa: BLE001 - any failure means "no reading"
            log.info("could not render %s: %s", url, err)
            return None
        finally:
            page.close()


@contextmanager
def renderer(polite: PoliteSession) -> Iterator[Renderer]:
    """A headless browser for the length of a `with` block."""
    from playwright.sync_api import sync_playwright  # optional dependency

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        try:
            yield Renderer(browser, polite)
        finally:
            browser.close()
