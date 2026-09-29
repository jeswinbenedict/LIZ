"""Outside signals: what gets read, how it is matched, and what is written.

Momentum is growth between daily snapshots, so a signal read against the
wrong tool, or silently dropped, shows up on Discover as a tool "rising" that
is not. These run offline against a fake reader.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

from liz_scraper.normalize import choose_tagline, is_first_person, strip_name_prefix
from liz_scraper.signals import (
    match_hn_hit,
    normalize_url,
    plan_updates,
    repo_batches,
)

NOW = datetime(2026, 9, 29, tzinfo=timezone.utc)


class FakeReader:
    def __init__(self, stars=None, stories=None, points=None):
        self.stars = stars or {}
        self.stories = stories or {}
        self.points = points or {}
        self.lookups: list[str] = []
        self.points_asked: list[str] = []

    def github_stars(self, repos):
        return {r: self.stars[r] for r in repos if r in self.stars}

    def find_hn_story(self, website_url, source_url):
        self.lookups.append(website_url)
        return self.stories.get(website_url)

    def hn_points(self, ids):
        self.points_asked.extend(ids)
        return {i: self.points[i] for i in ids if i in self.points}


def test_normalize_url_ignores_scheme_www_and_trailing_slash():
    assert normalize_url("https://www.Example.com/app/") == "example.com/app"
    assert normalize_url("http://example.com/app?ref=hn") == "example.com/app"
    assert normalize_url(None) == ""


def test_repo_batches_stay_under_githubs_query_limit():
    repos = [f"owner{i}/some-fairly-long-repository-name-{i}" for i in range(40)]
    batches = repo_batches(repos)
    assert sum(len(b) for b in batches) == 40
    for batch in batches:
        assert len(" ".join(f"repo:{r}" for r in batch)) <= 250


def test_hn_hit_must_link_to_the_tool_itself():
    hits = [
        {"objectID": "1", "url": "https://other.dev"},
        {"objectID": "2", "url": "https://www.tool.app/"},
    ]
    assert match_hn_hit(hits, "https://tool.app")["objectID"] == "2"
    assert match_hn_hit(hits, "https://unrelated.io") is None


def test_stars_are_matched_case_insensitively_by_repo():
    tools = [{"id": "t1", "gh_repo": "Owner/Repo", "source": "github"}]
    updates = plan_updates(tools, FakeReader(stars={"owner/repo": 1234}), now=NOW)
    assert updates == [{"id": "t1", "gh_stars": 1234}]


def test_hn_story_is_found_once_then_remembered():
    tools = [{
        "id": "t1", "source": "hackernews", "website_url": "https://tool.app",
        "source_url": "https://tool.app", "created_at": NOW.isoformat(),
        "hn_id": None, "hn_points": None,
    }]
    reader = FakeReader(stories={"https://tool.app": {"objectID": "999"}},
                        points={"999": (212, 40)})
    [row] = plan_updates(tools, reader, now=NOW)
    assert row == {"id": "t1", "hn_id": "999", "hn_points": 212, "hn_comments": 40}


def test_old_stories_with_points_are_not_reread():
    old = (NOW - timedelta(days=90)).isoformat()
    tools = [{
        "id": "t1", "source": "hackernews", "created_at": old,
        "hn_id": "5", "hn_points": 80,
    }]
    reader = FakeReader(points={"5": (81, 3)})
    assert plan_updates(tools, reader, now=NOW) == []
    assert reader.points_asked == []


def test_tools_from_other_sources_are_not_searched_on_hn():
    tools = [{"id": "t1", "source": "producthunt", "website_url": "https://x.app",
              "created_at": NOW.isoformat()}]
    reader = FakeReader()
    plan_updates(tools, reader, now=NOW)
    assert reader.lookups == []


def test_first_person_launch_copy_is_recognised():
    assert is_first_person("I built a tool to combine photos")
    assert is_first_person("We made an agent network")
    assert is_first_person("I couldn't deal with another Claude Code tab")
    assert is_first_person("My clipboard, without AI watermarks")
    assert not is_first_person("Instant diagrams from a sentence")
    assert not is_first_person("Webflow for agents")
    assert not is_first_person("")


def test_site_description_replaces_launch_copy_only():
    site = "Combine separate photos into one scene."
    assert choose_tagline("I built a tool to combine photos", site) == site
    assert choose_tagline("Combine photos into one scene", site) == (
        "Combine photos into one scene"
    )
    # No better text to hand: keep what there is rather than nothing.
    assert choose_tagline("I built a thing", "") == "I built a thing"
    assert choose_tagline("I built a thing", "I am the maker") == "I built a thing"


def test_a_tagline_does_not_repeat_the_name_printed_above_it():
    assert strip_name_prefix("Koi.rest \u2013 watch some fish and regain your balance",
                             "Koi.rest") == "Watch some fish and regain your balance"
    assert strip_name_prefix("TradingAgents: Multi-Agents LLM Financial Trading",
                             "TradingAgents") == "Multi-Agents LLM Financial Trading"
    # Not a prefix, or nothing worth keeping after it: leave it alone.
    assert strip_name_prefix("Watch fish with Koi.rest", "Koi.rest") == "Watch fish with Koi.rest"
    assert strip_name_prefix("Koi.rest \u2013 fish", "Koi.rest") == "Koi.rest \u2013 fish"
    assert strip_name_prefix("Kobrand makes logos", "Kobra") == "Kobrand makes logos"
