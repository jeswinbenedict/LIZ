from liz_scraper.normalize import (
    CATEGORIES,
    build_tool_row,
    canonical_url,
    choose_name,
    clean_title,
    content_hash,
    infer_category,
    infer_pricing,
    looks_like_a_name,
    slugify,
)


# Real titles that produced bad catalog names before this logic existed.
def test_clean_title_strips_show_hn_and_takes_the_name():
    assert clean_title("Show HN: MacTap, use knocks on your MacBook as shortcuts") == "MacTap"
    assert clean_title("Rokz: a browser port of a 1990 ASCII dungeon crawler") == "Rokz"
    assert clean_title("Sparrow-2 – noise cancellation for conversational AI") == "Sparrow-2"


def test_clean_title_leaves_a_bare_name_alone():
    assert clean_title("Posterlet") == "Posterlet"


def test_looks_like_a_name_rejects_descriptions():
    assert looks_like_a_name("MacTap")
    assert looks_like_a_name("Thread to Self")
    assert not looks_like_a_name("Free scanning app with ML crops")
    assert not looks_like_a_name("A tool that writes your emails")


def test_choose_name_prefers_the_site_when_the_title_only_describes():
    name = choose_name("Free scanning app with ML crops, front/back", "TimelineScan")
    assert name == "TimelineScan"


def test_choose_name_keeps_the_title_when_it_names_the_product():
    # The site title is noisier here, so the launch title wins.
    assert choose_name("MacTap, use knocks on your MacBook", "MacTap - the best app ever") == "MacTap"


def test_choose_name_falls_back_when_the_site_is_no_better():
    assert choose_name("Free scanning app with ML crops", "") == "Free scanning app with ML crops"


def test_slugify_strips_punctuation_and_case():
    assert slugify("Notion AI!") == "notion-ai"
    assert slugify("  Runway ML  ") == "runway-ml"


def test_canonical_url_ignores_tracking_and_www():
    a = canonical_url("https://www.example.com/tool/?utm_source=ph")
    b = canonical_url("https://example.com/tool")
    assert a == b


def test_content_hash_is_stable_across_url_noise():
    a = content_hash("https://www.runwayml.com/?ref=producthunt")
    b = content_hash("https://runwayml.com")
    assert a == b


def test_content_hash_differs_for_different_tools():
    assert content_hash("https://a.com") != content_hash("https://b.com")


def test_content_hash_survives_a_renamed_tool():
    # A corrected name must update the existing row, not insert a second one.
    assert content_hash("https://timelinescan.com/x") == content_hash(
        "https://timelinescan.com/x"
    )


def test_infer_category_picks_specific_bucket():
    assert infer_category("Sora", "text-to-video generation") == "ai-video"
    assert infer_category("Whisper", "speech transcription") == "ai-audio"


def test_infer_category_falls_back_when_nothing_matches():
    assert infer_category("Zzz", "an inscrutable product") == "new-apps"


def test_infer_pricing_reads_plan_signals():
    assert infer_pricing("Start free, upgrade for $20 per month") == "freemium"
    assert infer_pricing("Pricing starts at $49/mo") == "paid"
    assert infer_pricing("This project is open source") == "free"
    assert infer_pricing("A page that says nothing useful") == "unknown"


def test_build_tool_row_matches_schema_constraints():
    row = build_tool_row(
        name="Test Tool",
        website_url="https://testtool.com",
        tagline="Does a thing",
        description="A longer description of the thing.",
        tags=["a", "b", "c", "d", "e", "f"],
        pricing_type="freemium",
    )

    assert row["slug"] == "test-tool"
    assert row["category"] in CATEGORIES
    assert row["pricing_type"] in {"free", "freemium", "paid", "unknown"}
    assert len(row["tags"]) == 5
    assert row["status"] == "pending"
    assert row["content_hash"]


def test_build_tool_row_rejects_bad_pricing_value():
    row = build_tool_row(
        name="Test", website_url="https://t.com", pricing_type="cheap"
    )
    assert row["pricing_type"] == "unknown"


def test_build_tool_row_requires_name_and_url():
    try:
        build_tool_row(name="", website_url="https://t.com")
    except ValueError:
        pass
    else:
        raise AssertionError("expected ValueError for empty name")
