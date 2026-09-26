"""Re-enriching a held row decides what a reader will see, so the decision is
tested without a network. The fixture is shaped like a real Product Hunt row
from the backlog: the website is still the listing, and the description is the
tagline repeated because the listing page was all enrichment could reach.
"""

from __future__ import annotations

from liz_scraper.enrich import PageFacts
from liz_scraper.retry_held import rebuild

HELD = {
    "id": "row-1",
    "name": "Plane Agents",
    "tagline": "Assign work to AI agents, like any teammate",
    "description": "Assign work to AI agents, like any teammate",
    "website_url": "https://www.producthunt.com/products/planehq",
    "source": "producthunt",
    "source_url": "https://www.producthunt.com/products/planehq",
    "logo_url": None,
    "category": "ai-agents",
    "platforms": ["web"],
    "pricing_type": "unknown",
    "hold_reason": "website is still the producthunt.com listing, not the product",
}

FACTS = PageFacts(
    title="Plane — Project management for teams and their agents",
    description="Plane is an open-source project tracker where AI agents can "
    "pick up issues, update status and hand work back to people.",
    logo_url="https://plane.so/logo.png",
    pricing_type="freemium",
    platforms=["web"],
    category="ai-agents",
)


def test_a_resolved_row_is_published_and_its_reason_cleared():
    update = rebuild(HELD, "https://plane.so", FACTS)
    assert update is not None
    assert update["status"] == "published"
    assert update["hold_reason"] is None
    assert update["website_url"] == "https://plane.so"


def test_the_product_page_replaces_the_repeated_tagline():
    update = rebuild(HELD, "https://plane.so", FACTS)
    assert update["description"].startswith("Plane is an open-source")
    # The tagline the maker wrote is still the better one-line summary.
    assert update["tagline"] == HELD["tagline"]


def test_facts_fill_what_the_listing_could_not():
    update = rebuild(HELD, "https://plane.so", FACTS)
    assert update["logo_url"] == "https://plane.so/logo.png"
    assert update["pricing_type"] == "freemium"


def test_known_pricing_is_not_overwritten_with_unknown():
    known = {**HELD, "pricing_type": "paid"}
    blank = PageFacts(title="", description=FACTS.description, pricing_type="unknown")
    update = rebuild(known, "https://plane.so", blank)
    assert update["pricing_type"] == "paid"


def test_still_blocked_changes_nothing():
    # From a runner that is still getting 403, enrichment falls back to the
    # listing. Writing that back would only restate the problem.
    assert rebuild(HELD, HELD["website_url"], None) is None
    assert rebuild(HELD, HELD["website_url"], FACTS) is None


def test_a_row_that_resolves_but_is_still_thin_stays_held_with_the_new_reason():
    thin = PageFacts(title="", description="", logo_url=None)
    no_prose = {**HELD, "description": ""}
    update = rebuild(no_prose, "https://plane.so", thin)
    assert update["status"] == "pending"
    # The reason moves on from "still the listing" to what is actually wrong
    # now, so the admin queue shows the current problem.
    assert "listing" not in update["hold_reason"]


def test_the_content_hash_is_left_alone():
    # Keyed on the listing URL; changing it would make the next feed run see
    # this product as new and write a duplicate.
    update = rebuild(HELD, "https://plane.so", FACTS)
    assert "content_hash" not in update
    assert "slug" not in update
