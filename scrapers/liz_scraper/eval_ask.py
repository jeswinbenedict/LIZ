"""Measure Ask Liz against a fixed set of questions with known answers.

    python -m liz_scraper.eval_ask                  # summary
    python -m liz_scraper.eval_ask --misses         # and every question it got wrong

Ask Liz's thresholds were first tuned on a handful of queries against a
160-tool catalog, and by September 2026 it answered nothing for two of three
everyday questions. This is the fixed yardstick for any change to retrieval:
run it before and after, and keep what moves the numbers.

What is measured:

- answered: questions with a right answer that got at least one result.
- hit@3 / hit@5: a right tool among the first three / five results.
- empty: questions with a right answer that got nothing at all.
- honest "none": questions nothing in the catalog answers, that got nothing.

Sends the evaluation key (ASK_EVAL_KEY, also set as a function secret), which
skips the public rate limit: 60 questions would otherwise take three hours.
"""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import sys

import requests

from .config import load_settings

QUESTIONS = pathlib.Path(__file__).resolve().parent.parent / "eval" / "ask_liz_questions.json"


def score(results: list[str], expect: list[str]) -> dict:
    wanted = {e.lower() for e in expect}
    names = [r.lower() for r in results]
    first_hit = next((i for i, n in enumerate(names) if n in wanted), None)
    return {
        "answerable": bool(expect),
        "returned": len(results),
        "hit3": first_hit is not None and first_hit < 3,
        "hit5": first_hit is not None and first_hit < 5,
    }


def summarize(rows: list[dict]) -> dict:
    answerable = [r for r in rows if r["answerable"]]
    unanswerable = [r for r in rows if not r["answerable"]]

    def pct(n: int, d: int) -> float:
        return round(100 * n / d, 1) if d else 0.0

    return {
        "questions": len(rows),
        "hit@3_pct": pct(sum(r["hit3"] for r in answerable), len(answerable)),
        "hit@5_pct": pct(sum(r["hit5"] for r in answerable), len(answerable)),
        "answered_pct": pct(sum(r["returned"] > 0 for r in answerable), len(answerable)),
        "empty_pct": pct(sum(r["returned"] == 0 for r in answerable), len(answerable)),
        "honest_none_pct": pct(sum(r["returned"] == 0 for r in unanswerable), len(unanswerable)),
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="liz_scraper.eval_ask")
    parser.add_argument("--misses", action="store_true", help="List every miss.")
    parser.add_argument("--limit", type=int, default=5)
    args = parser.parse_args(argv)

    settings = load_settings()
    if not settings.configured:
        print("error: SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set", file=sys.stderr)
        return 2
    url = f"{settings.supabase_url.rstrip('/')}/functions/v1/ask-liz"
    headers = {
        "Authorization": f"Bearer {settings.service_role_key}",
        "apikey": settings.service_role_key,
        "Content-Type": "application/json",
        "x-liz-eval": os.environ.get("ASK_EVAL_KEY", ""),
    }

    questions = json.loads(QUESTIONS.read_text(encoding="utf-8"))["questions"]
    rows = []
    session = requests.Session()
    for item in questions:
        resp = session.post(url, headers=headers,
                            json={"query": item["q"], "limit": args.limit}, timeout=60)
        if resp.status_code != 200:
            print(f"error: HTTP {resp.status_code} for {item['q']!r}: {resp.text[:200]}",
                  file=sys.stderr)
            return 1
        results = [r["name"] for r in (resp.json().get("data") or [])]
        row = score(results, item["expect"]) | {"q": item["q"], "got": results}
        rows.append(row)

    print(json.dumps(summarize(rows), indent=2))
    if args.misses:
        for r in rows:
            wrong = (r["answerable"] and not r["hit3"]) or (not r["answerable"] and r["returned"])
            if wrong:
                print(f"- {r['q']!r}: {r['got'][:5] or 'nothing'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
