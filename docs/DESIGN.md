# Liz design system — Signal

The source of truth for how Liz looks and behaves. Written for whoever changes
the UI next — a person or Claude — so the app stays one design rather than a
collection of screens. Tokens live in `lib/app/theme.dart`; this explains them.

**Signal**, chosen on 1 October 2026: a trading desk for AI tools, in black
and red. Three concepts were drawn (an evolution of the previous calm light
look, *Signal*, and a colourful bento); the owner chose Signal in black with
red light, after a TRON: Ares reference — deep black, thin seams of glowing
red. The concepts are on the canvas "Liz redesign concepts". What it replaced
is at the end.

---

## 1. Principles

1. **Signal first.** Liz's difference is knowing what is taking off and why.
   Ranks, trend lines and the reason in words lead every screen they appear
   on; the description comes after.
2. **Red means something.** One red marks what you can act on (primary
   buttons, links), where you are (the selected tab), and what is rising
   (ranks, trend lines, reasons). Nothing else is red — not prices, not
   avatars, not icons in a list.
3. **Light lines, sparingly.** The glow is the signature, so it is rare: the
   seam under the top bar and over the tab bar, the top edge of a signal
   panel, the leader of the movers table, primary buttons. A screen full of
   glow is a screen with no emphasis.
4. **Instruments speak monospace.** Labels, ranks, deltas and reasons are set
   in JetBrains Mono capitals; words people read are Space Grotesk.
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
| `canvas` | `#050506` | App background |
| `surface` | `#0D0E11` | Cards, panels, sidebar, sheets |
| `surfaceMuted` | `#121318` | Menus, quiet fills |
| `surfaceHover` | `#191A20` | Hover fills, logo and avatar tiles |
| `hairline` | `#1F2128` | Card borders, separators |
| `hairlineStrong` | `#2E313A` | Inputs, outlines, unselected pills |
| `textPrimary` | `#F4F5F7` | Titles, body |
| `textSecondary` | `#A3A7B1` | Taglines, metadata, placeholders, labels |
| `textTertiary` | `#6F7380` | Chevrons, disabled — never text |

### Red

| Token | Value | Job |
|---|---|---|
| `accent` | `#FF3B3B` | Red text, icons, lines, focus (5.4:1 on `surface`) |
| `accentFill` | `#D7141A` | Behind white text: primary buttons, badges (5.2:1 with white) |
| `accentHover` | `#FF5C5C` | Hover on red text |
| `accentSoft` | red @ 14% | Selected pills and segments, tonal buttons |
| `glow` | `#FF2A2A` | The light of the light lines — only ever blurred |
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

- **Space Grotesk** — everything people read. Geometric, slightly technical,
  legible at body sizes.
- **JetBrains Mono** — instruments: `LizText.label` (11px capitals, 1.0
  tracking: "SIGNAL · 30 DAYS", "RANK", column headings, eyebrows) and
  `LizText.mono` (13px: ranks "01", deltas "+1.6k in 29 days", reasons
  "+2.2k GitHub stars this week"). Write label text in capitals; the style
  does not transform it.

| Role | Size / line | Weight | Tracking | Used for |
|---|---|---|---|---|
| `display` | 44 / 46 | 700 | −1.4 | Desktop hero |
| `largeTitle` | 32 / 36 | 700 | −0.9 | Page titles |
| `title1` | 26 / 31 | 700 | −0.6 | Tool name; phone page titles |
| `title2` | 21 / 26 | 600 | −0.3 | Section headers |
| `title3` | 18 / 23 | 600 | −0.2 | Card group titles, wordmark |
| `headline` | 15 / 21 | 600 | −0.1 | Card titles, list rows |
| `body` | 15 / 22 | 400 | 0 | Paragraphs |
| `callout` | 14 / 20 | 400 | 0 | Taglines, secondary copy |
| `subhead` | 13 / 18 | 500 | 0 | Metadata lines |
| `footnote` | 12 / 16 | 500 | 0.1 | Timestamps, counts |
| `caption` | 11 / 14 | 600 | 0.3 | Badges |
| `label` | 11 / 14 mono | 500 | 1.0 | Instrument labels, eyebrows |
| `mono` | 13 / 18 mono | 500 | 0 | Ranks, deltas, reasons |

Rules: nothing under 11px; no weight under 400; at most three sizes on a card.

**Eyebrow.** A page or section may carry one short mono line above its title,
in red with a faint glow: `// MOMENTUM, NOT HYPE`, `// TOP MOVERS · 7 DAYS`
(`PageHeader(eyebrow:)`, `SectionHeader(eyebrow:)`). Only where it adds
meaning; most sections have none.

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
| `xs` | 4 | Badges, filter pills, selected segments |
| `sm` | 6 | Buttons, inputs, list rows, sidebar items |
| `md` | 10 | Cards, panels, the movers table |
| `lg` | 14 | Dialogs |
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
| bar | `canvas` @ 82% + 24px blur | a `GlowLine` | seam | Phone top bar and tab bar |
| lit | — | `accent` | `LizShadows.glow` | Primary button, selected tab icon, the movers leader |

**`GlowLine`** (theme.dart) is the light line: 1px, brightest in the middle,
fading to nothing at both ends, with an 8px red glow. Bars use strength 0.85;
a signal panel's top edge 0.8; inside content, less.

**Trend lines** (`SignalSparkline`) are drawn as light: a blurred red stroke
under a crisp one, a fill fading to nothing beneath, and a lit dot on today.

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
selected one is red with a glow on its icon. Tablet: a 72px rail; the selected
button is lit (red edge, faint red fill). Desktop: a 248px sidebar on
`surface` — *Browse* and *Library* groups with mono labels, search at the top,
the account at the bottom; the selected row has a faint red fill and a red bar
on its leading edge.

**Wordmark.** The glyph in red with a blurred copy behind it as glow, and
"LIZ" in spaced capitals (read by screen readers as "Liz").

**Buttons.** *Primary* — `accentFill`, white label, lit (a red glow that
strengthens on hover). *Tonal* (`LizButtons.tonal`) — red outline at 70% on
`accentSoft`, white label, not lit. *Outlined* — `hairlineStrong` outline that
turns red on hover. *Text* — red label. Heights 44 phone, 40 desktop.

**Filter pills and segmented controls.** Off: an outline on `surface`,
secondary text. On: lit — a red edge on `accentSoft`, primary text, a faint
glow. Square-ish (`xs`), not capsules.

**Inputs.** `surface` fill, `hairlineStrong` outline, red outline on focus.

**Top movers table** (`TopMovers`, Discover). The ranked list of the week's
fastest growers. Wide (≥ 760 of room): a table with mono headings — RANK ·
TOOL · WHAT IT DOES · 14-DAY SIGNAL · WHY IT'S RISING · PRICE. Narrow: rank,
logo, name, the reason in mono red, and a small trend line. Ranks are mono
"01"–"06", red for the top three. The leader's row is lit: a red seam on its
leading edge and red light fading across it.

**Signal panel** (`ToolSignalsSection`, the tool page). Right after the facts
strip, before any words about the tool: a `surface` panel with a `GlowLine`
along its top, "SIGNAL · N DAYS" and the reason in mono, the trend line full
width, then the change in mono ("GitHub stars: 3.0k → 4.6k since 2 Sep",
"+1.6k in 29 days").

**Tool card.** Logo, name (`headline`), two-line tagline (`callout`,
secondary), one metadata line (`● Freemium · Video · ★ 4.7`). Bookmark as a
quiet icon button. "New" is a small red badge.

**Tool logo.** A real logo sits on a white app-icon tile (most logos are made
for white). Without one: a monochrome tile — `surfaceHover`, `hairlineStrong`
edge, the initial in white. No colour per tool.

**Avatar.** The person's picture, or their initials in white on a dark disc
ringed in red. No colour per person.

**Grouped list** (Settings, Profile). Rows in a `surface` group, hairlines
inset past the icon; icons white on a dark tile — only a destructive row is
coloured. Group titles are mono labels.

**Empty state.** An icon, a `title3`, one sentence, at most one action.

---

## 8. Screens

- **Discover.** Eyebrow and title, a large search field, then the *Top
  movers* table, *New this week*, *For you*, and the catalog: category pills,
  the sort segmented control, the price filter and the card grid.
- **Tool page.** Logo, name, tagline; *Visit website* (primary) with *Save*
  and *Compare* (tonal); the facts strip with mono labels; the **signal
  panel**; then *Summary*, *About*, timeline, similar tools, in the news,
  what's new, reviews.
- **Search, Ask Liz, News, Saved, Compare, Alerts, Profile, Settings, Sign
  in** take the theme without layouts of their own; their structure is as
  before.

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
