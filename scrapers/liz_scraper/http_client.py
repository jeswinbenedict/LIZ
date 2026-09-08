"""A deliberately polite HTTP client.

Every outbound request checks robots.txt for our own user-agent, honours the
crawl delay the host asks for, and backs off on failure. Sources that disallow
us are skipped rather than worked around.
"""

from __future__ import annotations

import logging
import time
from urllib.parse import urlsplit
from urllib.robotparser import RobotFileParser

import requests

from .config import DEFAULT_CRAWL_DELAY, REQUEST_TIMEOUT, USER_AGENT

log = logging.getLogger(__name__)


class PoliteSession:
    def __init__(self, user_agent: str = USER_AGENT) -> None:
        self.user_agent = user_agent
        self._session = requests.Session()
        self._session.headers.update({"User-Agent": user_agent})
        self._robots: dict[str, RobotFileParser | None] = {}
        self._delays: dict[str, float] = {}
        self._last_hit: dict[str, float] = {}

    def _host_key(self, url: str) -> str:
        parts = urlsplit(url)
        return f"{parts.scheme}://{parts.netloc}"

    def _robots_for(self, url: str) -> RobotFileParser | None:
        host = self._host_key(url)
        if host in self._robots:
            return self._robots[host]

        parser = RobotFileParser()
        parser.set_url(f"{host}/robots.txt")
        try:
            resp = self._session.get(f"{host}/robots.txt", timeout=REQUEST_TIMEOUT)
            if resp.status_code >= 400:
                # No usable robots.txt: treat as "allowed", still rate limited.
                parser = None
            else:
                parser.parse(resp.text.splitlines())
        except requests.RequestException:
            parser = None

        self._robots[host] = parser
        if parser is not None:
            delay = parser.crawl_delay(self.user_agent)
            if delay:
                self._delays[host] = float(delay)
        return parser

    def allowed(self, url: str) -> bool:
        parser = self._robots_for(url)
        if parser is None:
            return True
        return parser.can_fetch(self.user_agent, url)

    def _throttle(self, url: str) -> None:
        host = self._host_key(url)
        delay = self._delays.get(host, DEFAULT_CRAWL_DELAY)
        last = self._last_hit.get(host)
        if last is not None:
            elapsed = time.monotonic() - last
            if elapsed < delay:
                time.sleep(delay - elapsed)
        self._last_hit[host] = time.monotonic()

    def get(self, url: str, *, retries: int = 2) -> requests.Response | None:
        """Fetch a URL, or return None if disallowed or persistently failing."""
        if not self.allowed(url):
            log.info("robots.txt disallows %s — skipping", url)
            return None

        for attempt in range(retries + 1):
            self._throttle(url)
            try:
                resp = self._session.get(url, timeout=REQUEST_TIMEOUT)
            except requests.RequestException as err:
                log.warning("request failed (%s): %s", url, err)
            else:
                if resp.status_code < 400:
                    return resp
                # Rate limited or server-side hiccup: worth another try.
                if resp.status_code not in (429, 500, 502, 503, 504):
                    log.info("giving up on %s (HTTP %s)", url, resp.status_code)
                    return None
                log.warning("HTTP %s from %s", resp.status_code, url)

            if attempt < retries:
                time.sleep(2 ** attempt * 2)

        return None
