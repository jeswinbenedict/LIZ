"""discover → dedupe → enrich → upsert.

Kept separate from the CLI so n8n (or a test) can drive the same pipeline
without shelling out.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass

from .config import load_settings
from .enrich import enrich_url
from .http_client import PoliteSession
from .normalize import build_tool_row, choose_name, content_hash
from .sources import ALL_SOURCES
from .supabase_sink import SupabaseSink

log = logging.getLogger(__name__)


@dataclass
class RunResult:
    discovered: int = 0
    skipped_existing: int = 0
    enriched: int = 0
    written: int = 0
    rows: list[dict] | None = None


def run(
    *,
    sources: list[str] | None = None,
    limit: int = 30,
    dry_run: bool = False,
    status: str = "pending",
) -> RunResult:
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
        facts = enrich_url(session, candidate.url)
        if facts is not None:
            result.enriched += 1

        rows.append(
            build_tool_row(
                name=choose_name(candidate.name, facts.title if facts else ""),
                website_url=candidate.url,
                tagline=candidate.tagline or (facts.description if facts else ""),
                description=(facts.description if facts else candidate.tagline),
                logo_url=facts.logo_url if facts else None,
                category=facts.category if facts else None,
                platforms=facts.platforms if facts else ["web"],
                pricing_type=facts.pricing_type if facts else "unknown",
                source=candidate.source,
                source_url=candidate.url,
                status=status,
            )
        )

    result.rows = rows
    if sink is not None:
        result.written = sink.upsert_tools(rows)

    return result
