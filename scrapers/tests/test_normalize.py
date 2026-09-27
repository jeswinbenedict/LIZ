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
    strip_tracking,
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


def test_strip_tracking_removes_referral_params_only():
    assert strip_tracking("https://acme.ai/?ref=producthunt") == "https://acme.ai"
    assert strip_tracking("https://acme.ai/x?utm_source=ph&utm_medium=web") == "https://acme.ai/x"
    # A parameter the page actually needs must survive.
    assert strip_tracking("https://acme.ai/p?id=7&ref=ph") == "https://acme.ai/p?id=7"


def test_build_tool_row_stores_a_clean_website_url():
    row = build_tool_row(name="Acme", website_url="https://acme.ai/?ref=producthunt")
    assert row["website_url"] == "https://acme.ai"


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


def test_infer_pricing_ignores_dollar_signs_without_a_figure():
    # These were all read as "paid" when any "$" counted.
    assert infer_pricing("Save $ on your workflow") == "unknown"
    assert infer_pricing("Our pricing page explains the plans") == "unknown"


def test_infer_pricing_ignores_funding_amounts():
    # A raise is not a price list.
    assert infer_pricing("We raised $2M to build this") == "unknown"
    assert infer_pricing("Backed by a $500K seed round") == "unknown"
    assert infer_pricing("Plans start at $12 a month") == "paid"


def test_infer_pricing_treats_a_trial_as_paid_not_free():
    assert infer_pricing("Start your free trial today") == "paid"
    assert infer_pricing("Try it free for 14 days") == "paid"
    assert infer_pricing("14-day free trial, no credit card") == "freemium"


def test_infer_pricing_recognises_more_free_tier_phrasings():
    assert infer_pricing("Get started for free") == "free"
    assert infer_pricing("No credit card required") == "free"
    assert infer_pricing("Free for personal use") == "free"


def test_open_source_with_paid_hosting_is_not_free():
    text = "Open source and self-hostable. Cloud plans from $29 per month."
    assert infer_pricing(text) == "paid"


def test_open_source_with_a_free_tier_is_freemium():
    text = "Open source. Free plan available, or $10/mo for teams."
    assert infer_pricing(text) == "freemium"


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


# --- naming from the domain --------------------------------------------------
# Three launches reached the catalog named after their own sentences: "Making an
# app to organize all basic aspects…", "Check/strip AI watermarks (C2PA)…". Each
# had a perfectly good name sitting in its URL.

def test_name_from_domain_reads_as_a_product_name():
    from liz_scraper.normalize import name_from_domain
    assert name_from_domain("https://demo.ontoplano.com") == "Ontoplano"
    assert name_from_domain("https://remove-ai-watermark.com") == "Remove Ai Watermark"
    assert name_from_domain("https://www.tucky.io/x") == "Tucky"


def test_name_from_domain_ignores_boilerplate_subdomains():
    from liz_scraper.normalize import name_from_domain
    assert name_from_domain("https://app.linear.app") == "Linear"
    assert name_from_domain("https://get.slack.com") == "Slack"


def test_choose_name_falls_back_to_the_domain_before_a_sentence():
    name = choose_name(
        "Check/strip AI watermarks (C2PA) and hidden metadata",
        "",
        url="https://remove-ai-watermark.com",
    )
    assert name == "Remove Ai Watermark"


def test_choose_name_still_prefers_a_real_title_over_the_domain():
    assert choose_name("Posterlet", "", url="https://some-host.com") == "Posterlet"


# --- pricing false positives found by the 27 September backfill dry run -----

from liz_scraper.normalize import infer_pricing as _infer  # noqa: E402


def test_a_zero_dollar_plan_beside_a_paid_one_is_freemium():
    assert _infer("Free $0 A complete way to start. Premium $12 / month") == "freemium"


def test_what_a_freebie_is_worth_is_not_a_price():
    assert _infer("1,000 free conversations · $30 value. Join the waitlist") == "unknown"


def test_a_newsletter_subscribe_button_is_not_a_plan():
    assert _infer("Home Tools About Sign in Subscribe Experiments") == "unknown"


def test_real_prices_still_read_as_paid():
    assert _infer("Pro $20 per month") == "paid"
    assert _infer("Starter $9.99") == "paid"
    assert _infer("Only 10 USD") == "paid"
    assert _infer("$2M raised") == "unknown"


def test_prices_of_goods_on_a_demo_are_not_the_products_price():
    # An AI shopping agent's home page, full of its demo shop's stock.
    assert _infer(
        "Everyday hoodie Grey / Small €42 each View product. "
        "Garden House Lisbon €180 per night View rooms"
    ) == "unknown"
