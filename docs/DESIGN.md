# Liz design system — Signal

The source of truth for how Liz looks and behaves. Written for whoever changes
the UI next — a person or Claude — so the app stays one design rather than a
collection of screens. Tokens live in `lib/app/theme.dart`; this explains them.

**Signal**, chosen on 1 October 2026: a trading desk for AI tools, in black
and red. Refined on 27 October 2026 to an enterprise finish (§10): the black
and the red stay; the costume went — monospace labels, eyebrows, index
numbers and glowing seams — after a review against the house rules of
`taste-skill` (app screens), the motion principles of Emil Kowalski, and the
DESIGN.md files of Linear, Raycast and Vercel. A Stitch draft of Discover,
made independently from the same brief, landed on the same layout.

---

## 1. Principles

1. **Signal first.** Liz's difference is knowing what is taking off and why.
   Ranks, trend lines and the reason in words lead every screen they appear
   on; the description comes after.
2. **Red means something.** One red marks the primary action (one filled
   button per screen), links, and what is rising: trend lines and the growth
   figure in a reason ("**+2.2k** GitHub stars this week"). Nothing else is
   red — not ranks, not selection, not icons in a list, not prices.
3. **Nothing at rest glows.** No glow, no gradient, no shadow on anything
   lying on the page. Surfaces are told apart by a tone step and a 1px
   hairline; shadows are only for what floats (menus, dialogs).
4. **One typeface.** Space Grotesk for words and figures alike, with tabular
   numerals where figures line up. No monospace, no capital letter-spaced
   labels, no eyebrows above headings, no "01–06" numbering.
5. **Hierarchy by type and light, not boxes.** A new container is the last
   resort. On black, a raised thing is a slightly lighter surface with a
   hairline, never a drop shadow.
6. **Every size is a first-class size.** 320-pixel phones, 1.5x text, tablets
   and wide desktops are designed, not tolerated — and tested
   (`test/screen_sweep_test.dart`).

---

## 2. Colour

One theme. There is no light mode: `LizTheme.app()` is the theme, and
`LizPalette.ares` its palette, read with `context.liz`. Every pair below meets
WCAG contrast on the surfaces it is used on — body text at least 4.5:1, large
text and UI at least 3:1 — and the sweep checks it on every screen.

### Neutrals

| Token | Value | Job |
|---|---|---|
| `canvas` | `#09090B` | App background; the sidebar and rail share it |
| `surface` | `#111114` | Cards, panels, sheets |
| `surfaceMuted` | `#16161A` | Inputs, secondary buttons, menus |
| `surfaceHover` | `#1C1C21` | Hover fills; the selected nav row, segment and pill |
| `hairline` | `#232329` | Card borders, separators, bar edges |
| `hairlineStrong` | `#33333B` | Input and button outlines |
| `textPrimary` | `#EDEDF0` | Titles, body |
| `textSecondary` | `#A1A1AA` | Taglines, metadata, placeholders, labels, unselected nav |
| `textTertiary` | `#71717A` | Separators, chevrons, the selected pill's edge — never text |

### Red

| Token | Value | Job |
|---|---|---|
| `accent` | `#FF3B3B` | Red text, icons, lines, focus (5.4:1 on `surface`) |
| `accentFill` | `#D7141A` | Behind white text: primary buttons, badges (5.2:1 with white) |
| `accentHover` | `#FF5C5C` | Hover on red text |
| `accentSoft` | red @ 12% | Tinted badges ("New", "AI") |
| `glow` | `#FF2A2A` | Kept as a token; nothing is drawn with it since §10 |
| `rising` | `#FF3B3B` | The same red: in Signal, rising *is* the signal |

### Meaning

| Token | Value | Means |
|---|---|---|
| `positive` | `#34D399` | Free, healthy |
| `caution` | `#FFB020` | Paid, warning |
| `danger` | `#FF5A6E` | Destructive, failing — pinker than the accent, and always with words |

Prices are a small dot before a word (`● Free`): green for free, amber for
paid, grey for freemium. The word is the information; nothing depends on
colour alone.

`LizPalette.lightSite` exists for one thing: previewing the maker badge on
someone else's light website.

---

## 3. Typography

Both fonts are bundled variable fonts subset to Latin (`assets/fonts`, SIL Open
Font Licence beside them), never fetched at run time.

- **Space Grotesk** — everything: words and figures. Geometric, slightly
  technical, legible at body sizes. `LizText.label` (12px, sentence case) is
  for column headings and group titles; `LizText.mono` is the text face with
  tabular numerals, for ranks, counts and deltas. JetBrains Mono is still
  bundled but no longer used.

| Role | Size / line | Weight | Tracking | Used for |
|---|---|---|---|---|
| `display` | 40 / 44 | 600 | −1.2 | Sign-in claim |
| `largeTitle` | 28 / 34 | 600 | −0.7 | Page titles |
| `title1` | 24 / 30 | 600 | −0.5 | Tool name; phone page titles |
| `title2` | 19 / 25 | 600 | −0.3 | Section headers |
| `title3` | 17 / 23 | 600 | −0.2 | Card group titles, bar titles |
| `headline` | 15 / 21 | 600 | −0.1 | Card titles, list rows |
| `body` | 15 / 22 | 400 | 0 | Paragraphs |
| `callout` | 14 / 20 | 400 | 0 | Taglines, secondary copy |
| `subhead` | 13 / 18 | 500 | 0 | Metadata lines |
| `footnote` | 12 / 16 | 500 | 0.1 | Timestamps, counts |
| `caption` | 11 / 14 | 600 | 0.3 | Badges |
| `label` | 12 / 16 | 500 | 0 | Column headings, group titles (sentence case) |
| `mono` | 13 / 18 tabular | 500 | 0 | Ranks, counts, deltas |

Rules: nothing under 11px; no weight under 400; at most three sizes on a card.

**No eyebrows.** The small red mono line that used to sit above titles is
gone (§10); a title says what the section is, and its subtitle says the rest.

---

## 4. Space, size and shape

**Spacing:** a 4-point scale in 8-point rhythm,
`4 · 8 · 12 · 16 · 20 · 24 · 32 · 40 · 48 · 64`.

**Page gutters:** 16 phone, 24 tablet, 32 desktop. Content caps at 1200;
reading columns (news, legal, a tool's page) at 760.

**Breakpoints** by width, never device: phone < 600 ≤ tablet < 1024 ≤
desktop. Grids: 1 · 2 · 3, and 4 from 1500.

**Radii** — tighter than before; Signal is precise, not soft. Continuous
corners (`RoundedSuperellipseBorder`).

| Token | Radius | Used for |
|---|---|---|
| `xs` | 6 | Badges, filter pills, selected segments |
| `sm` | 8 | Buttons, inputs, list rows, sidebar items |
| `md` | 12 | Cards, panels, the movers table |
| `lg` | 16 | Dialogs |
| `xl` | 20 | Large hero panels |

Tool logos stay app-icon squircles at 22.5% of their size. Touch targets are at
least 48 on phones (the sweep checks it).

---

## 5. Depth and light

On black a shadow barely shows, so depth is a lighter surface plus a
hairline. Light is reserved for emphasis.

| Material | Fill | Edge | Light | Used for |
|---|---|---|---|---|
| base | `surface` | `hairline` | none | Cards, panels at rest |
| raised | `surface` | `hairlineStrong` | none | Hovered cards |
| floating | `surfaceMuted` | `hairlineStrong` | black shadow | Menus, popovers, snackbars |
| bar | `canvas` @ 92% over a blur | `hairline` | none | Phone top bar and tab bar; `LizTopBar` |

`GlowLine` and `LizShadows.glow` remain as names so older call sites compile;
the first draws a plain hairline and the second is empty.

**Trend lines** (`SignalSparkline`) are a crisp red line over a flat 10% red
area, with a solid dot on today. No blur, no gradient.

---

## 6. Motion

| Token | Duration | Curve | Used for |
|---|---|---|---|
| `quick` | 120 ms | ease-out | Hover, press, colour changes |
| `standard` | 220 ms | ease-out-cubic | Expanding, filtering, segment changes |
| `emphasized` | 320 ms | ease-in-out-cubic | Page transitions, sheets |

Cards lift on hover; pages fade forward; skeletons shimmer, never spin.
`MediaQuery.disableAnimations` turns all of it off.

---

## 7. Components

**Navigation.** Phone: a bar-material tab bar, five labelled destinations; the
selected one is white, the others grey. Tablet: a 72px rail; the selected
button sits on a `surfaceHover` tile. Desktop: a 240px sidebar on the canvas
with one hairline at its edge — *Browse* and *Library* groups with sentence-case
labels, search at the top, the account at the bottom; the selected row is a
neutral `surfaceHover` pill with white text, the rest grey.

**Top bar** (`LizTopBar`, pages that open over the app: a tool, Compare,
Alerts, Settings, legal pages, alternatives). A back button that always works —
to the previous page, or a fallback when the page was opened by its address —
and on wider windows the trail "Liz / Discover / Lensflow".

**Wordmark.** The glyph in red with a blurred copy behind it as glow, and
"LIZ" in spaced capitals (read by screen readers as "Liz").

**Buttons.** *Primary* — `accentFill`, white label, flat; one per screen.
*Secondary* (`LizButtons.tonal`) — `surfaceMuted` with a `hairlineStrong`
edge and a white label. *Outlined* — `hairlineStrong` outline that brightens
on hover. *Text* — red label. Heights 44 phone, 40 desktop.

**Filter pills and segmented controls.** Off: transparent with a `hairline`
edge, grey text. On: `surfaceHover` with a lighter edge and white text.
Square-ish (`xs`), not capsules.

**Inputs.** `surfaceMuted` fill, `hairlineStrong` outline, a light grey
outline on focus.

**Top movers table** (`TopMovers`, Discover). The ranked list of the week's
fastest growers. Wide (≥ 760 of room): a table with sentence-case headings —
# · Tool · What it does · Last 14 days · Why it's rising · Price; from 1280px
the filter pills sit beside the section title. Narrow: rank, logo, name, the
reason and a small trend line. Ranks are plain grey figures. Reasons are
`ReasonText`: the growth figure in red, the words in grey. Prices are
`PricingLabel` (a dot and a word, no box).

**Signal panel** (`ToolSignalsSection`, the tool page). Right after the facts
strip: a `surface` panel, "Last N days" and the reason, the trend line full
width, then the change ("GitHub stars: 3.0k → 4.6k since 2 Sep", "+1.6k in
29 days").

**Tool card.** Logo, name (`headline`), two-line tagline (`callout`,
secondary), one metadata line (`● Freemium · Video · ★ 4.7`). Bookmark as a
quiet icon button. "New" is a small red badge.

**Tool logo.** A real logo sits on a white app-icon tile (most logos are made
for white). Without one: a monochrome tile — `surfaceHover`, `hairlineStrong`
edge, the initial in white. No colour per tool.

**Avatar.** The person's picture, or their initials in white on a dark disc
ringed in red. No colour per person.

**Grouped list** (Settings, Profile). Rows in a `surface` group, hairlines
inset past the icon; icons grey or white — only a destructive row is
coloured. Group titles are sentence-case labels.

**Empty state.** An icon, a `title3`, one sentence, at most one action.

---

## 8. Screens

- **Discover.** Title and subtitle, a large search field, then the *Top
  movers* table, *New this week*, *For you*, and the catalog: category pills,
  the sort segmented control, the price filter and the card grid.
- **Sign in.** Wide: a brand panel (the claim, one sentence, and a preview of
  *Rising this week* drawn as the product draws it) beside the form. Narrow:
  the wordmark and the form. A first visit opens on *Create account*.
- **Tool page.** Logo, name, tagline; *Visit website* (primary) with *Save*
  and *Compare* (tonal); the facts strip with mono labels; the **signal
  panel**; then *Summary*, *About*, timeline, similar tools, in the news,
  what's new, reviews.
- **News.** A reading column: source in ink and the time in grey above each
  headline; the first story set larger (`NewsCard(lead:)`); *Quick take* a
  quiet grey control that opens the AI summary in a framed panel.
- **Ask Liz.** Before a question, the question: the red mark on a neutral
  tile, the title, the field and four example prompts. After, the answers
  as cards with the reason in Liz's voice.
- **Profile.** A header (avatar with a neutral ring, the name as the page's
  heading, a grey role badge, when they joined, the bio, and three figures —
  saved, reviews, posts — set as type). Wide: what you wrote on the left,
  *Your account* on the right; narrow: one column, the account first. Empty
  sections keep their frame, with one way forward.
- **Saved.** The count in the subtitle; *Select* beside the title. While
  choosing, a bar along the bottom says how many are picked and shows
  *Compare* from two. Nothing saved: a framed panel saying what saving is
  for (save, hear about it, compare) and *Find a tool*.
- **Alerts.** The unread count in the subtitle and *Mark all read* beside
  it; alerts under *Today*, *This week* and *Earlier*. Unread is a bolder
  title and a red dot; the icon tiles stay neutral. The browser-notification
  offer is a framed row with a quiet *Turn on*.
- **Settings.** A page title, then sections. Wide: each section's name and
  what it is for in a 260px column on the left, its rows on the right,
  sections divided by hairlines. Narrow: name and sentence above the rows.
  Switches are white when on — a state, not an action, so not red.
- **Search, Compare** take the theme without layouts of their own.

---

## 9. Accessibility

Contrast, labelled tap targets and the 48px minimum are checked on every screen
by the sweep, and badge colours directly (`test/accessibility_test.dart`). Red
text is `accent` (bright enough on black); white text sits only on
`accentFill` (dark enough to carry it). Every icon-only control has a label.
Text scales to 1.5x without clipping. Glow is decoration: nothing is conveyed
by light alone, and decorative lines are excluded from semantics.

---

## 10. What changed, and why

### 27 October 2026 — the enterprise refinement

| Before | Now | Why |
|---|---|---|
| JetBrains Mono capitals for labels, ranks and reasons | Space Grotesk throughout, sentence case, tabular figures | Mono labels read as costume, not instruments |
| Red eyebrows (`// MOMENTUM, NOT HYPE`) | None | A title should say it; an eyebrow repeats it |
| Ranks "01"–"06", red for the top three; a lit leader row | Plain grey figures; no lit row | Order is the data; colour belongs on growth |
| Reasons all in red mono | Growth figure in red, words in grey | One red element per row, on the number that matters |
| Glow on buttons, tabs, seams, sparklines, the leader | No glow at rest; plain hairlines | A glow everywhere is emphasis nowhere |
| Red-tinted selection (pills, segments, nav, rail) | Neutral raised tone, white text | Selection is not an action; red is kept for actions and data |
| Red-outlined secondary buttons | Neutral secondary buttons | One primary per screen, unmistakable |
| Sidebar on `surface` with a red bar | On the canvas, neutral pill | Navigation recedes; content leads |
| Sign-in panel with neon seams and a drawn trend | The claim and a preview of the product | Show the product, not decoration |
| Pages over the app had a back arrow only when opened by tapping | `LizTopBar`: back always works; "Liz / Discover / …" on wide windows | Every screen names the product and the way back |
| 4–20 radii | 6 / 8 / 12 / 16 / 20 | Fewer, more deliberate corners |
| Red switches, red *Mark all read* and *Turn on* | White switches; neutral outlined secondary actions | Red stays on the one primary action and on rising data |

### 1 October 2026 — Signal

| Before (28 Sep) | Now (Signal, 1 Oct) | Why |
|---|---|---|
| Light and dark themes, neutral greys, indigo accent | One black theme, one red | The owner chose a black-and-red, TRON: Ares-inspired look |
| Inter | Space Grotesk + JetBrains Mono | A technical voice; mono for the instruments |
| "Rising" as a two-column chart | The *Top movers* table with trend lines and reasons | Liz's signal, made the centrepiece |
| Signals as a section low on the tool page | A lit signal panel right after the facts | Lead with what only Liz knows |
| Glass bars with a hairline | Black bars with a glowing red seam | The light line is the signature |
| Monochrome inverted filter pills | Lit pills: red edge on faint red | Selection reads as "on" in a dark UI |
| A colour per tool logo and per avatar | Monochrome tiles and red-ringed avatars | Colour confetti fought the one red that means something |
| Freemium in the accent colour | Freemium grey | Red is not a price |
| 6–28px soft radii | 4–20px | Precise rather than soft |
