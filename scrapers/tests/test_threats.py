"""Screening sites against the malware and phishing lists.

Until October 2026 the check read abuse.ch's URLhaus hostfile. That download
started answering 410 Gone, the check failed open as designed, and nothing was
screened — with no sign anywhere. These pin the two lists it reads now, that a
list which cannot be read is named rather than ignored, and that a new tool
on either list is held with a reason saying which.
"""

from __future__ import annotations

import requests
from liz_scraper import pipeline, threats
from liz_scraper.enrich import PageFacts


def _domains(*hosts: str, filler: int = threats.MIN_ENTRIES) -> str:
    body = [f"filler{i}.example" for i in range(filler)]
    return "# Title: test list\n" + "\n".join([*hosts, *body]) + "\n"


class _Resp:
    def __init__(self, text: str = "", status: int = 200):
        self.text = text
        self.status_code = status

    def raise_for_status(self):
        if self.status_code >= 400:
            raise requests.HTTPError(f"{self.status_code}")


class _Session:
    """Answers each list's URL from a dict; anything else is a 404."""

    def __init__(self, answers: dict[str, _Resp]):
        self.answers = answers

    def get(self, url, **_):
        return self.answers.get(url, _Resp(status=404))


MALWARE, PHISHING = threats.LISTS


def test_both_formats_parse_and_comments_are_skipped():
    text = "# comment\nbad.example\n0.0.0.0 worse.example\n\nWWW.Upper.Example.\n"
    assert threats.parse_domains(text) == {
        "bad.example", "worse.example", "www.upper.example"
    }


def test_both_lists_are_read_and_each_names_its_own_reason():
    session = _Session({
        MALWARE.url: _Resp(_domains("malware.example")),
        PHISHING.url: _Resp(_domains("login-bank.example")),
    })
    fetched = threats.fetch_lists(session)
    assert fetched.missing == []
    assert threats.reason_for("https://malware.example/app", fetched) == MALWARE.reason
    assert "phishing" in threats.reason_for("https://x.login-bank.example", fetched)
    assert threats.reason_for("https://fine.example", fetched) is None


def test_a_gone_or_broken_list_is_named_not_silently_empty():
    session = _Session({
        MALWARE.url: _Resp(status=410),
        PHISHING.url: _Resp("only.example\n"),  # an error page, not a list
    })
    fetched = threats.fetch_lists(session)
    assert fetched.hosts == {}
    assert fetched.missing == ["malware", "phishing"]


def test_the_daily_check_fails_when_no_list_could_be_read(monkeypatch, capsys):
    monkeypatch.setenv("SUPABASE_URL", "https://x.supabase.co")
    monkeypatch.setenv("SUPABASE_SERVICE_ROLE_KEY", "key")
    monkeypatch.setattr(threats, "fetch_lists",
                        lambda: threats.Fetched(missing=["malware", "phishing"]))
    assert threats.main([]) == 1
    assert "nothing was screened" in capsys.readouterr().err


def test_a_new_tool_on_the_phishing_list_is_held_with_that_reason(monkeypatch):
    class _Candidate:
        name = "Totally Real"
        url = "https://totally-real.example"
        tagline = "Agents that do your taxes while you sleep, safely and fast"
        source = "hackernews"

    facts = PageFacts(
        title="Totally Real",
        description="Agents that do your taxes while you sleep, safely and fast.",
        logo_url="https://totally-real.example/logo.png",
    )

    class _Sink:
        def __init__(self, _settings):
            self.written = []

        def existing_hashes(self, _hashes):
            return set()

        def existing_sites(self, _keys):
            return {}

        def upsert_tools(self, rows):
            self.written.extend(rows)
            return len(rows)

    monkeypatch.setattr(pipeline, "ALL_SOURCES", {"fake": lambda s, limit: [_Candidate()]})
    monkeypatch.setattr(pipeline, "resolve_and_enrich", lambda s, url: (url, facts))
    monkeypatch.setattr(pipeline, "SupabaseSink", _Sink)
    monkeypatch.setattr(
        pipeline,
        "fetch_threat_lists",
        lambda: threats.Fetched(hosts={"phishing": {"totally-real.example"}}),
    )

    row = pipeline.run(sources=["fake"]).rows[0]
    assert row["status"] == "pending"
    assert row["hold_reason"] == PHISHING.reason
