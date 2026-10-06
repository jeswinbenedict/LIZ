"""Walks through Liz the way a visitor does, and checks each step landed.

    python tool/qa/journeys.py chromium
    python tool/qa/journeys.py webkit --phone
    python tool/qa/journeys.py chromium --only search

Elements are found by role and name — "the link called Number 1" — as a
screen reader finds them, so a journey also fails when a control is unnamed
or announced as the wrong thing. Exits 1 if any journey fails; a screenshot
of the failure goes to $LIZ_QA_OUT/liz-qa.

Two waits are deliberate, learned from false failures: after switching the
sign-in form's mode (its fields animate) and after focusing a text field
(WebKit attaches Flutter's hidden input a beat later and drops keys typed
before it).
"""

from __future__ import annotations

import re
import sys

from common import BASE, OUT, NeedsAccount, discover, launch, new_page, ready, sign_in
from playwright.sync_api import expect, sync_playwright

JOURNEYS = []
# Journeys about the sign-in page itself run signed out.
SIGNED_OUT = set()


def journey(fn):
    JOURNEYS.append(fn)
    return fn


def signed_out(fn):
    SIGNED_OUT.add(fn.__name__)
    return fn


@journey
@signed_out
def sign_in_wall(page, found):
    # Straight to a tool page without signing in: the wall sends you to sign
    # in, remembering where you were going.
    page.goto(BASE + "/tools/anything")
    ready(page, settle_ms=1500)
    # The browser may show the address with or without its slashes escaped.
    page.wait_for_url(re.compile(r"/signin\?from=(%2F|/)tools(%2F|/)anything"), timeout=10000)
    # A fresh browser is a new visitor: the form opens on "Create account".
    expect(page.get_by_role("heading", name="Create your account")).to_be_visible()
    # The legal pages stay open.
    page.goto(BASE + "/privacy")
    ready(page, settle_ms=1000)
    assert page.url.endswith("/privacy"), page.url
    return "signed-out visit goes to sign-in; legal pages open"


def first_mover(page):
    return page.get_by_role("link", name=re.compile(r"^Number 1,"))


@journey
def movers_filter(page, found):
    page.goto(BASE + "/")
    ready(page)
    page.get_by_role("button", name="Show Agents movers").click()
    page.wait_for_timeout(2500)
    empty = page.get_by_text("Nothing of this kind is rising this week.").count()
    assert empty or first_mover(page).count(), "neither movers nor the empty message"
    page.get_by_role("button", name="Show All movers").click()
    page.wait_for_timeout(2000)
    assert first_mover(page).count(), "All shows no movers"
    return "rows" if not empty else "empty state"


@journey
def mover_opens_tool(page, found):
    page.goto(BASE + "/")
    ready(page)
    first_mover(page).first.click()
    page.wait_for_url(re.compile(r"/tools/"), timeout=15000)
    page.wait_for_timeout(2000)
    expect(page.get_by_role("link", name="Visit website")).to_be_visible()
    path = page.url.replace(BASE, "")
    # The address survives a reload, and Back returns to Discover.
    page.reload()
    ready(page)
    expect(page.get_by_role("link", name="Visit website")).to_be_visible()
    page.go_back()
    page.wait_for_timeout(2500)
    assert page.url.rstrip("/") == BASE, page.url
    return f"{path}, survives reload, Back works"


@journey
def search(page, found):
    page.goto(BASE + "/search")
    ready(page)
    page.keyboard.type("voice")
    page.wait_for_timeout(3000)
    return page.get_by_text(re.compile(r"^\d+ tools?$")).first.inner_text()


@journey
def cmd_k_opens_search(page, found):
    page.goto(BASE + "/")
    ready(page)
    page.keyboard.press("Control+k")
    page.wait_for_url(re.compile(r"/search"), timeout=10000)
    return "ok"


@journey
def ask_liz(page, found):
    page.goto(BASE + "/ask")
    ready(page)
    page.get_by_role("textbox").first.click()
    page.wait_for_timeout(400)
    page.keyboard.type("turn a podcast into short clips")
    page.keyboard.press("Enter")
    page.wait_for_timeout(9000)
    assert "went wrong" not in page.locator("body").inner_text().lower(), "error shown"
    return "answered"


@journey
def compare_from_tool(page, found):
    page.goto(BASE + found["tool"])
    ready(page)
    page.get_by_role("button", name="Compare").first.click()
    page.wait_for_timeout(2000)
    page.get_by_role("checkbox").first.click()
    page.get_by_role("button", name=re.compile(r"^Compare \d tools$")).click()
    page.wait_for_url(re.compile(r"/compare\?ids="), timeout=10000)
    return page.url.replace(BASE, "")


@journey
def save_tool(page, found):
    # Into a tool from Discover and back out through the app, not by reloading
    # the page: a demo build keeps saves in memory, as a live one does not.
    page.goto(BASE + "/")
    ready(page)
    first_mover(page).first.click()
    page.wait_for_url(re.compile(r"/tools/"), timeout=15000)
    page.wait_for_timeout(2000)
    name = page.get_by_role("heading", level=1).first.inner_text()
    # Read the state from the button's name, not its text: on a phone the
    # button is an icon.
    saved = page.get_by_role("button", name="Saved", exact=True)
    if saved.count():  # saved on an earlier run
        saved.first.click()
        page.wait_for_timeout(1500)
    page.get_by_role("button", name="Save").first.click()
    expect(page.get_by_role("button", name="Saved").first).to_be_visible(timeout=5000)
    page.get_by_role("button", name="Back").first.click()
    page.wait_for_timeout(1500)
    # The sidebar's Saved is a button; a phone's bottom bar makes it a tab.
    page.get_by_role("button", name="Saved", exact=True).or_(
        page.get_by_role("tab", name=re.compile(r"^Saved"))
    ).first.click()
    page.wait_for_url(re.compile(r"/saved"), timeout=10000)
    page.wait_for_timeout(2000)
    expect(page.get_by_text(name).first).to_be_visible(timeout=8000)
    return f"saved and listed {name}"


@journey
@signed_out
def signin_validation(page, found):
    page.goto(BASE + "/signin")
    ready(page)
    page.get_by_role("radio", name="Create account").click()
    page.wait_for_timeout(800)  # the name field animates in
    expect(page.get_by_role("heading", name="Create your account")).to_be_visible()
    expect(page.get_by_role("radio", name="Create account")).to_be_checked()
    page.get_by_role("button", name="Create account").click()
    expect(page.get_by_text("Enter a display name so people know who you are.")
           .filter(visible=True).first).to_be_visible(timeout=4000)
    page.get_by_role("radio", name="Sign in").click()
    page.wait_for_timeout(800)  # the name field animates away
    page.get_by_role("textbox", name="Email").click()
    page.wait_for_timeout(400)
    page.keyboard.type("not-an-email")
    page.get_by_role("textbox", name="Password").click()
    page.wait_for_timeout(400)
    page.keyboard.type("x")
    page.keyboard.press("Enter")  # Enter on the password field submits
    expect(page.get_by_text("That email address doesn't look right.")
           .filter(visible=True).first).to_be_visible(timeout=4000)
    return "validation and Enter-to-submit work"


@journey
@signed_out
def forgot_password_carries_email(page, found):
    page.goto(BASE + "/signin")
    ready(page)
    # The reset link lives on the Sign in tab; a new visitor starts on the other.
    page.get_by_role("radio", name="Sign in").click()
    page.wait_for_timeout(800)
    page.get_by_role("textbox", name="Email").click()
    page.wait_for_timeout(400)
    page.keyboard.type("me@example.com")
    page.get_by_role("button", name="Forgot your password?").click()
    page.wait_for_url(re.compile(r"/forgot-password\?email=me%40example\.com|"
                                 r"/forgot-password\?email=me@example\.com"), timeout=10000)
    return page.url.replace(BASE, "")


@journey
def notfound_recovers(page, found):
    page.goto(BASE + "/definitely/not/here")
    ready(page)
    expect(page.get_by_role("heading", name="This page is not here")).to_be_visible()
    page.get_by_role("button", name="Go to Discover").click()
    page.wait_for_timeout(2000)
    assert page.url.rstrip("/") == BASE, page.url
    return "back to Discover"


@journey
def news_links(page, found):
    page.goto(BASE + "/news")
    ready(page)
    links = page.get_by_role("link").count()
    shares = page.get_by_role("button", name="Share").count()
    # A phone shows two or three stories; the list builds only what is on
    # screen, and the last one's Share button may sit just below the fold.
    assert links >= 2 and shares >= 2, (links, shares)
    return f"{links} story links, {shares} share buttons"


@journey
def keyboard_only(page, found):
    page.goto(BASE + "/")
    ready(page)
    for i in range(60):
        page.keyboard.press("Tab")
        page.wait_for_timeout(120)
        label = page.evaluate(
            "(() => { const e = document.activeElement;"
            " return e ? (e.getAttribute('aria-label') || e.textContent || '').slice(0, 60)"
            " : ''; })()")
        if label.startswith("Number 1,"):
            page.keyboard.press("Enter")
            page.wait_for_url(re.compile(r"/tools/"), timeout=10000)
            return f"first mover after {i + 1} tabs; Enter opened it"
    raise AssertionError("never reached the first mover by Tab")


@journey
def category_page(page, found):
    page.goto(BASE + "/category/ai-audio")
    ready(page)
    expect(page.get_by_role("heading", name="Audio", level=1)).to_be_visible()
    assert "Audio" in page.title(), page.title()
    return page.title()


def main() -> int:
    engine = next((a for a in sys.argv[1:] if not a.startswith("-")), "chromium")
    size = (390, 844) if "--phone" in sys.argv else (1440, 900)
    only = sys.argv[sys.argv.index("--only") + 1] if "--only" in sys.argv else None
    OUT.mkdir(parents=True, exist_ok=True)
    results = []
    with sync_playwright() as p:
        browser = launch(p, engine)
        try:
            state = sign_in(browser)
            found = discover(browser, state)
        except NeedsAccount as e:
            # No account for this backend: check the wall and the sign-in page.
            print(f"note: {e}; running the signed-out journeys only")
            state, found = None, {}
        for fn in JOURNEYS:
            name = fn.__name__
            if only and only not in name:
                continue
            guest = name in SIGNED_OUT
            if state is None and not guest:
                continue
            ctx, page = new_page(browser, *size, state=None if guest else state)
            errors = []
            page.on("pageerror", lambda e, errors=errors: errors.append(str(e)[:200]))
            try:
                detail = fn(page, found) or ""
                ok = not errors
                results.append((name, ok, detail if ok else f"{detail}; page errors {errors}"))
            except Exception as e:  # noqa: BLE001 — every failure is reported
                page.screenshot(path=str(OUT / f"journey-{engine}-{size[0]}-{name}.png"))
                results.append((name, False, f"{type(e).__name__}: {str(e)[:400]}"))
            ctx.close()
        browser.close()
    for name, ok, detail in results:
        print(("PASS " if ok else "FAIL ") + f"{name}: {detail}")
    passed = sum(ok for _, ok, _ in results)
    print(f"{passed}/{len(results)} journeys passed ({engine}, {size[0]}px)")
    return 0 if passed == len(results) else 1


if __name__ == "__main__":
    raise SystemExit(main())
