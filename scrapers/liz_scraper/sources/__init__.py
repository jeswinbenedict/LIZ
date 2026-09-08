"""Discovery sources — each returns raw candidates for the enrichment stage."""

from .hackernews import discover as discover_hackernews
from .producthunt import discover as discover_producthunt

__all__ = ["discover_hackernews", "discover_producthunt", "ALL_SOURCES"]

ALL_SOURCES = {
    "producthunt": discover_producthunt,
    "hackernews": discover_hackernews,
}
