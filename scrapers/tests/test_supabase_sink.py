"""The sink's job is to not lose a run.

A scheduled scrape once wrote 0 of 34 rows because a single name collision made
PostgREST reject the whole batch: `slug` is unique, and a new product reusing a
stored product's name violates it even though the upsert conflicts on
content_hash.
"""

import pytest

from liz_scraper.config import Settings
from liz_scraper.supabase_sink import SupabaseSink


@pytest.fixture
def sink():
    return SupabaseSink(Settings(supabase_url="https://x.supabase.co", service_role_key="k"))


def _rows(n):
    return [
        {"name": f"Tool {i}", "slug": f"tool-{i}", "content_hash": f"{i:064x}"}
        for i in range(n)
    ]


def test_writes_every_row_when_the_batch_succeeds(sink, monkeypatch):
    monkeypatch.setattr(sink, "_post", lambda rows: (True, ""))
    assert sink.upsert_tools(_rows(5)) == 5


def test_one_bad_row_no_longer_discards_the_whole_batch(sink, monkeypatch):
    rows = _rows(4)
    bad_slug = rows[2]["slug"]

    def fake_post(chunk):
        if len(chunk) > 1:
            return False, "409 Client Error: Conflict"
        # The collision is on slug, so only the original spelling fails.
        if chunk[0]["slug"] == bad_slug:
            return False, "409 Client Error: Conflict"
        return True, ""

    monkeypatch.setattr(sink, "_post", fake_post)
    # 3 write directly; the 4th succeeds once its slug is disambiguated.
    assert sink.upsert_tools(rows) == 4


def test_a_colliding_slug_is_retried_with_a_deterministic_suffix(sink):
    row = {"name": "Scriptly", "slug": "scriptly", "content_hash": "abcdef1234567890"}
    first = SupabaseSink._disambiguate(row)
    second = SupabaseSink._disambiguate(row)

    assert first["slug"] == "scriptly-abcdef"
    # Re-running must reuse the slug, not invent a new row each time.
    assert first["slug"] == second["slug"]
    assert row["slug"] == "scriptly", "the original row must not be mutated"


def test_disambiguation_keeps_the_slug_within_the_column_limit(sink):
    row = {"name": "x", "slug": "a" * 80, "content_hash": "f" * 64}
    assert len(SupabaseSink._disambiguate(row)["slug"]) <= 60


def test_a_row_that_fails_even_when_disambiguated_is_counted_as_lost(sink, monkeypatch):
    monkeypatch.setattr(sink, "_post", lambda rows: (False, "500 Server Error"))
    assert sink.upsert_tools(_rows(3)) == 0


def test_empty_input_is_a_no_op(sink):
    assert sink.upsert_tools([]) == 0


def test_credentials_are_required():
    with pytest.raises(ValueError):
        SupabaseSink(Settings(supabase_url="", service_role_key=""))
