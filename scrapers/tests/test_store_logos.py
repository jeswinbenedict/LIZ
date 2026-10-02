"""The logo job's rules for remembering a miss."""

from __future__ import annotations

from liz_scraper.store_logos import NO_LOGO, proxy_url, same_logo_filter, should_mark_none

FN = "https://x.supabase.co/functions/v1"


def test_writes_only_match_the_value_that_was_read():
    assert same_logo_filter(None) == "is.null"
    # An empty logo_url is a value, not a missing one: it needs eq.
    assert same_logo_filter(NO_LOGO) == "eq."
    assert same_logo_filter("https://a.test/l.png") == "eq.https://a.test/l.png"


def test_a_row_already_marked_is_not_written_again():
    assert should_mark_none({"logo_url": None})
    assert should_mark_none({"logo_url": "https://a.test/l.png"})
    assert not should_mark_none({"logo_url": NO_LOGO})


def test_a_marked_row_is_still_looked_up_by_domain():
    # "" is falsy, so a marked row asks the proxy by domain again; a logo
    # that appears later is still found.
    assert proxy_url(FN, {"logo_url": NO_LOGO, "website_url": "https://agentgit.co"}) == (
        f"{FN}/logo?domain=agentgit.co"
    )
    # A host whose favicon is not the tool's own gives no source at all.
    assert proxy_url(FN, {"logo_url": NO_LOGO, "website_url": "https://github.com/a/b"}) is None
