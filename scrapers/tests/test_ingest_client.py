"""The laptop holds LIZ_INGEST_KEY, not the service key.

With it set, every read and write the scraper makes must go to the
scraper-ingest function — never to PostgREST, which that key cannot open.
"""

import pytest
import requests
from liz_scraper import retry_held
from liz_scraper.config import Settings
from liz_scraper.ingest_client import IngestClient
from liz_scraper.supabase_sink import SupabaseSink

URL = "https://x.supabase.co"


class FakeResponse:
    def __init__(self, status, body):
        self.status_code = status
        self._body = body
        self.text = str(body)

    def json(self):
        return self._body


class FakeSession:
    """Records requests; answers scraper-ingest calls from `answers`."""

    def __init__(self, answers=None, status=200):
        self.calls = []
        self.answers = answers or {}
        self.status = status

    def post(self, url, headers=None, json=None, **_):
        self.calls.append((url, headers, json))
        data = self.answers.get(json["action"])
        return FakeResponse(self.status, {"data": data, "error": None if self.status < 400 else "no"})

    def get(self, *a, **k):  # PostgREST — must not be reached
        raise AssertionError("PostgREST used with an ingest key")

    patch = get


def _ingest_settings():
    return Settings(supabase_url=URL, service_role_key="", ingest_key="i" * 48)


def test_either_key_lets_the_scraper_run_but_only_the_service_key_runs_jobs():
    assert Settings(URL, "service").can_scrape
    assert _ingest_settings().can_scrape
    assert not Settings(URL, "").can_scrape
    assert Settings(URL, "service").configured
    assert not _ingest_settings().configured
    assert not Settings(URL, "service").uses_ingest


def test_the_ingest_key_wins_when_both_are_present():
    assert Settings(URL, "service", ingest_key="i" * 48).uses_ingest


def test_calls_carry_the_key_in_its_own_header_and_go_to_the_function():
    session = FakeSession({"existing": {"published": ["a"], "sites": {}}})
    assert IngestClient(_ingest_settings(), session).published(["a", "b"]) == {"a"}
    url, headers, body = session.calls[0]
    assert url == f"{URL}/functions/v1/scraper-ingest"
    assert headers["x-liz-ingest"] == "i" * 48
    assert "Authorization" not in headers and "apikey" not in headers
    assert body == {"action": "existing", "hashes": ["a", "b"]}


def test_a_refusal_raises_like_a_failed_postgrest_call():
    client = IngestClient(_ingest_settings(), FakeSession(status=401))
    with pytest.raises(requests.RequestException):
        client.upsert([{"content_hash": "x"}])


def test_the_sink_reads_and_writes_through_the_function():
    sink = SupabaseSink(_ingest_settings())
    session = FakeSession({
        "existing": {"published": ["h1"], "sites": {"example.com": "h1"}},
        "upsert": {"written": 1, "refused": []},
    })
    sink._session = session
    sink._ingest = IngestClient(sink.settings, session)

    assert sink.existing_hashes(["h1", "h2"]) == {"h1"}
    assert sink.existing_sites(["example.com"]) == {"example.com": "h1"}
    assert sink.upsert_tools([{"name": "T", "slug": "t", "content_hash": "h2"}]) == 1
    assert [c[2]["action"] for c in session.calls] == ["existing", "existing", "upsert"]


def test_held_rows_are_fetched_through_the_function():
    session = FakeSession({"held": [{"id": "1"}]})
    rows = retry_held.fetch_held(_ingest_settings(), session, 10)
    assert rows == [{"id": "1"}]
    assert session.calls[0][2] == {
        "action": "held", "marker": retry_held._LISTING_MARKER, "limit": 10,
    }
