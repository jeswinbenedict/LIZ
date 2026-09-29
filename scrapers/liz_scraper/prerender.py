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

The app then starts exactly as it would at any other address. The HTML
content is visually hidden (it sits behind the canvas anyway) and hidden from
screen readers once the app has drawn its first frame, so nothing is read
twice. It is the same text the app shows, so this is a page summary, not
cloaking.

Also writes sitemap.xml and robots.txt. Reads only published rows, with the
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
from datetime import datetime, timezone
from urllib.parse import quote

import requests

from .config import REQUEST_TIMEOUT

TOOL_COLUMNS = (
    "id,name,slug,tagline,description,ai_summary,category,pricing_type,"
    "price_note,website_url,gh_repo,gh_stars,hn_id,hn_points,trend_reason,"
    "avg_rating,rating_count,created_at,updated_at,image_url"
)

PRICING_LABEL = {"free": "Free", "freemium": "Freemium", "paid": "Paid"}

# Visually hidden, the way screen-reader-only text is: still in the document
# for crawlers and for anyone reading the page without the app.
_HIDDEN_STYLE = (
    "position:absolute;width:1px;height:1px;padding:0;margin:-1px;"
    "overflow:hidden;clip:rect(0,0,0,0);white-space:nowrap;border:0"
)

_FIRST_FRAME_SCRIPT = """<script>
    // The app draws the same content; once it has, keep screen readers from
    // reading this summary as well.
    window.addEventListener('flutter-first-frame', function () {
      var page = document.getElementById('liz-page');
      if (page) page.setAttribute('aria-hidden', 'true');
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
    block = (f'<main id="liz-page" style="{_HIDDEN_STYLE}">\n{content}\n</main>\n'
             f"  {_FIRST_FRAME_SCRIPT}\n")
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


def sitemap(site: Site, tools: list[dict], categories: list[dict]) -> str:
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    entries = [(site.url("/"), today)]
    entries += [(site.url(f"/category/{quote(c['slug'])}"), today) for c in categories]
    entries += [(site.url(tool_path(t)), (t.get("updated_at") or today)[:10]) for t in tools]
    rows = "".join(f"  <url><loc>{esc(u)}</loc><lastmod>{d}</lastmod></url>\n"
                   for u, d in entries)
    return ('<?xml version="1.0" encoding="UTF-8"?>\n'
            '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
            f"{rows}</urlset>\n")


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

    rising = [t for t in tools if t.get("trend_reason")][:12]
    index.write_text(home_page(template, rising, listed, site), encoding="utf-8")
    (build / "robots.txt").write_text(robots(site), encoding="utf-8")
    if site.base:
        (build / "sitemap.xml").write_text(sitemap(site, tools, listed), encoding="utf-8")

    print(json.dumps({"tools": written, "categories": len(listed),
                      "sitemap": bool(site.base)}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
