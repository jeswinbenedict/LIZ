"""Pages for crawlers and link previews (liz_scraper.prerender).

Tool text is scraped from the open web, so it is untrusted: a tagline must
not be able to add markup to the page or end the JSON-LD block. And the
structured data must not claim a rating nobody gave — Liz once displayed
invented ones.
"""

from __future__ import annotations

import json
import re

from liz_scraper.prerender import Site, category_page, robots, sitemap, tool_page

TEMPLATE = """<!DOCTYPE html><html lang="en"><head>
  <base href="/">
  <meta name="description" content="Liz — default.">
  <title>Liz — Discover the next big AI tool</title>
  <meta property="og:title" content="Liz">
  <meta property="og:description" content="default">
  <meta property="og:image" content="icons/Icon-512.png">
  <meta name="twitter:card" content="summary">
  <meta name="twitter:title" content="Liz">
  <meta name="twitter:description" content="default">
</head>
<body>
  <script src="flutter_bootstrap.js" async=""></script>
</body></html>"""

TOOL = {
    "id": "t1", "name": "Koi.rest", "slug": "koi-rest",
    "tagline": "Watch some fish and regain your balance",
    "description": "A koi pond to stare at.",
    "ai_summary": ["Calming koi pond.", "Nothing else."],
    "category": "new-apps", "pricing_type": "free", "price_note": None,
    "website_url": "https://koi.rest", "gh_repo": None, "gh_stars": None,
    "hn_id": "49837006", "hn_points": 228, "trend_reason": "228 points on Hacker News",
    "avg_rating": 0, "rating_count": 0, "created_at": "2026-09-25T10:00:00Z",
    "updated_at": "2026-09-29T10:00:00Z",
}
SITE = Site("https://liz.example")


def _ld(page: str) -> dict:
    m = re.search(r'<script type="application/ld\+json">(.*?)</script>', page, re.S)
    assert m, "no JSON-LD"
    return json.loads(m.group(1))


def test_a_tool_page_has_its_own_title_description_and_canonical():
    page = tool_page(TEMPLATE, TOOL, SITE, "New Apps", [])
    assert "<title>Koi.rest — Watch some fish and regain your balance | Liz</title>" in page
    assert '<link rel="canonical" href="https://liz.example/tools/koi-rest">' in page
    assert 'content="Liz — default."' not in page
    assert page.count("<title>") == 1
    assert "flutter_bootstrap.js" in page, "the app still starts"


def test_the_page_text_is_there_without_javascript():
    page = tool_page(TEMPLATE, TOOL, SITE, "New Apps", [])
    body = page.split("<body>", 1)[1]
    assert "<h1>Koi.rest</h1>" in body
    assert "Calming koi pond." in body
    assert 'href="https://news.ycombinator.com/item?id=49837006"' in body
    assert 'href="/category/new-apps"' in body


def test_no_rating_is_claimed_that_nobody_gave():
    ld = _ld(tool_page(TEMPLATE, TOOL, SITE, "New Apps", []))
    assert ld["@type"] == "SoftwareApplication"
    assert "aggregateRating" not in ld
    rated = _ld(tool_page(TEMPLATE, TOOL | {"rating_count": 3, "avg_rating": 4.33}, SITE, "", []))
    assert rated["aggregateRating"] == {
        "@type": "AggregateRating", "ratingValue": 4.3, "ratingCount": 3}


def test_scraped_text_cannot_add_markup_or_end_the_script():
    evil = TOOL | {
        "name": 'Evil <img src=x onerror=alert(1)>',
        "tagline": '</script><script>alert(1)</script>',
    }
    page = tool_page(TEMPLATE, evil, SITE, "New Apps", [])
    assert "<img src=x" not in page
    assert "<script>alert(1)" not in page
    # The JSON-LD block still parses and still says what the text was.
    assert "alert(1)" in _ld(page)["description"]


def test_category_pages_link_every_tool():
    other = TOOL | {"id": "t2", "name": "Other", "slug": "other"}
    page = category_page(TEMPLATE, {"name": "New Apps", "slug": "new-apps"},
                         [TOOL, other], SITE)
    assert 'href="/tools/koi-rest"' in page and 'href="/tools/other"' in page
    assert _ld(page)["@type"] == "ItemList"


def test_sitemap_and_robots():
    xml = sitemap(SITE, [TOOL], [{"name": "New Apps", "slug": "new-apps"}])
    assert "<loc>https://liz.example/tools/koi-rest</loc><lastmod>2026-09-29</lastmod>" in xml
    assert "<loc>https://liz.example/category/new-apps</loc>" in xml
    text = robots(SITE)
    assert "Sitemap: https://liz.example/sitemap.xml" in text
    assert "Disallow: /admin" in text


def test_without_a_site_address_nothing_absolute_is_invented():
    page = tool_page(TEMPLATE, TOOL, Site(""), "New Apps", [])
    assert 'rel="canonical"' not in page
    assert "url" not in _ld(page)


def test_the_title_matches_the_one_the_app_sets():
    # lib/shared/widgets/page_title.dart (PageTitle.forTool) cuts the same way;
    # test/page_title_test.dart expects this exact string.
    long = TOOL | {
        "name": "Delightful Cells",
        "tagline": "Reliable AI batch processing for spreadsheets, with retries "
                   "and progress you can watch",
    }
    page = tool_page(TEMPLATE, long, SITE, "", [])
    assert ("<title>Delightful Cells — Reliable AI batch processing for "
            "spreadsheets,… | Liz</title>") in page


def test_a_tool_with_a_picture_previews_with_it():
    page = tool_page(TEMPLATE, TOOL | {"image_url": "https://koi.rest/og.png"}, SITE, "", [])
    assert '<meta property="og:image" content="https://koi.rest/og.png">' in page
    assert 'content="summary_large_image"' in page
    assert _ld(page)["image"] == "https://koi.rest/og.png"
    plain = tool_page(TEMPLATE, TOOL, SITE, "", [])
    assert 'content="https://liz.example/icons/Icon-512.png"' in plain
    assert 'content="summary"' in plain
