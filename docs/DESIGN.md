# Liz design system

The source of truth for how Liz looks and behaves. Written for whoever changes
the UI next — a person or Claude — so the app stays one design rather than a
collection of screens. Tokens live in `lib/app/theme.dart`; this explains them.

Redesigned 28 September 2026. What it replaced, and why, is at the end.

---

## 1. Principles

1. **Content first.** Tool names, what they do, and whether they are worth a
   look. Chrome recedes: neutral surfaces, hairline borders, no decoration that
   does not carry information.
2. **One accent.** Indigo marks what you can act on and where you are. Nothing
   else is coloured unless the colour itself means something (price, a trend).
3. **Hierarchy by type, not by boxes.** Size and weight order a screen. A new
   container is the last resort, not the first.
4. **Quiet metadata.** One line of small secondary text says what four coloured
   pills used to shout.
5. **Calm motion.** Things respond to the pointer and settle; nothing bounces
   for its own sake, and everything stops when the reader asks for reduced
   motion.
6. **Every size is a first-class size.** 320-pixel phones, 1.5x text, tablets
   and wide desktops are designed, not tolerated (and tested:
   `test/screen_sweep_test.dart`).

References that shaped it: Apple's Human Interface Guidelines (type roles,
hierarchy, tab bar to sidebar by size class, 11pt minimum), Radix Colors (a
12-step scale where every step has one job), Vercel's Geist (a small set of
named materials), the App Store (product pages, top charts), and apple.com's
neutrals.

---

## 2. Colour

Neutral greys carry the interface; the accent is used sparingly. Every pair
below was chosen for WCAG contrast: body text at least 4.5:1, large text and
UI at least 3:1. `LizColors.legibleOn` adjusts any tinted text that would fall
short.

### Neutrals

| Token | Light | Dark | Job |
|---|---|---|---|
| `canvas` | `#FBFBFD` | `#0A0A0B` | App background |
| `surface` | `#FFFFFF` | `#161618` | Cards, sheets, bars |
| `surfaceMuted` | `#F5F5F7` | `#1C1C1E` | Inputs, segmented tracks, grouped rows |
| `surfaceHover` | `#EFEFF2` | `#232326` | Hover and pressed fills |
| `hairline` | `#E5E5EA` | `#2C2C2E` | Card borders, separators |
| `hairlineStrong` | `#D2D2D7` | `#3A3A3C` | Hovered borders, input outlines |
| `textPrimary` | `#1D1D1F` | `#F5F5F7` | Titles, body |
| `textSecondary` | `#6E6E73` | `#A1A1A6` | Taglines, metadata, placeholders |
| `textTertiary` | `#86868B` | `#8A8A8F` | Icons, chevrons, disabled — never text (3.6:1 on white) |

### Accent

| Token | Light | Dark | Job |
|---|---|---|---|
| `accent` | `#5856D6` | `#7B79FF` | Links, selection, accent text and icons |
| `accentFill` | `#5856D6` | `#5E5CE6` | Behind white text: primary buttons (the dark `accent` is 3.7:1 with white) |
| `accentHover` | `#4B49C8` | `#8E8CFF` | Hover on primary |
| `accentSoft` | accent @ 10% | accent @ 18% | Tonal buttons, selected rows |

### Meaning

Used only where the colour itself says something.

| Token | Light | Dark | Means |
|---|---|---|---|
| `positive` | `#248A3D` | `#30D158` | Free, up |
| `caution` | `#B25000` | `#FF9F0A` | Paid, warning |
| `rising` | `#C93400` | `#FF7A45` | Trending |
| `danger` | `#D70015` | `#FF453A` | Destructive, failing |

Pricing appears as a small coloured dot before a neutral word (`● Free`), not
a coloured pill: the colour is a cue, the word is the information.

---

## 3. Typography

Inter, bundled (not fetched). It is the closest open-source match to Apple's
SF Pro, and like SF it tightens tracking as size grows. Roles follow Apple's
text styles, sized for the web:

| Role | Size / line | Weight | Tracking | Used for |
|---|---|---|---|---|
| `display` | 40 / 44 | 700 | −1.2 | Desktop page hero |
| `largeTitle` | 32 / 38 | 700 | −0.8 | Page titles |
| `title1` | 26 / 32 | 700 | −0.5 | Tool name on its page |
| `title2` | 21 / 27 | 650 | −0.3 | Section headers |
| `title3` | 18 / 24 | 600 | −0.2 | Card group titles |
| `headline` | 15 / 21 | 600 | −0.1 | Card titles, list rows |
| `body` | 15 / 22 | 400 | 0 | Paragraphs |
| `callout` | 14 / 20 | 400 | 0 | Taglines, secondary copy |
| `subhead` | 13 / 18 | 500 | 0 | Metadata lines, buttons in dense UI |
| `footnote` | 12 / 16 | 500 | 0.1 | Timestamps, counts |
| `caption` | 11 / 14 | 600 | 0.3 | Eyebrows, badges (UPPERCASE only here) |

Rules: no weights below 400; nothing under 11px; numbers that change in place
(counts, ranks) use tabular figures; at most three sizes on one card.

---

## 4. Space, size and shape

**Spacing** is a 4-point scale used in 8-point rhythm:
`4 · 8 · 12 · 16 · 20 · 24 · 32 · 40 · 48 · 64`.

**Page gutters:** 16 on phones, 24 on tablets, 32 on desktop. Content caps at
1200 wide; reading columns (news, legal, a tool's page) at 760.

**Breakpoints** (by width, like Apple's size classes, never by device):
phone < 600 ≤ tablet < 1024 ≤ desktop. Grid columns: 1 · 2 · 3, and 4 from
1500.

**Radii** use Apple's continuous-corner squircle (`RoundedSuperellipseBorder`):

| Token | Radius | Used for |
|---|---|---|
| `xs` | 6 | Badges, tiny chips |
| `sm` | 10 | Buttons, inputs, list rows |
| `md` | 14 | Cards |
| `lg` | 20 | Sheets, hero panels, dialogs |
| `pill` | 999 | Primary call-to-action capsules, filter pills |

Tool logos are squircles at 22.5% of their size, like app icons.

**Touch targets** are at least 44 wide and tall on phones, 36 on desktop.

---

## 5. Materials and elevation

Flat by default; depth only where something sits above something else.

| Material | Fill | Border | Shadow | Used for |
|---|---|---|---|---|
| `base` | `surface` | `hairline` | none | Cards at rest |
| `raised` | `surface` | `hairlineStrong` | `0 6 20 / 6%` | Hovered cards |
| `floating` | `surface` | `hairline` | `0 12 40 / 12%` | Menus, popovers, dialogs |
| `glass` | `surface` @ 72% + 24px blur | bottom hairline | none | Top bar, phone tab bar |

Glass is the one signature effect: bars stay light and let content show
through as it scrolls under them.

---

## 6. Motion

| Token | Duration | Curve | Used for |
|---|---|---|---|
| `quick` | 120 ms | ease-out | Hover, press, colour changes |
| `standard` | 220 ms | ease-out-cubic | Expanding, filtering, tab changes |
| `emphasized` | 320 ms | ease-in-out-cubic | Page transitions, sheets |

- Cards lift 2px and gain the `raised` material on hover; press scales to 98%.
- Page pushes fade forward; tab switches cross-fade.
- Lists fade in their first page; skeletons shimmer, never spin.
- `MediaQuery.disableAnimations` turns all of it off.

---

## 7. Components

**Navigation.** Phone: a glass tab bar with five labelled destinations,
selection shown by tint alone. Tablet: a 72px icon rail. Desktop: a 248px
sidebar in two groups — *Browse* (Discover, Ask Liz, News) and *Library*
(Saved, Alerts) — with search at the top and the account at the bottom.

**Top bar.** Large title that sits in the page and, as the page scrolls, gives
way to a compact glass bar.

**Search field.** 40px, `surfaceMuted` fill, `sm` radius, magnifier left; on
desktop a `⌘K` hint right. Search is a field, not an icon.

**Buttons.** *Primary* — accent fill, white label, capsule on pages, `sm`
radius in forms. *Tonal* — `accentSoft` fill, accent label. *Plain* — label
only. Heights: 44 phone, 40 desktop, 32 compact.

**Segmented control.** For mutually exclusive views (Trending · New · Top
rated): a muted track with a sliding white thumb.

**Filter pills.** Categories scroll sideways. Unselected: muted fill,
secondary text. Selected: `textPrimary` fill, inverted text — monochrome, so
it never competes with the accent.

**Tool card.** Squircle logo (44), name (`headline`), two-line tagline
(`callout`, secondary), then one metadata line (`subhead`, secondary):
`● Freemium · Video · ★ 4.7`. Bookmark as a quiet icon button top-right.
"New" is a small accent text badge. `base` material, `raised` on hover.

**Chart row.** Rank numeral (tabular, `title3`, tertiary), logo, name and
tagline, and a trend value — the App Store's Top Charts, used for *Rising*.

**Badge.** `caption` text on a 10% tint, `xs` radius, for status words only
("New", "Beta"). Never more than one on a card.

**Grouped list.** For Settings and Profile: rows inside a `surface` group with
`md` radius, separated by hairlines inset past the icon — iOS Settings.

**Empty state.** A 56px icon in a soft circle, a `title3`, one sentence, and at
most one action.

**Skeleton.** The shape of the real content in `surfaceMuted`, shimmering.

---

## 8. Screens

- **Discover.** Desktop hero: `largeTitle` "Discover", one sentence, and a
  large search field. Then *Rising this week* as a two-column chart of five,
  then the catalog: category pills, the sort segmented control and price
  filter on one toolbar, and the card grid.
- **Tool page.** App Store product page: 96px logo, `title1` name, tagline,
  primary *Visit* capsule with *Save* and *Follow* beside it; an info strip
  (rating, price, category, rank) under hairlines; then *Summary*, *About*,
  *What's new*, *Similar tools* and *Ratings & reviews* as titled sections in
  a 760 column.
- **Search.** The field is the title. Results as cards; the price filter
  beside the count.
- **Ask Liz.** A centred composer as the whole page — a large field and four
  suggestions as cards; results as a ranked list with each tool's reason.
- **News.** An editorial list: source and time as an eyebrow, `title3`
  headline, two lines of summary, image on the right on wide screens.
- **Saved.** The card grid, with compare selection as a floating bar.
- **Compare.** Tools as columns with sticky headers, attributes as rows with
  hairline separators, and the best value in each row emphasised.
- **Profile & Settings.** Grouped lists; the profile header as a centred
  avatar, name and handle.
- **Sign in.** A centred card on the canvas: wordmark, title, fields, one
  primary button, then the other ways in.

---

## 9. Accessibility

Contrast is checked in both themes on every screen by the sweep; badge colours
are checked directly (`test/accessibility_test.dart`). Every icon-only control
has a label. Focus rings use the accent at 2px. Text scales to 1.5x without
clipping. Nothing is conveyed by colour alone — the price dot always sits next
to its word.

---

## 10. What changed, and why

| Before | Why it did not work | Now |
|---|---|---|
| Material 3 generated from one seed | Everything tinted lavender; looked like a template | Neutral greys and one accent |
| Four coloured pills per card | Seven colours competing on a single card | One quiet metadata line |
| Two rows of outlined chips for filters | Heavy, wrapped, sort looked like a category | Category pills plus a segmented sort on one toolbar |
| Cards with fixed height and empty space | Uneven rhythm | Cards sized to their content |
| Search as an icon | Discovery app hiding its main tool | Search field in the hero and sidebar |
| "Rising early" as small tiles | Rank was a number in a pill | A chart with rank numerals |
| Outlined buttons with thick borders | Every action looked equally important | Primary, tonal and plain, by importance |
| Tool page as a list of boxes | No clear top, AI summary in a purple box | Product-page hero, info strip, titled sections |
| Settings as bare rows | Unstructured | Grouped lists |
