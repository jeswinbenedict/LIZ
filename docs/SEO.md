# Pages search engines can read

Liz draws itself on a canvas. Without help, every address — `/`, `/tools/elevenlabs`,
`/category/ai-video` — returns the same HTML: an empty shell titled "Liz", with
no description and no text. A search engine has nothing to index and a shared
link previews as "Liz" whatever it points at. Directories like Liz get most of
their visitors from search, so this matters more than any single feature.

## What the deploy does

After `flutter build web`, `python -m liz_scraper.prerender` (in
`.github/workflows/deploy-web.yml`) writes:

| File | Served at | Contains |
|---|---|---|
| `tools/<slug>.html` | `/tools/<slug>` | the tool's title, description, canonical link, Open Graph and Twitter tags, schema.org `SoftwareApplication`, and its text: tagline, summary, description, price, category, signals, links |
| `category/<slug>.html` | `/category/<slug>` | every tool in the category, linked, as a schema.org `ItemList` |
| `index.html` | `/` | this week's rising tools and every category, linked |
| `sitemap.xml`, `robots.txt` | | every page above; personal pages excluded |

Each is a copy of the built `index.html`, so the app starts on it exactly as it
would anywhere else. The text sits in a visually hidden `<main id="liz-page">`
— behind the canvas in any case — and is hidden from screen readers once the
app draws its first frame, so it is never read twice. It is the same content
the app shows: a summary of the page, not cloaking.

Once the app is running, `PageTitle` (lib/shared/widgets/page_title.dart)
keeps the tab title the same as the static one. Google reads the title after
the page's script has run, and MaterialApp would otherwise replace it with
the default.

## Rules the generated pages keep

- **Only facts Liz holds.** No `aggregateRating` unless people have rated the
  tool; Liz once displayed invented ratings (docs/RANKING.md).
- **Scraped text is untrusted.** Everything is HTML-escaped, and JSON-LD has no
  raw `<`, so a tagline cannot add markup or close the script block.
- **Fresh daily.** The workflow runs on push and every morning at 05:30 UTC,
  after the scraper and the nightly ranking.

## Serving

Cloudflare Pages serves `tools/x.html` at `/tools/x` and falls back to
`index.html` for every other path (a site with no `404.html` is treated as a
single-page app). `SITE_URL` must be set for canonical links and the sitemap;
without it the pages are still written, with no absolute links invented.
