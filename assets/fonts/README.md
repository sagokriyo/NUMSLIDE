# Fonts

**`MalamPoek.ttf` is the game's display voice** — a chunky, rounded, hand-drawn
bubble font (Khurasan Studio, free for personal **and** commercial use). It
carries the headings, the hero "2048" wordmark, and the tile numerals, so the
playful brand voice is unmistakable where it counts.

**`Nunito` is the reading voice** — body text and UI labels (`ui_font`) are set in
Nunito: warm and rounded like Malam Poek, but far more legible at small sizes and
in long strings (stats, settings, how-to-play). It carries the same symbol
fallback, so decorative glyphs still resolve.

| file | family | role |
|------|--------|------|
| `MalamPoek.ttf`                | Malam Poek | **display** — `display_font`, `display_font_heavy` (headings, hero wordmark, tile numerals) |
| `Nunito-VariableFont_wght.ttf` | Nunito | **reading** — `ui_font` (body text, UI labels) |
| `Exo2-VariableFont_wght.ttf`   | Exo 2  | legacy fallback (only if Malam Poek is removed) |
| `Baloo2-VariableFont_wght.ttf` | Baloo 2 | one borrowed glyph: the wordmark's "4" (`extruded_word.gd` `ALT_GLYPH_FONT`) |
| `Cinzel-VariableFont_wght.ttf`, `Caveat-VariableFont_wght.ttf`, `PressStart2P-Regular.ttf` | — | **unreferenced** — the former per-theme faces (see below); safe to delete |

**Themes carry no typography.** `ThemeData` used to export a `heading_font`
(Cinzel on Sanctum / Star Atlas / Starforged / Clockwork, Caveat on Paper /
Skywriter, Baloo on Kawaii / Candy Pop / Carnival) and, earlier, a `number_font`
(PressStart2P on the four pixel themes). Each swapped a `ThemeManager` font slot
on every theme change, so the app's type visibly changed as the player browsed
the Themes screen. Both exports are gone: every font slot is set once in
`_load_fonts`, sealed in `_seal_base_fonts`, and `_apply` never touches them.
`regression/headless/suites/test_theme_visuals.gd` sweeps the whole catalog and
fails if any theme moves any slot, if a palette grows a `font*` key, or if a
Font-typed export reappears on `ThemeData`.

Wiring lives in [theme_manager.gd](../../autoload/theme_manager.gd) `_load_fonts()`:
Malam Poek is loaded as two `FontVariation`s that share the file but step up in
synthetic boldness via `variation_embolden` (display → hero); Nunito is loaded as
a single medium-weight `FontVariation` for `ui_font`. Because Malam Poek is a
single weight, its display hierarchy comes from embolden + size, not a `wght` axis.

**Glyph coverage / fallback.** Malam Poek ships full Latin + digits + basic
punctuation but **none** of the decorative UI symbols used in code
(`‹ › ‖ ↺ ⚙ ✓ ✦ ◷ ❍ ⧖ ❖ ▣ ∞`). Every variation therefore carries a `SystemFont`
fallback (`_symbol_fallback()`, e.g. *Segoe UI Symbol* on Windows, the device's
symbol font on export) so those glyphs resolve transparently — nothing tofus.
Run [tools/font_probe.gd](../../tools/font_probe.gd) to re-check coverage after a
font swap.

**Shaded / dimensional wordmark.** The signature violet→pink→orange letter
shading is applied by [gradient_text.gd](../../ui/components/gradient_text.gd)
(2D, e.g. the Home hero) and [extruded_word.gd](../../ui/components/extruded_word.gd)
(faux-3D extruded "2048" on the loading screen — TextMesh can't tessellate this
font's self-intersecting outlines, so depth is faked with shaded offset copies).

To change the look, drop in a new `.ttf`, point `MALAM_FONT_PATH` at it, and
re-run `--import`.
