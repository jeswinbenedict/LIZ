"""strip_feed_nav: the Product Hunt feed's trailing "Discussion | Link".

Replaced a regular expression that backtracked polynomially on long runs of
whitespace (CodeQL py/redos, SECURITY_AUDIT.md).
"""
import time

from liz_scraper.sources.producthunt import strip_feed_nav


def test_strips_the_navigation_suffix():
    assert strip_feed_nav("Voice notes to text Discussion | Link") == "Voice notes to text"
    assert strip_feed_nav("Voice notes to text  Discussion |  Link  ") == "Voice notes to text"
    assert strip_feed_nav("Voice notes to text discussion|link|") == "Voice notes to text"


def test_keeps_words_that_only_end_with_the_suffix():
    assert strip_feed_nav("Share a backlink") == "Share a backlink"
    assert strip_feed_nav("Hyperlink") == "Hyperlink"


def test_leaves_ordinary_taglines_alone():
    assert strip_feed_nav("Assign work to AI agents") == "Assign work to AI agents"
    assert strip_feed_nav("") == ""
    assert strip_feed_nav("Link") == ""


def test_is_fast_on_hostile_whitespace():
    hostile = "x" + " " * 50_000 + "Discussion" + " |" * 5_000 + "!"
    started = time.perf_counter()
    strip_feed_nav(hostile)
    assert time.perf_counter() - started < 1.0
