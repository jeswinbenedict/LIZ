"""The pipeline decides what a scheduled run publishes.

The daily GitHub Actions scrape passed --status pending long after Phase 7 made
that flag an override, which bypassed the quality gate on every run and wrote
gate-passing rows with a hold reason of just "held" — so the health signal for
an unexplained backlog could not see them either. These pin both halves.
"""

from __future__ import annotations

import pytest

from liz_scraper import pipeline
from liz_scraper.enrich import PageFacts


class _Candidate:
    def __init__(self, name, url, tagline):
        self.name = name
        self.url = url
        self.tagline = tagline
        self.source = "hackernews"


GOOD = _Candidate("Prove Together", "https://provetogether.ai",
                  "Agents pool compute to prove theorems together")
FACTS = PageFacts(
    title="Prove Together",
    description="Install the skill and your agents pool compute to work on "
    "open problems together.",
    logo_url="https://provetogether.ai/logo.png",
)


@pytest.fixture(autouse=True)
def offline(monkeypatch):
    monkeypatch.setattr(pipeline, "ALL_SOURCES", {"fake": lambda s, limit: [GOOD]})
    monkeypatch.setattr(pipeline, "resolve_and_enrich", lambda s, url: (url, FACTS))


def test_left_alone_the_gate_decides_and_a_good_row_is_published():
    result = pipeline.run(sources=["fake"], dry_run=True)
    row = result.rows[0]
    assert row["status"] == "published"
    assert row["hold_reason"] is None
    assert result.published == 1


def test_forcing_pending_says_so_instead_of_claiming_a_hold():
    result = pipeline.run(sources=["fake"], dry_run=True, status="pending")
    row = result.rows[0]
    assert row["status"] == "pending"
    # Recorded as a bare "held", this looked like a real hold and was invisible
    # to the unexplained-backlog signal.
    assert row["hold_reason"] != "held"
    assert "override" in row["hold_reason"]


def test_a_row_the_gate_refuses_is_held_with_the_gate_reason(monkeypatch):
    listing = _Candidate("Plane Agents", "https://www.producthunt.com/products/planehq",
                         "Assign work to AI agents, like any teammate")
    monkeypatch.setattr(pipeline, "ALL_SOURCES", {"fake": lambda s, limit: [listing]})
    monkeypatch.setattr(pipeline, "resolve_and_enrich", lambda s, url: (url, None))

    row = pipeline.run(sources=["fake"], dry_run=True).rows[0]
    assert row["status"] == "pending"
    assert "listing" in row["hold_reason"]
