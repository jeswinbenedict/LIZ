"""discover → dedupe → enrich → upsert.

Kept separate from the CLI so n8n (or a test) can drive the same pipeline
without shelling out.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass, field

from .config import load_settings
from .enrich import resolve_and_enrich
from .http_client import PoliteSession
from .normalize import (
    build_tool_row,
    choose_name,
    choose_tagline,
    content_hash,
    site_key,
    strip_name_prefix,
)
from .quality import assess
from .sources import ALL_SOURCES
from .supabase_sink import SupabaseSink
from .threats import Fetched as ThreatLists
from .threats import fetch_lists as fetch_threat_lists
from .threats import reason_for as threat_reason_for

log = logging.getLogger(__name__)


@dataclass
class RunResult:
    discovered: int = 0
    skipped_existing: int = 0
    enriched: int = 0
    written: int = 0
    published: int = 0
    # Already in the catalog under another listing URL (site_key).
    duplicates: int = 0
    held: dict[str, int] = field(default_factory=dict)
    rows: list[dict] | None = None


def run(
    *,
    sources: list[str] | None = None,
    limit: int = 30,
    dry_run: bool = False,
    status: str | None = None,
) -> RunResult:
    """Run the pipeline.

    `status` forces every row to one status; leaving it None lets the quality
    gate decide per row, which is what a scheduled run wants.
    """
    session = PoliteSession()
    selected = sources or list(ALL_SOURCES)

    candidates = []
    for name in selected:
        discover = ALL_SOURCES.get(name)
        if discover is None:
            log.warning("unknown source: %s", name)
            continue
        candidates.extend(discover(session, limit=limit))

    result = RunResult(discovered=len(candidates))
    if not candidates:
        result.rows = []
        return result

    sink = None if dry_run else SupabaseSink(load_settings())

    # Skip anything already stored before spending requests on enrichment.
    if sink is not None:
        known = sink.existing_hashes([content_hash(c.url) for c in candidates])
        before = len(candidates)
        candidates = [c for c in candidates if content_hash(c.url) not in known]
        result.skipped_existing = before - len(candidates)

    # Hosts serving malware or phishing (liz_scraper.threats). Only on real
    # runs: a dry run should not depend on the network beyond the sources
    # themselves.
    threats = fetch_threat_lists() if sink is not None else ThreatLists()

    rows: list[dict] = []
    for candidate in candidates:
        # A listing URL is where the tool was found; follow it to where the
        # tool actually lives, so the facts describe the product.
        site_url, facts = resolve_and_enrich(session, candidate.url)
        if facts is not None:
            result.enriched += 1

        name = choose_name(
            candidate.name,
            facts.title if facts else "",
            url=site_url,
        )
        tagline = choose_tagline(
            candidate.tagline, facts.description if facts else ""
        ) or (facts.description if facts else "")
        row = build_tool_row(
            name=name,
            website_url=site_url,
            tagline=strip_name_prefix(tagline, name),
            description=(facts.description if facts else candidate.tagline),
            logo_url=facts.logo_url if facts else None,
            category=facts.category if facts else None,
            platforms=facts.platforms if facts else ["web"],
            pricing_type=facts.pricing_type if facts else "unknown",
            source=candidate.source,
            source_url=candidate.url,
            status="pending",
        )

        # The story a tool launched with, so its points can be read daily
        # (liz_scraper.signals). Every row carries both keys: PostgREST
        # rejects a batch whose rows have different columns.
        row["hn_id"] = getattr(candidate, "external_id", None)
        row["hn_points"] = getattr(candidate, "points", None)
        # The product's preview image for its page (migration 0045).
        row["image_url"] = facts.image_url if facts else None

        # The gate reads the finished row rather than the candidate, so it
        # judges what a reader would actually get — including whether
        # enrichment managed to follow the listing through to the product.
        verdict = assess(row)
        row["status"] = status or verdict.status
        # No override publishes a site known to serve malware or phish.
        threat = threat_reason_for(row["website_url"], threats)
        if threat is not None:
            row["status"] = "pending"
            verdict.reasons.insert(0, threat)
        if row["status"] == "published":
            row["hold_reason"] = None
            result.published += 1
        else:
            # A row can be pending while having passed the gate, when --status
            # forced it. Recording that as "held" made it look like a real hold
            # and hid it from the unexplained-backlog signal, so say what
            # actually happened.
            reason = (
                verdict.reasons[0]
                if verdict.reasons
                else "passed the quality gate; held by --status override"
            )
            # Recorded on the row so the admin queue and the health check can
            # tell "held for a known reason" from "nobody has looked at this".
            row["hold_reason"] = reason
            result.held[reason] = result.held.get(reason, 0) + 1

        rows.append(row)

    if sink is not None:
        # Same product, different listing URL: the content hash differs but the
        # site does not. Writing it would publish a second copy (migration 0049).
        published = sink.existing_sites([site_key(r["website_url"]) for r in rows])
        fresh = [r for r in rows
                 if published.get(site_key(r["website_url"]), r["content_hash"])
                 == r["content_hash"]]
        result.duplicates = len(rows) - len(fresh)
        rows = fresh

    result.rows = rows
    if sink is not None:
        result.written = sink.upsert_tools(rows)

    return result
