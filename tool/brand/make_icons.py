"""Draw every raster copy of the Liz mark from its geometry.

The mark ("the Rise") is two flat shapes on a 64-unit square — the same
points as `LizMark.stem` and `LizMark.blade` in lib/shared/widgets/liz_mark.dart.
Run after changing either, from the repository root:

    python tool/brand/make_icons.py

Writes the favicon, the web app icons, the launcher source icon, the web
splash images and the link-preview card. Needs Pillow.
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
STEM = [(10, 6), (24, 6), (24, 58), (10, 58)]
BLADE = [(30, 44), (56, 24), (56, 38), (30, 58)]
RED = (255, 59, 59, 255)  # LizPalette.accent
INK = (237, 237, 240, 255)  # textPrimary
DIM = (161, 161, 170, 255)  # textSecondary
ICON_BG = (5, 5, 6, 255)  # the manifest's background colour
FONT = ROOT / "assets" / "fonts" / "SpaceGrotesk-Latin.ttf"
SS = 8  # drawn this many times larger, then scaled down: smooth edges


def mark(size, color=RED, pad=0.0, bg=(0, 0, 0, 0), radius=0.0):
    """The mark centred in a size-square, `pad` of the side clear around it,
    on `bg` — a rounded square when `radius` (a fraction of the side)."""
    big = size * SS
    im = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    if radius:
        d.rounded_rectangle([0, 0, big - 1, big - 1], radius * big, fill=bg)
    else:
        d.rectangle([0, 0, big, big], fill=bg)
    inner, off = big * (1 - 2 * pad), big * pad
    for shape in (STEM, BLADE):
        d.polygon([(off + x / 64 * inner, off + y / 64 * inner) for x, y in shape], fill=color)
    return im.resize((size, size), Image.LANCZOS)


def font(px, weight="Bold"):
    f = ImageFont.truetype(str(FONT), px)
    f.set_variation_by_name(weight)
    return f


def text(d, xy, s, f, fill, tracking=0.0):
    """Draw `s` letter by letter, `tracking` (in em) between letters."""
    x, y = xy
    for ch in s:
        d.text((x, y), ch, font=f, fill=fill)
        x += d.textlength(ch, font=f) + tracking * f.size
    return x


def og_card(path):
    """1200×627 link preview: the lockup, the promise, one line of what."""
    w, h = 1200, 627
    im = Image.new("RGBA", (w, h), (9, 9, 11, 255))
    im.alpha_composite(mark(150), (96, 132))
    d = ImageDraw.Draw(im)
    text(d, (262, 120), "liz", font(150), INK, tracking=-0.03)
    text(d, (100, 350), "Find AI tools while they", font(54), INK, tracking=-0.01)
    text(d, (100, 414), "are still rising.", font(54), INK, tracking=-0.01)
    text(d, (100, 512), "Daily launches  ·  plain-words search  ·  what is climbing",
         font(28, "Regular"), DIM)
    im.convert("RGB").save(path, optimize=True)


def main():
    web = ROOT / "web"
    # Favicon: a dark rounded tile, so the red reads on light and dark tabs.
    mark(48, pad=0.17, bg=(9, 9, 11, 255), radius=0.22).save(web / "favicon.png")
    # Manifest icons: full squares (the OS rounds them); maskable ones keep
    # the mark inside the 80% safe circle.
    for n in (192, 512):
        mark(n, pad=0.2, bg=ICON_BG).save(web / "icons" / f"Icon-{n}.png")
        mark(n, pad=0.28, bg=ICON_BG).save(web / "icons" / f"Icon-maskable-{n}.png")
    mark(1024, pad=0.2, bg=ICON_BG).save(ROOT / "assets" / "icon" / "liz-icon-red.png")
    # Splash: the mark alone on transparency, at the size the page shows it.
    mark(384, pad=0.2).save(ROOT / "assets" / "icon" / "liz-splash.png")
    for i in (1, 2, 3, 4):
        img = mark(96 * i, pad=0.2)
        img.save(web / "splash" / "img" / f"dark-{i}x.png")
        img.save(web / "splash" / "img" / f"light-{i}x.png")
    og_card(web / "og-card.png")
    print("icons written")


if __name__ == "__main__":
    main()
