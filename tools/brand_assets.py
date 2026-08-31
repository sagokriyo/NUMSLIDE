"""Brand asset pipeline - studio intro logo + Android launcher icon.

Takes the two authored source images in `brand/` and derives every sized
variant the project actually ships. Re-run it whenever a source is redrawn;
nothing downstream is hand-edited, so the derivatives can always be rebuilt.

    python tools/brand_assets.py            # write the assets
    python tools/brand_assets.py --preview  # also render the mask preview sheet

Sources (kept out of the APK by export_presets' exclude_filter):
    brand/sagokriyo_logo_source.png   wide studio wordmark, any resolution
    brand/app_icon_source.png         square app icon art, any resolution

Derivatives:
    assets/images/sagokriyo_logo.png            intro screen (scenes/splash/intro)
    assets/icon/launcher_192.png                Android legacy launcher icon
    assets/icon/adaptive_foreground_432.png     Android adaptive foreground
    assets/icon/adaptive_background_432.png     Android adaptive background
    assets/icon/adaptive_monochrome_432.png     Android 13+ themed-icon glyph
    icon.png                                    editor / desktop window icon
    tools/out/play_store_512.png                Play Console hi-res icon (not in the APK)

ADAPTIVE ICON GEOMETRY - the part that is easy to get wrong. Android composites
the two 432x432 layers, then cuts a launcher-chosen mask out of the result: a
circle on Pixel, a squircle on Samsung, a rounded square elsewhere. Crucially
the outer 18 of 108dp on every side is ALWAYS discarded, so the mask is
inscribed in the central 288px - a layer authored full-bleed loses a quarter of
its width before any mask is even chosen.

EXACT FIT. The art is a rounded-square badge with its own neon frame, and that
frame has to BE the icon's edge or the result reads as a sticker floating on a
wash. So the badge is cropped to the frame's outer edge (not its glow halo),
stretched square (the source is ~1% off), and scaled to the 288px viewport plus
BLEED so anti-aliased mask edges never expose a dark hairline. Its corner
radius (~22% of the width) matches a rounded-square launcher; for masks with a
tighter corner, the wedge outside the frame is filled in the BACKGROUND layer
by growing the frame's own glow outward (`_square_off`), so every mask shape
cuts through glow, never through a foreign colour. Squircle and circle masks cut
INSIDE the badge and clip its corner tiles - that is inherent to a square
composition and the same trade every framed game icon makes. The rest of the
background is a blurred, dimmed wash of the art, only ever seen in the
launcher's drag / parallax animations.

HERO LAYOUT. The art as drawn is a feature graphic - mascot, nine tiles, the
wordmark, a pill and an infinity glyph - and at launcher size (48dp) all of it
is tiny: the hollow neon letters thin to pale outlines, the mascot's face is
~14dp wide. So ICON_LAYOUT="hero" re-composes the SAME art for the icon: the
mascot lifted out and enlarged 1.5x, the SUDOKU wordmark with its dark glass
strokes filled (a gamma lift + saturation push inside the letter shapes, so
they read as solid candy at 48dp), and the LIMITLESS pill under it, all on the
original frame over a clean plum vignette. The letters cannot get wider - the
frame pins the wordmark's width - so they are stretched a touch taller instead.
Every cut is a mask on the source (luminance / saturation / hue, seeded flood
fills, a few measured exclusions where a tile sits behind a letter), so the
derivatives are still rebuilt from brand/ alone. ICON_LAYOUT="full" is the
badge exactly as drawn.

THEMED ICONS (Android 13+) tint the alpha of a single-colour monochrome layer.
That slot is NOT optional in practice: left empty, Godot ships the export
template's own glyph - the Godot robot - and every phone with themed icons on
shows a robot for this game. The art is bright shapes on a black field, so its
luminance IS the glyph; the ramp below turns it into a soft silhouette.
"""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent

SRC_LOGO = ROOT / "brand" / "sagokriyo_logo_source.png"
SRC_ICON = ROOT / "brand" / "app_icon_source.png"

OUT_LOGO = ROOT / "assets" / "images" / "sagokriyo_logo.png"
OUT_ICON_DIR = ROOT / "assets" / "icon"
OUT_WINDOW_ICON = ROOT / "icon.png"
OUT_PLAY_ICON = ROOT / "tools" / "out" / "play_store_512.png"

# The intro draws the wordmark at 92% of the screen width, so a 1440p phone asks
# for ~1325 real px of it. 1200 was UNDER that: the texture was upscaled on the
# way to the panel, which is exactly what read as soft. Keep the authored width.
LOGO_MAX_W = 1536

FRAME = 432     # adaptive layer size Godot expects
VIEWPORT = 288  # the 72 of 108dp Android actually shows, at 432px authoring size
BLEED = 3       # px the badge overhangs the viewport on each side

# Pixels of blur on the full-bleed background wash, at 432px.
BG_BLUR = 20

# How far the background wash is dimmed. At full strength it is as bright as the
# artwork sitting on it, and the badge's edge dissolves into its own halo; held
# down here, the same wash still fills the frame but the art reads as the subject.
BG_DIM = 0.42

# Luminance at or below which a pixel counts as the flat backing field.
DARK_LEVEL = 26

# Luminance at which the frame's outer edge is found. The glow halo outside the
# frame is fainter than this; the frame line itself is far brighter.
EDGE_LEVEL = 50

# Luminance ramp for the themed-icon glyph: at or below MONO_LO a pixel is
# transparent, at or above MONO_HI fully opaque, smoothstepped between. LO sits
# above the dark starfield and tile interiors so only the lit shapes survive.
MONO_LO, MONO_HI = 40, 150


def _trim_dark(img: Image.Image, threshold: int = 12) -> Image.Image:
    """Crop the flat near-black margin the source art is rendered on.

    Uses a luminance threshold rather than getbbox()'s alpha test, because both
    sources are fully opaque - their "empty" margin is black pixels, not
    transparent ones, so getbbox() would return the whole frame.
    """
    grey = img.convert("L").point(lambda v: 255 if v > threshold else 0)
    box = grey.getbbox()
    return img.crop(box) if box else img


def build_logo() -> None:
    src = Image.open(SRC_LOGO).convert("RGBA")
    art = _trim_dark(src)
    if art.width > LOGO_MAX_W:
        h = round(art.height * LOGO_MAX_W / art.width)
        art = art.resize((LOGO_MAX_W, h), Image.LANCZOS)
    OUT_LOGO.parent.mkdir(parents=True, exist_ok=True)
    art.save(OUT_LOGO, optimize=True)
    print(f"  {OUT_LOGO.relative_to(ROOT)}  {art.width}x{art.height}")


def _key_corners(art: Image.Image) -> Image.Image:
    """Punch the black OUTSIDE the badge's rounded corners to transparent.

    A bounding-box crop leaves those four black wedges behind, and against the
    coloured background layer they read as a hard black square framing the
    icon. Thresholding luminance alone would also punch holes in the badge's
    own dark interior, so instead flood the near-black region inward from each
    corner: the badge's bright rim stops the fill, and everything it reaches is
    by definition outside the art.
    """
    dark = art.convert("L").point(lambda v: 255 if v <= DARK_LEVEL else 0)
    w, h = dark.size
    for seed in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)):
        if dark.getpixel(seed) == 255:
            ImageDraw.floodfill(dark, seed, 128, thresh=0)
    alpha = np.where(np.array(dark) == 128, 0, 255).astype(np.uint8)
    out = art.copy()
    out.putalpha(Image.fromarray(alpha, "L").filter(ImageFilter.GaussianBlur(1.1)))
    return out


def _icon_art(layout: str | None = None) -> Image.Image:
    """The badge cut to its frame's outer edge, transparent outside the frame.

    Not squared here: the source frame is a hair off square, and padding it
    would put that hair of margin back on two sides. `_fit` stretches it.
    """
    src = Image.open(SRC_ICON).convert("RGB")
    if (layout or ICON_LAYOUT) == "hero":
        src = _hero_compose(src)
    return _key_corners(_trim_dark(src.convert("RGBA"), EDGE_LEVEL))


# ---------------------------------------------------------------------------
# HERO LAYOUT - the art re-composed for a launcher (see the module docstring).
# ---------------------------------------------------------------------------
# "hero": mascot enlarged, the SUDOKU wordmark with its glass strokes filled,
# the LIMITLESS pill - on the original frame. "full": the badge as drawn.
ICON_LAYOUT = "full"

# Every coordinate below was measured on brand/app_icon_source.png at HERO_REF
# px square, and the source is resampled to HERO_REF before cutting - so a
# lossless re-export of the SAME composition at any resolution still cuts in
# the right places. A redrawn composition needs them re-measured (or
# ICON_LAYOUT = "full" until it is).
HERO_REF = 1254
# The mascot: body + four tufts, each flood-filled from its own seed inside a
# keep box whose bottom edge cuts the hands flat where the wordmark will sit.
# Tiles 2 / 3 lean into that box; they are refused by hue - the mascot has no
# green, and its only blue (the middle tuft) is right of x 600.
HERO_MASCOT_KEEP = (440, 85, 852, 454)
HERO_MASCOT_SEEDS = ((650, 310), (570, 125), (655, 125), (720, 165), (520, 185))
HERO_MASCOT_BLUE_LEFT_OF = 600
# The wordmark: the rows the letters own (hands above, tiles 5-9 below), the two
# slivers where tile 1 (purple, BEHIND the S) peeks out beside the S, and the
# zone where tile 4 (orange, behind the second U) shows above the K / U.
HERO_WORD_BAND = (60, 454, 1200, 704)
HERO_WORD_SLIVERS = ((60, 444, 91, 552), (263, 444, 287, 552))
HERO_WORD_TILE4_ZONE = (900, 0, HERO_REF, 552)   # orange in here is tile 4, not a letter
HERO_WORD_TILE_ZONES = ((0, 0, 345, 552), (900, 0, HERO_REF, 552))  # only the letters' immediate glow
HERO_STROKE_CLOSE = 16      # closes the hollow glass strokes; the O's counter (~80px) stays open
HERO_GLASS_GAMMA = 0.55     # value^gamma inside the strokes - lifts the dark glass
HERO_GLASS_SAT = 1.28       # saturation push inside the strokes
# The LIMITLESS pill: a stadium whose rim is a hairline the flood fill breaks on,
# so it is cut by its measured outline.
HERO_PILL = (231, 962, 1026, 1068)
HERO_PILL_RADIUS = 53
# Tiles 5-9 are only found to keep their glow OUT of the wordmark's halo.
HERO_TILE_SEEDS = ((210, 850), (425, 830), (640, 830), (855, 830), (1070, 850))
HERO_TILE_BOXES = ((75, 690, 340, 1000), (300, 690, 545, 960), (520, 690, 750, 950),
                   (725, 690, 975, 960), (935, 700, 1200, 1000))
# The frame's interior is repainted (a plum vignette) this far inside the
# frame's outer edge, feathered into its inner glow; a few of the art's own
# sparkles are put back on it.
HERO_INSET = 46
HERO_VIGNETTE = ((34, 20, 60), (9, 7, 16))
HERO_SPARKLES = ((1097, 209), (155, 240), (300, 168), (930, 92),
                 (1025, 1090), (190, 1010), (140, 670), (1170, 680))
# Placement, all vs the source's own scale.
HERO_MASCOT_SCALE = 1.5     # the face is the thing that has to read
HERO_WORD_STRETCH = 1.16    # letters a touch taller; the frame pins their width
HERO_PILL_W = 780
HERO_GAP_WORD_PILL = 26
HERO_HANDS_OVERLAP = 40     # the hands rest on the letters (at a 300px-tall word)


def _h_lum(a: np.ndarray) -> np.ndarray:
    return a[..., 0] * 0.299 + a[..., 1] * 0.587 + a[..., 2] * 0.114


def _h_hsv(a: np.ndarray) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Hue (degrees), saturation and value of an RGB float array."""
    r, g, b = a[..., 0] / 255, a[..., 1] / 255, a[..., 2] / 255
    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    d = mx - mn
    s = np.where(mx > 0, d / np.maximum(mx, 1e-6), 0)
    dd = np.maximum(d, 1e-6)
    rc, gc, bc = (mx - r) / dd, (mx - g) / dd, (mx - b) / dd
    h = np.where(mx == r, bc - gc, np.where(mx == g, 2.0 + rc - bc, 4.0 + gc - rc))
    h = np.where(d > 1e-6, (h / 6.0) % 1.0 * 360.0, 0.0)
    return h, s, mx


def _h_rect(shape: tuple[int, int], box: tuple[int, int, int, int]) -> np.ndarray:
    m = np.zeros(shape, bool)
    m[box[1]:box[3], box[0]:box[2]] = True
    return m


def _h_filter(mask: np.ndarray, f: ImageFilter.Filter) -> np.ndarray:
    return np.asarray(Image.fromarray((mask * 255).astype(np.uint8)).filter(f)) > 127


def _h_dilate(mask: np.ndarray, r: int) -> np.ndarray:
    return _h_filter(mask, ImageFilter.MaxFilter(2 * r + 1))


def _h_close(mask: np.ndarray, r: int) -> np.ndarray:
    return _h_filter(_h_dilate(mask, r), ImageFilter.MinFilter(2 * r + 1))


def _h_component(mask: np.ndarray, seed: tuple[int, int]) -> np.ndarray:
    """The connected region of `mask` containing `seed` (x, y)."""
    # .copy(): fromarray hands back a read-only buffer image, and floodfill
    # swallows the write error and silently does nothing on it.
    img = Image.fromarray((mask * 255).astype(np.uint8)).copy()
    if img.getpixel(seed) != 255:
        raise RuntimeError(f"hero layout: no art at seed {seed} - re-measure the constants")
    ImageDraw.floodfill(img, seed, 128, thresh=0)
    return np.asarray(img) == 128


def _h_seed(mask: np.ndarray, near: tuple[int, int], reach: int = 120) -> tuple[int, int]:
    """The first lit pixel found spiralling out from `near`."""
    x, y = near
    for r in range(0, reach, 2):
        for dx, dy in ((0, 0), (r, 0), (-r, 0), (0, r), (0, -r), (r, r), (-r, -r), (r, -r), (-r, r)):
            if mask[y + dy, x + dx]:
                return (x + dx, y + dy)
    raise RuntimeError(f"hero layout: no art near {near} - re-measure the constants")


def _h_fill_holes(mask: np.ndarray) -> np.ndarray:
    inv = Image.fromarray(np.pad(((~mask) * 255).astype(np.uint8), 1, constant_values=255)).copy()
    ImageDraw.floodfill(inv, (0, 0), 128, thresh=0)
    return ~(np.asarray(inv)[1:-1, 1:-1] == 128)


def _h_cutout(src: Image.Image, alpha: np.ndarray, feather: float = 1.0, fade_bottom: int = 0) -> Image.Image:
    """RGBA crop of `src` at the bbox of `alpha` (full-image float 0..1)."""
    ys, xs = np.where(alpha > 0.02)
    box = (int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1)
    m = alpha[box[1]:box[3], box[0]:box[2]].astype(np.float32)
    if fade_bottom:
        ramp = np.ones(m.shape[0], np.float32)
        ramp[-fade_bottom:] = np.linspace(1, 0, fade_bottom)
        m = m * ramp[:, None]
    a = Image.fromarray((m * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(feather))
    out = src.crop(box).convert("RGBA")
    out.putalpha(a)
    return out


def _hero_compose(src: Image.Image) -> Image.Image:
    """The icon re-composed from the source art: frame + mascot + wordmark + pill."""
    if src.size != (HERO_REF, HERO_REF):
        src = src.resize((HERO_REF, HERO_REF), Image.LANCZOS)
    a = np.asarray(src).astype(np.float32)
    shape = a.shape[:2]
    yy, xx = np.mgrid[0:shape[0], 0:shape[1]]
    lum = _h_lum(a)
    hue, sat, val = _h_hsv(a)

    def lit(lum_t: float, sat_t: float, v_t: float) -> np.ndarray:
        return (lum > lum_t) | ((sat > sat_t) & (val > v_t))

    def hue_in(lo: float, hi: float) -> np.ndarray:
        return (hue >= lo) & (hue <= hi) & (sat > 0.25)

    # --- mascot
    mm = ((lum > 85) | ((sat > 0.5) & (val > 0.45))) & _h_rect(shape, HERO_MASCOT_KEEP)
    mm &= ~hue_in(90, 175)                                      # tile 3 (green) and its glow
    mm &= ~(hue_in(195, 255) & (xx < HERO_MASCOT_BLUE_LEFT_OF))  # tile 2 (blue) and its glow
    mascot_mask = np.zeros(shape, bool)
    for sd in HERO_MASCOT_SEEDS:
        mascot_mask |= _h_component(mm, _h_seed(mm, sd, 40))
    mascot_mask = _h_fill_holes(_h_dilate(mascot_mask, 2))
    mascot = _h_cutout(src, mascot_mask.astype(np.float32), fade_bottom=8)

    # --- tiles 5-9 (their glow must stay out of the wordmark's halo)
    tiles_mask = np.zeros(shape, bool)
    for sd, tb in zip(HERO_TILE_SEEDS, HERO_TILE_BOXES):
        tm = lit(60, 0.45, 0.30) & _h_rect(shape, tb)
        tiles_mask |= _h_fill_holes(_h_close(_h_component(tm, _h_seed(tm, sd)), 10))

    # --- wordmark
    slivers = ~(hue_in(8, 48) & _h_rect(shape, HERO_WORD_TILE4_ZONE))
    for box in HERO_WORD_SLIVERS:
        slivers &= ~_h_rect(shape, box)
    wm = lit(55, 0.45, 0.30) & _h_rect(shape, HERO_WORD_BAND) & slivers
    letters = np.zeros(shape, bool)
    x0, y0, x1, y1 = HERO_WORD_BAND
    mid = (y0 + y1) // 2
    for sx in range(x0 + 30, x1 - 10, 8):
        for sy in (mid - 20, mid + 20):
            if wm[sy, sx] and not letters[sy, sx]:
                letters |= _h_component(wm, (sx, sy))
    solid = _h_close(letters, HERO_STROKE_CLOSE)
    # The neon halo, from luminance, kept close to the letters and off the
    # hands (above), the tiles (below) and the tiles peeking out behind.
    halo = np.clip((lum - 36) / (75 - 36), 0, 1) * _h_rect(shape, (x0, y0 + 2, x1, y1 + 16))
    halo *= _h_dilate(solid, 8)
    halo *= ~_h_dilate(tiles_mask | mascot_mask, 4)
    halo *= slivers
    near = _h_dilate(solid, 3)
    for box in HERO_WORD_TILE_ZONES:
        halo *= ~(_h_rect(shape, box) & ~near)
    alpha_w = np.maximum(solid.astype(np.float32), halo)
    # The "pale" fix: lift the dark glass inside the strokes and saturate.
    rgb = a.copy()
    inside = solid & ~(lum > 150)
    vv = np.where(inside, np.power(np.clip(val, 0, 1), HERO_GLASS_GAMMA), val)
    rgb = rgb * np.where(val > 1e-4, vv / np.maximum(val, 1e-4), 1.0)[..., None]
    grey = _h_lum(rgb)[..., None]
    rgb = grey + (rgb - grey) * np.where(solid, HERO_GLASS_SAT, 1.0)[..., None]
    boosted = Image.fromarray(rgb.clip(0, 255).astype(np.uint8))
    word = _h_cutout(boosted, alpha_w).filter(ImageFilter.UnsharpMask(radius=3, percent=90, threshold=2))

    # --- pill
    pill_alpha = Image.new("L", src.size, 0)
    ImageDraw.Draw(pill_alpha).rounded_rectangle(HERO_PILL, radius=HERO_PILL_RADIUS, fill=255)
    pill = _h_cutout(src, np.asarray(pill_alpha).astype(np.float32) / 255, feather=1.5)

    # --- base: the frame, its interior repainted as a vignette
    fx0, fy0, fx1, fy1 = src.convert("L").point(lambda v: 255 if v > EDGE_LEVEL else 0).getbbox()
    ix0, iy0, ix1, iy1 = fx0 + HERO_INSET, fy0 + HERO_INSET, fx1 - HERO_INSET, fy1 - HERO_INSET
    fill = Image.new("L", src.size, 0)
    ImageDraw.Draw(fill).rounded_rectangle(
        (ix0, iy0, ix1, iy1), radius=int((fx1 - fx0) * 0.22) - HERO_INSET, fill=255)
    fm = (np.asarray(fill.filter(ImageFilter.GaussianBlur(14))).astype(np.float32) / 255)[..., None]
    cx, cy = (fx0 + fx1) / 2, (fy0 + fy1) / 2
    dist = np.sqrt(((xx - cx) / (fx1 - fx0) * 2) ** 2 + ((yy - cy) / (fy1 - fy0) * 2) ** 2)
    t = np.clip(dist, 0, 1)[..., None]
    c0, c1 = (np.array(c, np.float32) for c in HERO_VIGNETTE)
    inner = c0 * (1 - t) + c1 * t
    base = Image.fromarray((a * (1 - fm) + inner * fm).clip(0, 255).astype(np.uint8)).convert("RGBA")
    for sx, sy in HERO_SPARKLES:
        r = 26
        crop = src.crop((sx - r, sy - r, sx + r, sy + r)).convert("RGBA")
        la = np.clip((_h_lum(np.asarray(crop).astype(np.float32)[..., :3]) - 20) / 60, 0, 1)
        crop.putalpha(Image.fromarray((la * 255).astype(np.uint8)))
        base.alpha_composite(crop, (sx - r, sy - r))

    # --- layout: mascot over the word (hands resting on the letters), pill under
    ww = (ix1 - ix0) - 8
    wh = int(word.height * (ww / word.width) * HERO_WORD_STRETCH)
    word_s = word.resize((ww, wh), Image.LANCZOS)
    mw, mh = int(mascot.width * HERO_MASCOT_SCALE), int(mascot.height * HERO_MASCOT_SCALE)
    mascot_s = mascot.resize((mw, mh), Image.LANCZOS)
    ph = int(pill.height * HERO_PILL_W / pill.width)
    pill_s = pill.resize((HERO_PILL_W, ph), Image.LANCZOS)
    over = int(HERO_HANDS_OVERLAP * (wh / 300))
    total = mh - over + wh + HERO_GAP_WORD_PILL + ph
    top = iy0 + ((iy1 - iy0) - total) // 2
    out = base.copy()
    out.alpha_composite(mascot_s, (int(cx - mw / 2), top))
    wy = top + mh - over
    out.alpha_composite(word_s, (int(cx - ww / 2), wy))
    out.alpha_composite(pill_s, (int(cx - HERO_PILL_W / 2), wy + wh + HERO_GAP_WORD_PILL))
    return out.convert("RGB")


def _fit(art: Image.Image, side: int) -> Image.Image:
    """The badge at `side` px square. The ~1% aspect correction is invisible."""
    return art.resize((side, side), Image.LANCZOS)


def _square_off(badge: Image.Image, reach: int = 64) -> Image.Image:
    """Fill the transparent corner wedges by growing the frame's glow outward.

    Each pass gives every still-empty pixel the mean of its filled neighbours,
    so the wedge takes the colour of the frame's outer glow right beside it and
    the fill fades naturally instead of ending in a seam. `reach` passes cover
    a wedge of that depth; a 22%-radius corner on a 294px badge is ~20px deep.
    """
    rgb = np.asarray(badge.convert("RGB"), dtype=np.float32)
    known = np.asarray(badge.getchannel("A")) > 8
    # Pad by one so the neighbour rolls never wrap to the far side of the badge.
    rgb = np.pad(rgb, ((1, 1), (1, 1), (0, 0)))
    known = np.pad(known, 1)
    for _ in range(reach):
        if known.all():
            break
        acc = np.zeros_like(rgb)
        cnt = np.zeros(known.shape, np.float32)
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                k = np.roll(np.roll(known, dy, 0), dx, 1)
                acc += np.roll(np.roll(rgb, dy, 0), dx, 1) * k[..., None]
                cnt += k
        grow = ~known & (cnt > 0)
        rgb[grow] = acc[grow] / cnt[grow][:, None]
        known |= grow
    out = Image.fromarray(rgb[1:-1, 1:-1].clip(0, 255).astype(np.uint8), "RGB")
    return out.convert("RGBA")


def _wash(badge: Image.Image) -> Image.Image:
    """Full-bleed blurred, dimmed smear of the badge's own colours."""
    big = int(FRAME * 1.35)
    bg = badge.convert("RGB").resize((big, big), Image.LANCZOS)
    off = (big - FRAME) // 2
    bg = bg.crop((off, off, off + FRAME, off + FRAME)).filter(ImageFilter.GaussianBlur(BG_BLUR))
    dimmed = (np.asarray(bg, dtype=np.float32) * BG_DIM).astype(np.uint8)
    wash = Image.new("RGBA", (FRAME, FRAME), (11, 12, 15, 255))
    wash.alpha_composite(Image.fromarray(dimmed, "RGB").convert("RGBA"))
    return wash


def _monochrome(badge: Image.Image) -> Image.Image:
    """White-on-transparent glyph of the badge for Android's themed icons."""
    lum = np.asarray(badge.convert("L"), dtype=np.float32)
    a = np.clip((lum - MONO_LO) / (MONO_HI - MONO_LO), 0.0, 1.0)
    a = a * a * (3.0 - 2.0 * a)
    alpha = Image.fromarray((a * 255).astype(np.uint8), "L")
    alpha = alpha.filter(ImageFilter.GaussianBlur(0.8))
    alpha = ImageChops.multiply(alpha, badge.getchannel("A"))  # keep the keyed corners
    out = Image.new("RGBA", badge.size, (255, 255, 255, 255))
    out.putalpha(alpha)
    return out


def build_icons(preview: bool) -> None:
    art = _icon_art()
    OUT_ICON_DIR.mkdir(parents=True, exist_ok=True)

    # Legacy launcher icon and the desktop window icon show the art unmasked,
    # so they take the badge as-is: full-bleed, transparent outside the frame.
    for path, size in ((OUT_ICON_DIR / "launcher_192.png", 192), (OUT_WINDOW_ICON, 256)):
        _fit(art, size).save(path, optimize=True)
        print(f"  {path.relative_to(ROOT)}  {size}x{size}")

    side = VIEWPORT + 2 * BLEED
    off = (FRAME - side) // 2
    badge = _fit(art, side)

    # Background: the wash everywhere, and under the viewport the badge with its
    # corner wedges grown shut, so a tight-cornered mask still cuts through glow.
    bg = _wash(badge)
    bg.paste(_square_off(badge), (off, off))
    bg_path = OUT_ICON_DIR / "adaptive_background_432.png"
    bg.save(bg_path, optimize=True)
    print(f"  {bg_path.relative_to(ROOT)}  {FRAME}x{FRAME}")

    # Foreground: the badge itself, frame on the viewport edge, on transparency.
    fg = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
    fg.paste(badge, (off, off))
    fg_path = OUT_ICON_DIR / "adaptive_foreground_432.png"
    fg.save(fg_path, optimize=True)
    print(f"  {fg_path.relative_to(ROOT)}  {FRAME}x{FRAME}  (badge {side}px on the {VIEWPORT}px viewport)")

    # Monochrome: the same placement, as a tintable silhouette.
    mono = Image.new("RGBA", (FRAME, FRAME), (0, 0, 0, 0))
    mono.paste(_monochrome(badge), (off, off))
    mono_path = OUT_ICON_DIR / "adaptive_monochrome_432.png"
    mono.save(mono_path, optimize=True)
    print(f"  {mono_path.relative_to(ROOT)}  {FRAME}x{FRAME}  (themed-icon glyph)")

    # Play Console wants a full-bleed opaque 512 and rounds the corners itself.
    OUT_PLAY_ICON.parent.mkdir(parents=True, exist_ok=True)
    _square_off(_fit(art, 512)).save(OUT_PLAY_ICON, optimize=True)
    print(f"  {OUT_PLAY_ICON.relative_to(ROOT)}  512x512  (upload to Play Console)")

    if preview:
        _preview(Image.alpha_composite(bg, fg), mono)


def _mask(shape: str) -> Image.Image:
    """One launcher mask, drawn at 4x for a clean anti-aliased downsample."""
    s = VIEWPORT * 4
    m = Image.new("L", (s, s), 0)
    d = ImageDraw.Draw(m)
    if shape == "circle":
        d.ellipse((0, 0, s - 1, s - 1), fill=255)
    else:
        radius = 0.42 if shape == "squircle" else 0.22
        d.rounded_rectangle((0, 0, s - 1, s - 1), radius=int(s * radius), fill=255)
    return m.resize((VIEWPORT, VIEWPORT), Image.LANCZOS)


def _preview(composite: Image.Image, mono: Image.Image) -> None:
    """Render the composite as the three common launchers would show it,
    plus the monochrome glyph tinted the way a themed-icon launcher does.

    Models the 18dp crop first - the outer quarter of the 432px frame never
    reaches the screen - then masks what is left. Previewing a mask inscribed
    in the full frame instead makes the artwork look far smaller than it ships.
    """
    inset = (FRAME - VIEWPORT) // 2
    seen = composite.crop((inset, inset, inset + VIEWPORT, inset + VIEWPORT))
    shapes = ("circle", "squircle", "rounded")
    pad = 28
    sheet = Image.new(
        "RGBA", (VIEWPORT * 4 + pad * 5, VIEWPORT + pad * 2), (24, 24, 28, 255)
    )
    for i, shape in enumerate(shapes):
        tile = seen.copy()
        tile.putalpha(_mask(shape))
        sheet.alpha_composite(tile, (pad + i * (VIEWPORT + pad), pad))
    # Themed: a Material You pairing - the glyph's alpha tinted onto a pastel disc.
    glyph = mono.crop((inset, inset, inset + VIEWPORT, inset + VIEWPORT))
    themed = Image.new("RGBA", (VIEWPORT, VIEWPORT), (205, 222, 255, 255))
    ink = Image.new("RGBA", (VIEWPORT, VIEWPORT), (28, 52, 110, 255))
    ink.putalpha(glyph.getchannel("A"))
    themed.alpha_composite(ink)
    themed.putalpha(_mask("circle"))
    sheet.alpha_composite(themed, (pad + 3 * (VIEWPORT + pad), pad))
    out = ROOT / "tools" / "out" / "icon_masks.png"
    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out)
    print(f"  {out.relative_to(ROOT)}  preview: {', '.join(shapes)}, themed")
    _sizes_sheet()


def _sizes_sheet() -> None:
    """Both layouts at launcher sizes (48dp at 4x / 3x / 2x, and 64px), on a
    wallpaper-ish ground - the legibility check the hero layout exists for.
    """
    sizes = (192, 144, 96, 64)
    pad = 30
    sheet = Image.new("RGBA", (sum(sizes) + pad * (len(sizes) + 1), 192 * 2 + pad * 3), (58, 66, 96, 255))
    for row, layout in enumerate(("full", "hero")):
        art = _icon_art(layout)
        x = pad
        for side in sizes:
            tile = _fit(art, side)
            tile.putalpha(ImageChops.multiply(tile.getchannel("A"), _mask("rounded").resize((side, side), Image.LANCZOS)))
            sheet.alpha_composite(tile, (x, pad + row * (192 + pad)))
            x += side + pad
    out = ROOT / "tools" / "out" / "icon_sizes.png"
    sheet.save(out)
    print(f"  {out.relative_to(ROOT)}  preview: full vs hero at {', '.join(map(str, sizes))} px")


def main() -> int:
    missing = [p for p in (SRC_LOGO, SRC_ICON) if not p.exists()]
    if missing:
        for p in missing:
            print(f"missing source: {p.relative_to(ROOT)}", file=sys.stderr)
        return 1
    build_logo()
    build_icons("--preview" in sys.argv)
    print("\nNow re-import so Godot picks up the new files:")
    print('  & "D:\\Godot_v4.7.1-stable_win64_console.exe" --headless --path . --import')
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
