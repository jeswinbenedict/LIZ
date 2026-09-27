"""Is this row fit to show a reader?

Ingestion writes everything it finds as `pending`, and the only way out was an
admin tapping each row. That did not scale: 423 tools piled up in sixteen days
while 194 were visible, and two thirds of what the pipeline found never reached
anyone.

The answer is not to publish everything — plenty of what arrives is genuinely
not a catalog entry. It is to write down what "good enough to show" means, once,
as something that can be argued with and tested, and let the pipeline apply it.

The bar is deliberately about *usefulness to a reader*, not completeness. A tool
with no logo still tells someone what it does; a tool whose Visit button goes
back to Product Hunt does not.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from urllib.parse import urlsplit

from .enrich import AGGREGATOR_HOSTS

# A name that is really a sentence, a headline, or a fragment of one. These
# come from feeds that put the whole announcement in the title.
_MAX_NAME_WORDS = 6
_MAX_NAME_CHARS = 60

# Below this a tagline says nothing: "AI tool", "New app".
_MIN_TAGLINE_CHARS = 15

# Hosts that are a page about a thing rather than the thing itself. Publishing
# one sends a reader to someone else's write-up instead of the product.
_WRITE_UP_HOSTS = {
    "medium.com",
    "substack.com",
    "dev.to",
    "reddit.com",
    "twitter.com",
    "x.com",
    "linkedin.com",
    "youtube.com",
    "youtu.be",
    "notion.site",
    "docs.google.com",
}


# Where a link is one person's conversation, generated page or file rather than
# a product. Launch posts link these often: "I built this with Claude" goes to
# the shared artifact. Published, one was listed as "Claude" and sat beside the
# real Claude; another was a PDF named after the host it was served from.
_SHARED_PATHS = {
    "claude.ai": ("/share/", "/artifact/", "/artifacts/", "/public/"),
    "chatgpt.com": ("/share/", "/c/"),
    "chat.openai.com": ("/share/", "/c/"),
    "gemini.google.com": ("/app/", "/share/", "/gem/"),
    "g.co": ("/gemini/",),
}
_FILE_HOSTS = {"raw.githubusercontent.com", "gist.github.com",
               "gist.githubusercontent.com"}
_FILE_SUFFIXES = (".pdf", ".zip", ".doc", ".docx", ".ppt", ".pptx", ".csv")


def _is_shared_content(website: str, host: str) -> bool:
    try:
        path = urlsplit(website).path.lower()
    except ValueError:
        return False
    if _matches(host, _FILE_HOSTS) or path.endswith(_FILE_SUFFIXES):
        return True
    prefixes = _SHARED_PATHS.get(host, ())
    return any(path.startswith(prefix) for prefix in prefixes)


@dataclass(frozen=True)
class Verdict:
    """Whether a row may be published, and why not when it may not."""

    publish: bool
    reasons: list[str] = field(default_factory=list)

    @property
    def status(self) -> str:
        return "published" if self.publish else "pending"


def _host(url: str) -> str:
    try:
        return urlsplit(url).netloc.lower().removeprefix("www.")
    except ValueError:
        return ""


def _matches(host: str, known: set[str]) -> bool:
    """Whether `host` is one of `known`, or a subdomain of one.

    Not a registrable-domain shortcut: `news.ycombinator.com` is three labels
    and truncating to the last two would compare `ycombinator.com` against a
    set that lists the full host, and miss. Matching on the suffix boundary
    also keeps `githubnext-clone.dev` from reading as GitHub.
    """
    return any(host == entry or host.endswith("." + entry) for entry in known)


def assess(row: dict) -> Verdict:
    """Decide whether `row` is fit to publish.

    Pure and side-effect free, so the same rule can run at ingest, over the
    existing backlog, and in a test.
    """
    reasons: list[str] = []

    name = (row.get("name") or "").strip()
    tagline = (row.get("tagline") or "").strip()
    description = (row.get("description") or "").strip()
    website = (row.get("website_url") or "").strip()

    if not name:
        reasons.append("no name")
    elif len(name) > _MAX_NAME_CHARS or len(name.split()) > _MAX_NAME_WORDS:
        # "Fugu Max and Fugu Ultra v2: Orchestrating the Pareto Frontier" is a
        # blog post title, not a product.
        reasons.append("name reads as a headline, not a product")

    if not website:
        reasons.append("no website")
    else:
        host = _host(website)
        if not host:
            reasons.append("website is not a usable URL")
        elif _matches(host, AGGREGATOR_HOSTS):
            # The single most important rule. Every Product Hunt row currently
            # in the backlog fails here: the scraper could not reach the product
            # page from a cloud IP, so website_url is still the listing. A
            # catalog of links back to another catalog is not a catalog.
            reasons.append(f"website is still the {host} listing, not the product")
        elif _matches(host, _WRITE_UP_HOSTS):
            reasons.append(f"website is a post on {host}, not a product")
        elif _is_shared_content(website, host):
            reasons.append(f"website is a shared chat or file on {host}, not a product")

    if not tagline:
        reasons.append("no tagline")
    elif len(tagline) < _MIN_TAGLINE_CHARS:
        reasons.append("tagline too short to say anything")

    if not description:
        reasons.append("no description")

    return Verdict(publish=not reasons, reasons=reasons)


def summarise(rows: list[dict]) -> dict[str, int]:
    """Count why a batch was held back, for a run log or a health signal."""
    counts: dict[str, int] = {}
    for row in rows:
        verdict = assess(row)
        if verdict.publish:
            counts["published"] = counts.get("published", 0) + 1
            continue
        # Attribute a held row to its first reason so the totals add up to the
        # number of rows rather than the number of problems.
        key = verdict.reasons[0]
        counts[key] = counts.get(key, 0) + 1
    return counts
