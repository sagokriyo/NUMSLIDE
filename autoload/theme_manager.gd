extends Node
## ThemeManager — the colour brain of the game.
##
## Themes are authored as ThemeData resources in data/themes/*.tres (imported
## from the sibling project's curated set). At startup each is loaded and mapped
## into the flat "palette" shape the UI consumes, so the rest of the app is
## unaware of where colours come from. Exposes the active palette, builds a Godot
## `Theme` resource for consistent Control styling, and provides the tile colour
## ramp. Emits `theme_changed` so live screens restyle.

signal theme_changed(palette: Dictionary)

# Malam Poek — the game's signature face: a chunky, rounded, hand-drawn bubble
# display font (Khurasan Studio, free for commercial use). Used UNIFORMLY across
# the whole app (UI text, headings, hero wordmark, tile numerals) so the brand
# voice is consistent everywhere. It carries full Latin + digits but NOT the
# decorative UI symbols (∞ ⚙ ‹ › ✓ …), so a system symbol font is wired as a
# glyph fallback — missing glyphs resolve transparently and nothing tofus.
const MALAM_FONT_PATH := "res://assets/fonts/MalamPoek.ttf"

# Bundled premium typography (variable fonts → all weights from one file each).
# Nunito = warm, calm, rounded UI text; Exo 2 = geometric, confident numerals for
# the hero "2048" wordmark, the tiles, and the score. Both are open-licensed.
# Missing files fall back to the engine default, so the project still runs.
const UI_FONT_PATH := "res://assets/fonts/Nunito-VariableFont_wght.ttf"
const DISPLAY_FONT_PATH := "res://assets/fonts/Exo2-VariableFont_wght.ttf"
# Roboto is used for ALL text when present (drop the .ttf in assets/fonts/).
# Falls back to Nunito/Exo2 if absent so the project always runs.
const ROBOTO_CANDIDATES := [
	"res://assets/fonts/Roboto-VariableFont_wdth,wght.ttf",
	"res://assets/fonts/Roboto-VariableFont_wght.ttf",
	"res://assets/fonts/Roboto-Regular.ttf",
	"res://assets/fonts/Roboto.ttf",
]

# -----------------------------------------------------------------------------
# Themes are loaded from data/themes/*.tres (ThemeData) and mapped into the flat
# palette the UI expects:
#   bg0/bg1/bg2  surfaces (deepest → board cell)
#   glass/stroke  translucent fill + hairline border
#   text/text_dim/text_faint  type hierarchy
#   accent/accent_soft  brand / interactive
#   gold  warm "achievement" tone for high tiles (blended per theme)
# -----------------------------------------------------------------------------
const ThemeIds := preload("res://data/themes/theme_ids.gd")
const THEME_DIR := "res://data/themes/"
const _WARM_GOLD := Color("E7C56B")
const DEFAULT_ID := "starforged"

var _current_id := DEFAULT_ID
var _palette: Dictionary = {}
var _palettes: Dictionary = {}      # id -> mapped palette Dictionary (claimed themes only)
var _order: Array[String] = []      # display order (matches ThemeIds.IDS)
## id -> res:// path for every catalog theme whose .tres has NOT been claimed
## yet. Boot loads only the stored theme + the free fallback synchronously; the
## rest are queued on the resource loader's worker thread (_queue_rest) and
## claimed on first catalog touch (_claim_all / _ensure_theme).
var _pending: Dictionary = {}
## The fun-ramp hue-spread counter (see _store_palette). A member rather than a
## loop local because themes are now mapped across several calls; _claim_all
## walks the catalog in _order so the assignment order — which is part of a fun
## theme's palette value — matches the old eager loader exactly.
var _fun_i := 0
var theme: Theme
## The live theme-switch crossfade, if one is running (see _begin_switch_fade).
var _fade_layer: CanvasLayer = null

## Public fonts. `ui_font` is the default for all text; `display_font` is used by
## big numbers (wordmark, scores) via add_theme_font_override.
##
## TYPOGRAPHY IS NOT THEMEABLE. Every one of these is set ONCE, in _load_fonts,
## and sealed by _seal_base_fonts; _apply never touches them. A theme changes
## colour, material and motion — it does not change the app's voice. There used
## to be a per-theme heading face (ThemeData.heading_font: Cinzel on Sanctum,
## Baloo on Carnival, Caveat on Paper …) that swapped display_font on every
## theme change, so the headings visibly re-lettered themselves as the player
## browsed the Themes screen. That was removed: Malam Poek is the display face
## under every palette in the catalog, and test_theme_visuals sweeps the whole
## catalog to prove no theme reassigns any of these.
##
## `tile_font` / `tile_font_heavy` are the numerals ON A BOARD. Every board —
## the grid controller's tiles, Drop's blobs, Fling's blocks, Tower's stack, the
## three solids, the Home mini-boards and the academy's demo tiles — draws from
## these two and from nothing else (test_board_typography pins the readers).
var ui_font: Font
var display_font: Font
var display_font_heavy: Font   # extra-bold weight for headings + hero numbers
var tile_font: Font            # the board numerals — the app's own face, always
var tile_font_heavy: Font      # the same, at the heavy weight boards ask for
## The BRAND face — the wordmark's font. The app's own heavy face, like every
## other slot; it keeps its own name so the logo's reader is explicit.
var brand_font: Font
## The faces _load_fonts built, kept under a second name so a suite can prove
## by IDENTITY that nothing downstream ever re-wrapped or replaced them.
var _base_display: Font
var _base_display_heavy: Font

func _ready() -> void:
	_load_fonts()
	_init_catalog()
	var stored_id: String = SettingsManager.theme_id()
	# Only what boot actually DRAWS is loaded synchronously: the stored theme,
	# plus the free fallback boot could downgrade to. All ~50 ThemeData .tres
	# used to load right here, before the first frame; the rest of the catalog
	# is queued on the resource loader's worker instead (_queue_rest below) and
	# claimed on first catalog touch — no later than the Themes screen. Boot
	# renders exactly as before: the active palette is fully loaded and applied
	# before anything draws.
	_claim_one(stored_id)
	_claim_one(DEFAULT_ID)
	_current_id = stored_id
	# An id the catalog cannot honour (a theme renamed/retired since the save was
	# written, a hand-edited save, or a file that just refused to load) falls
	# back to the default...
	if not _palettes.has(_current_id):
		# _order can be EMPTY here: a failed claim prunes its id, so a catalog of
		# one corrupt file leaves nothing — land on DEFAULT_ID and let the safety
		# net below conjure it, as the eager loader's net did.
		_current_id = DEFAULT_ID if _has_theme(DEFAULT_ID) or _order.is_empty() \
			else String(_order[0])
		_claim_one(_current_id)
	# ...and we never boot into a premium theme the player no longer owns (e.g. a
	# refund revoked premium since last session).
	if not EntitlementManager.is_theme_unlocked(_current_id):
		_current_id = _free_fallback_id()
		_claim_one(_current_id)
	# Nothing usable loaded at all (torn files): the eager loader's safety net,
	# kept — the app always has at least one theme to wake up in.
	if not _palettes.has(_current_id):
		_pending.erase(DEFAULT_ID)
		_palettes[DEFAULT_ID] = _fallback_palette()
		if not _order.has(DEFAULT_ID):
			_order.append(DEFAULT_ID)
		_current_id = DEFAULT_ID
	# Persist ANY correction before applying it — the premium downgrade AND the
	# unknown id alike. Writing it back is what HEALS the save: left alone, an id the
	# app already refuses would sit in `settings.theme` for every future boot to
	# silently re-correct. SettingsManager and EntitlementManager both boot ahead of
	# us (autoload order), and setting_changed is connected only below, so this write
	# can never re-enter _apply().
	if _current_id != stored_id:
		SettingsManager.set_value("theme", _current_id)
	_queue_rest()
	_apply(_current_id)
	SettingsManager.setting_changed.connect(_on_setting_changed)
	EntitlementManager.premium_changed.connect(_on_premium_changed)

# --- Theme loading + mapping --------------------------------------------------
## Builds the catalog's ORDER and the pending set from the manifest without
## opening a single .tres — cataloguing is split from loading so boot can load
## just the theme it draws (see _ready). Idempotent for the same reason the old
## eager loader was: _order/_pending are APPENDED to below, so a re-entry (a
## lazy reload, a test that re-instantiates this autoload) must start clean or
## every id would be handed back twice.
func _init_catalog() -> void:
	_order.clear()
	_palettes.clear()
	_pending.clear()
	_fun_i = 0
	for id in ThemeIds.IDS:
		var sid := String(id)
		var path := THEME_DIR + sid + ".tres"
		if not ResourceLoader.exists(path):
			continue
		_order.append(sid)
		_pending[sid] = path
	# Safety net so the app always has at least one theme.
	if _order.is_empty():
		_palettes[DEFAULT_ID] = _fallback_palette()
		_order.append(DEFAULT_ID)

## Queue every still-unclaimed theme on the resource loader's worker thread
## (sequential, no sub-threads — RULES 4.6). load_threaded_get on the same path
## later JOINS the request, so a claim can never load a file twice, and a claim
## landing after the worker already finished is a plain hand-over.
func _queue_rest() -> void:
	for id in _pending:
		# A failed request stays silent: _claim_one's synchronous fallback still
		# covers the id, exactly as the eager loader would have loaded it.
		var _rc := ResourceLoader.load_threaded_request(String(_pending[id]))

## Claim ONE pending theme: join its threaded request (or load it synchronously
## when no request is in flight) and map it into the palette catalog. An
## unloadable file is pruned from the catalog — the eager loader never listed
## those either.
func _claim_one(id: String) -> void:
	if not _pending.has(id):
		return
	var path := String(_pending[id])
	_pending.erase(id)
	var td: ThemeData = null
	var st := ResourceLoader.load_threaded_get_status(path)
	if st == ResourceLoader.THREAD_LOAD_IN_PROGRESS or st == ResourceLoader.THREAD_LOAD_LOADED:
		td = ResourceLoader.load_threaded_get(path) as ThemeData
	else:
		# Not queued yet (boot) or the threaded request failed — one sync try.
		td = load(path) as ThemeData
	if td == null:
		_order.erase(id)
		return
	_store_palette(id, td)

## Claim EVERYTHING still pending, in CATALOG order — mapping order is part of a
## fun theme's palette value (_fun_i), so partial claims must not reorder it.
## A no-op once the catalog is fully claimed, which is the steady state after
## the first touch.
func _claim_all() -> void:
	if _pending.is_empty():
		return
	for id in _order.duplicate():
		_claim_one(String(id))

## Whether `id` is a catalog theme at all — claimed or still pending. The lazy
## twin of the old `_palettes.has(id)` membership test.
func _has_theme(id: String) -> bool:
	return _palettes.has(id) or _pending.has(id)

## Membership test that LOADS: true only when `id` resolves to a claimed
## palette, claiming the catalog on a miss. Claims ALL pending (not just `id`)
## so _fun_i walks the catalog in order — see _claim_all.
func _ensure_theme(id: String) -> bool:
	if _palettes.has(id):
		return true
	if _pending.has(id):
		_claim_all()
	return _palettes.has(id)

## Map a loaded ThemeData into the catalog.
func _store_palette(id: String, td: ThemeData) -> void:
	var pal := _map_theme(td)
	# Only the non-luxe themes use the fun rainbow ramp, so we spread just THOSE
	# across the colour wheel (golden-ratio increment) — with ~a dozen of them their
	# boards land far apart and no two look alike. Luxe themes keep bespoke ramps.
	# (Every SHIPPED theme is luxe — see tile_style_for — so boot's out-of-order
	# claim of the stored theme can never consume a fun slot today.)
	if _LUXE_RAMPS.has(td.board_style):
		pal["tile_hue_base"] = 0.0  # unused — luxe themes have their own ramp
	else:
		pal["tile_hue_base"] = fmod(float(_fun_i) * 0.6180339887, 1.0)
		_fun_i += 1
	_palettes[id] = pal

# -----------------------------------------------------------------------------
# The contrast pass.
#
# Measured over the whole catalogue before it existed: a card sat at WCAG 1.08
# against its own backdrop (worst 1.00 — Coral Depths), a secondary panel at 1.11
# against that card, and the hairline meant to edge them at 1.60. Body text was
# never the problem — it lands near 15:1 on the darks — but nothing on a screen
# had an EDGE, so every surface dissolved into the wallpaper and a screen read as
# one soft wash of the same three values.
#
# This runs once per theme on the DERIVED palette, so all 56 .tres files keep the
# colours they were authored with and the separation is added on top:
#   * surfaces are pushed apart until each clears a real ratio over whatever it
#     sits on — darks settle the backdrop and lift the card off it, lights leave
#     the white card alone and deepen the page under it, so both open the same
#     gap in the direction the theme was already drawn;
#   * the card fill and the control surfaces gain honest alpha — FILLS only, never
#     the borders, which is the one lever this pass deliberately does not pull
#     (see the border block below);
#   * secondary and tertiary ink stop dissolving into the page;
#   * accents keep their hue and gain chroma.
#
# A colour that already clears its ratio is returned untouched, so a theme that
# drew a real step keeps exactly the step it drew — the pass only ever moves what
# was too close to its neighbour. Everything is derived, so the whole app's
# contrast is these eighteen numbers and nothing else.
# -----------------------------------------------------------------------------
const _PUNCH_CARD := 1.45              ## dark: bg1 over bg0
const _PUNCH_ALT := 1.22               ## bg2 over bg1 (both directions)
const _PUNCH_LIGHT_CARD := 1.34        ## light: bg1 over bg0, reached by deepening bg0
const _PUNCH_DEEPEN := 0.12            ## dark: the backdrop settles toward black first
const _PUNCH_DESAT := 0.55             ## chroma eased back per unit of value climbed
const _PUNCH_GLASS_A := 0.11           ## dark card fill (was 0.05)
## The BORDER alphas are deliberately left where they were authored. Raising them
## was tried: every glass shard in the app is edged by one of these — the currency
## chips, the badge shelves, the settings cards, the pills — and lifting them drew
## a visible outline around each, so the shards stopped matching each other and
## started looking like line art. Contrast here comes from FILLS and from INK, both
## of which change a colour without adding a stroke that was never in the design.
const _PUNCH_STROKE_A := 0.10
const _PUNCH_CTRL_STROKE_A := 0.10
const _PUNCH_LIGHT_CTRL_STROKE_A := 0.38
const _PUNCH_CTRL_A := 0.14            ## switch tracks, slider rails, segmented bars
const _PUNCH_LIGHT_CTRL_A := 0.18      ## the light themes' accent veil (was 0.12)
const _PUNCH_HOVER_A := 0.24           ## the accent wash behind a pressed Button (was 0.16)
const _PUNCH_INK := 0.12               ## body text leans this far toward white / black
const _PUNCH_DIM := 0.20               ## text_dim lerps this far toward text
## ...and further on the lights, which deepen their backdrop rather than lifting
## their card: without the extra reach the page would close on the caption faster
## than the caption darkens, and the palest themes (Sakura, Kawaii) would come out
## of a CONTRAST pass with less of it than they went in with.
const _PUNCH_DIM_LIGHT := 0.36
const _PUNCH_FAINT := 0.28             ## text_faint's lerp toward bg (was 0.45)
const _PUNCH_CHROMA := 1.18            ## accent / accent2 saturation gain
const _PUNCH_VALUE := 1.05             ## ...and their value gain, on the darks only

## `c` at a different HSV value, hue kept. Chroma eases back as the value climbs
## (and firms up as it falls): a dark surface brightened without letting go of any
## saturation stops reading as a surface and starts reading as a block of colour.
static func _at_value(c: Color, v: float) -> Color:
	var s: float = clampf(c.s * (1.0 - _PUNCH_DESAT * (v - c.v)), 0.0, 1.0)
	return Color.from_hsv(c.h, s, clampf(v, 0.0, 1.0), c.a)

## `c` raised (`up`) or deepened until it clears `ratio` against `under`.
## Bisection on HSV value — 12 passes lands inside 1/4096 of the channel, and it
## runs twice per theme, once, at load. A hue with no room left surrenders
## everything it has rather than reporting failure: the ratio is a target here,
## not a promise every palette can keep.
static func _to_ratio(c: Color, under: Color, ratio: float, up: bool) -> Color:
	if _wcag_contrast(c, under) >= ratio:
		return c
	var lo: float = c.v                    # fails, by the line above
	var hi: float = 1.0 if up else 0.0     # the far end
	var far := _at_value(c, hi)
	if _wcag_contrast(far, under) < ratio:
		return far
	for _i in 12:
		var mid: float = (lo + hi) * 0.5
		if _wcag_contrast(_at_value(c, mid), under) >= ratio:
			hi = mid
		else:
			lo = mid
	return _at_value(c, hi)

## `c` with its authored hue and more chroma — plus, on the darks, a touch more
## light. This is for the washed-out members of the catalogue (Silver Rain at 0.11
## saturation, Moonlit Bamboo at 0.18, Thunderstorm at 0.25); a theme already near
## full chroma clamps and barely moves.
static func _vivid(c: Color, is_light: bool) -> Color:
	var v: float = c.v if is_light else clampf(c.v * _PUNCH_VALUE, 0.0, 1.0)
	return Color.from_hsv(c.h, clampf(c.s * _PUNCH_CHROMA, 0.0, 1.0), v, c.a)

func _map_theme(td: ThemeData) -> Dictionary:
	var bg: Color = td.bg
	# Light themes need a different surface recipe: cards read as frosted *white*
	# floating above the pastel backdrop (not a faint dark tint), with a soft cool
	# shadow that's actually visible on a light background. Dark themes keep the
	# original translucent-white-on-dark glass and a near-black shadow.
	#
	# Decided on the AUTHORED backdrop, before the contrast pass moves it: a light
	# theme deepened toward its own cards must never start reading as a dark one.
	var is_light: bool = bg.get_luminance() > 0.5
	# Body copy leans a little further from the page it sits on. It was never the
	# weak link — the darks read near 15:1 — but the same lean is what pays the
	# lights back for the backdrop they are about to give up.
	var text: Color = td.text.lerp(Color.BLACK if is_light else Color.WHITE, _PUNCH_INK)
	var accent: Color = _vivid(td.accent, is_light)
	var surface: Color = td.surface
	var surface_alt: Color = td.surface_alt
	var grad: Color = td.bg_gradient_bottom
	if is_light:
		# The white card was always right; it is the page under it that sat too
		# close to it. Deepening the backdrop takes the gradient's second stop down
		# by the same amount, so the wash keeps the shape it was authored with.
		var deep := _to_ratio(bg, surface, _PUNCH_LIGHT_CARD, false)
		grad = _at_value(grad, grad.v + (deep.v - bg.v))
		bg = deep
		surface_alt = _to_ratio(surface_alt, surface, _PUNCH_ALT, false)
	else:
		bg = _at_value(bg, bg.v * (1.0 - _PUNCH_DEEPEN))
		grad = _at_value(grad, grad.v * (1.0 - _PUNCH_DEEPEN))
		surface = _to_ratio(surface, bg, _PUNCH_CARD, true)
		surface_alt = _to_ratio(surface_alt, surface, _PUNCH_ALT, true)
	var glass_col: Color = Color(text.r, text.g, text.b, _PUNCH_GLASS_A)
	var stroke_col: Color = Color(text.r, text.g, text.b, _PUNCH_STROKE_A)
	var shadow_base: Color = bg
	# CONTROL surfaces (switch tracks, slider rails, segmented bars, glass-button
	# fills, dividers) sit ON TOP of glass cards. On dark themes the card fill
	# (`glass`) doubles fine as a control fill, but on light themes `glass` is the
	# frosted WHITE card itself — a control painted with it disappears white-on-
	# white. Light themes therefore rest controls on an "accent veil": a soft wash
	# of the theme's own accent, so every light theme keeps its colour identity
	# while controls read clearly on the white card.
	var control_col: Color = Color(text.r, text.g, text.b, _PUNCH_CTRL_A)
	var control_stroke_col: Color = Color(text.r, text.g, text.b, _PUNCH_CTRL_STROKE_A)
	if is_light:
		glass_col = Color(1, 1, 1, 0.92)
		stroke_col = Color(1, 1, 1, 0.95)
		shadow_base = text.lerp(accent, 0.12)
		control_col = Color(accent.r, accent.g, accent.b, _PUNCH_LIGHT_CTRL_A)
		control_stroke_col = Color(accent.r, accent.g, accent.b, _PUNCH_LIGHT_CTRL_STROKE_A)
	# The two secondary inks. `text_dim` leans back toward the body colour and
	# `text_faint` stops well short of the page it used to fade into — between them
	# they carry every caption, section header and nav label in the app, which is
	# most of the text a player actually looks at.
	var muted: Color = td.text_muted.lerp(text, _PUNCH_DIM_LIGHT if is_light else _PUNCH_DIM)
	return {
		"name": td.display_name,
		"category": td.category,
		"colorblind_safe": td.colorblind_safe,
		"is_light": is_light,
		"bg0": bg,
		"bg1": surface,
		"bg2": surface_alt,
		"bg_grad": grad,
		"glass": glass_col,
		"stroke": stroke_col,
		"control": control_col,
		"control_stroke": control_stroke_col,
		"shadow": shadow_base,
		"text": text,
		"text_dim": muted,
		"text_faint": muted.lerp(bg, _PUNCH_FAINT),
		"accent": accent,
		# Two DIFFERENT things that used to share one name. `accent_soft` is the
		# translucent hover/press wash the Theme resource paints behind Buttons —
		# always the primary accent, never a second hue. `accent2` is the theme's
		# authored PARTNER colour (Carnival's gold against its red, Vaporwave's
		# cyan against its pink): every .tres sets one, and nothing read it, because
		# this mapping used to overwrite it with the alpha line above. BoardFx now
		# draws its two-tone effects from accent2, so those 49 second hues finally land.
		"accent_soft": Color(accent.r, accent.g, accent.b, _PUNCH_HOVER_A),
		"accent2": _vivid(td.accent_soft, is_light),
		"gold": accent.lerp(_WARM_GOLD, 0.6),
		"danger": Color("E5736B"),
		"success": Color("6FCF97"),
		"ambience_id": td.ambience_id,
		# NO typography key. A palette used to carry `font_heading` (and before
		# that `font_number`), and each was a theme re-lettering part of the app.
		# Fonts are sealed in _load_fonts; test_theme_visuals fails on a palette
		# that grows a font key back.
		# Live gameplay feel. `fx` drives the merge-burst style + vivid tiles;
		# `bg_motif` (from background_id) picks BoardFx's signature ambient effect.
		"fx": td.fx_style,
		"bg_motif": td.background_id,
		"board_style": td.board_style,
		"glow": td.glow_color,
		"glow_on": td.enable_glow,
	}

func _fallback_palette() -> Dictionary:
	return {
		"name": "Obsidian", "category": "minimal", "colorblind_safe": false,
		"is_light": false,
		# Hand-written, and stepped by the same numbers the contrast pass applies to
		# every mapped theme — the torn-files net should not be the one palette in
		# the app whose surfaces sit on top of each other.
		"bg0": Color("08090C"), "bg1": Color("272B34"), "bg2": Color("343945"),
		"bg_grad": Color("060607"),
		"glass": Color(1, 1, 1, _PUNCH_GLASS_A), "stroke": Color(1, 1, 1, _PUNCH_STROKE_A),
		"control": Color(1, 1, 1, _PUNCH_CTRL_A),
		"control_stroke": Color(1, 1, 1, _PUNCH_CTRL_STROKE_A),
		"shadow": Color("08090C"),
		"text": Color("ECEEF3"), "text_dim": Color("A9AEB9"), "text_faint": Color("757B87"),
		"accent": Color("6E8BFF"), "accent_soft": Color(0.43, 0.55, 1.0, _PUNCH_HOVER_A),
		"accent2": Color("2EE0AD"),
		"gold": Color("E7C56B"), "danger": Color("E5736B"), "success": Color("6FCF97"),
		"ambience_id": "",
		"fx": "calm", "bg_motif": "motes",
		"glow": Color(0.43, 0.55, 1.0, 0.5),
	}

# --- Fonts --------------------------------------------------------------------
func _load_fonts() -> void:
	if ResourceLoader.exists(MALAM_FONT_PATH):
		# Malam Poek everywhere — one voice across the whole app. The face is a
		# single weight, so we synthesise the type hierarchy with `embolden`:
		# body/UI sits at the natural weight, the display tier a touch heavier, and
		# the hero wordmark heaviest. A shared symbol fallback backs every variation.
		var fb := _symbol_fallback()
		# Reading text (body / UI labels) is Nunito — a clean, warm, highly legible
		# face that avoids the bubble font's small-size legibility cost. Headings, the
		# hero wordmark and the tile numerals stay Malam Poek, so the playful brand
		# voice is unchanged where it matters. Nunito carries the same symbol fallback
		# so decorative UI glyphs (↺ ⚙ ✓ ‹ › …) still resolve.
		ui_font = _nunito(fb)
		display_font = _malam(0.12, fb)
		display_font_heavy = _malam(0.42, fb)
		_seal_base_fonts()
		return
	var roboto := _roboto_path()
	if roboto.is_empty():
		# No Roboto present — keep the bundled Nunito (UI) + Exo2 (display).
		ui_font = _weighted(UI_FONT_PATH, 500)
		display_font = _weighted(DISPLAY_FONT_PATH, 600)
		display_font_heavy = _weighted(DISPLAY_FONT_PATH, 900)
	else:
		# Roboto everywhere: regular for UI text, bold/black for hero numbers.
		ui_font = _weighted(roboto, 500)
		display_font = _weighted(roboto, 700)
		display_font_heavy = _weighted(roboto, 900)
	# `embolden` synthetically thickens the heavy weight so the wordmark reads bold
	# even if the variable weight axis is clamped by the font's import settings.
	if display_font_heavy is FontVariation:
		(display_font_heavy as FontVariation).variation_embolden = 0.6
	_seal_base_fonts()

## Seal the app's faces. Called ONCE from _load_fonts and never again: every
## font slot the app exposes is assigned here and nowhere else, so a theme
## change cannot move a single glyph. (_apply used to re-derive display_font
## from the palette's heading face right after this — that is the code path
## that made the headings change font with the wallpaper, and it is gone.)
func _seal_base_fonts() -> void:
	_base_display = display_font
	_base_display_heavy = display_font_heavy
	brand_font = display_font_heavy   # the logo's face
	tile_font = _base_display          # the board's two faces
	tile_font_heavy = _base_display_heavy

## A Malam Poek FontVariation at a given synthetic boldness, backed by the symbol
## fallback so glyphs the face lacks (∞ ⚙ ‹ › ✓ …) still render.
func _malam(embolden: float, fallback: Font) -> Font:
	var base := load(MALAM_FONT_PATH) as FontFile
	if base == null:
		return fallback
	var fv := FontVariation.new()
	fv.base_font = base
	if embolden != 0.0:
		fv.variation_embolden = embolden
	if fallback != null:
		fv.fallbacks = [fallback] as Array[Font]
	return fv

## Nunito FontVariation for reading text (body / UI labels), backed by the symbol
## fallback so glyphs Nunito lacks (↺ ⚙ ✓ ‹ › …) still render. Keeps the friendly,
## rounded feel of the app while reading far cleaner than Malam Poek at body sizes.
func _nunito(fallback: Font) -> Font:
	var base := load(UI_FONT_PATH) as FontFile
	if base == null:
		return fallback
	var fv := FontVariation.new()
	fv.base_font = base
	fv.variation_opentype = {"wght": 500}
	if fallback != null:
		fv.fallbacks = [fallback] as Array[Font]
	return fv

## System font that covers the decorative UI glyphs Malam Poek doesn't ship.
## On export it resolves to whatever the device provides; `allow_system_fallback`
## lets the OS substitute for anything still missing.
func _symbol_fallback() -> Font:
	var sf := SystemFont.new()
	sf.font_names = PackedStringArray([
		"Segoe UI Symbol", "Segoe UI Emoji", "Segoe UI", "Arial Unicode MS", "Noto Sans Symbols2",
	])
	sf.allow_system_fallback = true
	return sf

func _roboto_path() -> String:
	for p in ROBOTO_CANDIDATES:
		if ResourceLoader.exists(p):
			return p
	return ""

func _weighted(path: String, weight: int) -> Font:
	if not ResourceLoader.exists(path):
		return null
	var base := load(path) as FontFile
	if base == null:
		return null
	var fv := FontVariation.new()
	fv.base_font = base
	fv.variation_opentype = {"wght": weight}
	return fv

# --- Active theme -------------------------------------------------------------
func _on_setting_changed(key: String, value: Variant) -> void:
	if key == "theme":
		set_theme(String(value))

func set_theme(id: String) -> void:
	if not _ensure_theme(id):
		# An id the catalog cannot honour never becomes active — and must not be left
		# sitting in the save either (however it arrived: settings restore, a retired
		# theme, a hand-edited save).
		_heal_persisted_theme()
		return
	if id == _current_id:
		return
	# Locked premium themes can never be applied, however the id arrived (settings
	# restore, cloud sync later, etc.). The Themes UI routes locked taps to the
	# paywall; this is the defensive backstop.
	if not EntitlementManager.is_theme_unlocked(id):
		return
	_begin_switch_fade()
	_apply(id)

## The world CHANGES rather than snaps: a live theme switch grabs the frame the
## old theme just drew, holds it over the rebuilt UI, and dissolves it — a
## sub-second crossfade instead of a hard cut. User-facing switches only: boot
## and the healing paths call _apply() directly and never pay the readback.
## No-ops wherever a snapshot can't or shouldn't happen (headless runs, reduce
## motion, out of tree), so probes and suites see byte-identical behaviour.
func _begin_switch_fade() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if SettingsManager.reduce_motion():
		return
	if not is_inside_tree():
		return
	# A fade already mid-flight (rapid taps on the Themes screen): drop it and
	# snapshot fresh — the capture below reads the last PRESENTED frame, so at
	# worst the new snapshot still wears the dying overlay, which is the old
	# theme anyway.
	if _fade_layer != null and is_instance_valid(_fade_layer):
		_fade_layer.queue_free()
		_fade_layer = null
	var vp := get_viewport()
	if vp == null:
		return
	var img: Image = vp.get_texture().get_image()
	if img == null or img.is_empty():
		return
	var layer := CanvasLayer.new()
	layer.layer = 90   # above every screen layer, below nothing that matters mid-switch
	var shot := TextureRect.new()
	shot.texture = ImageTexture.create_from_image(img)
	shot.stretch_mode = TextureRect.STRETCH_SCALE
	shot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shot.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(shot)
	add_child(layer)
	_fade_layer = layer
	var tw := shot.create_tween()
	# One tick of hold so the rebuilt screens land beneath before the veil thins.
	tw.tween_interval(0.06)
	tw.tween_property(shot, "modulate:a", 0.0, 0.38) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(layer.queue_free)

func _apply(id: String) -> void:
	# Claim-before-read: under the lazy catalog a perfectly valid id may still
	# be pending (only the stored theme + fallback claim at boot). Probes and
	# tools call _apply directly with arbitrary ids — without this they
	# silently kept the current theme (or crashed on the raw _palettes read).
	if not _ensure_theme(id):
		push_warning("ThemeManager._apply: unknown/unloadable theme '%s' — keeping '%s'" % [id, _current_id])
		return
	_current_id = id
	_palette = (_palettes[id] as Dictionary).duplicate(true)
	# Fonts are deliberately NOT touched here — see the font vars' doc comment.
	theme = _build_theme()
	theme_changed.emit(_palette)

## A free theme to fall back to when the active one becomes locked. Prefers the
## default — which IS the whole free set now — then the first unlocked theme
## available, which for a free player means whatever they bought with gems.
func _free_fallback_id() -> String:
	# _ensure_theme, not _has_theme: a candidate must actually CLAIM before it
	# is vouched for — a pending id whose .tres later fails to load would
	# dead-end the premium-revoke path with the locked theme still active
	# until the next boot (the adversarial review's lazy-vouching finding).
	if _ensure_theme(DEFAULT_ID) and EntitlementManager.is_theme_unlocked(DEFAULT_ID):
		return DEFAULT_ID
	for id in _order.duplicate():
		if EntitlementManager.is_theme_unlocked(id) and _ensure_theme(String(id)):
			return String(id)
	return _current_id

## On revoke, if the active theme is now locked, downgrade to a free theme and
## persist it so the change survives a restart. (No-op when going premium.)
func _on_premium_changed(_is_premium: bool) -> void:
	if not EntitlementManager.is_theme_unlocked(_current_id):
		SettingsManager.set_value("theme", _free_fallback_id())

## Rewrites `settings.theme` when it holds an id the catalog cannot honour, so the
## save SELF-HEALS instead of carrying a dead id (a retired theme, a hand-edited
## save) through every boot while the runtime silently re-corrects it. Same single
## SettingsManager write-through the premium downgrade uses; the resulting
## setting_changed lands back in set_theme() on the id that is already active, so it
## stops there. A stored id that IS a real theme is left alone —
## `random_theme_each_game` deliberately runs on a theme the save does not hold.
func _heal_persisted_theme() -> void:
	var stored: String = SettingsManager.theme_id()
	if _has_theme(stored):
		return   # a real theme, claimed or still pending — never heal those away
	SettingsManager.set_value("theme", _current_id)

## "Surprise me" — switch to a random UNLOCKED theme other than the current one.
## No-op (returns "") when the setting is off, or when nothing else is unlocked.
## Returns the id it moved to, so callers and tests can see what happened.
##
## Lives here rather than in a screen because it is a THEME rule, and while it sat
## in gameplay.gd it was a theme rule only Classic/Challenger/Grand obeyed: Tower,
## Merge Drop and Arena Fling never called it, so "Random Theme" silently did
## nothing in three of the five modes. One implementation is what stops the mode
## contract drifting again.
##
## Deliberately does NOT persist. set_theme() applies without writing settings, so
## the player's CHOSEN theme is what the save keeps and what they return to when
## they switch the toggle back off — the surprise lasts for the session, not
## forever. _heal_persisted_theme() documents the other side of that bargain.
func maybe_randomize_for_game() -> String:
	if not SettingsManager.random_theme_each_game():
		return ""
	var pool: Array[String] = []
	for id in _order:
		var sid := String(id)
		if sid != _current_id and EntitlementManager.is_theme_unlocked(sid):
			pool.append(sid)
	if pool.is_empty():
		return ""
	var pick := String(pool[randi() % pool.size()])
	# Claim before committing: an id whose file turns out unloadable must report
	# "" (nothing moved), keeping the return contract honest under lazy loading.
	if not _ensure_theme(pick):
		return ""
	set_theme(pick)
	return pick

func current_id() -> String:
	return _current_id

func palette() -> Dictionary:
	return _palette

## The active theme's gameplay feel profile:
## "calm" | "playful" | "arcade" | "living" | "vivid".
func fx() -> String:
	return String(_palette.get("fx", "calm"))

## How dense a theme's ambient particle field runs, as a multiplier on the amount
## each motif authors.
##
## ThemeData declares five feel profiles and the code only ever tested for two of
## them ("arcade" and "playful"), so the seventeen themes tagged `living` and the
## one tagged `vivid` behaved exactly like `calm` — a label with no behaviour
## behind it. Each profile owns a step now. `playful` and `calm` keep 1.0 so the
## themes that already read correctly are untouched; the change is confined to
## the two values that did nothing.
func fx_density() -> float:
	return fx_density_for(_palette)

## The same density, for an ARBITRARY palette instead of the active one — what
## lets the Themes cards photograph a theme's world without wearing it.
func fx_density_for(p: Dictionary) -> float:
	match String(p.get("fx", "calm")):
		"arcade": return 1.40
		"vivid":  return 1.28
		"living": return 1.20
		_:        return 1.0

## True on the profiles that answer a big merge with a swell rather than a jolt —
## the board breathing instead of being hit. (Arcade/playful take the jolt path.)
func fx_breathes() -> bool:
	var f := fx()
	return f == "living" or f == "vivid"

## The active theme's signature ambient effect for BoardFx (snow/rain/stars/...).
func bg_motif() -> String:
	return String(_palette.get("bg_motif", "motes"))

## The active theme's premium board/tile treatment (plain/gold/silver/crystal/...).
func board_style() -> String:
	return String(_palette.get("board_style", "plain"))

## The metallic/crystalline accent for the active board_style — used for the board
## frame rim and the tile sheen. Alpha 0 means "plain" (no luxe treatment), so
## callers can cheaply skip it.
##
## NOTE this is deliberately NOT the same set as _LUXE_RAMPS. A ramp gives a theme
## its own tile colours; an arm here additionally makes the BOARD metallic (well
## wash + wider frame bloom + prismatic shimmer). Themes whose material is matte —
## paper, sand, folded card — own a bespoke ramp and fall through to alpha 0 on
## purpose. What was a real gap is a theme whose material IS metal or light
## silently landing in the fallback: `nova`, `comet` and `atlas` did exactly that,
## so Nova Forge, Skywriter and Star Atlas rendered plain boards.
func board_accent() -> Color:
	return board_accent_for(_palette)

## The same luxe accent, for an ARBITRARY palette instead of the active one
## (the Themes cards' backdrop captures — see fx_density_for).
func board_accent_for(p: Dictionary) -> Color:
	match String(p.get("board_style", "plain")):
		"gold":     return Color(1.00, 0.82, 0.36)
		"silver":   return Color(0.88, 0.91, 0.98)
		"crystal":  return Color(0.64, 0.90, 1.00)
		"molten":   return Color(1.00, 0.52, 0.18)
		"deep":     return Color(0.32, 0.86, 0.96)
		"jade":     return Color(0.68, 0.98, 0.80)
		"phantom":  return Color(0.92, 0.42, 0.96)
		"shadow":   return Color(0.56, 0.66, 0.82)
		"desert":   return Color(1.00, 0.85, 0.46)
		"toxic":    return Color(0.46, 1.00, 0.46)
		"rose":     return Color(1.00, 0.74, 0.68)
		"emerald":  return Color(0.40, 0.96, 0.62)
		"ruby":     return Color(1.00, 0.40, 0.56)
		"biolum":   return Color(0.30, 0.98, 0.88)   # the plankton flash
		"amethyst": return Color(0.78, 0.52, 1.00)
		"bronze":   return Color(0.88, 0.64, 0.34)
		"matrix":   return Color(0.36, 1.00, 0.44)
		"rgb":      return Color(0.35, 0.86, 1.00)
		"void":     return Color(1.00, 0.56, 0.22)
		"astral":   return Color(0.52, 0.78, 1.00)
		"ink":      return Color(0.28, 0.32, 0.40)
		"plasma":   return Color(1.00, 0.36, 0.72)
		# The three that were missing: all metal-or-fire concepts, all reward tier.
		"nova":     return Color(1.00, 0.78, 0.42)   # forge amber off the anvil
		"comet":    return Color(0.42, 1.00, 0.82)   # mint-white ion trail
		"atlas":    return Color(0.93, 0.82, 0.55)   # antique engraved brass
		# Boards that gained a bespoke ramp and whose material is metallic or emissive.
		"aurora":   return Color(0.42, 0.95, 0.75)   # cold sky light
		"firefly":  return Color(0.95, 0.88, 0.42)   # warm abdominal glow
		"stellar":  return Color(0.62, 0.54, 1.00)   # starlight violet
		"storm":    return Color(0.80, 0.92, 1.00)   # lightning white-blue
		"crt":      return Color(1.00, 0.42, 0.30)   # hot cabinet phosphor
		"bloodmoon":return Color(0.94, 0.46, 0.28)   # lunar ember
		"coral":    return Color(0.38, 0.96, 0.88)   # aqua off the reef
		"koi":      return Color(1.00, 0.66, 0.36)   # koi orange
		"lantern":  return Color(1.00, 0.72, 0.34)   # lit paper
		"lacquer":  return Color(0.82, 0.86, 0.94)   # polished steel
		"nebula":   return Color(0.94, 0.42, 0.86)   # emission magenta
		"vapor":    return Color(0.35, 0.95, 0.95)   # chrome cyan
		"hoarfrost":return Color(0.86, 0.96, 1.00)   # pale rime
		"duskbloom":return Color(0.94, 0.62, 0.80)   # blossom under dusk
		"foliage":  return Color(0.92, 0.62, 0.28)   # turned-leaf amber
		"cel":      return Color(0.72, 0.60, 1.00)   # ink-line violet
		"confect":  return Color(1.00, 0.56, 0.82)   # sugar-glass pink
		"bigtop":   return Color(1.00, 0.78, 0.34)   # fairground gold
		"pastelpop":return Color(0.98, 0.70, 0.90)   # candy lacquer
		"honey":    return Color(1.00, 0.78, 0.28)   # raw honey caught by the light
		"diamond":  return Color(0.90, 0.97, 1.00)   # white fire off the table
		"morpho":   return Color(0.56, 0.68, 1.00)   # morpho iridescence
		"plume":    return Color(0.24, 0.92, 0.84)   # iridescent teal
		# The ten of 2026-08-27.
		"marble":   return Color(0.82, 0.68, 0.42)   # polished brass in the veins
		"noir":     return Color(0.95, 0.91, 0.84)   # ivory on black lacquer
		"bismuth":  return Color(1.00, 0.55, 0.80)   # the magenta film
		"azure":    return Color(0.90, 0.96, 1.00)   # sun on cloud
		"lagoon":   return Color(0.35, 0.90, 0.90)   # sun on water
		"savanna":  return Color(1.00, 0.70, 0.36)   # the low sun
		# Deliberately absent, so they keep a MATTE board: dawn, press, sand,
		# origami, onyx, and of the ten: mono (a flat page), wash (wet paper)
		# and redwood (bark). Paper, sand, folded card and wood do not reflect.
		_:          return Color(0, 0, 0, 0)

func color(key: String) -> Color:
	return _palette.get(key, Color.MAGENTA)

## A COPY of the display order. Handing out `_order` itself let any caller sort,
## append to or clear the catalog's live order by reference — the Themes picker
## and gameplay's random-theme roll both iterate it — while the sibling accessor
## palette_for() has always copied. One shallow duplicate of the catalog's Strings
## (49 today; deliberately not written as a literal, the count moves every release).
## Claims the whole catalog first: callers walk these ids straight into
## palette_for/theme_name, and an id whose file turns out unloadable must be
## pruned before it is handed out — the eager loader never listed those.
func all_theme_ids() -> Array:
	_claim_all()
	return _order.duplicate()

## A read-only copy of any theme's palette without switching to it (used by the
## Themes screen to render previews). A SHALLOW duplicate IS the full copy here:
## every palette value is a Variant value type (Color/String/bool/float — see
## _map_theme), so the deep walk bought nothing. Revisit the flag before ever
## adding a container value to a palette.
func palette_for(id: String) -> Dictionary:
	_ensure_theme(id)   # first touch of a lazily-queued theme joins its load here
	return (_palettes.get(id, {}) as Dictionary).duplicate(false)

func theme_name(id: String) -> String:
	_ensure_theme(id)
	return String((_palettes.get(id, {}) as Dictionary).get("name", id))

## The accent a badge wears on chips and unlock toasts, taken from the theme it
## HISTORICALLY paid out (Entitlements.LEGACY_REWARD_BADGES). Badges pay gems
## now, so this is purely cosmetic — it survives only because it gives each
## badge its own identity colour for free. Falls back to gold for unmapped
## badges; very dark accents are lifted so they stay readable on glass cards.
func badge_accent(badge_id: String) -> Color:
	var fallback := Color("F4C13E")
	var theme_id := Entitlements.badge_legacy_theme(badge_id)
	if theme_id.is_empty():
		return fallback
	var col: Color = palette_for(theme_id).get("accent", fallback)
	if col.get_luminance() < 0.22:
		col = col.lightened(0.3)
	return col

## Theme ids grouped by OWNERSHIP — "free" | "shop" | "premium" — the picker's
## three sections. "free" is My Themes: every theme the player can wear right
## now, whichever road opened it (the free set, a gem purchase, a grandfathered
## badge, or the premium bundle). "shop" and "premium" hold only what is STILL
## locked, by the road that opens it. So a theme moves into My Themes the moment
## it is bought or earned, and premium folds the whole Premium section into My
## Themes — an owned theme sitting under a price tag or a crown read as "not
## yours yet" no matter what the tap did. Order within each section follows
## `_order`; empty sections are omitted. Returns Array of {category, ids}.
##
## Shop sits in the MIDDLE deliberately: it is the tier a free player can
## actually reach, so it should be what they scroll into after their own themes,
## with premium beyond it.
func grouped_themes() -> Array:
	_claim_all()   # the picker previews every id it is handed — resolve them all
	var free: Array[String] = []
	var shop: Array[String] = []
	var premium: Array[String] = []
	for id in _order:
		if EntitlementManager.is_theme_unlocked(id):
			free.append(id)
		elif Entitlements.theme_is_shop(id):
			shop.append(id)
		else:
			premium.append(id)
	var out: Array = []
	if not free.is_empty():
		out.append({"category": "free", "ids": free})
	if not shop.is_empty():
		out.append({"category": "shop", "ids": shop})
	if not premium.is_empty():
		out.append({"category": "premium", "ids": premium})
	return out

# -----------------------------------------------------------------------------
# Tile colour ramp.
# Low tiles are quiet, near-neutral surfaces; the scheme warms gradually toward
# gold as numbers climb, so progression *feels* like ascent rather than noise.
# Past the point where a ramp runs out of anchors the apex tier keeps the giants
# separating (see _apex_tone). Returns {bg: Color, fg: Color, glow: Color}.
# -----------------------------------------------------------------------------
func tile_style(value: int) -> Dictionary:
	return tile_style_for(_palette, value)

# Premium tile ramps: each board_style climbs through its OWN colour story (low →
# high), so a Toxic board reads acid-green and a Crystal board reads icy-blue
# rather than the generic rainbow. Sampled by tile level in _sample_luxe().
const _LUXE_RAMPS := {
	"gold":    ["3A2E12", "8A6A1E", "D9A82A", "F4C84A", "FFE9A8"],
	"silver":  ["2C3038", "5A6472", "8A95A6", "C2CBD8", "F2F6FC"],
	"crystal": ["123048", "1E6E9E", "33A8D8", "7FD8F2", "DDF6FF"],
	"molten":  ["2E0E06", "7A1E08", "C8400C", "F47A1E", "FFC24A"],
	"deep":    ["07242E", "0E5A66", "1E98A0", "6FD0DA", "DDF6FF"],
	"jade":    ["10301E", "1E6E40", "36A86A", "7FD8A0", "E8F8D0"],
	"phantom": ["1E0A2E", "5A1E8A", "9B3BD0", "C86AE8", "F0C8FF"],
	"shadow":  ["1A1E26", "39465E", "5E7290", "97A8C4", "DDE6F2"],
	"desert":  ["1A1638", "5A4A1E", "B89030", "E8C24A", "FFE9A8"],
	"toxic":   ["08240C", "1E6E1A", "4DB81E", "9BE82A", "E8FFA8"],
	# Sakura: the real blossom range — baby pink on the low tiles climbing through
	# pink and reddish pink into deep red up top (matches the petal confetti).
	"rose":    ["6E0F22", "D6203C", "FF5C8A", "FF9EC0", "FFD9E8"],
	"emerald": ["052A18", "0A6E3A", "16B060", "5FE0A0", "DAF8E0"],
	"ruby":    ["2E0810", "7A1430", "C81E48", "F0567E", "FFC8D8"],
	# Bioluminescence — light emerging from black, which is the whole phenomenon.
	# It replaced "sapphire" (a generic royal-blue walk that sat 0.154 from Starforged's
	# "astral" — the tightest pair in the catalogue — and said nothing about the theme).
	# Six anchors: the abyss where blue light finally dies, indigo, deep teal water,
	# then the two tiers that ARE the organism — electric bio-teal and the mint flash —
	# topped by the pale glow a bloom leaves in the water. The dark end is VIOLET, so
	# it reads apart from Ocean's blue-teal "deep" (0.215) at every tier.
	"biolum":  ["0A0428", "112A6E", "0A6E8E", "10C8A6", "5AFFDA", "CDFFF2"],
	"amethyst":["1A0A30", "3E1E8A", "7A3BD0", "AE74EC", "E2CCFF"],
	# Clockwork's alone now (Autumn moved to "foliage"), so the top tile turns cold:
	# a mechanism reads as brass AND steel rather than uniformly warm.
	"bronze":  ["1E2228", "5A3A14", "9A6A28", "D89A40", "F6D8A0"],
	"matrix":  ["031A06", "0A5A18", "12A82E", "4DF050", "C8FFCC"],
	# -------------------------------------------------------------------------
	# Ramps authored to end the two ways a board used to betray its own theme.
	#
	# (1) No ramp at all. A theme outside this dict and outside category "fun" fell
	#     to the generic accent->gold walk below, so ten boards — Neon City, Aurora,
	#     Space, Obsidian, three of the four FREE themes — all climbed to the same
	#     warm gold no matter what colour the rest of the screen was.
	# (2) A ramp shared with another theme. board_style is the ramp key, so Cosmic
	#     Nebula / Sanctum / Vaporwave were one board, and Ocean / Coral Depths /
	#     Koi Garden were another. Each pile-up below keeps the theme with the best
	#     claim on the original ramp and gives the rest their own.
	#
	# Authored DARK -> LIGHT: index 0 is the 1024 tile, index 4 the value-2 tile
	# (_sample_luxe walks it backwards). Neighbours want a real lightness step or
	# the mid tiles smear together.
	# -------------------------------------------------------------------------
	# --- (1) themes that had no ramp of their own ---
	"aurora":  ["0A2E24", "126E52", "1FB884", "6BEBBF", "F2C8E8"],  # green hem -> teal -> magenta tip, as the shader paints it
	"dawn":    ["3A2E5E", "6B5CED", "B08AE0", "F0A8B4", "FDE4D6"],  # night lilac -> periwinkle -> rose -> first light
	"firefly": ["0A1A0C", "1E4A18", "5E8A1E", "C4C838", "F2EEA8"],  # forest floor -> moss -> abdominal glow
	"stellar": ["1A1040", "3A2596", "6B52D8", "A594F0", "EDE6FC"],  # violet giant -> starlight
	"storm":   ["101828", "243A5E", "4A7AA8", "96C4E8", "F2F9FF"],  # slate -> rain-lit -> the strike
	"press":   ["1A1C24", "38425E", "6E7385", "B4B2AC", "F2EFE6"],  # navy ink -> graphite -> stock
	"sand":    ["3A3428", "6E6350", "9A8F76", "C4BAA0", "EFE8D6"],  # basalt -> weathered stone -> raked sand
	"onyx":    ["0E1412", "1E3A32", "2EA382", "8AE8CC", "EAF7F2"],  # graphite -> mint -> cold white
	"origami": ["2A2C50", "4A4E80", "8C93C4", "FF997A", "FAF2E8"],  # dusk fold -> sky fold -> coral -> cream
	# --- (2) themes moved off a ramp another theme had the better claim to ---
	"hoarfrost":["3A5A72", "6E92AE", "9EC4DC", "CBE4F2", "F4FCFF"], # Arctic
	"foliage": ["4A0F14", "8A2A16", "C4581E", "E8933A", "F0D89A"],  # Autumn; Clockwork keeps machined "bronze"
	"bloodmoon":["1F0508", "5E1418", "9A2A22", "D4562E", "F0A868"], # Blood Moon, atmospheric; Ruby keeps the gemstone ramp
	"coral":   ["3A0A30", "8A1F5E", "D44A92", "F58CC0", "D8FAF2"],  # Coral Depths; Ocean keeps "deep"
	"koi":     ["5E2408", "A8541A", "E08A3A", "F0C49A", "EAF7F5"],  # Koi Garden — the fish, not the pond
	"duskbloom":["2E0A2A", "6E1F52", "B04A88", "E08CBA", "F8D8E8"], # First Bloom at dusk; Sakura keeps light "rose"
	"lantern": ["6E1410", "A83A16", "E0752A", "F5B04A", "FFEDC4"],  # lit paper; Golden Rain keeps metallic "gold"
	"lacquer": ["1A0A0E", "5E1420", "A82E3E", "C9CFDC", "F2F5FA"],  # Ronin — lacquer, blood, steel; Shadow Fog keeps "shadow"
	"nebula":  ["4A0A52", "961F9E", "D43AB8", "EE8AD0", "D8F6FF"],  # emission magenta -> cyan core; Sanctum keeps "amethyst"
	"vapor":   ["4A0A5E", "96149E", "FF59BF", "FFA8DC", "59F2F2"],  # Vaporwave — pink and cyan, non-negotiable
	# --- (3) the five playful themes, split off one shared pastel sweep ---
	"cel":     ["2E1F7A", "5A46C4", "8C7AE8", "BFB0F5", "EAE4FF"],  # Anime — cel-shaded sky
	"crt":     ["2A0A14", "8A0F2E", "E01F4A", "FF6B2E", "FFE04D"],  # Arcade — cabinet primaries
	# Candy Pop — the one ramp in the catalogue that is deliberately NOT a single
	# colour story. It used to span hue 323-329 — a 2 degree spread, i.e. one pink
	# — which put it inside Sakura's "rose" and made the two boards read as the
	# same theme. A candy jar is assorted, so this walks the whole wheel (deep
	# berry -> strawberry -> bubblegum -> grape -> sky -> mint -> lemon) while
	# LIGHTNESS still descends monotonically, so tiers keep separating by value
	# and the numeral colour never flips back and forth. Seven anchors, not five:
	# _sample_luxe indexes by ramp.size(), so a longer ramp just means finer hops.
	"confect": ["7A1450", "E02858", "F05CB0", "C87AE8", "5FC8E8", "A8F0C8", "FFF3A0"],
	"bigtop":  ["5E0A18", "A81428", "E0303F", "F5A83A", "FFF0D6"],  # Carnival — stripe red into fairground gold
	"pastelpop":["5A2E8A", "9A5AC4", "D48AE0", "F2B8E8", "FFEDF8"], # Kawaii — a two-colour theme, not a rainbow
	# Shop-theme ramps (bought with gems; see Entitlements.SHOP_THEMES).
	"rgb":     ["C81E96", "6E2ED8", "2E5AE0", "1FB8D8", "DDF8FF"],  # Keystroke RGB — the LED spectrum
	"void":    ["140A24", "46208A", "8A3ED0", "E08A3E", "FFE0C0"],  # Event Horizon — accretion glow -> the void
	"astral":  ["0A1430", "1E3A78", "2E6EC0", "6FB8E8", "EAF6FF"],  # Starforged — starlight blues
	# Ink Wash — rice paper -> wet ink. Unevenly spaced on purpose: real brushwork
	# pools darkest where the stroke ends, so the top two anchors sit closer than
	# an even walk would put them.
	"ink":     ["0E1014", "2A2E38", "5E6474", "A2A8B4", "F2EFE6"],
	"plasma":  ["24083E", "5E14A8", "B01EC8", "F04EB0", "FFD2F0"],  # Antigrav — magenta plasma
	"nova":    ["2A0A24", "8A1440", "D8402E", "F49A2E", "FFF6D8"],  # Nova Forge — plum coals -> white-hot
	"comet":   ["1E0A34", "4A2278", "1E8A80", "5FE0B0", "E8FFF4"],  # Skywriter — aubergine night -> mint script
	"atlas":   ["07222A", "10525A", "2E8F86", "C9A85C", "F6ECCF"],  # Star Atlas — patina chart -> antique gold
	# --- (4) the 2026-08 additions ---
	# Honeycomb — the inside of a hive read top to bottom: old capped wax at
	# the dark end, raw honey through the middle, fresh comb at the light end.
	"honey":   ["2A1806", "7A4A0E", "C4890F", "F0B72E", "FFE7A6"],
	# Diamond Rain — deliberately the COLDEST ramp in the catalogue: it is the
	# only one that ends at true white, which is what separates it from Silver
	# Rain sitting next to it in the picker.
	"diamond": ["141C28", "37546F", "84AECE", "CFE9FA", "FFFFFF"],
	# Butterfly Grove — the blue morpho, NOT the monarch it used to paint.
	# The monarch ramp ran hue 18-37 against Honeycomb's 30-44: two dark-brown
	# boards climbing to amber, 7-14 degrees apart, on two premium themes sitting
	# next to each other in the picker. A hive has to be amber, so the grove is
	# the one that moves — and the flock art already flies three species
	# (confetti.gd _butterfly_wings), so the morpho is on screen either way.
	# Black venation -> indigo -> the iridescent blue field -> the green flash a
	# morpho throws off-angle -> the swallowtail's pale yellow. It ends WARM on
	# purpose: every other blue ramp (astral, storm, diamond) ends pale blue or
	# white, and that warm tip is what keeps this one out of their territory.
	"morpho":  ["0A0618", "2A1470", "3F5CE0", "56B0F0", "8FE8D8", "F6F0B4"],
	# Peacock — the eye of a train feather, centre outward: indigo pupil,
	# teal iris, green field, gold rim.
	"plume":   ["07142E", "0D4A78", "0F9E94", "2FD8AE", "F0D68A"],
	# --- (5) the ten of 2026-08-27 ---
	# Each measured against the whole catalogue before it was authored
	# (tools/ramp_separation_probe.gd): tightest neighbour >= 0.155 on the
	# suite's mean-L1 measure, floor 0.10. The crowded hues (warm orange,
	# purple, pink) were avoided on purpose; these sit in the gaps.
	"marble":  ["6B4F2A", "B08D57", "D6C9B0", "F0ECE4", "FFFFFF"],  # Carrara - white stone into brass
	"noir":    ["050505", "3B2B1F", "8F6A3C", "DCC39A", "F4EEE1"],  # Noir - ivory, champagne, cognac, black
	"mono":    ["1A1A1A", "595959", "A6A6A6", "D9D9D9", "FFFFFF"],  # Mono - flat greys, nothing else
	"wash":    ["1E2A3A", "2E5C8A", "9C86C9", "E9A5B8", "FDF3B8"],  # Aquarelle - lemon, rose, violet, prussian, payne's grey
	"bismuth": ["12122E", "5A3FB0", "D65A9C", "3FC9B4", "F3E4A0"],  # Bismuth - the oxide film: gold, teal, magenta, violet, indigo
	"azure":   ["06224F", "0F5BC4", "3E9EF5", "A9D8FF", "FFFDF5"],  # Altitude - cloud white into the deep sky
	"lagoon":  ["053A48", "0C8A9C", "3ACFC8", "AEEFEA", "FFFFFF"],  # Lagoon - foam into deep water
	"savanna": ["16112A", "5B2F73", "C4506A", "FFA65C", "FFE4B0"],  # Savanna - the dusk walk, cream to night
	"redwood": ["120A08", "3A1A12", "8A3F2E", "8FBF7A", "EEF2EE"],  # Redwood - fog, fern, bark, deep bark
}

# -----------------------------------------------------------------------------
# The APEX tier — tiles past the end of a ramp.
#
# Both ramps run out of road long before the board does: a luxe ramp reaches its
# DARKEST anchor at 1024 and the theme-specific one its LIGHTEST gold at 4096,
# and every bigger tile used to repeat that one colour — so 4096 / 8192 / 16384
# / 32768 and beyond were colour-indistinct from each other.
# Real play goes well past 8192 (continue-past-win keeps doubling), so from the
# last anchor onward each further level takes a notch of its own: the hue sets off
# the SHORT way round toward the blue-violet end of the wheel and keeps walking,
# chroma grows (so even the near-neutral ramps — ink, silver, shadow — separate
# visibly) and brightness eases toward the tier's target. Warm boards heat through
# amber and crimson into magenta, cool ones deepen through indigo into violet, and
# the light gold ramp turns iridescent — the giants read as "past the ramp", not
# as noise. Three moving parts, so a ramp that is dark AND near-neutral (silver)
# still separates on chroma and hue when it has little brightness left to give.
#
# Everything at or below the anchor is untouched, so the tiles players actually
# see all game keep their authored colours exactly.
# -----------------------------------------------------------------------------
const _APEX_LUXE_STEP := 10     # value 1024 — where a luxe ramp hits its last anchor
const _APEX_PLAIN_STEP := 12    # value 4096 — where the theme-specific ramp tops out
const _APEX_SPAN := 8           # levels kept distinct past the anchor (2048 → 262144)
const _APEX_HUE_STEP := 0.052   # ~19° of colour wheel per level
const _APEX_HUE_END := 0.72     # blue-violet: the end every apex walk heads for
const _APEX_SAT_STEP := 0.09    # chroma gained per level
const _APEX_SAT_MAX := 0.80
const _APEX_LUXE_V := 0.50      # deep ramps lift toward this (<=0.5 keeps numerals white)
const _APEX_PLAIN_V := 1.00     # the light gold ramp keeps climbing into full light
const _APEX_EASE := 0.72        # <1: the brightness walk front-loads onto the REACHABLE giants

## The apex treatment for a tile `over` levels past the point where its ramp ended.
## Pure: (anchor, over, v_target) -> Color, so the same value always resolves to the
## same colour. `over` is clamped to _APEX_SPAN so an absurd tile value can never
## wrap the hue walk back around onto a lower tier's colour.
func _apex_tone(anchor: Color, over: int, v_target: float) -> Color:
	var n: float = float(clampi(over, 1, _APEX_SPAN))
	var dir: float = 1.0 if fposmod(_APEX_HUE_END - anchor.h, 1.0) <= 0.5 else -1.0
	var hue: float = fposmod(anchor.h + dir * _APEX_HUE_STEP * n, 1.0)
	var sat: float = clampf(anchor.s + _APEX_SAT_STEP * n, 0.0, _APEX_SAT_MAX)
	# Eased rather than even: the biggest brightness step lands on the first levels
	# past the anchor — the ones play actually reaches — and the far tail merely
	# settles onto the target instead of spending half the walk on tiles nobody sees.
	var val: float = lerpf(anchor.v, v_target, pow(n / float(_APEX_SPAN), _APEX_EASE))
	return Color.from_hsv(hue, sat, val, anchor.a)

## Sample a premium ramp at a tile level (step 1 → low, 10 → the darkest anchor),
## interpolating between its anchor colours; past 1024 the apex tier takes over.
func _sample_luxe(style: String, step: int) -> Color:
	var ramp: Array = _LUXE_RAMPS[style]
	# Reversed: the ramps are authored dark->light, but tiles must read LIGHT (value 2)
	# -> DARK (top tiles), so sample from the light end down.
	var t: float = 1.0 - clampf(float(step - 1) / 9.0, 0.0, 1.0)
	var fpos: float = t * float(ramp.size() - 1)
	var i: int = int(floor(fpos))
	var j: int = mini(i + 1, ramp.size() - 1)
	var col: Color = Color(String(ramp[i])).lerp(Color(String(ramp[j])), fpos - float(i))
	if step > _APEX_LUXE_STEP:
		# The ramp has no darker anchor left to give: keep the giants separating.
		col = _apex_tone(col, step - _APEX_LUXE_STEP, _APEX_LUXE_V)
	return col

func tile_style_for(p: Dictionary, value: int) -> Dictionary:
	var text_dark := Color("17140D")
	var text_light: Color = p["text"]
	# The ramp is indexed by MAGNITUDE. Antimatter tiles are negative, and the old
	# `maxf(value, 2)` clamped every one of them to step 1 — a -512 painted itself
	# as a 2, so the entire negative half of the board read as one colour. Sign is
	# carried by the MATERIAL instead (CandyFace's void face), not by the hue, so
	# +512 and -512 share a colour and differ in whether they emit or swallow light.
	var mag := absi(value)
	var step := int(round(log(maxf(mag, 2)) / log(2.0)))  # 1 (value 2) .. 11+
	var accent: Color = p["accent"]
	var bg2: Color = p["bg2"]
	var gold: Color = p["gold"]
	var style := String(p.get("board_style", "plain"))
	var bg: Color
	if _LUXE_RAMPS.has(style):
		# Every SHIPPED theme takes this branch: each one owns a bespoke colour story,
		# sampled light -> dark. The two branches below are the safety net for a theme
		# authored without a ramp — reachable by a new .tres, no longer by the catalog.
		bg = _sample_luxe(style, step)
	elif String(p.get("category", "")) == "fun":
		# Fallback for a "fun" theme with no ramp: a gentle pastel rainbow rooted at
		# the theme's spread base hue. The five playful themes used to share this and
		# read as one board with five hue offsets; they now have ramps of their own
		# (cel / crt / confect / bigtop / pastelpop).
		var base: float = float(p.get("tile_hue_base", accent.h))
		var hue: float = fmod(base + float(step) * 0.055, 1.0)
		var t: float = clampf(float(step - 1) / 10.0, 0.0, 1.0)
		bg = Color.from_hsv(hue, 0.65, lerpf(0.92, 0.98, t))
	else:
		# Fallback for any other theme with no ramp: pale surface tints on the low
		# tiles lifting into accent-tinted mids, then warm gold up top. Derived from
		# the palette, so a new theme still gets something coherent for free — but it
		# ALWAYS ends gold, which is why the ten themes that used to land here (Neon
		# City, Aurora, Space, Obsidian, Thunderstorm, Daybreak, Paper, Zen Garden,
		# Origami Sky, Firefly Night) each have an authored ramp now instead.
		if mag <= 4:
			bg = bg2.lerp(text_light, 0.05 + 0.04 * step)
		elif mag <= 32:
			bg = bg2.lerp(accent, 0.10 + 0.05 * (step - 2))
		elif mag <= 256:
			bg = accent.lerp(gold, 0.25 * (step - 5)).darkened(0.15)
		else:
			var t: float = clampf(float(step - 9) / 3.0, 0.0, 1.0)
			bg = gold.lerp(gold.lightened(0.18), t)
			if step > _APEX_PLAIN_STEP:
				# 4096 is as light as the gold reward tone goes; the giants above it
				# turn iridescent instead of all sharing that one colour.
				bg = _apex_tone(bg, step - _APEX_PLAIN_STEP, _APEX_PLAIN_V)
	# More colour strength on the non-premium ramps (fun + theme-specific) —
	# richer, more saturated hues without changing the palette itself. Lifted
	# again in the "vibrant & fun" pass: stronger chroma + a whisper more light.
	if not _LUXE_RAMPS.has(style):
		bg = Color.from_hsv(bg.h, clampf(bg.s * 1.36, 0.0, 1.0), clampf(bg.v * 1.03, 0.0, 1.0))
	# Legible numerals: whichever ink actually contrasts more (WCAG relative
	# luminance). The old encoded-luminance threshold (> 0.58) mislabeled bright
	# SATURATED fills — a hot vaporwave pink reads "deep" to the encoded average
	# but carries little real light, and white ink on it measured ~2.6:1. The
	# argmax can never pick the weaker ink, so the whole ramp clears the
	# contrast floor test_theme_visuals pins.
	var fg: Color = text_dark if _wcag_contrast(text_dark, bg) >= \
		_wcag_contrast(Color(1, 1, 1), bg) else Color(1, 1, 1)
	# Glow tint used for the merge halo/burst — the tile's own colour reads best.
	var glow: Color = bg.lightened(0.25)
	glow.a = 0.0  # glow alpha is animated up on merge by the tile view
	return {"bg": bg, "fg": fg, "glow": glow}

## WCAG contrast ratio between two colours (relative luminance on LINEARISED
## channels — Color.get_luminance() averages the encoded ones, which is exactly
## the error the numeral ink rule above used to inherit).
static func _wcag_contrast(a: Color, b: Color) -> float:
	var la := _wcag_lum(a)
	var lb := _wcag_lum(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)

static func _wcag_lum(c: Color) -> float:
	return 0.2126 * _wcag_lin(c.r) + 0.7152 * _wcag_lin(c.g) + 0.0722 * _wcag_lin(c.b)

static func _wcag_lin(c: float) -> float:
	return c / 12.92 if c <= 0.03928 else pow((c + 0.055) / 1.055, 2.4)

# -----------------------------------------------------------------------------
# Theme resource. Applies the palette + DesignSystem tokens to standard Controls
# so plain Buttons/Labels/Panels already look on-brand before custom styling.
# -----------------------------------------------------------------------------
func _build_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = DesignSystem.TYPE_BODY
	if ui_font:
		t.default_font = ui_font

	var panel_sb := _glass_box(_palette["bg1"])
	t.set_stylebox("panel", "Panel", panel_sb)
	t.set_stylebox("panel", "PanelContainer", panel_sb)

	t.set_color("font_color", "Label", _palette["text"])

	# Plain Buttons use the CONTROL fill, not the card fill — on light themes the
	# card fill is frosted white and a button painted with it vanishes on a card.
	var btn_normal := _flat_box(Color(_palette["control"]))
	var btn_hover := _flat_box(_palette["accent_soft"])
	var btn_pressed := _flat_box(Color(_palette["accent_soft"]).darkened(0.1))
	var btn_empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb: StyleBox = btn_empty
		match state:
			"normal": sb = btn_normal
			"hover": sb = btn_hover
			"pressed": sb = btn_pressed
		t.set_stylebox(state, "Button", sb)
	t.set_color("font_color", "Button", _palette["text"])
	t.set_color("font_hover_color", "Button", _palette["text"])
	t.set_color("font_pressed_color", "Button", _palette["text"])
	t.set_color("font_disabled_color", "Button", _palette["text_faint"])

	return t

func _glass_box(fill: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(int(DesignSystem.RADIUS_LG))
	sb.set_border_width_all(1)
	sb.border_color = _palette["stroke"]
	sb.set_content_margin_all(DesignSystem.SPACE_LG)
	var sh := DesignSystem.shadow(2, _palette.get("shadow", _palette["bg0"]))
	sb.shadow_color = sh["color"]
	sb.shadow_size = sh["size"]
	sb.shadow_offset = sh["offset"]
	return sb

func _flat_box(fill: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(int(DesignSystem.RADIUS_MD))
	sb.set_content_margin_all(DesignSystem.SPACE_MD)
	return sb
