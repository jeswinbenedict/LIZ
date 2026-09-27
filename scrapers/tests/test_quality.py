"""The gate decides what a reader sees, so it is worth arguing with in tests.

The fixtures are real rows taken from the live pending backlog on 26 September
2026, not invented ones — the gate exists because of what is actually in there.
"""

from __future__ import annotations

from liz_scraper.quality import Verdict, assess, summarise


def _row(**overrides) -> dict:
    base = {
        "name": "Prove Together",
        "tagline": "Agents pool compute to prove theorems together",
        "description": "Install the Prove Together skill. Your agents pool "
        "compute and coordinate on open problems.",
        "website_url": "https://provetogether.ai",
    }
    base.update(overrides)
    return base


class TestPasses:
    def test_a_real_product_page_passes(self):
        assert assess(_row()).publish

    def test_a_missing_logo_is_not_disqualifying(self):
        # 59% of the backlog has no logo. A card without one still tells you
        # what the tool does, and the fallback tile is designed for this.
        assert assess(_row(logo_url=None)).publish

    def test_unknown_pricing_is_not_disqualifying(self):
        # 77% of the backlog is unknown. "We do not know yet" is honest and
        # the card renders it; holding a tool back over it helps nobody.
        assert assess(_row(pricing_type="unknown")).publish

    def test_no_tags_is_not_disqualifying(self):
        # Every row in the backlog has empty tags.
        assert assess(_row(tags=[])).publish


class TestAggregators:
    def test_a_product_hunt_listing_is_refused(self):
        # The whole Product Hunt backlog looks like this: Cloudflare returns
        # 403 to the runner, so the scraper never reached the product page and
        # website_url is still the listing.
        verdict = assess(
            _row(
                name="Plane Agents",
                tagline="Assign work to AI agents, like any teammate",
                website_url="https://www.producthunt.com/products/planehq",
            )
        )
        assert not verdict.publish
        assert "producthunt.com" in verdict.reasons[0]

    def test_every_known_aggregator_is_refused(self):
        for url in [
            "https://www.producthunt.com/products/x",
            "https://news.ycombinator.com/item?id=1",
            "https://github.com/owner/repo",
            "https://apps.apple.com/app/id1",
            "https://play.google.com/store/apps/details?id=x",
        ]:
            assert not assess(_row(website_url=url)).publish, url

    def test_a_subdomain_of_an_aggregator_is_refused(self):
        assert not assess(_row(website_url="https://blog.producthunt.com/x")).publish

    def test_a_write_up_is_refused(self):
        # Someone's post about a tool is not the tool.
        for url in [
            "https://medium.com/@someone/i-tried-this-ai-tool",
            "https://www.reddit.com/r/ai/comments/abc",
            "https://x.com/someone/status/1",
            "https://www.youtube.com/watch?v=abc",
        ]:
            assert not assess(_row(website_url=url)).publish, url

    def test_a_product_whose_name_merely_contains_a_host_is_fine(self):
        assert assess(_row(website_url="https://githubnext-clone.dev")).publish


class TestHeadlines:
    def test_a_blog_post_title_is_refused(self):
        # Straight from the backlog: Hacker News gives the submission title,
        # which for a lab announcement is a sentence.
        verdict = assess(
            _row(name="Fugu Max and Fugu Ultra v2: Orchestrating the Pareto Frontier")
        )
        assert not verdict.publish
        assert "headline" in verdict.reasons[0]

    def test_a_long_but_plausible_product_name_passes(self):
        assert assess(_row(name="Kanverse GPU Borrow")).publish

    def test_a_one_word_name_passes(self):
        assert assess(_row(name="Ember")).publish


class TestMissingFields:
    def test_no_description_is_refused(self):
        assert not assess(_row(description="")).publish

    def test_no_tagline_is_refused(self):
        assert not assess(_row(tagline="")).publish

    def test_a_tagline_that_says_nothing_is_refused(self):
        assert not assess(_row(tagline="AI tool")).publish

    def test_no_website_is_refused(self):
        assert not assess(_row(website_url="")).publish

    def test_a_malformed_url_is_refused(self):
        assert not assess(_row(website_url="not a url")).publish


class TestVerdict:
    def test_status_maps_to_the_column(self):
        assert Verdict(publish=True).status == "published"
        assert Verdict(publish=False, reasons=["x"]).status == "pending"

    def test_every_reason_is_reported_not_just_the_first(self):
        verdict = assess({"name": "", "tagline": "", "description": "", "website_url": ""})
        assert not verdict.publish
        assert len(verdict.reasons) == 4


class TestSummarise:
    def test_totals_add_up_to_the_row_count(self):
        rows = [
            _row(),
            _row(website_url="https://www.producthunt.com/products/a"),
            _row(website_url="https://www.producthunt.com/products/b"),
            _row(description=""),
        ]
        counts = summarise(rows)
        assert sum(counts.values()) == len(rows)
        assert counts["published"] == 1


class TestSharedContent:
    """Published rows from 27 September 2026 that were not products."""

    def test_a_shared_chat_or_artifact_is_held(self):
        for url in [
            "https://claude.ai/artifact/XmWGFtQPgn8aJvU193Ksf8",
            "https://claude.ai/share/61ae35d6-82f2-425a-84b6-907a3ec1b5c4",
            "https://gemini.google.com/app/b4b90aeb20c60c14",
            "https://chatgpt.com/share/abc",
        ]:
            verdict = assess(_row(website_url=url))
            assert not verdict.publish, url
            assert "shared chat or file" in verdict.reasons[0]

    def test_a_file_is_held(self):
        for url in [
            "https://raw.githubusercontent.com/kbr-/math-research/3979e0c/"
            "publications/whitepaper.pdf",
            "https://acme.ai/whitepaper.pdf",
            "https://gist.github.com/someone/abc123",
        ]:
            assert not assess(_row(website_url=url)).publish, url

    def test_the_assistants_themselves_still_pass(self):
        # The rule is about what is at the path, not the host: Claude, ChatGPT
        # and Gemini are products, a conversation inside one is not.
        for url in ["https://claude.ai", "https://chatgpt.com",
                    "https://gemini.google.com", "https://chatgpt.com/g/g-xyz"]:
            assert assess(_row(website_url=url)).publish, url
