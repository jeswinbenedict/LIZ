"""What Liz's browser checks share: where the app is, how to start a
browser, when a page is ready, and which real pages to visit.

The pages are discovered rather than written down, so the same checks run
against the live catalog (`flutter run --release` with the Supabase defines)
and against the bundled demo data in CI, where the tools are different.

Every page but sign-in, password help and the legal pages is behind sign-in.
The checks sign in once and reuse that session (Firebase keeps it in
IndexedDB, which Playwright carries over). A demo build accepts any
credentials; against the live backend set LIZ_EMAIL and LIZ_PASSWORD to a test
account — without them only the sign-in wall itself can be checked.
"""

from __future__ import annotations

import os
import pathlib
import re
import tempfile

BASE = os.environ.get("LIZ_URL", "http://localhost:8100").rstrip("/")
OUT = pathlib.Path(os.environ.get("LIZ_QA_OUT", tempfile.gettempdir())) / "liz-qa"
ENGINES = ("chromium", "msedge", "firefox", "webkit")

# Flutter fires this once the first frame is on screen; the sweep times it.
FIRST_FRAME_SCRIPT = """
window.__liz = {firstFrame: null};
window.addEventListener('flutter-first-frame', () => {
  window.__liz.firstFrame = performance.now();
});
"""


def launch(p, engine: str):
    """A browser for one of ENGINES. msedge is Chromium with Edge's build."""
    if engine == "msedge":
        return p.chromium.launch(channel="msedge")
    return getattr(p, engine).launch()


# Pages a signed-in visitor is moved off, so they are checked signed out.
SIGNED_OUT_ONLY = {"signin", "forgot", "reset"}
# Pages anyone may open.
PUBLIC = SIGNED_OUT_ONLY | {"privacy", "terms"}

DEMO_EMAIL = "qa@example.com"
DEMO_PASSWORD = "demo-password-1"


class NeedsAccount(RuntimeError):
    """Signing in failed: a live backend needs a real test account."""


# The clock the pages read. CI runs in UTC, and a page that groups by day
# (News) lays out differently at 3 a.m. in Kolkata than at 9 p.m. in UTC: a
# check that passed here once failed there. Same zone, same pages.
TIMEZONE = os.environ.get("LIZ_TZ", "UTC")


def new_page(browser, width: int = 1440, height: int = 900, state=None):
    ctx = browser.new_context(
        viewport={"width": width, "height": height},
        storage_state=state,
        timezone_id=TIMEZONE,
    )
    ctx.add_init_script(FIRST_FRAME_SCRIPT)
    return ctx, ctx.new_page()


def sign_in(browser) -> dict:
    """Signs in through the real form and returns the session to reuse."""
    email = os.environ.get("LIZ_EMAIL", DEMO_EMAIL)
    password = os.environ.get("LIZ_PASSWORD", DEMO_PASSWORD)
    ctx, page = new_page(browser)
    try:
        page.goto(BASE + "/signin")
        ready(page, settle_ms=1500)
        # A browser nobody has signed in on opens on "Create account".
        page.get_by_role("radio", name="Sign in").click()
        page.wait_for_timeout(800)  # the name field animates away
        page.get_by_role("textbox", name="Email").click()
        page.wait_for_timeout(400)  # WebKit attaches the text input a beat later
        page.keyboard.type(email)
        page.get_by_role("textbox", name="Password").click()
        page.wait_for_timeout(400)
        page.keyboard.type(password)
        page.keyboard.press("Enter")
        try:
            page.wait_for_url(lambda url: "/signin" not in url, timeout=20000)
        except Exception as e:  # noqa: BLE001 — explained below
            raise NeedsAccount(
                "could not sign in — against a live backend set LIZ_EMAIL and "
                "LIZ_PASSWORD to a test account"
            ) from e
        ready(page, settle_ms=1500)
        return ctx.storage_state(indexed_db=True)
    finally:
        ctx.close()


def ready(page, settle_ms: int = 3000) -> None:
    """Waits for the first frame, then for data to arrive."""
    page.wait_for_function(
        "window.__liz && window.__liz.firstFrame !== null", timeout=30000
    )
    page.wait_for_timeout(settle_ms)


def discover(browser, state: dict) -> dict[str, str]:
    """Real addresses to visit: two tools, one's alternatives, a comparison
    and a tool by id — taken from Discover and the compare picker."""
    ctx, page = new_page(browser, state=state)
    try:
        page.goto(BASE + "/")
        ready(page)
        slugs: list[str] = []
        for href in page.locator('a[href^="/tools/"]').evaluate_all(
            "els => els.map(e => e.getAttribute('href'))"
        ):
            if href not in slugs:
                slugs.append(href)
        if len(slugs) < 2:
            raise RuntimeError(f"Discover listed {len(slugs)} tool links; need two")
        tool, tool2 = slugs[0], slugs[1]

        page.goto(BASE + tool)
        ready(page)
        page.get_by_role("button", name="Compare").first.click()
        page.wait_for_timeout(2000)
        page.get_by_role("checkbox").first.click()
        page.get_by_role("button", name=re.compile(r"^Compare \d tools$")).click()
        page.wait_for_url(re.compile(r"/compare\?ids="), timeout=10000)
        compare = page.url.replace(BASE, "")
        first_id = compare.split("ids=")[1].split(",")[0]
        return {
            "tool": tool,
            "tool2": tool2,
            "alternatives": tool.replace("/tools/", "/alternatives/", 1),
            "compare": compare,
            "tool_by_id": f"/tool/{first_id}",
        }
    finally:
        ctx.close()


def routes(found: dict[str, str]) -> list[tuple[str, str]]:
    """Every page of the app, by name."""
    return [
        ("discover", "/"),
        ("news", "/news"),
        ("ask", "/ask"),
        ("saved", "/saved"),
        ("profile", "/profile"),
        ("settings", "/profile/settings"),
        ("tool", found["tool"]),
        ("tool-2", found["tool2"]),
        ("tool-by-id", found["tool_by_id"]),
        ("alternatives", found["alternatives"]),
        ("category", "/category/ai-audio"),
        ("search", "/search?q=voice"),
        ("compare", found["compare"]),
        ("alerts", "/alerts"),
        ("signin", "/signin"),
        ("forgot", "/forgot-password"),
        ("reset", "/reset-password"),
        ("privacy", "/privacy"),
        ("terms", "/terms"),
        ("admin", "/admin"),
        ("welcome", "/welcome"),
        ("notfound", "/no-such-page"),
    ]
