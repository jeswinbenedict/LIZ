from liz_scraper.enrich import parse_page

PAGE = """
<html>
  <head>
    <title>Acme AI | The best AI thing</title>
    <meta property="og:site_name" content="Acme AI">
    <meta property="og:description" content="Acme AI writes your blog posts for you.">
    <meta property="og:image" content="/social.png">
    <link rel="apple-touch-icon" href="/icons/touch.png">
    <link rel="icon" href="/favicon.ico">
  </head>
  <body>
    <a href="https://apps.apple.com/app/acme">iOS app</a>
    <a href="https://play.google.com/store/apps/details?id=acme">Android app</a>
    <p>Start free, then $19 per month for Pro.</p>
  </body>
</html>
"""


def test_parse_page_prefers_site_name_for_title():
    facts = parse_page(PAGE, "https://acme.ai")
    assert facts.title == "Acme AI"


def test_parse_page_reads_og_description():
    facts = parse_page(PAGE, "https://acme.ai")
    assert "writes your blog posts" in facts.description


def test_parse_page_prefers_touch_icon_and_absolutizes_it():
    facts = parse_page(PAGE, "https://acme.ai")
    assert facts.logo_url == "https://acme.ai/icons/touch.png"


def test_parse_page_detects_store_platforms():
    facts = parse_page(PAGE, "https://acme.ai")
    assert set(facts.platforms) == {"web", "ios", "android"}


def test_parse_page_infers_freemium_from_body_text():
    facts = parse_page(PAGE, "https://acme.ai")
    assert facts.pricing_type == "freemium"


def test_parse_page_survives_empty_html():
    facts = parse_page("<html></html>", "https://empty.com")
    assert facts.title == ""
    assert facts.platforms == ["web"]


def test_title_falls_back_to_title_tag_and_trims_suffix():
    html = "<html><head><title>Zeta — an AI tool</title></head></html>"
    facts = parse_page(html, "https://zeta.com")
    assert facts.title == "Zeta"


def test_parse_page_decodes_utf8_bytes_without_mojibake():
    raw = (
        '<html><head><meta charset="utf-8">'
        '<meta property="og:description" content="Summarize anything…">'
        "</head></html>"
    ).encode("utf-8")
    facts = parse_page(raw, "https://acme.ai")
    assert "…" in facts.description
    assert "â€¦" not in facts.description


def test_logo_skips_inline_data_uri_favicons():
    html = """
    <html><head>
      <link rel="icon" href="data:image/svg+xml,%3Csvg%3E%3C/svg%3E">
      <meta property="og:image" content="https://acme.ai/real-logo.png">
    </head></html>
    """
    facts = parse_page(html, "https://acme.ai")
    assert facts.logo_url == "https://acme.ai/real-logo.png"


def test_logo_is_none_when_only_data_uris_exist():
    html = '<html><head><link rel="icon" href="data:image/png;base64,AAA"></head></html>'
    facts = parse_page(html, "https://acme.ai")
    assert facts.logo_url is None


def test_aggregator_page_contributes_no_name():
    html = """
    <html><head>
      <meta property="og:site_name" content="Product Hunt">
      <meta property="og:description" content="Agentic video analysis.">
    </head></html>
    """
    facts = parse_page(html, "https://www.producthunt.com/products/google")
    # Otherwise a tool ends up literally named "Product Hunt".
    assert facts.title == ""


def test_aggregator_page_contributes_no_logo():
    html = """
    <html><head>
      <link rel="apple-touch-icon" href="/ph-favicon.png">
      <meta property="og:image" content="https://ph-static.imgix.net/brand.png">
      <meta property="og:description" content="Multi-agent marketplace.">
    </head></html>
    """
    facts = parse_page(html, "https://www.producthunt.com/products/openmarket")
    # Otherwise every Product Hunt find would wear Product Hunt's logo.
    assert facts.logo_url is None
    assert "marketplace" in facts.description


def test_product_site_still_contributes_a_logo():
    html = '<html><head><link rel="icon" href="/icon.png"></head></html>'
    facts = parse_page(html, "https://acme.ai")
    assert facts.logo_url == "https://acme.ai/icon.png"


def test_poster_tool_classified_as_design_not_agents():
    html = """
    <html><head>
      <meta property="og:site_name" content="Posterlet">
      <meta property="og:description"
            content="Free AI poster maker. Chat with our assistant to create posters and flyers.">
    </head></html>
    """
    facts = parse_page(html, "https://posterlet.com")
    assert facts.category == "ai-design"


def test_category_prefers_title_over_body_noise():
    html = """
    <html><head>
      <meta property="og:site_name" content="MoodJournal">
      <meta property="og:description" content="A daily journal for your notes and mood.">
    </head><body>
      <nav>Screenshots gallery image photo picture</nav>
    </body></html>
    """
    facts = parse_page(html, "https://moodjournal.com")
    assert facts.category == "ai-productivity"
