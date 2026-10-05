"""Loads every page at four widths and records what went wrong.

    python tool/qa/sweep.py chromium            # all pages, four widths
    python tool/qa/sweep.py firefox --key       # six key pages, desktop + phone

For each load: uncaught errors, failed requests (4xx/5xx), horizontal
overflow and time to first frame. Screenshots and a JSON report go to
$LIZ_QA_OUT/liz-qa (the system temp folder by default). Exits 1 if any page
threw or overflowed; a failed request is reported but does not fail the run,
since a tool with no logo is expected to 404.
"""

from __future__ import annotations

import json
import sys
import time

from common import BASE, OUT, SIGNED_OUT_ONLY, discover, launch, new_page, routes, sign_in
from playwright.sync_api import sync_playwright

WIDTHS = {"desktop": (1440, 900), "laptop": (1024, 700), "tablet": (834, 1112),
          "phone": (390, 844)}
KEY = {"discover", "tool", "search", "news", "signin", "compare"}
IGNORED = ("favicon", "chrome-extension://", "moz-extension://")


def visit(browser, name, path, size, engine, state):
    ctx, page = new_page(browser, *size, state=None if name in SIGNED_OUT_ONLY else state)
    errors, failed = [], []
    page.on("pageerror", lambda e: errors.append(str(e)[:300]))
    page.on("response", lambda r: failed.append(f"{r.status} {r.url.split('?')[0][-90:]}")
            if r.status >= 400 and not any(s in r.url for s in IGNORED) else None)
    start = time.time()
    page.goto(BASE + path, wait_until="load", timeout=60000)
    try:
        page.wait_for_function("window.__liz && window.__liz.firstFrame !== null",
                               timeout=30000)
    except Exception:  # noqa: BLE001 — a missing frame is the finding
        errors.append("no first frame within 30 s")
    page.wait_for_timeout(3000)
    first = page.evaluate("window.__liz ? window.__liz.firstFrame : null")
    page.screenshot(path=str(OUT / f"{engine}-{name}-{size[0]}.png"))
    overflow = page.evaluate("document.documentElement.scrollWidth > window.innerWidth + 1")
    ctx.close()
    return {"route": name, "path": path, "width": size[0],
            "first_frame_ms": round(first) if first else None,
            "load_s": round(time.time() - start, 1),
            "errors": errors, "failed": failed[:8], "overflow": overflow}


def main() -> int:
    engine = sys.argv[1] if len(sys.argv) > 1 else "chromium"
    key_only = "--key" in sys.argv
    OUT.mkdir(parents=True, exist_ok=True)
    results = []
    with sync_playwright() as p:
        browser = launch(p, engine)
        state = sign_in(browser)
        pages = [r for r in routes(discover(browser, state)) if not key_only or r[0] in KEY]
        widths = {k: v for k, v in WIDTHS.items() if not key_only or k in ("desktop", "phone")}
        for size in widths.values():
            for name, path in pages:
                r = visit(browser, name, path, size, engine, state)
                results.append(r)
                bad = r["errors"] or r["overflow"]
                print(("!! " if bad else "ok ") + f"{name:13} {size[0]:>4}px "
                      f"{r['first_frame_ms'] or '-':>5} ms"
                      + (f"  errors={r['errors']}" if r["errors"] else "")
                      + ("  OVERFLOW" if r["overflow"] else "")
                      + (f"  failed={r['failed']}" if r["failed"] else ""), flush=True)
        browser.close()
    (OUT / f"{engine}-sweep.json").write_text(json.dumps(results, indent=1))
    frames = sorted(r["first_frame_ms"] for r in results if r["first_frame_ms"])
    broken = [r for r in results if r["errors"] or r["overflow"]]
    print(f"\n{len(results)} loads, {len(broken)} broken; first frame median "
          f"{frames[len(frames) // 2] if frames else '-'} ms, max {frames[-1] if frames else '-'} ms")
    return 1 if broken else 0


if __name__ == "__main__":
    raise SystemExit(main())
