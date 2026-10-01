"""Give every tool and category a page a search engine can read.

    python -m liz_scraper.prerender --build ../build/web --site https://liz.pages.dev

Liz draws itself on a canvas, so the HTML a crawler or a link preview fetches
is the same empty shell for every address: no title, no description, no text.
This writes one HTML file per tool (`tools/<slug>.html`, served at
`/tools/<slug>`) and per category, each a copy of the built index.html with:

- its own <title>, description, canonical link and Open Graph / Twitter tags,
  so a shared link previews the tool rather than "Liz";
- JSON-LD (schema.org SoftwareApplication) with facts Liz actually holds —
  no rating unless people have rated it;
- the page's content as plain HTML: name, tagline, summary, description,
  price, and links to the site, its category and related pages, so the
  catalog can be crawled link by link.

The app then starts exactly as it would at any other address. Until it has
drawn, the HTML content is shown as a plain page — a reader on a slow phone
gets the tool's name and description at once instead of a logo — and then it
is visually hidden and hidden from screen readers, so nothing is shown or
read twice. It is the same text the app shows: a page summary, not cloaking.

Also writes a badge per tool (`badge/<slug>.svg`, and `-dark.svg`) that its
maker can embed, sitemap.xml and robots.txt. Reads only published rows, with the
public anon key: SUPABASE_URL and SUPABASE_ANON_KEY.
"""

from __future__ import annotations

import argparse
import html
import json
import os
import pathlib
import re
import sys
from datetime import UTC, datetime
from urllib.parse import quote

import requests

from .config import REQUEST_TIMEOUT

TOOL_COLUMNS = (
    "id,name,slug,tagline,description,ai_summary,category,pricing_type,"
    "price_note,website_url,gh_repo,gh_stars,hn_id,hn_points,trend_reason,"
    "avg_rating,rating_count,created_at,updated_at,image_url,momentum"
)

PRICING_LABEL = {"free": "Free", "freemium": "Freemium", "paid": "Paid"}

# The page's content, shown as a plain readable page while the app loads —
# on a slow phone that is several seconds in which a visitor reads the tool
# instead of watching a logo. It replaces the splash image on these pages, and
# once the app has drawn its first frame it becomes visually hidden (still in
# the document for crawlers) and hidden from screen readers, so nothing is
# shown or read twice. Colours follow the app's own surfaces (docs/DESIGN.md).
_PAGE_STYLE = """<style id="liz-page-style">
    #liz-page ~ #splash { display: none; }
    #liz-page { box-sizing: border-box; max-width: 760px; margin: 0 auto;
      padding: 24px 20px 48px; color: #1C1B22; background: #FAF9FD;
      font: 16px/1.55 Inter, -apple-system, "Segoe UI", system-ui, sans-serif; }
    #liz-page nav a { color: #1C1B22; font-weight: 700; font-size: 20px;
      text-decoration: none; }
    #liz-page h1 { font-size: 30px; line-height: 1.15; margin: 28px 0 6px; }
    #liz-page h2 { font-size: 20px; margin: 28px 0 8px; }
    #liz-page p, #liz-page li { color: #4A4857; }
    #liz-page a { color: #4F4DC9; }
    #liz-page ul { padding-left: 20px; }
    #liz-page .liz-loading { margin-top: 32px; font-size: 14px; color: #6E6C7B; }
    @media (prefers-color-scheme: dark) {
      #liz-page { color: #ECEBF2; background: #131318; }
      #liz-page nav a { color: #ECEBF2; }
      #liz-page p, #liz-page li { color: #B9B7C6; }
      #liz-page a { color: #A9A7FA; }
    }
    #liz-page.liz-hidden { position: absolute; width: 1px; height: 1px;
      padding: 0; margin: -1px; overflow: hidden; clip: rect(0,0,0,0);
      white-space: nowrap; border: 0; }
  </style>"""

_FIRST_FRAME_SCRIPT = """<script>
    // The app draws the same content; once it has, hide this copy from view
    // and from screen readers so nothing is shown or read twice.
    window.addEventListener('flutter-first-frame', function () {
      var page = document.getElementById('liz-page');
      if (!page) return;
      page.classList.add('liz-hidden');
      page.setAttribute('aria-hidden', 'true');
    });
  </script>"""


def esc(value: object) -> str:
    return html.escape(str(value or ""), quote=True)


def clip(text: str, limit: int) -> str:
    text = re.sub(r"\s+", " ", text or "").strip()
    return text if len(text) <= limit else text[: limit - 1].rsplit(" ", 1)[0] + "…"


def summary_lines(raw: object) -> list[str]:
    if isinstance(raw, list):
        return [str(x) for x in raw if str(x).strip()]
    if isinstance(raw, dict) and isinstance(raw.get("bullets"), list):
        return [str(x) for x in raw["bullets"] if str(x).strip()]
    return []


def json_ld(data: dict) -> str:
    # No raw "<" at all: "</script>" in scraped text would end the block early,
    # and < is the same character to a JSON parser.
    body = json.dumps(data, ensure_ascii=False).replace("<", "\\u003c")
    return f'<script type="application/ld+json">{body}</script>'


def tool_json_ld(tool: dict, url: str | None, category_name: str) -> dict:
    data: dict = {
        "@context": "https://schema.org",
        "@type": "SoftwareApplication",
        "name": tool["name"],
        "description": clip(tool.get("tagline") or tool.get("description") or "", 300),
        "applicationCategory": category_name or "AI tool",
        "operatingSystem": "Web",
    }
    if url:
        data["url"] = url
    if tool.get("website_url"):
        data["sameAs"] = [tool["website_url"]]
    if tool.get("pricing_type") == "free":
        data["offers"] = {"@type": "Offer", "price": "0", "priceCurrency": "USD"}
    # Only ratings people actually gave. Liz once showed invented ones.
    if (tool.get("rating_count") or 0) > 0:
        data["aggregateRating"] = {
            "@type": "AggregateRating",
            "ratingValue": round(float(tool["avg_rating"]), 1),
            "ratingCount": int(tool["rating_count"]),
        }
    return data


def replace_head(template: str, *, title: str, description: str,
                 url: str | None, image: str | None, extra: str) -> str:
    """The template's head with this page's title, description and links."""
    out = re.sub(r"<title>.*?</title>", f"<title>{esc(title)}</title>", template, count=1, flags=re.S)
    out = re.sub(r'(<meta name="description" content=")[^"]*(")',
                 lambda m: m.group(1) + esc(description) + m.group(2), out, count=1)
    for prop in ("og:title", "twitter:title"):
        attr = "property" if prop.startswith("og:") else "name"
        out = re.sub(rf'(<meta {attr}="{prop}" content=")[^"]*(")',
                     lambda m: m.group(1) + esc(title) + m.group(2), out, count=1)
    for prop in ("og:description", "twitter:description"):
        attr = "property" if prop.startswith("og:") else "name"
        out = re.sub(rf'(<meta {attr}="{prop}" content=")[^"]*(")',
                     lambda m: m.group(1) + esc(description) + m.group(2), out, count=1)
    if image:
        out = re.sub(r'(<meta property="og:image" content=")[^"]*(")',
                     lambda m: m.group(1) + esc(image) + m.group(2), out, count=1)
    links = []
    if url:
        links.append(f'<link rel="canonical" href="{esc(url)}">')
        links.append(f'<meta property="og:url" content="{esc(url)}">')
    links.append(extra)
    return out.replace("</head>", "  " + "\n  ".join(links) + "\n</head>", 1)


def insert_body(page: str, content: str) -> str:
    content += '\n<p class="liz-loading">Opening Liz…</p>'
    block = (f'<main id="liz-page">\n{content}\n</main>\n'
             f"  {_FIRST_FRAME_SCRIPT}\n")
    page = page.replace("</head>", f"  {_PAGE_STYLE}\n</head>", 1)
    return page.replace("<body>", "<body>\n" + block, 1)


class Site:
    def __init__(self, site_url: str) -> None:
        self.base = site_url.rstrip("/")

    def url(self, path: str) -> str | None:
        return f"{self.base}{path}" if self.base else None


def tool_path(tool: dict) -> str:
    return f"/tools/{quote(tool['slug'])}"


def tool_page(template: str, tool: dict, site: Site, category_name: str,
              related: list[dict]) -> str:
    name = tool["name"]
    tagline = clip(tool.get("tagline") or "", 160)
    title = clip(f"{name} — {tagline}" if tagline else name, 70) + " | Liz"
    description = clip(
        " ".join(filter(None, [tagline, clip(tool.get("description") or "", 200)])), 160
    ) or f"{name} on Liz."
    url = site.url(tool_path(tool))

    facts = []
    pricing = PRICING_LABEL.get(tool.get("pricing_type") or "")
    if pricing:
        facts.append(f"<li>Price: {esc(pricing)}"
                     + (f" — {esc(tool['price_note'])}" if tool.get("price_note") else "")
                     + "</li>")
    if category_name:
        facts.append(f'<li>Category: <a href="/category/{esc(tool["category"])}">'
                     f"{esc(category_name)}</a></li>")
    if tool.get("trend_reason"):
        facts.append(f"<li>This week: {esc(tool['trend_reason'])}</li>")
    if tool.get("gh_repo"):
        stars = f" ({tool['gh_stars']:,} stars)" if tool.get("gh_stars") else ""
        facts.append(f'<li><a href="https://github.com/{esc(tool["gh_repo"])}">'
                     f"Source on GitHub</a>{esc(stars)}</li>")
    if tool.get("hn_id"):
        pts = f" ({tool['hn_points']} points)" if tool.get("hn_points") else ""
        facts.append(f'<li><a href="https://news.ycombinator.com/item?id={esc(tool["hn_id"])}">'
                     f"Discussed on Hacker News</a>{esc(pts)}</li>")
    first_seen = (tool.get("created_at") or "")[:10]
    if first_seen:
        facts.append(f"<li>First seen by Liz: <time datetime=\"{esc(first_seen)}\">"
                     f"{esc(first_seen)}</time></li>")

    bullets = "".join(f"<li>{esc(b)}</li>" for b in summary_lines(tool.get("ai_summary")))
    related_links = "".join(
        f'<li><a href="{esc(tool_path(r))}">{esc(r["name"])}</a> — {esc(clip(r.get("tagline") or "", 90))}</li>'
        for r in related
    )
    content = "\n".join(filter(None, [
        '<nav><a href="/">Liz</a></nav>',
        "<article>",
        f"<h1>{esc(name)}</h1>",
        f"<p>{esc(tagline)}</p>" if tagline else "",
        f"<ul>{bullets}</ul>" if bullets else "",
        f"<p>{esc(clip(tool.get('description') or '', 1200))}</p>" if tool.get("description") else "",
        f"<ul>{''.join(facts)}</ul>" if facts else "",
        (f'<p><a href="{esc(tool["website_url"])}" rel="noopener">Visit {esc(name)}</a></p>'
         if tool.get("website_url") else ""),
        "</article>",
        (f"<section><h2>More in {esc(category_name)}</h2><ul>{related_links}</ul></section>"
         if related_links else ""),
    ]))
    # A shared link previews the product itself when its site gave a picture.
    image = tool.get("image_url") or site.url("/icons/Icon-512.png")
    ld = tool_json_ld(tool, url, category_name)
    if tool.get("image_url"):
        ld["image"] = tool["image_url"]
    page = replace_head(template, title=title, description=description, url=url,
                        image=image, extra=json_ld(ld))
    if tool.get("image_url"):
        page = page.replace('<meta name="twitter:card" content="summary">',
                            '<meta name="twitter:card" content="summary_large_image">', 1)
    return insert_body(page, content)


def category_page(template: str, category: dict, tools: list[dict], site: Site) -> str:
    name = category["name"]
    title = f"{name} AI tools, ranked by what is rising | Liz"
    description = clip(
        f"{len(tools)} {name.lower()} AI tools on Liz, ranked by measured growth "
        "on GitHub, Hacker News and Liz: "
        + ", ".join(t["name"] for t in tools[:8]) + ".", 160)
    url = site.url(f"/category/{quote(category['slug'])}")
    items = "".join(
        f'<li><a href="{esc(tool_path(t))}">{esc(t["name"])}</a> — {esc(clip(t.get("tagline") or "", 110))}</li>'
        for t in tools
    )
    content = (f'<nav><a href="/">Liz</a></nav>\n<h1>{esc(name)} AI tools</h1>\n'
               f"<ul>{items}</ul>")
    ld = {
        "@context": "https://schema.org",
        "@type": "ItemList",
        "name": f"{name} AI tools",
        "itemListElement": [
            {"@type": "ListItem", "position": i + 1, "name": t["name"],
             **({"url": site.url(tool_path(t))} if site.base else {})}
            for i, t in enumerate(tools[:50])
        ],
    }
    page = replace_head(template, title=title, description=description, url=url,
                        image=site.url("/icons/Icon-512.png"), extra=json_ld(ld))
    return insert_body(page, content)


def home_page(template: str, rising: list[dict], categories: list[dict], site: Site) -> str:
    rising_items = "".join(
        f'<li><a href="{esc(tool_path(t))}">{esc(t["name"])}</a> — {esc(t.get("trend_reason") or "")}</li>'
        for t in rising
    )
    category_items = "".join(
        f'<li><a href="/category/{esc(c["slug"])}">{esc(c["name"])}</a></li>'
        for c in categories
    )
    content = ("<h1>Liz — discover AI tools while they are still rising</h1>\n"
               "<p>New AI tools from Product Hunt, Hacker News and GitHub, ranked by "
               "how fast they are growing this week.</p>\n"
               + (f"<section><h2>Rising this week</h2><ul>{rising_items}</ul></section>\n"
                  if rising_items else "")
               + f"<section><h2>Categories</h2><ul>{category_items}</ul></section>")
    page = template
    url = site.url("/")
    if url:
        page = page.replace(
            "</head>",
            f'  <link rel="canonical" href="{esc(url)}">\n'
            f'  <meta property="og:url" content="{esc(url)}">\n</head>', 1)
    return insert_body(page, content)


# Fewer than this many close alternatives, and an "Alternatives to X" page
# would be thin — a page with one link on it helps nobody and reads as spam.
MIN_ALTERNATIVES = 3

# How close counts as an alternative on a page meant for search engines.
# gte-small puts any two product descriptions near 0.83; measured on the
# catalog (1 Oct 2026), 0.86 still paired a prompt optimiser with a
# spreadsheet tool, while at 0.88 the neighbours do the same job. 246 tools
# have three such neighbours; the rest get no page rather than a weak one.
ALTERNATIVE_FLOOR = 0.88


def alternatives_page(template: str, tool: dict, alts: list[dict], site: Site) -> str:
    name = tool["name"]
    title = clip(f"Alternatives to {name}", 70) + " | Liz"
    description = clip(
        f"{len(alts)} tools that do a similar job to {name}, closest first: "
        + ", ".join(a["name"] for a in alts[:6]) + ".", 160)
    url = site.url(f"/alternatives/{quote(tool['slug'])}")
    items = "".join(
        f'<li><a href="{esc(tool_path(a))}">{esc(a["name"])}</a> — '
        f'{esc(clip(a.get("tagline") or "", 110))}</li>'
        for a in alts
    )
    content = (
        f'<nav><a href="/">Liz</a></nav>\n<h1>Alternatives to {esc(name)}</h1>\n'
        f'<p>Tools that do the most similar job to '
        f'<a href="{esc(tool_path(tool))}">{esc(name)}</a>, closest first.</p>\n'
        f"<ul>{items}</ul>"
    )
    ld = {
        "@context": "https://schema.org",
        "@type": "ItemList",
        "name": f"Alternatives to {name}",
        "itemListElement": [
            {"@type": "ListItem", "position": i + 1, "name": a["name"],
             **({"url": site.url(tool_path(a))} if site.base else {})}
            for i, a in enumerate(alts)
        ],
    }
    page = replace_head(template, title=title, description=description, url=url,
                        image=site.url("/icons/Icon-512.png"), extra=json_ld(ld))
    return insert_body(page, content)


def fetch_alternatives(url: str, key: str, tools: list[dict]) -> dict[str, list[dict]]:
    """Close alternatives per tool id, from the same similar_tools query the
    app's alternatives page uses (12 neighbours, a 0.08 window)."""
    from concurrent.futures import ThreadPoolExecutor

    def one(tool: dict) -> tuple[str, list[dict]]:
        try:
            resp = requests.post(
                f"{url.rstrip('/')}/rest/v1/rpc/similar_tools",
                json={"source_id": tool["id"], "match_count": 12,
                      "min_similarity": 0.8, "window_size": 0.08},
                headers={"apikey": key, "Authorization": f"Bearer {key}"},
                timeout=REQUEST_TIMEOUT,
            )
            resp.raise_for_status()
            return tool["id"], resp.json()
        except requests.RequestException:
            return tool["id"], []

    with ThreadPoolExecutor(max_workers=8) as pool:
        return dict(pool.map(one, tools))


def sitemap(site: Site, tools: list[dict], categories: list[dict],
            alternatives: list[dict] | None = None) -> str:
    today = datetime.now(UTC).strftime("%Y-%m-%d")
    entries = [(site.url("/"), today)]
    entries += [(site.url(f"/category/{quote(c['slug'])}"), today) for c in categories]
    entries += [(site.url(tool_path(t)), (t.get("updated_at") or today)[:10]) for t in tools]
    entries += [(site.url(f"/alternatives/{quote(t['slug'])}"), today)
                for t in alternatives or []]
    rows = "".join(f"  <url><loc>{esc(u)}</loc><lastmod>{d}</lastmod></url>\n"
                   for u, d in entries)
    return ('<?xml version="1.0" encoding="UTF-8"?>\n'
            '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
            f"{rows}</urlset>\n")


# A badge a maker can put on their own site, linking back to the tool's page
# on Liz: the way Product Hunt grew. Two variants per tool, for light and dark
# pages, in the app's own neutrals (docs/DESIGN.md). "Rising" only while Liz's
# ranking says so: the pages are rebuilt daily, so a badge never claims a
# trend that has passed for more than a day.
_BADGE_THEMES = {
    "light": {"bg": "#FFFFFF", "line": "#D2D2D7", "caption": "#6E6E73",
              "word": "#1D1D1F", "accent": "#5856D6", "rising": "#C93400"},
    "dark": {"bg": "#161618", "line": "#3A3A3C", "caption": "#A1A1A6",
             "word": "#F5F5F7", "accent": "#7B79FF", "rising": "#FF7A45"},
}
BADGE_WIDTH, BADGE_HEIGHT = 136, 48


def badge_svg(tool: dict, theme: str = "light") -> str:
    c = _BADGE_THEMES[theme]
    # The app's own test (Tool.isRising), so badge and page agree.
    rising = bool(tool.get("trend_reason")) and (tool.get("momentum") or 0) > 0
    label = f"{tool.get('name') or 'This tool'} — {'rising' if rising else 'listed'} on Liz"
    if rising:
        icon = (f'<path d="M102 30l7-7 4 4 9-9M115 18h7v7" fill="none" '
                f'stroke="{c["rising"]}" stroke-width="2.2" '
                'stroke-linecap="round" stroke-linejoin="round"/>')
    else:
        icon = (f'<circle cx="112" cy="24" r="9" fill="{c["accent"]}"/>'
                '<path d="M108 24.2l2.8 2.8 5.2-5.6" fill="none" stroke="#FFFFFF" '
                'stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>')
    font = "Inter,-apple-system,'Segoe UI',Helvetica,Arial,sans-serif"
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{BADGE_WIDTH}" '
        f'height="{BADGE_HEIGHT}" viewBox="0 0 {BADGE_WIDTH} {BADGE_HEIGHT}" '
        f'role="img" aria-label="{esc(label)}"><title>{esc(label)}</title>'
        f'<rect x="0.5" y="0.5" width="{BADGE_WIDTH - 1}" height="{BADGE_HEIGHT - 1}" '
        f'rx="10" fill="{c["bg"]}" stroke="{c["line"]}"/>'
        f'<g font-family="{font}">'
        f'<text x="16" y="20" font-size="9.5" font-weight="600" letter-spacing="0.8" '
        f'fill="{c["caption"]}">{"RISING ON" if rising else "LISTED ON"}</text>'
        f'<text x="16" y="38" font-size="19" font-weight="700" '
        f'fill="{c["word"]}">Liz</text></g>{icon}</svg>'
    )


def robots(site: Site) -> str:
    lines = ["User-agent: *", "Allow: /",
             # Personal and operational pages have nothing to index.
             "Disallow: /admin", "Disallow: /saved", "Disallow: /alerts",
             "Disallow: /profile", "Disallow: /signin"]
    if site.base:
        lines.append(f"Sitemap: {site.base}/sitemap.xml")
    return "\n".join(lines) + "\n"


def fetch(url: str, key: str, table: str, params: dict) -> list[dict]:
    rows: list[dict] = []
    offset = 0
    while True:
        resp = requests.get(
            f"{url.rstrip('/')}/rest/v1/{table}",
            params={**params, "limit": 1000, "offset": offset},
            headers={"apikey": key, "Authorization": f"Bearer {key}"},
            timeout=REQUEST_TIMEOUT,
        )
        resp.raise_for_status()
        page = resp.json()
        rows.extend(page)
        if len(page) < 1000:
            return rows
        offset += 1000


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="liz_scraper.prerender")
    parser.add_argument("--build", required=True, help="The flutter build output (build/web).")
    parser.add_argument("--site", default=os.environ.get("SITE_URL", ""),
                        help="Public origin, for canonical links and the sitemap.")
    args = parser.parse_args(argv)

    supabase_url = os.environ.get("SUPABASE_URL", "").strip()
    key = os.environ.get("SUPABASE_ANON_KEY", "").strip()
    if not supabase_url or not key:
        print("error: SUPABASE_URL and SUPABASE_ANON_KEY must be set", file=sys.stderr)
        return 2

    build = pathlib.Path(args.build)
    index = build / "index.html"
    template = index.read_text(encoding="utf-8")
    if 'id="liz-page"' in template:
        print("error: index.html is already prerendered; rebuild first", file=sys.stderr)
        return 2

    site = Site(args.site)
    tools = fetch(supabase_url, key, "tools", {
        "select": TOOL_COLUMNS, "status": "eq.published",
        "order": "momentum.desc,created_at.desc"})
    categories = fetch(supabase_url, key, "categories",
                       {"select": "name,slug", "order": "name"})
    names = {c["slug"]: c["name"] for c in categories}
    by_category: dict[str, list[dict]] = {}
    for t in tools:
        by_category.setdefault(t.get("category") or "", []).append(t)

    (build / "tools").mkdir(exist_ok=True)
    written = 0
    for t in tools:
        if not t.get("slug") or "/" in t["slug"]:
            continue
        related = [r for r in by_category.get(t.get("category") or "", []) if r["id"] != t["id"]][:8]
        page = tool_page(template, t, site, names.get(t.get("category") or "", ""), related)
        (build / "tools" / f"{t['slug']}.html").write_text(page, encoding="utf-8")
        written += 1

    (build / "category").mkdir(exist_ok=True)
    listed = [c for c in categories if by_category.get(c["slug"])]
    for c in listed:
        page = category_page(template, c, by_category[c["slug"]], site)
        (build / "category" / f"{c['slug']}.html").write_text(page, encoding="utf-8")

    (build / "alternatives").mkdir(exist_ok=True)
    with_alts = []
    for t_id, alts in fetch_alternatives(supabase_url, key, tools).items():
        tool = next(t for t in tools if t["id"] == t_id)
        alts = [a for a in alts if (a.get("similarity") or 0) >= ALTERNATIVE_FLOOR]
        if len(alts) < MIN_ALTERNATIVES or not tool.get("slug") or "/" in tool["slug"]:
            continue
        page = alternatives_page(template, tool, alts, site)
        (build / "alternatives" / f"{tool['slug']}.html").write_text(page, encoding="utf-8")
        with_alts.append(tool)

    (build / "badge").mkdir(exist_ok=True)
    for t in tools:
        if not t.get("slug") or "/" in t["slug"]:
            continue
        (build / "badge" / f"{t['slug']}.svg").write_text(badge_svg(t), encoding="utf-8")
        (build / "badge" / f"{t['slug']}-dark.svg").write_text(
            badge_svg(t, "dark"), encoding="utf-8")

    rising = [t for t in tools if t.get("trend_reason")][:12]
    index.write_text(home_page(template, rising, listed, site), encoding="utf-8")
    (build / "robots.txt").write_text(robots(site), encoding="utf-8")
    if site.base:
        (build / "sitemap.xml").write_text(
            sitemap(site, tools, listed, with_alts), encoding="utf-8")

    print(json.dumps({"tools": written, "categories": len(listed),
                      "alternatives": len(with_alts), "sitemap": bool(site.base)}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
