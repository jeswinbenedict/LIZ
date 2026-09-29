from liz_scraper.enrich import find_product_url, is_aggregator, parse_page


LISTING = """
<html><body>
  <a href="https://openmarket.m11.ai">Visit</a>
  <a href="https://openmarket.m11.ai/pricing">Pricing</a>
  <a href="https://openmarket.m11.ai">Get it</a>
  <a href="https://x.com/openmarket">Twitter</a>
  <a href="https://www.linkedin.com/company/x">LinkedIn</a>
  <a href="https://lu.ma/event">Launch event</a>
  <a href="https://www.producthunt.com/posts/other">Another post</a>
</body></html>
"""


def test_find_product_url_picks_the_most_linked_real_site():
    url = find_product_url(LISTING, "https://www.producthunt.com/products/openmarket")
    assert url.startswith("https://openmarket.m11.ai")


def test_find_product_url_ignores_socials_and_the_directory_itself():
    html = """
    <html><body>
      <a href="https://x.com/maker">X</a>
      <a href="https://www.producthunt.com/posts/x">PH</a>
    </body></html>
    """
    assert find_product_url(html, "https://www.producthunt.com/products/x") is None


def test_is_aggregator_identifies_listing_hosts():
    assert is_aggregator("https://www.producthunt.com/products/x")
    assert not is_aggregator("https://acme.ai")

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


# --- the pricing page -------------------------------------------------------

from liz_scraper import enrich as enrich_module  # noqa: E402
from liz_scraper.enrich import find_pricing_url  # noqa: E402


def test_a_pricing_link_is_found_by_its_label():
    html = """<a href="/docs">Docs</a><a href="/p/tiers">Pricing</a>"""
    assert find_pricing_url(html, "https://acme.ai/") == "https://acme.ai/p/tiers"


def test_a_pricing_link_is_found_by_its_path_when_the_label_says_nothing():
    html = """<a href="https://app.acme.ai/plans">See what fits</a>"""
    assert find_pricing_url(html, "https://acme.ai") == "https://app.acme.ai/plans"


def test_someone_elses_pricing_page_is_not_this_products():
    html = """<a href="https://stripe.com/pricing">Pricing</a>
              <a href="https://other.co.uk/pricing">Pricing</a>"""
    assert find_pricing_url(html, "https://acme.co.uk") is None


def test_no_pricing_link_means_no_guess():
    assert find_pricing_url("<a href='/blog'>Blog</a>", "https://acme.ai") is None


class _Response:
    def __init__(self, html):
        self.content = html.encode()
        self.headers = {"Content-Type": "text/html; charset=utf-8"}


class _Session:
    def __init__(self, pages):
        self.pages = pages
        self.fetched = []

    def get(self, url):
        self.fetched.append(url)
        page = self.pages.get(url)
        return _Response(page) if page is not None else None


def test_a_silent_home_page_is_answered_by_its_pricing_page():
    session = _Session({
        "https://acme.ai": "<title>Acme</title><a href='/pricing'>Pricing</a>",
        "https://acme.ai/pricing": "Free plan. Pro $20 per month.",
    })
    facts = enrich_module.enrich_url(session, "https://acme.ai")
    assert facts.pricing_type == "freemium"


def test_the_pricing_page_outranks_the_home_page():
    # Noodle Seed's home page shows its demo shop ("Everyday Backpack $89");
    # its pricing page has a free plan.
    session = _Session({
        "https://acme.ai": "<a href='/pricing'>Pricing</a> Everyday Backpack $89",
        "https://acme.ai/pricing": "Free $0 / month. Growth $49 / month.",
    })
    facts = enrich_module.enrich_url(session, "https://acme.ai")
    assert facts.pricing_type == "freemium"


def test_with_no_pricing_page_the_home_page_still_answers():
    session = _Session({"https://acme.ai": "Only $9 per month."})
    facts = enrich_module.enrich_url(session, "https://acme.ai")
    assert facts.pricing_type == "paid"
    # No pricing link, so no pricing page is fetched (and none is guessed).
    assert not any("pricing" in u for u in session.fetched)


def test_an_unreadable_pricing_page_leaves_it_unknown():
    session = _Session({"https://acme.ai": "<a href='/pricing'>Pricing</a>"})
    facts = enrich_module.enrich_url(session, "https://acme.ai")
    assert facts.pricing_type == "unknown"


def test_a_tool_inside_a_bigger_site_does_not_take_the_sites_prices():
    # Found in the first dry run: an Obsidian plugin came out "paid" from
    # Obsidian Sync's pricing, a free survey from its publisher's SEO plans.
    html = """<a href="https://obsidian.md/pricing">Pricing</a>
              <a href="/pricing">Pricing</a>"""
    assert find_pricing_url(
        html, "https://community.obsidian.md/plugins/modelica-studio"
    ) is None


def test_a_tool_inside_a_bigger_site_may_have_pricing_of_its_own():
    html = """<a href="/apps/acme/pricing">Pricing</a>"""
    assert find_pricing_url(html, "https://host.dev/apps/acme") == (
        "https://host.dev/apps/acme/pricing"
    )


# --- a favicon nobody declared ----------------------------------------------

class _BytesResponse:
    def __init__(self, body, content_type="image/x-icon"):
        self.content = body
        self.headers = {"Content-Type": content_type}


class _MixedSession(_Session):
    """Pages as HTML strings, anything else as raw responses."""

    def __init__(self, pages, raw):
        super().__init__(pages)
        self.raw = raw

    def get(self, url):
        if url in self.raw:
            self.fetched.append(url)
            return self.raw[url]
        return super().get(url)


def test_an_undeclared_favicon_is_found_at_the_root():
    session = _MixedSession(
        {"https://acme.ai/app": "<title>Acme</title>"},
        {"https://acme.ai/favicon.ico": _BytesResponse(b"\x00\x00\x01\x00rest",
                                                        "application/octet-stream")},
    )
    facts = enrich_module.enrich_url(session, "https://acme.ai/app")
    assert facts.logo_url == "https://acme.ai/favicon.ico"


def test_a_single_page_apps_html_is_not_a_favicon():
    # SPAs answer every path with their HTML shell and a 200.
    session = _MixedSession(
        {"https://acme.ai": "<title>Acme</title>"},
        {"https://acme.ai/favicon.ico": _BytesResponse(b"<!doctype html>", "text/html")},
    )
    assert enrich_module.enrich_url(session, "https://acme.ai").logo_url is None


def test_a_declared_logo_costs_no_favicon_request():
    session = _MixedSession(
        {"https://acme.ai": "<link rel='icon' href='/i.png'><title>Acme</title>"}, {}
    )
    facts = enrich_module.enrich_url(session, "https://acme.ai")
    assert facts.logo_url == "https://acme.ai/i.png"
    assert "https://acme.ai/favicon.ico" not in session.fetched


def test_the_logo_backfill_prefers_a_declared_icon_and_skips_listings():
    from liz_scraper.backfill_logos import logo_for

    declared = _MixedSession(
        {"https://acme.ai": "<link rel='apple-touch-icon' href='/t.png'>"}, {}
    )
    assert logo_for(declared, "https://acme.ai") == "https://acme.ai/t.png"

    undeclared = _MixedSession(
        {"https://acme.ai": "<title>Acme</title>"},
        {"https://acme.ai/favicon.ico": _BytesResponse(b"\x89PNG....")},
    )
    assert logo_for(undeclared, "https://acme.ai") == "https://acme.ai/favicon.ico"

    # A listing's icon is the directory's, never the product's.
    listing = _MixedSession({}, {})
    assert logo_for(listing, "https://www.producthunt.com/products/x") is None
    assert listing.fetched == []


def test_an_svg_icon_is_passed_over_for_a_raster_one():
    # Flutter cannot draw SVG; 84 published tools showed a letter tile for it.
    from bs4 import BeautifulSoup
    from liz_scraper.enrich import extract_logo

    html = """<link rel="icon" href="/icon.svg?v=2" type="image/svg+xml">
              <link rel="icon" href="/favicon-32.png">"""
    assert extract_logo(BeautifulSoup(html, "lxml"), "https://acme.ai") == (
        "https://acme.ai/favicon-32.png"
    )
    only_svg = """<link rel="icon" href="/logo" type="image/svg+xml">"""
    assert extract_logo(BeautifulSoup(only_svg, "lxml"), "https://acme.ai") is None


def test_preview_image_is_absolute_and_never_svg():
    from bs4 import BeautifulSoup
    from liz_scraper.enrich import extract_preview_image

    def image(head: str) -> str | None:
        return extract_preview_image(
            BeautifulSoup(f"<html><head>{head}</head></html>", "lxml"),
            "https://tool.app/start",
        )

    assert image('<meta property="og:image" content="/og.png">') == "https://tool.app/og.png"
    assert image('<meta property="og:image" content="/og.svg">') is None
    assert image('<meta property="og:image" content="data:image/png;base64,xx">') is None
    assert image('<meta name="twitter:image" content="https://cdn.tool.app/t.jpg">') == (
        "https://cdn.tool.app/t.jpg")
    assert image("") is None
