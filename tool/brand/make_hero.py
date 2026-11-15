"""Build the sign-in hero (the seven characters) from the source illustration.

The source is a flattened picture whose "transparent" background is a
checkerboard painted into the pixels, so this:

1. cuts the characters out: the checkerboard is flood-filled from the edges,
   and pockets of it enclosed by hair or arms are found by their two shades;
2. paints each iris out of the eye, leaving the white of the eye with its own
   shading, so the app can draw an iris that moves (lib/features/auth/hero);
3. writes a mask of each eye's opening, so whatever the app draws in an eye
   (iris, eyelid) stays inside it and never touches lashes, lids or glasses;
4. writes the eyes' measurements and sampled colours as Dart.

Run from the repository root, with numpy, scipy and Pillow:

    python tool/brand/make_hero.py tool/brand/source/characters-source.webp \n        tool/brand/source/characters-closed-source.webp

The eyes below were measured by hand on the cut-out (its top-left is the
source's (0, 2)): centre and radii of the opening, then the iris as drawn.
"""
import json
import sys
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from scipy import ndimage
from scipy.spatial import ConvexHull

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "hero"
DART = ROOT / "lib" / "features" / "auth" / "hero" / "hero_eyes.dart"


# id: (opening cx, cy, rx, ry, iris cx, cy, r)
EYES = {
    "c1L": (435, 226, 17.5, 15, 442, 228, 10),
    "c1R": (496, 244, 14, 12, 492, 245, 9),
    "c2L": (658, 180, 18, 13, 665, 184, 11),
    "c2R": (721, 196, 14.5, 13, 718, 197, 10),
    "c3L": (892, 163, 18, 15, 898, 166, 11),
    "c3R": (960, 151, 17.5, 13.5, 958, 153, 11),
    "c4L": (1150, 258, 14.5, 12, 1155, 258, 10),
    "c4R": (1215, 233, 16.5, 11, 1212, 233, 10),
    "c5L": (525, 476, 18, 12, 532, 480, 10),
    "c5R": (587, 494, 8, 12, 585, 495, 7),
    "c6L": (836, 487, 22, 13, 844, 490, 13),
    "c6R": (923, 490, 20, 13, 920, 493, 12),
    "c7L": (1106, 499, 16, 13, 1110, 498, 10),
    "c7R": (1169, 469, 19, 15, 1164, 473, 12),
}


def cut_out(rgb: np.ndarray) -> np.ndarray:
    """Alpha for the characters: the checkerboard, and pockets of it, removed."""
    a = rgb.astype(np.int16)
    mx, mn = a.max(2), a.min(2)
    bg_like = ((mx - mn) <= 14) & (mn >= 188)
    h, w = bg_like.shape
    seen = np.zeros((h, w), bool)
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            if bg_like[y, x] and not seen[y, x]:
                seen[y, x] = True
                q.append((y, x))
    for y in range(h):
        for x in (0, w - 1):
            if bg_like[y, x] and not seen[y, x]:
                seen[y, x] = True
                q.append((y, x))
    while q:
        y, x = q.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and bg_like[ny, nx] and not seen[ny, nx]:
                seen[ny, nx] = True
                q.append((ny, nx))
    # Enclosed pockets: both checker shades present, so not a white object.
    lab, _ = ndimage.label(bg_like)
    for i, sl in enumerate(ndimage.find_objects(lab), start=1):
        comp = lab[sl] == i
        if seen[sl][comp].any() or comp.sum() < 250:
            continue
        vals = mn[sl][comp]
        if (vals >= 245).mean() > 0.2 and ((vals >= 195) & (vals <= 215)).mean() > 0.2:
            seen[sl] |= comp
    fg = Image.fromarray((~seen).astype(np.uint8) * 255, "L")
    # Shrink past the fringe blended with the checkerboard, then soften.
    return np.array(fg.filter(ImageFilter.MinFilter(5)).filter(ImageFilter.GaussianBlur(1.0)))


def inpaint(img: np.ndarray, unknown: np.ndarray, known: np.ndarray, rounds: int = 400) -> np.ndarray:
    """Fills `unknown` pixels smoothly from `known` neighbours (harmonic
    fill: each unknown pixel becomes the mean of its neighbours, repeated
    until settled). Pixels in neither set take no part."""
    out = img.copy()
    if not unknown.any():
        return out
    use = (known | unknown).astype(float)
    seed = img[known].mean(0) if known.any() else img.reshape(-1, 3).mean(0)
    out[unknown] = seed
    k = np.array([[0, 1, 0], [1, 0, 1], [0, 1, 0]], float)
    weight = ndimage.convolve(use, k, mode="constant")
    for _ in range(rounds):
        for c in range(3):
            total = ndimage.convolve(out[..., c] * use, k, mode="constant")
            # A pixel with no neighbour in play (walled in by a frame)
            # keeps the seed rather than averaging nothing into black.
            reach = unknown & (weight > 0)
            out[..., c][reach] = (total / np.maximum(weight, 1e-6))[reach]
    return out


# The GitHub logo on the cap and on the mug, in cut-out coordinates: the
# white badge's centre and radii. Liz's own mark goes in their place.
LOGOS = {"cap": (704.1, 59.4, 22.0, 19.5), "mug": (582.5, 831.0, 33.0, 30.5)}
STEM = [(10, 6), (24, 6), (24, 58), (10, 58)]  # LizMark.stem
BLADE = [(30, 44), (56, 24), (56, 38), (30, 58)]  # LizMark.blade
RED = np.array([255.0, 59.0, 59.0])  # LizPalette.accent


def replace_logo(rgb, cx, cy, rx, ry):
    """The badge becomes the fabric around it, and the Liz mark is drawn on
    that fabric in brand red, foreshortened as the badge was and lit by the
    same light (brighter where the cloth is)."""
    h, w, _ = rgb.shape
    x0, y0 = int(cx - rx - 14), int(cy - ry - 14)
    x1, y1 = int(cx + rx + 14), int(cy + ry + 14)
    patch = rgb[y0:y1, x0:x1].astype(float)
    box = patch.shape[:2]
    L = patch @ [0.299, 0.587, 0.114]
    # The badge is not a perfect ellipse: take every bright pixel of it too,
    # or crescents of its white ring stay behind.
    near = ellipse(box, cx - x0, cy - y0, rx + 8, ry + 8)
    badge = ellipse(box, cx - x0, cy - y0, rx + 2.5, ry + 2.5) | ndimage.binary_dilation(near & (L > 120), iterations=2)
    badge = ndimage.binary_fill_holes(badge) & near
    # And the badge's own outline just outside it, which otherwise stayed
    # and framed the patch as a disc.
    badge = ndimage.binary_dilation(badge, iterations=3)
    cloth = ~badge & ellipse(box, cx - x0, cy - y0, rx + 13, ry + 13) & (L < 150)
    # Coarse to fine, so the cloth's shading reaches the middle of a region
    # this size; one pass at full size left it a flat disc.
    small = (box[1] // 4, box[0] // 4)
    rough = np.stack([
        np.array(Image.fromarray(patch[..., c].astype(np.float32)).resize(small, Image.BILINEAR)) for c in range(3)
    ], -1).astype(float)
    sb = np.array(Image.fromarray(badge.astype(np.uint8) * 255).resize(small, Image.NEAREST)) > 0
    sc = np.array(Image.fromarray(cloth.astype(np.uint8) * 255).resize(small, Image.NEAREST)) > 0
    rough = inpaint(rough, sb, sc, rounds=1500)
    up = np.stack([
        np.array(Image.fromarray(rough[..., c].astype(np.float32)).resize((box[1], box[0]), Image.BILINEAR)) for c in range(3)
    ], -1)
    patch[badge] = up[badge]
    patch = inpaint(patch, badge, cloth, rounds=1500)
    # The mark: 46 x 52 units of the 64-grid, 1.3 badge-heights tall.
    K = 4
    size = ry * 2 * 0.62 / 52
    sx = size * rx / ry
    m = Image.new("L", (box[1] * K, box[0] * K), 0)
    d = ImageDraw.Draw(m)
    for shape in (STEM, BLADE):
        d.polygon([(((cx - x0) + (x - 33) * sx) * K, ((cy - y0) + (y - 32) * size) * K) for x, y in shape], fill=255)
    a = (np.array(m.resize((box[1], box[0]), Image.BOX)).astype(float) / 255)[..., None]
    light = (patch @ [0.299, 0.587, 0.114])
    light = np.clip(0.78 + (light - light[badge].mean()) / 120, 0.6, 1.05)[..., None]
    patch = patch * (1 - a) + (RED * light) * a
    rgb[y0:y1, x0:x1] = np.clip(patch, 0, 255).astype(np.uint8)


def frame_mask(img, open_big, key, ecx, ecy, rx, ry):
    """Frames of glasses in a patch: thick dark strokes (lashes, thinner
    than three pixels, vanish under an opening) that reach well away from the
    eye. Right round the eye dark is lash, except where a frame really crosses
    it (c5R, half behind the bridge)."""
    L = img @ [0.299, 0.587, 0.114]
    thick = ndimage.binary_opening(L < 70, structure=np.ones((3, 3)))
    near = ndimage.binary_dilation(open_big, iterations=9)
    lab, n = ndimage.label(thick)
    frame = np.zeros(L.shape, bool)
    for i in range(1, n + 1):
        comp = lab == i
        if (comp & ~near).sum() > 12:
            frame |= comp
    frame = ndimage.binary_dilation(frame, iterations=1) & (L < 110)
    # The eye's own iris is dark and thick too, and where it touches a frame
    # (c5R, against the bridge) it joined it; the opening is never frame.
    frame &= ~ndimage.binary_dilation(open_big, iterations=1)
    if key != "c5R":
        frame &= ~ellipse(L.shape, ecx, ecy, rx + 4, ry + 4)
    return frame


def closed_eye(f, closed_src, key, ex, ey, rx, ry):
    """Where the closed-eyes picture's eye sits on this face.

    The region is the eye with lashes and lids, generously; the offset is the
    shift (within eight pixels) at which the skin and brows around it agree
    best between the two paintings."""
    q = 22
    cx0, cy0 = int(ex - rx - q), int(ey - ry - q)
    big = (int(2 * (ry + q)) + 1, int(2 * (rx + q)) + 1)
    region = ellipse(big, ex - cx0, ey - cy0, rx + 7, ry + 7)
    ring = ellipse(big, ex - cx0, ey - cy0, rx + 16, ry + 14) & ~ellipse(big, ex - cx0, ey - cy0, rx + 9, ry + 9)
    here = f[cy0 : cy0 + big[0], cx0 : cx0 + big[1]] @ [0.299, 0.587, 0.114]
    best, at = 1e18, (0, 0)
    for dy in range(-8, 9):
        for dx in range(-8, 9):
            there = closed_src[cy0 + dy : cy0 + dy + big[0], cx0 + dx : cx0 + dx + big[1]].astype(float) @ [0.299, 0.587, 0.114]
            if there.shape != here.shape:
                continue
            diff = np.abs((here - here[ring].mean()) - (there - there[ring].mean()))[ring].mean()
            if diff < best:
                best, at = diff, (dx, dy)
    print(f"  {key}: closed eye offset {at}, mismatch {best:.1f}")
    return region, at, (cx0, cy0)


def ellipse(shape, cx, cy, rx, ry) -> np.ndarray:
    yy, xx = np.mgrid[0 : shape[0], 0 : shape[1]]
    return ((xx - cx) / rx) ** 2 + ((yy - cy) / ry) ** 2 <= 1


def main(src: str, closed_path: str) -> None:
    rgb_full = np.array(Image.open(src).convert("RGB"))
    alpha_full = cut_out(rgb_full)
    x0, y0, x1, y1 = Image.fromarray(alpha_full).getbbox()
    rgb = rgb_full[y0:y1, x0:x1].copy()
    for cx, cy, rx_, ry_ in LOGOS.values():
        replace_logo(rgb, cx, cy, rx_, ry_)
    # The closed-eyes painting, in the cut-out's coordinates (padded, so a
    # shifted window near an edge never runs out).
    cs = np.array(Image.open(closed_path).convert("RGB"))
    closed_src = np.pad(cs, ((40, 40), (40, 40), (0, 0)), mode="edge")[40 + y0 :, 40 + x0 :]
    alpha = alpha_full[y0:y1, x0:x1]
    h, w = alpha.shape
    f = rgb.astype(float)
    lum = f @ [0.299, 0.587, 0.114]
    sat = f.max(2) - f.min(2)

    mask = np.zeros((h, w), np.uint8)
    mask_cov = np.zeros((h, w))
    sprites = []
    closed = np.zeros((h, w, 4), np.uint8)
    keep_frames = np.zeros((h, w), bool)
    out_eyes = []
    for key, (ex, ey, rx, ry, ix, iy, ir) in EYES.items():
        pad = 6
        bx0, by0 = int(ex - rx - pad), int(ey - ry - pad)
        bx1, by1 = int(ex + rx + pad) + 1, int(ey + ry + pad) + 1
        L, S = lum[by0:by1, bx0:bx1], sat[by0:by1, bx0:bx1]
        box = (by1 - by0, bx1 - bx0)
        inside = ellipse(box, ex - bx0, ey - by0, rx + 1.5, ry + 1.5)
        sclera = inside & (L > 150) & (S < 70)
        iris_disc = ellipse(box, ix - bx0, iy - by0, ir + 1, ir + 1)
        core = inside & ellipse(box, ex - bx0, ey - by0, rx - 1, ry - 1)
        pts = np.argwhere(sclera | (iris_disc & core))
        hull = ConvexHull(pts[:, ::-1])
        poly = np.array([pts[v, ::-1] for v in hull.vertices], float)
        # The opening as an anti-aliased shape: the hull through the white's
        # outermost pixel centres, eased out by most of a pixel and drawn at
        # four times the size, so every edge pixel gets its true coverage. A
        # hard-edged region had replaced the artist's soft lid edge with flat
        # white, which showed as steps when the picture was scaled up.
        centre = poly.mean(0)
        out = poly + (poly - centre) / np.linalg.norm(poly - centre, axis=1)[:, None] * 0.8
        K = 4
        m = Image.new("L", (box[1] * K, box[0] * K), 0)
        ImageDraw.Draw(m).polygon([((x + 0.5) * K, (y + 0.5) * K) for x, y in out], fill=255)
        cov = np.array(m.resize((box[1], box[0]), Image.BOX)).astype(float) / 255
        # The hull cuts a straight chord where the iris meets a lid, leaving
        # the iris's last pixels outside it; patched from mixed neighbours they
        # showed as speckled strips along the lower lids. So the opening also
        # takes in the painted iris itself, out to where the skin starts.
        wide = ellipse(box, ex - bx0, ey - by0, rx + 2.5, ry + 2.5)
        iris_px = ellipse(box, ix - bx0, iy - by0, ir + 2.5, ir + 2.5) & (L < 150) & wide
        body = ndimage.binary_fill_holes(ndimage.binary_closing(sclera | iris_px | (cov > 0.5), iterations=2)) & wide
        cov = np.maximum(cov, np.clip(ndimage.gaussian_filter(body.astype(float), 0.6) * 1.6 - 0.3, 0, 1) * wide)
        cov *= wide
        # Never over the lash line: dark pixels on the rim, away from the iris
        # (its own rim, further out than measured, is not lash and goes).
        rim = ~ndimage.binary_erosion(cov > 0.5, iterations=2)
        lash = (L < 110) & rim & ~ellipse(box, ix - bx0, iy - by0, ir + 3.5, ir + 3.5)
        cov[lash] = 0
        opening = cov > 0.5

        orig = rgb[by0:by1, bx0:bx1].astype(float)
        patch = orig.copy()
        # The old iris where it ran under the lids, outside the opening: left
        # in place it showed as dark marks along the lid line whenever the new
        # iris moved away. It is rebuilt from the lid around it.
        ghost = (
            ellipse(box, ix - bx0, iy - by0, ir + 2.5, ir + 2.5)
            & (cov < 0.05)
            & ellipse(box, ex - bx0, ey - by0, rx + 3, ry + 3)
            & (L < 120)
        )
        patch = inpaint(patch, ghost, ~(ghost | (cov > 0)))
        # The eyeball, shaded from the artist's own white: seeded from white
        # away from the iris (whose soft edge and catchlights had seeded grey
        # and white specks), down to the lids' shading at the edges.
        seeds = sclera & (S < 60) & ~ellipse(box, ix - bx0, iy - by0, ir + 3, ir + 3)
        seeds = ndimage.binary_erosion(seeds, iterations=1) & (cov > 0.95)
        to_fill = (cov > 0) & ~seeds
        fill = inpaint(patch, to_fill, seeds, rounds=900)
        a = cov[..., None]
        patch[to_fill] = (fill * a + patch * (1 - a))[to_fill]
        rgb[by0:by1, bx0:bx1] = np.clip(patch, 0, 255).astype(np.uint8)
        np.maximum(mask_cov[by0:by1, bx0:bx1], cov, out=mask_cov[by0:by1, bx0:bx1])

        # The iris as painted, turned into a sprite: its colour at each
        # distance from the centre (rim, brown, pupil), taken from the part
        # the lids leave visible, so the drawn iris is the artist's.
        yy, xx = np.mgrid[0 : box[0], 0 : box[1]]
        rr = np.hypot(xx - (ix - bx0), yy - (iy - by0))
        # Inside the true edge only: sampled out to it, the white blended in
        # and drew a pale ring round some irises.
        seen = (cov > 0.9) & (rr <= ir - 0.5) & (L < 200)
        bins = np.arange(0, ir, 0.5)
        prof = []
        for b0 in bins:
            sel = seen & (rr >= b0) & (rr < b0 + 0.75)
            prof.append(np.median(orig[sel], 0) if sel.sum() >= 2 else None)
        known_i = [i for i, v in enumerate(prof) if v is not None]
        prof = np.array([
            prof[i] if prof[i] is not None
            else prof[min(known_i, key=lambda k: abs(k - i))]
            for i in range(len(prof))
        ])
        n = int(np.ceil((ir + 1.5) * 2 * K))
        sy, sx = np.mgrid[0:n, 0:n]
        sr = np.hypot(sx + 0.5 - n / 2, sy + 0.5 - n / 2) / K
        col = np.stack([np.interp(sr, bins, prof[:, c]) for c in range(3)], -1)
        alpha_s = np.clip(ir + 0.3 - sr, 0, 1)
        sprite = np.dstack([np.clip(col, 0, 255), alpha_s * 255]).astype(np.uint8)
        sprites.append((key, sprite))

        # The eye closed, as the artist painted it (the closed-eyes source):
        # that picture's eye, lined up on this face by the skin around it.
        region, (dx, dy), (cx0, cy0) = closed_eye(f, closed_src, key, ex, ey, rx, ry)
        big = region.shape
        lined = closed_src[cy0 + dy : cy0 + dy + big[0], cx0 + dx : cx0 + dx + big[1]].astype(float)
        here = f[cy0 : cy0 + big[0], cx0 : cx0 + big[1]]
        open_big = np.zeros(big, bool)
        oy, ox = by0 - cy0, bx0 - cx0
        open_big[oy : oy + opening.shape[0], ox : ox + opening.shape[1]] = opening
        # Frames of glasses always come from this picture: the closed one's sit
        # a pixel or two elsewhere, and two frames would show. So the closed
        # eye replaces only what lies inside the lens.
        frames_here = frame_mask(here, open_big, key, ex - cx0, ey - cy0, rx, ry)
        # The closed painting's frames matter only away from the eye: near it
        # they sit where this picture has eye, which must close all the same.
        frames_there = frame_mask(lined, open_big, key, ex - cx0, ey - cy0, rx, ry) & ~ellipse(
            big, ex - cx0, ey - cy0, rx + 4, ry + 4
        )
        frames = frames_here | frames_there
        region &= ~ndimage.binary_dilation(frames, iterations=2)
        # The eye itself always closes, out to its lashes, wherever a frame
        # of the closed painting fell.
        region |= ndimage.binary_dilation(open_big, iterations=2) & ~frames_here
        # Seamless: the difference between the two paintings, known all round
        # the region, is spread smoothly across it and added, so the edge
        # matches exactly instead of on average.
        edge = (
            ndimage.binary_dilation(region, iterations=2)
            & ~region
            & ~ndimage.binary_dilation(frames, iterations=3)
        )
        diff = np.zeros(big + (3,))
        diff[edge] = here[edge] - lined[edge]
        # Only skin against skin: where one painting has a frame edge, a lash
        # or a glint the other has not, the difference is not shading, and
        # spread across the lens it smeared.
        edge &= np.abs(diff @ [0.299, 0.587, 0.114]) < 22
        diff[~edge] = 0
        # Too few samples (an eye ringed by frame) means no correction rather
        # than one guessed from nothing, which turned that eye white.
        if edge.sum() >= 8:
            diff = inpaint(diff, region, edge, rounds=900)
        else:
            diff[:] = 0
        lined[region] += diff[region]
        sub = closed[cy0 : cy0 + big[0], cx0 : cx0 + big[1]]
        sub[..., :3][region] = np.clip(lined[region], 0, 255).astype(np.uint8)
        sub[..., 3][region] = 255
        keep_frames[cy0 : cy0 + big[0], cx0 : cx0 + big[1]] |= frames
        ry_, rx_ = np.nonzero(region)
        bx0_, by0_ = cx0, cy0
        # Out to where the feathered edge (below) fades away.
        f_ = 7
        lid_box = (
            max(0, bx0_ + rx_.min() - f_), max(0, by0_ + ry_.min() - f_),
            min(w, bx0_ + rx_.max() + 1 + f_), min(h, by0_ + ry_.max() + 1 + f_),
        )

        out_eyes.append(dict(
            id=key, ex=ex, ey=ey, rx=rx, ry=ry, ix=ix, iy=iy, ir=ir,
            lid_box=[float(v) for v in lid_box],
        ))

    OUT.mkdir(parents=True, exist_ok=True)
    base = Image.fromarray(np.dstack([rgb, alpha]), "RGBA")
    base.save(OUT / "characters.webp", quality=90, method=6)
    # White, with the openings in the alpha channel: the app composites it
    # with BlendMode.dstIn, which reads alpha only.
    # A half-pixel soft edge, so what is drawn in an eye meets the lid
    # anti-aliased instead of stepped.
    # The openings' own anti-aliased coverage, as drawn above.
    mask[:] = (mask_cov > 0.5) * 255
    soft = np.clip(mask_cov * 255, 0, 255).astype(np.uint8)
    openings = np.dstack([np.full_like(mask, 255)] * 3 + [soft])

    # The irises, side by side in one image; each eye records its place.
    atlas_w = sum(sp.shape[1] + 2 for _, sp in sprites)
    atlas_h = max(sp.shape[0] for _, sp in sprites)
    atlas = np.zeros((atlas_h, atlas_w, 4), np.uint8)
    places = {}
    x = 0
    for k, sp in sprites:
        atlas[: sp.shape[0], x : x + sp.shape[1]] = sp
        places[k] = (x, 0, x + sp.shape[1], sp.shape[0])
        x += sp.shape[1] + 2
    Image.fromarray(atlas, "RGBA").save(OUT / "irises.png", optimize=True)
    for e in out_eyes:
        e["sprite"] = places[e["id"]]
    Image.fromarray(openings, "RGBA").save(OUT / "eye_openings.png", optimize=True)
    # Feathered inward: the patch already meets the face seamlessly at its
    # border, so its edge fades over its own pixels. (Spreading colour outward
    # took the brightest neighbour and drew a light ring round each eye.)
    a = closed[..., 3] > 0
    closed[..., 3] = (np.clip(ndimage.gaussian_filter(a.astype(float), 1.5) * 2 - 1, 0, 1) * 255 * a).astype(np.uint8)
    # Frames stay this picture's, edge and all.
    closed[..., 3][ndimage.binary_dilation(keep_frames, iterations=1) & (mask == 0)] = 0
    # Lossless: lossy WebP traced the soft edge with a dotted line.
    Image.fromarray(closed, "RGBA").save(OUT / "eyes_closed.webp", lossless=True, method=6)

    lines = [
        "// Generated by tool/brand/make_hero.py — do not edit by hand.",
        "",
        "import 'dart:ui';",
        "",
        "import 'hero_eye.dart';",
        "",
        "/// The hero picture's size, in its own pixels.",
        f"const heroSize = Size({w}, {h});",
        "",
        "/// Every eye in the hero, measured on the picture.",
        "const heroEyes = <HeroEye>[",
    ]
    for e in out_eyes:
        lines.append(
            f"  HeroEye(opening: Rect.fromLTRB({e['ex'] - e['rx']}, {e['ey'] - e['ry']}, "
            f"{e['ex'] + e['rx']}, {e['ey'] + e['ry']}), iris: Offset({e['ix']}, {e['iy']}), "
            f"irisRadius: {e['ir']}, "
            f"lidArea: Rect.fromLTRB({', '.join(str(v) for v in e['lid_box'])}), "
            f"irisSprite: Rect.fromLTRB({', '.join(str(float(v)) for v in e['sprite'])})),"
        )
    lines += ["];", ""]
    DART.parent.mkdir(parents=True, exist_ok=True)
    DART.write_text("\n".join(lines), encoding="utf-8")
    # A record of the measurements, for inspecting the eyes; not shipped.
    json.dump(out_eyes, open(Path(__file__).with_name("hero-eyes.json"), "w"), indent=1)
    print(f"hero {w}x{h}, {len(out_eyes)} eyes")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
