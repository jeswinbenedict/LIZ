"""Re-judging the live catalog must only touch what the gate governs."""

from liz_scraper.review import judge_published


def _row(source, url):
    return {
        "id": url, "name": "Tool", "source": source, "website_url": url,
        "tagline": "Does something useful for people", "description": "It does.",
    }


def test_a_github_sourced_repo_is_left_alone():
    # The repository is the product for an open-source tool. The first dry run
    # of --published would have pulled twenty of them.
    assert judge_published([_row("github", "https://github.com/nari-labs/dia")]) == []
    assert judge_published([_row("curated", "https://github.com")]) == []


def test_a_launch_that_links_a_shared_chat_is_held():
    rows = [_row("hackernews", "https://claude.ai/share/61ae35d6"),
            _row("hackernews", "https://acme.ai")]
    assert [r["website_url"] for r in judge_published(rows)] == [
        "https://claude.ai/share/61ae35d6"
    ]
