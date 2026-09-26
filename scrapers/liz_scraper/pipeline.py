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
from .normalize import build_tool_row, choose_name, content_hash
from .quality import assess
from .sources import ALL_SOURCES
from .supabase_sink import SupabaseSink

log = logging.getLogger(__name__)


@dataclass
class RunResult:
    discovered: int = 0
    skipped_existing: int = 0
    enriched: int = 0
    written: int = 0
    published: int = 0
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

    rows: list[dict] = []
    for candidate in candidates:
        # A listing URL is where the tool was found; follow it to where the
        # tool actually lives, so the facts describe the product.
        site_url, facts = resolve_and_enrich(session, candidate.url)
        if facts is not None:
            result.enriched += 1

        row = build_tool_row(
            name=choose_name(
                candidate.name,
                facts.title if facts else "",
                url=site_url,
            ),
            website_url=site_url,
            tagline=candidate.tagline or (facts.description if facts else ""),
            description=(facts.description if facts else candidate.tagline),
            logo_url=facts.logo_url if facts else None,
            category=facts.category if facts else None,
            platforms=facts.platforms if facts else ["web"],
            pricing_type=facts.pricing_type if facts else "unknown",
            source=candidate.source,
            source_url=candidate.url,
            status="pending",
        )

        # The gate reads the finished row rather than the candidate, so it
        # judges what a reader would actually get — including whether
        # enrichment managed to follow the listing through to the product.
        verdict = assess(row)
        row["status"] = status or verdict.status
        if row["status"] == "published":
            row["hold_reason"] = None
            result.published += 1
        else:
            reason = verdict.reasons[0] if verdict.reasons else "held"
            # Recorded on the row so the admin queue and the health check can
            # tell "held for a known reason" from "nobody has looked at this".
            row["hold_reason"] = reason
            result.held[reason] = result.held.get(reason, 0) + 1

        rows.append(row)

    result.rows = rows
    if sink is not None:
        result.written = sink.upsert_tools(rows)

    return result
