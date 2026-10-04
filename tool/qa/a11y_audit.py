"""Reads every page's accessibility tree — what a screen reader is given —
and flags what its user would trip over.

    python tool/qa/a11y_audit.py            # desktop
    python tool/qa/a11y_audit.py --phone

Flutter draws on a canvas, so this tree is the only page a screen reader
sees. Checked on every page: a level-1 heading exists; no control lacks a
name; no name repeats itself ("Dismiss Dismiss") or doubles a full stop;
headings are short; every link has an address. Exits 1 on any finding.
"""

from __future__ import annotations

import re
import sys

from common import BASE, discover, launch, new_page, ready, routes
from playwright.sync_api import sync_playwright

NAMED = re.compile(r'^\s*- (\w+)(?: "((?:[^"\\]|\\.)*)")?(.*)$')
CONTROLS = {"button", "link", "textbox", "checkbox", "radio", "tab", "slider",
            "switch", "combobox"}


def audit(snapshot: str) -> list[str]:
    problems = []
    lines = snapshot.splitlines()
    has_h1 = False
    for i, line in enumerate(lines):
        # Entries holding a quote are wrapped whole in single quotes.
        m = NAMED.match(line.replace("- '", "- ").rstrip("'"))
        if not m:
            continue
        role, name, rest = m.groups()
        if role == "heading":
            has_h1 = has_h1 or "[level=1]" in rest
            if name and len(name) > 80:
                problems.append(f"heading too long ({len(name)}): {name[:60]}…")
        if role in CONTROLS and not name:
            problems.append(f"{role} with no name (line {i + 1})")
        if name:
            words = name.split()
            half = len(words) // 2
            if half and words[:half] == words[half:]:
                problems.append(f'{role} name repeats itself: "{name}"')
            # Two full stops, not part of an ellipsis ("...").
            if re.search(r"(?<!\.)\.\.(?!\.)", name):
                problems.append(f'{role} name has "..": {name[:60]}')
        if role == "link" and "/url:" not in (lines[i + 1] if i + 1 < len(lines) else ""):
            problems.append(f"link without an address: {(name or '')[:50]}")
    if not has_h1:
        problems.append("no level-1 heading")
    return problems


def main() -> int:
    size = (390, 844) if "--phone" in sys.argv else (1440, 900)
    total = 0
    with sync_playwright() as p:
        browser = launch(p, "chromium")
        for name, path in routes(discover(browser)):
            ctx, page = new_page(browser, *size)
            page.goto(BASE + path)
            ready(page)
            problems = sorted(set(audit(page.locator("body").aria_snapshot())))
            total += len(problems)
            print(("ok  " if not problems else "!!  ") + f"{name:13} {path}")
            for pr in problems:
                print("      - " + pr)
            ctx.close()
        browser.close()
    print(f"{total} findings ({size[0]}px)")
    return 1 if total else 0


if __name__ == "__main__":
    raise SystemExit(main())
