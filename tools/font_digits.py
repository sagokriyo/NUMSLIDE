#!/usr/bin/env python3
"""Digit legibility pass on Malam Poek — derives assets/fonts/MalamPoek.ttf.

Malam Poek's 1 and 7 are both "a slanted stem with a hat": the 1 wears a short
flag at the top-left, the 7 a wider bar, and at cell / note size the two
collapse into one silhouette (user report 2026-08-29: "1 and 7 are very close
looking and confusing"). Nothing in the app draws a digit outside this font —
the board's givens, candy tiles and pencil notes, the DigitPad, cage sums, the
HUD and the splash tiles all route through `ThemeManager.cell_font` /
`display_font` — so the fix lives in the font and lands everywhere at once.

What it does, from the UNTOUCHED original in `tools/font_src/MalamPoek.ttf`:

  * the 1 grows a FOOT — a horizontal base the 7 can never have — drawn in
    the face's own bubble language (a rounded slab with the shine dashes every
    horizontal stroke wears) and unioned into the stem with skia-pathops so the
    glyph stays one clean outer contour plus its dash holes. Side bearings keep
    the original's 10 / 16, so the wider glyph still centres under
    `HORIZONTAL_ALIGNMENT_CENTER` (that is how every draw site places digits).
  * `--seven-bar` additionally gives the 7 a continental crossbar through the
    stem (off by default — the foot alone separates the pair; keep the
    hand-drawn 7 unless it still reads wrong on a phone).
  * device-metric tables (hdmx / LTSH / VDMX) are dropped — they cache advance
    widths per pixel size for the old 1 — and the edited glyphs lose their
    TrueType hints (Godot imports the face with light hinting, which ignores
    bytecode anyway). The name table's version / unique-id strings mark the
    file as derived; the family name is unchanged.

Never hand-edit assets/fonts/MalamPoek.ttf — re-run this, then
`Godot --headless --path . --import`. Byte-identical on re-run (no timestamp).

    python tools/font_digits.py [--seven-bar] [--no-preview]

Deps: fonttools, skia-pathops, Pillow (preview) —
    pip install fonttools skia-pathops pillow
Preview: tools/out/font_digits.png (original vs derived at note → hero sizes).
"""
import argparse
import math
import os
import sys

try:
    import pathops
    from fontTools.pens.ttGlyphPen import TTGlyphPen
    from fontTools.ttLib import TTFont
    from fontTools.ttLib.removeOverlaps import removeOverlaps
except ImportError as exc:  # pragma: no cover
    sys.exit("font_digits.py needs fonttools + skia-pathops "
             "(pip install fonttools skia-pathops): %s" % exc)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "tools", "font_src", "MalamPoek.ttf")
OUT = os.path.join(ROOT, "assets", "fonts", "MalamPoek.ttf")
PREVIEW = os.path.join(ROOT, "tools", "out", "font_digits.png")

# ---- The 1's foot (font units; Malam Poek is 1000 / em) --------------------
# Measured on the original: the stem meets the baseline at x 98..372, the flag
# (y 527..763) is 236 tall, the 7's top bar ~250 — a ~210-tall slab is in weight.
FOOT_HALF_W = 245      # half-span, centred on the stem's base → ~490 wide (the 7 is 553)
FOOT_BOTTOM = -70      # the original stem overshoots the baseline to -68
FOOT_TOP = 140
FOOT_RADIUS = 90
FOOT_TILT_DEG = 1.5    # hand-drawn lean; positive lifts the right end
# The face's shine: a thin counter-direction dash just under the top edge of
# every horizontal stroke (the 1's flag wears a 123×25 and a 61×29). One per wing.
DASH_H = 26
DASH_DROP = 40         # dash centre-line below the foot's top edge
DASH_MARGIN = 24       # air from the wing's end and from the stem
ONE_LSB, ONE_RSB = 10, 16   # the original's bearings

# ---- Optional: a continental crossbar on the 7 -----------------------------
BAR_Y = 305            # bar centre; the stem spans x ~190..440 there
BAR_H = 150
BAR_EXTEND = 120       # past the stem on each side
BAR_RADIUS = 66
BAR_TILT_DEG = -5.0    # follows the 7's top bar, which slopes down to the right
SEVEN_LSB, SEVEN_RSB = 8, 10

WIDE = 10000           # a band wider than any glyph, for the stem probe


# ---- outline helpers -------------------------------------------------------
def _rotate(pts, pivot, deg):
    if not deg:
        return list(pts)
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    px, py = pivot
    return [(px + (x - px) * c - (y - py) * s, py + (x - px) * s + (y - py) * c)
            for x, y in pts]


def slab(pen, x0, y0, x1, y1, r, hole=False, tilt=0.0, pivot=None):
    """One rounded slab as a TrueType contour — clockwise (y-up) for solid ink,
    counter-clockwise for a shine hole. Each corner is a single quadratic with
    its control point ON the corner (within ~2 % of a circular arc), so the
    outline stays quadratic like the rest of the face."""
    r = min(r, (x1 - x0) / 2.0, (y1 - y0) / 2.0)
    # (point, on_curve) around the slab, clockwise in y-up coordinates: along
    # the top edge left → right, down the right side, back along the bottom.
    ring = [
        ((x0 + r, y1), True), ((x1 - r, y1), True),
        ((x1, y1), False), ((x1, y1 - r), True), ((x1, y0 + r), True),
        ((x1, y0), False), ((x1 - r, y0), True), ((x0 + r, y0), True),
        ((x0, y0), False), ((x0, y0 + r), True), ((x0, y1 - r), True),
        ((x0, y1), False),
    ]
    if hole:
        ring = [ring[0]] + ring[:0:-1]
    pts = _rotate([p for p, _ in ring], pivot or ((x0 + x1) / 2.0, (y0 + y1) / 2.0), tilt)
    ring = [(pts[i], on) for i, (_, on) in enumerate(ring)]
    pen.moveTo(ring[0][0])
    offs = []
    for p, on in ring[1:] + [ring[0]]:
        if on:
            if offs:
                pen.qCurveTo(*offs, p)
                offs = []
            else:
                pen.lineTo(p)
        else:
            offs.append(p)
    pen.closePath()


def _glyph_path(font, name):
    path = pathops.Path()
    font.getGlyphSet()[name].draw(path.getPen())
    return path


def _span(path, y0, y1):
    """The glyph's x extent inside the horizontal band y0..y1."""
    band = pathops.Path()
    p = band.getPen()
    p.moveTo((-WIDE, y0))
    p.lineTo((WIDE, y0))
    p.lineTo((WIDE, y1))
    p.lineTo((-WIDE, y1))
    p.closePath()
    b = pathops.op(path, band, pathops.PathOp.INTERSECTION).bounds
    return b[0], b[2]


def _finish(font, name, lsb, rsb):
    """Union the added contours into the glyph, then re-seat it on its
    original bearings so the widened outline still centres on its advance."""
    removeOverlaps(font, [name])
    glyf = font["glyf"]
    g = glyf[name]
    g.recalcBounds(glyf)
    g.coordinates.translate((lsb - g.xMin, 0))
    g.recalcBounds(glyf)
    font["hmtx"][name] = (g.xMax + rsb, lsb)
    return g


# ---- the edits -------------------------------------------------------------
def add_foot(font):
    glyf = font["glyf"]
    x0, x1 = _span(_glyph_path(font, "one"), 0, 60)      # the stem at the baseline
    cx = (x0 + x1) / 2.0
    fx0, fx1 = cx - FOOT_HALF_W, cx + FOOT_HALF_W
    pivot = (cx, (FOOT_BOTTOM + FOOT_TOP) / 2.0)
    pen = TTGlyphPen(font.getGlyphSet())
    glyf["one"].draw(pen, glyf)
    slab(pen, fx0, FOOT_BOTTOM, fx1, FOOT_TOP, FOOT_RADIUS, tilt=FOOT_TILT_DEG, pivot=pivot)
    yd = FOOT_TOP - DASH_DROP
    for a, b in ((fx0 + DASH_MARGIN, x0 - DASH_MARGIN),
                 (x1 + DASH_MARGIN, fx1 - DASH_MARGIN)):
        if b - a >= 40:
            slab(pen, a, yd - DASH_H / 2.0, b, yd + DASH_H / 2.0, DASH_H / 2.0,
                 hole=True, tilt=FOOT_TILT_DEG, pivot=pivot)
    glyf["one"] = pen.glyph()
    return _finish(font, "one", ONE_LSB, ONE_RSB), (x0, x1, cx)


def add_seven_bar(font):
    glyf = font["glyf"]
    x0, x1 = _span(_glyph_path(font, "seven"), BAR_Y - 20, BAR_Y + 20)
    bx0, bx1 = x0 - BAR_EXTEND, x1 + BAR_EXTEND
    pivot = ((bx0 + bx1) / 2.0, BAR_Y)
    pen = TTGlyphPen(font.getGlyphSet())
    glyf["seven"].draw(pen, glyf)
    slab(pen, bx0, BAR_Y - BAR_H / 2.0, bx1, BAR_Y + BAR_H / 2.0, BAR_RADIUS,
         tilt=BAR_TILT_DEG, pivot=pivot)
    yd = BAR_Y + BAR_H / 2.0 - DASH_DROP
    a, b = bx0 + DASH_MARGIN, x0 - DASH_MARGIN
    if b - a >= 40:
        slab(pen, a, yd - DASH_H / 2.0, b, yd + DASH_H / 2.0, DASH_H / 2.0,
             hole=True, tilt=BAR_TILT_DEG, pivot=pivot)
    glyf["seven"] = pen.glyph()
    return _finish(font, "seven", SEVEN_LSB, SEVEN_RSB), (x0, x1)


def mark_derived(font):
    tag = " (Sudoku digit pass: tools/font_digits.py)"
    for rec in font["name"].names:
        if rec.nameID in (3, 5):
            rec.string = rec.toUnicode() + tag
    for t in ("hdmx", "LTSH", "VDMX"):
        if t in font:
            del font[t]


# ---- preview ---------------------------------------------------------------
def preview(src, out, png, seven_bar):
    try:
        from PIL import Image, ImageDraw, ImageFont
    except ImportError:
        print("preview skipped: Pillow not installed")
        return
    sizes = (22, 30, 44, 64, 96, 150)
    samples = ("1 7", "1 7 17 71 117", "1234567890")   # orig, derived, derived
    rows = []
    for s in sizes:
        fo = ImageFont.truetype(src, s)
        fn = ImageFont.truetype(out, s)
        fonts = (fo, fn, fn)
        xs, x = [], 24
        for txt, f in zip(samples, fonts):
            xs.append(x)
            x += f.getlength(txt) + s * 0.7
        rows.append((s, fonts, xs, x))
    w = int(max(r[3] for r in rows)) + 24
    h = 60 + sum(s + 26 for s in sizes) * 2
    img = Image.new("RGB", (w, h), (24, 26, 36))
    d = ImageDraw.Draw(img)
    d.rectangle((0, h // 2, w, h), fill=(240, 236, 228))
    for ink, dim, top in (((245, 245, 245), (135, 138, 150), 20),
                          ((28, 28, 36), (150, 148, 140), h // 2 + 20)):
        y = top
        for s, fonts, xs, _ in rows:
            for i, (txt, f) in enumerate(zip(samples, fonts)):
                d.text((xs[i], y), txt, font=f, fill=dim if i == 0 else ink)
            y += s + 26
    d.text((24, 4), "orig", fill=(120, 120, 130))
    d.text((190, 4), "1 foot" + (" + 7 bar" if seven_bar else ""), fill=(120, 120, 130))
    os.makedirs(os.path.dirname(png), exist_ok=True)
    img.save(png)
    print("preview ->", os.path.relpath(png, ROOT))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--seven-bar", action="store_true", help="also cross the 7's stem")
    ap.add_argument("--no-preview", action="store_true")
    ap.add_argument("--out", default=OUT, help="output .ttf (default: the shipped font)")
    args = ap.parse_args()
    if not os.path.isfile(SRC):
        sys.exit("missing source font: %s" % SRC)
    font = TTFont(SRC, recalcTimestamp=False)
    g1, (sx0, sx1, cx) = add_foot(font)
    print("one:   stem base x %d..%d (centre %d) -> foot x %d..%d, bbox (%d,%d,%d,%d), advance %d (was 441)"
          % (sx0, sx1, cx, cx - FOOT_HALF_W, cx + FOOT_HALF_W,
             g1.xMin, g1.yMin, g1.xMax, g1.yMax, font["hmtx"]["one"][0]))
    if args.seven_bar:
        g7, (bx0, bx1) = add_seven_bar(font)
        print("seven: stem at y %d spans x %d..%d -> bar, bbox (%d,%d,%d,%d), advance %d (was 571)"
              % (BAR_Y, bx0, bx1, g7.xMin, g7.yMin, g7.xMax, g7.yMax, font["hmtx"]["seven"][0]))
    mark_derived(font)
    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    font.save(args.out)
    print("wrote", os.path.relpath(args.out, ROOT))
    if not args.no_preview:
        preview(SRC, args.out, PREVIEW, args.seven_bar)


if __name__ == "__main__":
    main()
