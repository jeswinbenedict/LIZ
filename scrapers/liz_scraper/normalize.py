"""Turn messy source data into rows the `tools` table will accept.

Category slugs and the pricing_type enum mirror supabase/migrations/0001_schema.sql —
a value outside these sets is rejected by the database, so keep them in sync.
"""

from __future__ import annotations

import hashlib
import re
from urllib.parse import parse_qsl, urlencode, urlsplit, urlunsplit

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

# An actual price, not any stray "$". The trailing guard rejects funding
# amounts — "$2M raised", "$500K seed" — which say nothing about what the
# product costs.
_PRICE_FIGURE = re.compile(
    r"[$€£]\s?\d[\d,]*(?:\.\d+)?(?![\d,.]*\s?[mkb]\b)"
    r"|\b\d+(?:\.\d+)?\s?(?:usd|eur|gbp)\b",
    re.I,
)

_SUBSCRIPTION = re.compile(
    r"\bper\s+(?:month|year|seat|user)\b|/\s?(?:mo|month|yr|year)\b"
    r"|\bbilled\s+(?:annually|monthly|yearly)\b|\bsubscribe\b"
    r"|\bupgrade\s+to\s+(?:pro|premium|plus|paid)\b",
    re.I,
)

# A time-limited trial is how paid products are sold, not a free tier.
_TRIAL = re.compile(
    r"\bfree\s+trial\b|\b\d+[-\s]day\s+(?:free\s+)?trial\b|\btry\s+(?:it\s+)?free\s+for\b",
    re.I,
)

# Language that only appears when there is a genuinely free way to use it.
# "start free" is excluded when a trial immediately follows.
_FREE_TIER = re.compile(
    r"\bfree\s+(?:plan|tier|version|forever)\b"
    r"|\b(?:get\s+started|start|sign\s+up)\s+(?:for\s+)?free\b(?!\s+trial)"
    r"|\bno\s+credit\s+card\b"
    r"|\bfree\s+to\s+use\b"
    r"|\bfree\s+for\s+(?:personal|individual|non[-\s]?commercial)\b",
    re.I,
)

_FULLY_FREE = re.compile(
    r"\b(?:100%\s+free|completely\s+free|always\s+free|free\s+and\s+open[-\s]source)\b",
    re.I,
)

_OPEN_SOURCE = re.compile(
    r"\bopen[-\s]source\b|\b(?:mit|apache|gpl|bsd)\s+licen[cs]e\b", re.I
)


def slugify(value: str, *, max_length: int = 60) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")
    return slug[:max_length].strip("-")


_TRACKING_PARAMS = re.compile(
    r"^(utm_\w+|ref|ref_src|source|via|fbclid|gclid|mc_cid|mc_eid)$", re.I
)


def strip_tracking(url: str) -> str:
    """Remove referral noise while keeping parameters the page needs.

    Links arrive from directories tagged "?ref=producthunt"; that belongs in
    our analytics, not in the link a reader clicks.
    """
    parts = urlsplit(url.strip())
    kept = [
        (k, v)
        for k, v in parse_qsl(parts.query, keep_blank_values=True)
        if not _TRACKING_PARAMS.match(k)
    ]
    query = urlencode(kept)
    path = parts.path.rstrip("/") if parts.path != "/" else ""
    return urlunsplit((parts.scheme, parts.netloc, path, query, ""))


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
    """Best-effort read of a product page's pricing model.

    Reports "unknown" rather than guessing: a wrong badge is worse than an
    absent one, because a reader has no way to tell it is wrong.
    """
    paid = bool(
        _PRICE_FIGURE.search(page_text)
        or _SUBSCRIPTION.search(page_text)
        or _TRIAL.search(page_text)
    )
    free_tier = bool(_FREE_TIER.search(page_text))

    if _FULLY_FREE.search(page_text) and not paid:
        return "free"
    if paid and free_tier:
        return "freemium"
    if paid:
        return "paid"
    if free_tier:
        return "free"
    # Open source alone is not free-of-charge: open-core products sell hosting.
    # It only decides the answer when nothing suggests money changes hands.
    if _OPEN_SOURCE.search(page_text):
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


def name_from_domain(url: str) -> str:
    """A product name derived from its own domain.

    Last resort, but usually a good one: a launch titled "Check/strip AI
    watermarks (C2PA)" lives at remove-ai-watermark.com, and the domain reads
    as a name where the sentence does not. Subdomains like www or demo are
    dropped so demo.ontoplano.com becomes "Ontoplano".
    """
    host = urlsplit(url).netloc.lower().split(":")[0]
    labels = [l for l in host.split(".") if l not in {"www", "demo", "app", "get", "try"}]
    if len(labels) > 2:  # keep the registrable label, not the subdomain
        labels = labels[-2:]
    if not labels:
        return ""
    return labels[0].replace("-", " ").replace("_", " ").title()


def choose_name(source_title: str, site_title: str = "", url: str = "") -> str:
    """Pick the best available product name.

    The listing title is used when it actually names the product. When it only
    describes one ("Free scanning app with ML crops"), the product's own site
    is the authority — first its title, then failing that its domain. A
    truncated sentence is the worst of the options, so it is the last.
    """
    candidate = clean_title(source_title)
    if looks_like_a_name(candidate):
        return candidate

    site = clean_text(site_title)
    if site and looks_like_a_name(site):
        return site

    if url:
        from_domain = name_from_domain(url)
        if from_domain and looks_like_a_name(from_domain):
            return from_domain

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
    website_url = strip_tracking(website_url)

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
