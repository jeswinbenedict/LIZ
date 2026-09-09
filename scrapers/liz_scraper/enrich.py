"""BeautifulSoup enrichment for a tool's own website.

Discovery feeds give us little more than a name and a link. This module visits
the product's own page and pulls the facts that make a catalog entry look
credible: a real description, a real logo, the pricing model, and which
platforms it ships on.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from urllib.parse import urljoin, urlsplit

from bs4 import BeautifulSoup

from .http_client import PoliteSession
from .normalize import DEFAULT_CATEGORY, clean_text, infer_category, infer_pricing

# Listing sites describe a product but are not the product. Their favicon and
# og:image belong to the directory, so taking either would stamp the same logo
# on every tool discovered there.
AGGREGATOR_HOSTS = {
    "producthunt.com",
    "news.ycombinator.com",
    "github.com",
    "apps.apple.com",
    "play.google.com",
}

# Links every listing page carries regardless of the product: the maker's
# socials, the launch event, the app stores. None of them is the product's home.
_OUTBOUND_NOISE = {
    "x.com", "twitter.com", "linkedin.com", "instagram.com", "facebook.com",
    "youtube.com", "tiktok.com", "discord.gg", "discord.com", "t.me",
    "lu.ma", "reddit.com", "medium.com", "substack.com", "apps.apple.com",
    "play.google.com", "itunes.apple.com", "calendly.com",
}

_STORE_PLATFORMS = {
    "apps.apple.com": "ios",
    "itunes.apple.com": "ios",
    "play.google.com": "android",
    "chromewebstore.google.com": "chrome",
    "chrome.google.com": "chrome",
    "addons.mozilla.org": "firefox",
    "apps.microsoft.com": "windows",
}


@dataclass
class PageFacts:
    title: str = ""
    description: str = ""
    logo_url: str | None = None
    image_url: str | None = None
    pricing_type: str = "unknown"
    platforms: list[str] = field(default_factory=lambda: ["web"])
    category: str | None = None


def _meta(soup: BeautifulSoup, *, prop: str | None = None, name: str | None = None) -> str:
    if prop:
        tag = soup.find("meta", attrs={"property": prop})
        if tag and tag.get("content"):
            return clean_text(tag["content"])
    if name:
        tag = soup.find("meta", attrs={"name": name})
        if tag and tag.get("content"):
            return clean_text(tag["content"])
    return ""


def extract_title(soup: BeautifulSoup) -> str:
    for candidate in (
        _meta(soup, prop="og:site_name"),
        _meta(soup, prop="og:title"),
        clean_text(soup.title.string if soup.title else ""),
    ):
        if candidate:
            # "Notion AI — Your AI assistant" → "Notion AI"
            return clean_text(candidate.split("|")[0].split("—")[0].split("–")[0], limit=120)
    return ""


def extract_description(soup: BeautifulSoup) -> str:
    for candidate in (
        _meta(soup, prop="og:description"),
        _meta(soup, name="description"),
        _meta(soup, name="twitter:description"),
    ):
        if candidate:
            return candidate
    return ""


def extract_logo(soup: BeautifulSoup, base_url: str) -> str | None:
    """Prefer a real touch icon over a low-res favicon; fall back to og:image."""
    selectors = [
        {"rel": "apple-touch-icon"},
        {"rel": "apple-touch-icon-precomposed"},
        {"rel": "icon"},
        {"rel": "shortcut icon"},
    ]
    for attrs in selectors:
        for link in soup.find_all("link", attrs=attrs):
            href = link.get("href")
            # Inline data: icons are usually emoji placeholders, and storing one
            # would bloat the row with something the app can't render well.
            if href and not href.strip().lower().startswith("data:"):
                return urljoin(base_url, href)

    og_image = _meta(soup, prop="og:image")
    if og_image and not og_image.strip().lower().startswith("data:"):
        return urljoin(base_url, og_image)
    return None


def extract_platforms(soup: BeautifulSoup) -> list[str]:
    platforms = {"web"}
    for anchor in soup.find_all("a", href=True):
        host = urlsplit(anchor["href"]).netloc.lower().removeprefix("www.")
        if host in _STORE_PLATFORMS:
            platforms.add(_STORE_PLATFORMS[host])
    return sorted(platforms)


def parse_page(html: str | bytes, base_url: str) -> PageFacts:
    # Passing bytes lets BeautifulSoup read the document's own charset instead of
    # requests guessing latin-1 and turning "…" into "â€¦".
    soup = BeautifulSoup(html, "lxml")

    title = extract_title(soup)
    description = extract_description(soup)

    # Pricing lives in nav labels and plan cards more often than in meta tags,
    # so read the rendered text rather than the head.
    body_text = clean_text(soup.get_text(" "), limit=20000)

    # Title and description describe the product; body text is mostly nav and
    # footer noise, so only fall back to it when the strong signals say nothing.
    category = infer_category(title, description)
    if category == DEFAULT_CATEGORY:
        category = infer_category(body_text[:2000])

    # A listing page's identity is the directory's, not the product's: its
    # og:site_name is "Product Hunt" and its icon is Product Hunt's. Taking
    # either would name every discovery after the site it was found on.
    host = urlsplit(base_url).netloc.lower().removeprefix("www.")
    if host in AGGREGATOR_HOSTS:
        title = ""
        logo_url = None
    else:
        logo_url = extract_logo(soup, base_url)

    return PageFacts(
        title=title,
        description=description,
        logo_url=logo_url,
        image_url=_meta(soup, prop="og:image") or None,
        pricing_type=infer_pricing(body_text),
        platforms=extract_platforms(soup),
        category=category,
    )


def is_aggregator(url: str) -> bool:
    return urlsplit(url).netloc.lower().removeprefix("www.") in AGGREGATOR_HOSTS


def find_product_url(html: str | bytes, listing_url: str) -> str | None:
    """The product's own home page, as linked from a listing page.

    A directory entry links out to the thing it describes, usually several
    times (header, hero button, footer). The most-linked host that is not the
    directory itself or a social profile is that product.
    """
    soup = BeautifulSoup(html, "lxml")
    listing_host = urlsplit(listing_url).netloc.lower().removeprefix("www.")

    counts: dict[str, int] = {}
    first_seen: dict[str, str] = {}
    for anchor in soup.find_all("a", href=True):
        href = anchor["href"].strip()
        if not href.startswith("http"):
            continue
        host = urlsplit(href).netloc.lower().removeprefix("www.")
        if not host or host == listing_host:
            continue
        if host in _OUTBOUND_NOISE or host in AGGREGATOR_HOSTS:
            continue
        counts[host] = counts.get(host, 0) + 1
        first_seen.setdefault(host, href)

    if not counts:
        return None
    best_host = max(counts, key=lambda h: counts[h])
    return first_seen[best_host]


def resolve_and_enrich(
    session: PoliteSession, url: str
) -> tuple[str, PageFacts | None]:
    """Enrich a candidate, following listing pages through to the real product.

    Returns the URL the facts describe, which becomes the tool's website_url —
    a directory page is where a tool was *found*, not where it lives.
    """
    if not is_aggregator(url):
        return url, enrich_url(session, url)

    response = session.get(url)
    if response is None:
        return url, None

    product_url = find_product_url(response.content, url)
    if product_url is None:
        # Fall back to the listing itself; parse_page suppresses the
        # directory's own name, logo and pricing.
        return url, parse_page(response.content, url)

    facts = enrich_url(session, product_url)
    if facts is None:
        return url, parse_page(response.content, url)
    return product_url, facts


def enrich_url(session: PoliteSession, url: str) -> PageFacts | None:
    """Fetch and parse a product page. Returns None when the page is unusable."""
    response = session.get(url)
    if response is None:
        return None
    content_type = response.headers.get("Content-Type", "")
    if "html" not in content_type.lower():
        return None
    return parse_page(response.content, url)
