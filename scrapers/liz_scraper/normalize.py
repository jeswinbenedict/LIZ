"""Turn messy source data into rows the `tools` table will accept.

Category slugs and the pricing_type enum mirror supabase/migrations/0001_schema.sql —
a value outside these sets is rejected by the database, so keep them in sync.
"""

from __future__ import annotations

import hashlib
import re
from urllib.parse import urlsplit, urlunsplit

CATEGORIES = {
    "ai-writing",
    "ai-video",
    "ai-image",
    "ai-audio",
    "ai-design",
    "ai-dev",
    "ai-agents",
    "ai-productivity",
    "ai-research",
    "new-apps",
}

DEFAULT_CATEGORY = "new-apps"

# Ordered: the first bucket whose keywords appear wins, so put the specific
# buckets before the catch-all ones.
_CATEGORY_KEYWORDS: list[tuple[str, tuple[str, ...]]] = [
    ("ai-video", ("video", "film", "footage", "youtube", "editing suite", "text-to-video")),
    ("ai-image", ("image", "photo", "picture", "diffusion", "text-to-image", "headshot")),
    ("ai-audio", ("audio", "voice", "speech", "music", "podcast", "transcription", "tts")),
    (
        "ai-design",
        (
            "design", "ui kit", "mockup", "logo", "figma", "branding",
            "poster", "flyer", "banner", "graphic", "illustration", "thumbnail",
        ),
    ),
    ("ai-agents", ("agent", "autonomous", "workflow automation", "copilot", "assistant")),
    ("ai-dev", ("code", "developer", "sdk", "api", "programming", "ide", "devtool")),
    ("ai-writing", ("writing", "copywriting", "essay", "blog", "grammar", "content")),
    ("ai-research", ("research", "paper", "academic", "citation", "dataset", "scholar")),
    ("ai-productivity", ("productivity", "notes", "meeting", "calendar", "task", "crm")),
]

_PAID_HINTS = ("pricing", "subscribe", "buy now", "start trial", "per month", "/mo", "$")
_FREE_TIER_HINTS = ("free plan", "free tier", "free forever", "start free", "try for free")
_FULLY_FREE_HINTS = ("open source", "100% free", "completely free", "mit license")


def slugify(value: str, *, max_length: int = 60) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")
    return slug[:max_length].strip("-")


def canonical_url(url: str) -> str:
    """Strip tracking params and trailing slashes so the same page hashes alike."""
    parts = urlsplit(url.strip())
    netloc = parts.netloc.lower().removeprefix("www.")
    path = parts.path.rstrip("/")
    return urlunsplit((parts.scheme.lower(), netloc, path, "", ""))


def content_hash(url: str) -> str:
    """Stable dedupe key: a tool is identified by where it lives.

    The title is deliberately excluded. Sources reword titles, and a hash that
    included one would treat a corrected name as a different tool and insert a
    duplicate rather than updating the existing row.
    """
    return hashlib.sha256(canonical_url(url).encode("utf-8")).hexdigest()


def infer_category(*texts: str) -> str:
    haystack = " ".join(t for t in texts if t).lower()
    for slug, keywords in _CATEGORY_KEYWORDS:
        if any(keyword in haystack for keyword in keywords):
            return slug
    return DEFAULT_CATEGORY


def infer_pricing(page_text: str) -> str:
    """Best-effort read of a product page's pricing model."""
    text = page_text.lower()

    if any(hint in text for hint in _FULLY_FREE_HINTS):
        return "free"

    has_paid_signal = any(hint in text for hint in _PAID_HINTS)
    has_free_signal = any(hint in text for hint in _FREE_TIER_HINTS)

    if has_paid_signal and has_free_signal:
        return "freemium"
    if has_paid_signal:
        return "paid"
    if has_free_signal:
        return "free"
    return "unknown"


# A launch title is a sentence, not a name. Splitting on the first of these
# recovers the product: "MacTap, use knocks on your MacBook" → "MacTap",
# "Rokz: a browser port of a 1990 dungeon crawler" → "Rokz".
_TITLE_SEPARATORS = re.compile(r"\s*[–—:,|]\s*|\s+-\s+")

# Titles that open with one of these are describing a thing, not naming it,
# so the product's own site is the better source for its name.
_DESCRIPTIVE_OPENERS = {
    "a", "an", "the", "my", "our", "free", "open", "how", "why", "what",
    "introducing", "show", "using", "build", "building", "make", "making",
    "i", "we", "this", "new", "simple", "easy", "fast", "best",
}


def clean_title(raw: str) -> str:
    """First segment of a launch title, with the 'Show HN:' prefix removed."""
    text = clean_text(raw)
    for prefix in ("Show HN:", "Ask HN:", "Launch HN:"):
        if text.lower().startswith(prefix.lower()):
            text = text[len(prefix):].strip()
            break
    first = _TITLE_SEPARATORS.split(text, maxsplit=1)[0].strip()
    return first or text


def looks_like_a_name(value: str) -> bool:
    """Whether a string reads as a product name rather than a description."""
    words = value.split()
    if not words or len(words) > 4:
        return False
    return words[0].strip("'\"").lower() not in _DESCRIPTIVE_OPENERS


def choose_name(source_title: str, site_title: str = "") -> str:
    """Pick the best available product name.

    The listing title is used when it actually names the product. When it only
    describes one ("Free scanning app with ML crops"), the product's own site
    is the authority on what it is called.
    """
    candidate = clean_title(source_title)
    if looks_like_a_name(candidate):
        return candidate

    site = clean_text(site_title)
    if site and looks_like_a_name(site):
        return site

    return candidate


def clean_text(value: str | None, *, limit: int | None = None) -> str:
    if not value:
        return ""
    collapsed = re.sub(r"\s+", " ", value).strip()
    if limit is not None and len(collapsed) > limit:
        return collapsed[: limit - 1].rstrip() + "…"
    return collapsed


def build_tool_row(
    *,
    name: str,
    website_url: str,
    tagline: str = "",
    description: str = "",
    logo_url: str | None = None,
    category: str | None = None,
    tags: list[str] | None = None,
    platforms: list[str] | None = None,
    pricing_type: str = "unknown",
    price_note: str | None = None,
    source: str = "scraper",
    source_url: str | None = None,
    launched_at: str | None = None,
    status: str = "pending",
) -> dict:
    """Assemble a row matching the `tools` table, with safe defaults."""
    name = clean_text(name, limit=120)
    if not name:
        raise ValueError("name is required")
    if not website_url:
        raise ValueError("website_url is required")

    resolved_category = category if category in CATEGORIES else infer_category(
        name, tagline, description, " ".join(tags or [])
    )

    return {
        "name": name,
        "slug": slugify(name),
        "tagline": clean_text(tagline, limit=140),
        "description": clean_text(description, limit=2000),
        "website_url": website_url,
        "logo_url": logo_url,
        "category": resolved_category,
        "tags": (tags or [])[:5],
        "platforms": platforms or ["web"],
        "pricing_type": pricing_type if pricing_type in
        {"free", "freemium", "paid", "unknown"} else "unknown",
        "price_note": price_note,
        "source": source,
        "source_url": source_url or website_url,
        "content_hash": content_hash(website_url),
        "launched_at": launched_at,
        "status": status,
    }
