"""Read the outside signals Liz ranks by: GitHub stars and Hacker News points.

    python -m liz_scraper.signals              # read and write
    python -m liz_scraper.signals --dry-run    # read and print, write nothing

Momentum is growth between daily snapshots (migration 0037), so these figures
have to be read every day for "Rising" to mean anything. The run finishes by
calling apply_signals(), which writes the batch, takes today's snapshot and
re-ranks the catalog in one call.

Both sources are free public APIs:

- GitHub: the search API accepts many ``repo:`` qualifiers in one query, so a
  hundred repositories cost a dozen requests rather than a hundred — which fits
  the unauthenticated budget. Set GITHUB_TOKEN (GitHub Actions provides one) for
  a higher ceiling.
- Hacker News: Algolia's HN API. Tools found on Show HN before their story id
  was recorded are matched once, by URL, and remembered.
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import time
from datetime import datetime, timedelta, timezone
from urllib.parse import urlsplit

import requests

from .config import REQUEST_TIMEOUT, USER_AGENT, load_settings

log = logging.getLogger(__name__)

GITHUB_SEARCH = "https://api.github.com/search/repositories"
HN_SEARCH = "https://hn.algolia.com/api/v1/search"

# GitHub rejects search queries over 256 characters.
_MAX_QUERY = 250
# Points on a Show HN post stop moving within days; after a month there is
# nothing left to read.
HN_REFRESH_DAYS = 30
# Lookups by URL are one request each, so cap them per run.
HN_LOOKUPS_PER_RUN = 150


def normalize_url(url: str | None) -> str:
    """Host and path without scheme, www, trailing slash or query."""
    if not url:
        return ""
    parts = urlsplit(url.strip())
    host = parts.netloc.lower().removeprefix("www.")
    return f"{host}{parts.path.rstrip('/')}".lower()


def repo_batches(repos: list[str], limit: int = _MAX_QUERY) -> list[list[str]]:
    """Group repositories into search queries that stay under GitHub's cap."""
    batches: list[list[str]] = []
    current: list[str] = []
    length = 0
    for repo in repos:
        term = len(f"repo:{repo}") + 1
        if current and length + term > limit:
            batches.append(current)
            current, length = [], 0
        current.append(repo)
        length += term
    if current:
        batches.append(current)
    return batches


def match_hn_hit(hits: list[dict], *urls: str | None) -> dict | None:
    """The Show HN story whose link is one of the tool's own URLs."""
    wanted = {normalize_url(u) for u in urls if u}
    wanted.discard("")
    for hit in hits:
        if normalize_url(hit.get("url")) in wanted:
            return hit
    return None


class SignalReader:
    def __init__(self, session: requests.Session | None = None) -> None:
        self.session = session or requests.Session()
        self.session.headers.setdefault("User-Agent", USER_AGENT)
        token = os.environ.get("GITHUB_TOKEN", "").strip()
        self._gh_headers = {"Accept": "application/vnd.github+json"}
        if token:
            self._gh_headers["Authorization"] = f"Bearer {token}"
        # Unauthenticated search allows 10 requests a minute; with a token, 30.
        self._gh_pause = 2.5 if token else 6.5

    def github_stars(self, repos: list[str]) -> dict[str, int]:
        """Stars by lower-cased ``owner/name``."""
        stars: dict[str, int] = {}
        for i, batch in enumerate(repo_batches(repos)):
            if i:
                time.sleep(self._gh_pause)
            query = " ".join(f"repo:{r}" for r in batch)
            try:
                resp = self.session.get(
                    GITHUB_SEARCH,
                    params={"q": query, "per_page": 100},
                    headers=self._gh_headers,
                    timeout=REQUEST_TIMEOUT,
                )
            except requests.RequestException as err:
                log.warning("GitHub search failed: %s", err)
                continue
            if resp.status_code == 403:
                log.warning("GitHub rate limit reached after %d batches", i)
                break
            if resp.status_code >= 400:
                log.warning("GitHub search HTTP %s for %d repos", resp.status_code, len(batch))
                continue
            for item in resp.json().get("items", []):
                stars[item["full_name"].lower()] = int(item.get("stargazers_count") or 0)
        return stars

    def hn_points(self, story_ids: list[str]) -> dict[str, tuple]:
        """(points, comments, posted_at) by story id."""
        found: dict[str, tuple] = {}
        for start in range(0, len(story_ids), 50):
            chunk = story_ids[start : start + 50]
            tags = "(" + ",".join(f"story_{sid}" for sid in chunk) + ")"
            try:
                resp = self.session.get(
                    HN_SEARCH,
                    params={"tags": tags, "hitsPerPage": len(chunk)},
                    timeout=REQUEST_TIMEOUT,
                )
                resp.raise_for_status()
            except requests.RequestException as err:
                log.warning("HN lookup failed: %s", err)
                continue
            for hit in resp.json().get("hits", []):
                found[str(hit["objectID"])] = (
                    int(hit.get("points") or 0),
                    int(hit.get("num_comments") or 0),
                    hit.get("created_at"),
                )
        return found

    def find_hn_story(self, website_url: str | None, source_url: str | None) -> dict | None:
        """Match a tool to its Show HN story by the URL it was posted with."""
        host = urlsplit(website_url or source_url or "").netloc.removeprefix("www.")
        if not host:
            return None
        try:
            resp = self.session.get(
                HN_SEARCH,
                params={
                    "query": host,
                    "restrictSearchableAttributes": "url",
                    "tags": "show_hn",
                    "hitsPerPage": 10,
                },
                timeout=REQUEST_TIMEOUT,
            )
            resp.raise_for_status()
        except requests.RequestException as err:
            log.warning("HN search failed for %s: %s", host, err)
            return None
        return match_hn_hit(resp.json().get("hits", []), website_url, source_url)


def plan_updates(
    tools: list[dict],
    reader: SignalReader,
    *,
    now: datetime | None = None,
) -> list[dict]:
    """Read every signal the catalog has a handle for; one dict per tool."""
    now = now or datetime.now(timezone.utc)
    updates: dict[str, dict] = {}

    # GitHub ---------------------------------------------------------------
    repos = {t["gh_repo"].lower(): t["id"] for t in tools if t.get("gh_repo")}
    if repos:
        stars = reader.github_stars(sorted(repos))
        for repo, count in stars.items():
            tool_id = repos.get(repo)
            if tool_id:
                updates.setdefault(tool_id, {"id": tool_id})["gh_stars"] = count
        log.info("GitHub: stars for %d of %d repos", len(stars), len(repos))

    # Hacker News: remember story ids we have not matched yet --------------
    lookups = 0
    hn_ids: dict[str, str] = {}
    # Newest first: a story's points only move in its first days, and stories
    # that never match are retried on every run — in any fixed order they would
    # take the whole lookup budget and starve everything behind them.
    for tool in sorted(tools, key=lambda t: t.get("created_at") or "", reverse=True):
        if tool.get("hn_id"):
            hn_ids[tool["id"]] = str(tool["hn_id"])
            continue
        if tool.get("source") != "hackernews" or lookups >= HN_LOOKUPS_PER_RUN:
            continue
        lookups += 1
        hit = reader.find_hn_story(tool.get("website_url"), tool.get("source_url"))
        if hit:
            hn_ids[tool["id"]] = str(hit["objectID"])
            updates.setdefault(tool["id"], {"id": tool["id"]})["hn_id"] = str(hit["objectID"])
    log.info("HN: matched %d stories by URL", sum(1 for u in updates.values() if "hn_id" in u))

    # Hacker News: points for anything recent, or never read ---------------
    cutoff = now - timedelta(days=HN_REFRESH_DAYS)
    by_id = {t["id"]: t for t in tools}
    to_read = [
        tool_id for tool_id in hn_ids
        if by_id[tool_id].get("hn_points") is None
        or _parse_time(by_id[tool_id].get("created_at")) >= cutoff
    ]
    points = reader.hn_points([hn_ids[t] for t in to_read])
    for tool_id in to_read:
        got = points.get(hn_ids[tool_id])
        if got is None:
            continue
        row = updates.setdefault(tool_id, {"id": tool_id})
        row["hn_id"] = hn_ids[tool_id]
        row["hn_points"], row["hn_comments"] = got[0], got[1]
        # When the story went up, for the tool's timeline (migration 0044).
        if len(got) > 2 and got[2]:
            row["hn_posted_at"] = got[2]
    log.info("HN: points for %d stories", len(points))

    return list(updates.values())


def _parse_time(value: str | None) -> datetime:
    if not value:
        return datetime.min.replace(tzinfo=timezone.utc)
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def _load_tools(rest_url: str, headers: dict) -> list[dict]:
    tools: list[dict] = []
    offset = 0
    while True:
        resp = requests.get(
            f"{rest_url}/tools",
            params={
                "select": "id,name,source,website_url,source_url,gh_repo,hn_id,hn_points,created_at",
                "status": "eq.published",
                "order": "id",
                "limit": 1000,
                "offset": offset,
            },
            headers=headers,
            timeout=REQUEST_TIMEOUT,
        )
        resp.raise_for_status()
        page = resp.json()
        tools.extend(page)
        if len(page) < 1000:
            return tools
        offset += 1000


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="liz_scraper.signals")
    parser.add_argument("--dry-run", action="store_true", help="Read, print, write nothing.")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args(argv)
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(levelname)s %(name)s: %(message)s",
    )

    settings = load_settings()
    if not settings.configured:
        print("error: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set")
        return 2
    headers = {
        "apikey": settings.service_role_key,
        "Authorization": f"Bearer {settings.service_role_key}",
        "Content-Type": "application/json",
    }

    tools = _load_tools(settings.rest_url, headers)
    updates = plan_updates(tools, SignalReader())
    summary = {
        "tools": len(tools),
        "updates": len(updates),
        "github": sum(1 for u in updates if "gh_stars" in u),
        "hacker_news": sum(1 for u in updates if "hn_points" in u),
    }

    if args.dry_run:
        print(json.dumps(summary, indent=2))
        print(json.dumps(updates[:10], indent=2))
        return 0

    # Always call it, even with nothing new: it also takes today's snapshot and
    # re-ranks, which must happen daily either way.
    resp = requests.post(
        f"{settings.rest_url}/rpc/apply_signals",
        headers=headers,
        json={"rows": updates},
        timeout=120,
    )
    if resp.status_code >= 400:
        print(f"error: apply_signals HTTP {resp.status_code}: {resp.text[:300]}")
        return 1
    summary["written"] = resp.json()
    print(json.dumps(summary, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
