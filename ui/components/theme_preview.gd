class_name ThemePreview
extends Control
## A small, self-contained LIVE preview of a theme's ambience — a cheap stand-in
## for the gameplay BoardFx, sized for a Themes-screen card.
##
## A live BoardFx runs real GPU particle systems — too heavy to spawn per card.
## Instead this shows the theme's REAL background as a photograph: a
## palette-overridden BoardFx (BoardFx.palette_override) renders the theme's own
## world once into a small offscreen viewport and the frame becomes the card's
## backdrop (see _bd_capture) — under the accent glow AppScreen hangs near the
## top of every real screen and the cinema vignette sinking the edges. Over it
## drifts the theme's OWN CONFETTI CAST: shapes and colours come from
## Confetti.recipe_preview (the same table the live showers use), so Sakura's
## card sheds blossoms, Clockwork drops gears and Golden Rain rains coins
## instead of every theme wearing the same soft dots.
## The dots remain only for the recipes that are weather rather than pieces
## (the storm wind, the sky waves, the fog bank, the laser show), animated by
## the motif's motion *family*:
##
##   fall     snow / petals / rain / leaves / gems / confetti / code   (top → down)
##   rise     embers / bubbles / fireflies / lanterns / balloons       (bottom → up)
##            ...plus ANY recipe whose pieces rise: a theme whose whole point is
##            that nothing falls (Antigrav) must never preview falling
##   twinkle  stars / space / nebula / crystals / fireworks            (blink in place)
##   drift    aurora / fog / motes / sunset / grid / gradients (soft)  (slow blobs)
##
## Decorative only — never eats input. Call setup(palette) once after
## construction.

var _bg: Color = Color.BLACK
var _bg2: Color = Color.BLACK
var _accent: Color = Color.WHITE
var _is_light := false
var _cols: Array[Color] = [Color.WHITE]
var _family: String = "drift"
var _t: float = 0.0
# The theme's confetti cast (Confetti.recipe_preview): [{tex, colors, scale}].
# Empty → the classic soft-dot field (the weather recipes).
var _cast: Array = []
var _cast_lo: float = 1.0     # the recipe's own piece-size band
var _cast_hi: float = 1.0
var _cast_shimmer := false    # shiny casts keep their catch-the-light pulse
# Motes, stored as parallel packed arrays (not an Array of Dictionary) so the
# per-frame update does no string-keyed hashing and no per-element allocation.
var _dp: PackedVector2Array   # normalized positions (0..1)
var _dr: PackedFloat32Array   # radii (px) — dot fallback only
var _dspd: PackedFloat32Array # speed
var _dph: PackedFloat32Array  # phase
var _dpi: PackedInt32Array    # cast part index (textured casts)
var _dsc: PackedFloat32Array  # sprite scale (textured casts)
var _dcol: PackedColorArray   # resolved colour per mote
var _bd_tex: Texture2D = null # photograph of the theme's real BoardFx world
var _bd_a: float = 0.0        # its fade-in
var _bd_id: String = ""       # request deferred to _ready (setup ran out-of-tree)
var _bd_pal: Dictionary = {}
var _kb_ph: float = randf() * TAU   # Ken Burns phase — every card breathes off-beat
## Height FRACTION of a name plate sitting on the TOP of the preview (0 = none).
## The vignette rises to the theme's own base colour under it, so a caption laid
## over the art reads in the theme's own text colour — the colour that palette
## was designed to put on that background — rather than needing a grey scrim
## belonging to no theme at all.
var plate: float = 0.0

func setup(pal: Dictionary, theme_id: String = "") -> void:
	_bg = pal.get("bg0", Color.BLACK)
	_bg2 = pal.get("bg_grad", _bg)
	_accent = pal.get("accent", Color.WHITE)
	_is_light = bool(pal.get("is_light", false))
	var hi: Color = _accent.lerp(Color.WHITE, 0.55)
	var warm: Color = pal.get("gold", _accent)
	_cols = [_accent, hi, warm]
	_family = _family_for(String(pal.get("bg_motif", "motes")))
	# The REAL background: a photograph of this theme's own BoardFx world (see
	# _bd_capture). Cached shots land instantly; fresh ones fade in when ready.
	# Headless renders nothing offscreen, so there the painted wash stands alone.
	_bd_tex = null
	_bd_a = 0.0
	_bd_id = ""
	if theme_id != "" and DisplayServer.get_name() != "headless":
		var ready_tex := _bd_lookup(theme_id)
		if ready_tex != null:
			_bd_tex = ready_tex
			_bd_a = 1.0
		elif is_inside_tree():
			_await_backdrop(theme_id, pal)
		else:
			# setup() runs before add_child (see themes.gd) — no tree to render
			# on yet, so _ready picks the request up.
			_bd_id = theme_id
			_bd_pal = pal
	var rec := Confetti.recipe_preview(pal)
	_cast = rec.get("parts", [])
	_cast_lo = float(rec.get("scale_lo", 1.0))
	_cast_hi = float(rec.get("scale_hi", 1.0))
	_cast_shimmer = bool(rec.get("shimmer", false))
	# A recipe whose pieces RISE overrides the motif family: Antigrav's whole
	# point is that nothing falls, and a lantern release previewed as falling
	# lanterns is the theme told backwards.
	if bool(rec.get("rise", false)):
		_family = "rise"
	# A textured cast never rides the blob-drift family: drift motion was
	# authored for huge soft blobs at 2-6% of the card per second, and real
	# confetti pieces at that speed are simply frozen — Event Horizon's eight
	# motionless star glints were the reported stuck card, and Clockwork,
	# Star Atlas, Paper, Arcade and Candy Pop sat in the same trap. Anything
	# the recipe doesn't RAISE, falls.
	elif not _cast.is_empty() and _family == "drift":
		_family = "fall"
	_seed()
	queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	resized.connect(queue_redraw)
	queue_redraw()
	if _bd_id != "":
		var id := _bd_id
		_bd_id = ""
		_await_backdrop(id, _bd_pal)

# --- The real backdrop, photographed ------------------------------------------
## A card's background is a PHOTOGRAPH of the theme's own BoardFx world: a
## palette-overridden BoardFx (see BoardFx.palette_override) renders that world
## into a small offscreen viewport and the frame becomes a texture. A LIVE
## BoardFx per card was rejected — ~16 worlds of particles and shader washes is
## a scroll-perf bill the Themes list cannot pay — while a photograph costs each
## card one texture draw.
##
## Those photographs are BAKED OFFLINE and shipped (assets/theme_cards/<id>.webp,
## made by tools/theme_backdrop_bake.gd), because taking them at runtime is what
## made the picker look like it was lagging: a fresh card wore the plain gradient
## while its world built offscreen, strictly one world at a time, and scrolling
## into new cards started that queue again — so browsing themes meant watching
## every card fill in a beat after you reached it. A baked shot is simply THERE
## on the card's first frame, at no build cost at all.
##
## render_world() below is the recipe both roads share; the live capture on top
## of it survives only as the fallback for a theme with no bake, which
## test_theme_backdrops exists to make sure never ships.
const BAKE_DIR := "res://assets/theme_cards"
const BAKE_SIZE := Vector2i(512, 256)
const _BD_CACHE_MAX := 20            # FIFO texture cap; evicted shots reload off disk

static var _bd_cache: Dictionary = {}     # theme id -> Texture2D
static var _bd_order: Array = []          # cache FIFO
static var _bd_inflight: Dictionary = {}  # id -> true while its shot renders
static var _bd_active: int = 0            # live capture viewports (concurrency cap)

static func bake_path(id: String) -> String:
	return "%s/%s.webp" % [BAKE_DIR, id]

## The photograph if one can be had RIGHT NOW — the session cache, then the
## shipped bake (a texture load, not a render). null means this theme has no
## bake and has to fall back to the live capture.
static func _bd_lookup(id: String) -> Texture2D:
	if _bd_cache.has(id):
		return _bd_cache[id]
	var path := bake_path(id)
	if not ResourceLoader.exists(path):
		return null
	var tex := load(path) as Texture2D
	if tex == null:
		return null
	_bd_keep(id, tex)
	return tex

## FIFO the cache so one long page cannot pin every backdrop in memory. Cards on
## screen hold their own reference either way; this only bounds what is kept for
## the NEXT card that asks.
static func _bd_keep(id: String, tex: Texture2D) -> void:
	_bd_cache[id] = tex
	_bd_order.append(id)
	while _bd_order.size() > _BD_CACHE_MAX:
		var old: String = _bd_order.pop_front()
		_bd_cache.erase(old)

## Requests the shot (a no-op if one is already rendering) and adopts it when
## the cache line lands. Only the WAITING side belongs to this card — the render
## itself is a static coroutine on the tree, so a card freed mid-shot never
## strands the in-flight flag.
##
## The request WAITS for the card to come NEAR the screen first: a page of
## thirty-odd cards used to photograph its whole tail below the fold while the
## fold was still animating in, and each world build pays its particle
## preprocess and any cold shape bakes on the main thread — that queue was the
## entrance stutter. Captures follow the scroll now (with most of a viewport of
## look-ahead, so slow scrolls meet the photo already landed), and they wait for
## the card to hold STILL for a few frames: a build hitching in the middle of a
## fling is scroll jank, while the same build at scroll-rest is invisible.
##
## The wait never gives up while the card lives (a bounded wait used to strand
## slow-scrolled tail cards on the plain gradient FOREVER — a permanently stuck
## card); instead a capture that failed is re-requested, a few times at most.
func _await_backdrop(id: String, pal: Dictionary) -> void:
	var tree := get_tree()
	if tree == null:
		return
	var last := global_position
	var still := 0
	while still < 3:
		await tree.process_frame
		if not is_inside_tree():
			return
		var now := global_position
		if _near_view() and now.distance_to(last) <= 2.0:
			still += 1
		else:
			still = 0
		last = now
	var tries := 0
	while not _bd_cache.has(id):
		if not is_inside_tree():
			return
		if not _bd_inflight.get(id, false):
			if tries >= 3:
				return   # three failed shots — the painted wash stands
			tries += 1
			_bd_capture(tree, id, pal)
		await tree.process_frame
	_bd_tex = _bd_cache[id]
	queue_redraw()

func _near_view() -> bool:
	var vp := get_viewport_rect()
	return get_global_rect().intersects(vp.grow(vp.size.y * 0.75))

## True while a backdrop photograph is rendering — the card burst timers hold
## their showers during it, so the one hitch a capture can cost never lands on
## the same frame as a dozen fresh emitters.
static func capture_busy() -> bool:
	return _bd_active > 0

## Renders ONE theme world offscreen and hands back the frame. The whole recipe
## for a card backdrop lives here so the shipped bakes and the runtime fallback
## cannot drift into two different-looking photographs of the same theme.
static func render_world(tree: SceneTree, pal: Dictionary, px: Vector2i = BAKE_SIZE) -> Image:
	var vp := SubViewport.new()
	vp.size = px
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.msaa_2d = Viewport.MSAA_DISABLED
	vp.handle_input_locally = false
	vp.gui_disable_input = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	# BoardFx lays out against this instead of the real viewport (UI.canvas_size).
	vp.set_meta("design_size", Vector2(px))
	# The theme's own base gradient under the world, exactly like AppScreen's.
	var bgr := TextureRect.new()
	var gt := GradientTexture2D.new()
	gt.fill_from = Vector2(0.0, 0.0)
	gt.fill_to = Vector2(0.0, 1.0)
	var grad := Gradient.new()
	var bg0: Color = pal.get("bg0", Color.BLACK)
	grad.set_color(0, bg0)
	grad.set_color(1, pal.get("bg_grad", bg0))
	gt.gradient = grad
	bgr.texture = gt
	bgr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vp.add_child(bgr)
	var fx := BoardFx.new()
	fx.palette_override = pal
	# Thinner than the menu backdrop (0.55): the photograph only needs enough
	# particles to dress the sky, and every particle is preprocess the build
	# frame pays synchronously — the density lever IS the capture-hitch lever.
	fx.ambience_scale = 0.4
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vp.add_child(fx)
	tree.root.add_child(vp)
	# Let the build land and the washes/shaders paint a real moment.
	for _i in 4:
		await tree.process_frame
	var img: Image = null
	if is_instance_valid(vp):
		img = vp.get_texture().get_image()
		vp.queue_free()
	return img

## The runtime fallback: photograph a theme that shipped without a bake, once,
## into the session cache.
static func _bd_capture(tree: SceneTree, id: String, pal: Dictionary) -> void:
	if _bd_inflight.get(id, false) or _bd_cache.has(id):
		return
	_bd_inflight[id] = true
	# STRICTLY one world building at a time: a build preprocess + cold bakes are
	# a main-thread bill, and two of them on one frame is a visible hitch.
	while _bd_active >= 1:
		await tree.process_frame
	_bd_active += 1
	var img: Image = await render_world(tree, pal, BAKE_SIZE)
	if img != null and not img.is_empty():
		_bd_keep(id, ImageTexture.create_from_image(img))
	# One clean frame between captures, so the next build lands on a fresh
	# frame instead of stacking onto this one readback.
	await tree.process_frame
	_bd_active -= 1
	_bd_inflight.erase(id)

func _family_for(motif: String) -> String:
	match motif:
		"snow", "petals", "rain", "rain_gold", "rain_silver", "rain_diamond", \
		"neon_rain", "code", "leaves", "confetti", "gems", \
		"honeycomb", "plumage", "wash":
			return "fall"
		"embers", "embers_lux", "bubbles", "fireflies", "firefly_night", \
		"lanterns", "balloons", "hearts", "deep_sea", "serpent", "koi", \
		"butterflies", "altitude", "lagoon", "savanna", "redwood":
			return "rise"
		"stars", "space", "nebula", "crystal", "fireworks", "moonlit", "biolum", \
		"circuit", "starmap", "stained_glass", "bismuth":
			return "twinkle"
		_:
			return "drift"

func _seed() -> void:
	var textured := not _cast.is_empty()
	var n := 30
	var rmin := 3.0; var rmax := 8.0
	var smin := 0.06; var smax := 0.22
	match _family:
		"drift":
			# Sprites carry more visual weight than soft dots, so textured
			# fields run slightly thinner in every family.
			n = 8 if textured else 10
			rmin = 55.0; rmax = 110.0; smin = 0.02; smax = 0.06
		"twinkle":
			n = 34 if textured else 40
			rmin = 2.0; rmax = 5.0; smin = 1.0; smax = 2.6
		_:  # fall / rise
			n = 22 if textured else 30
			rmin = 3.0; rmax = 8.0; smin = 0.06; smax = 0.22
	_dp.resize(n); _dr.resize(n); _dspd.resize(n); _dph.resize(n)
	_dpi.resize(n); _dsc.resize(n); _dcol.resize(n)
	for i in n:
		_dp[i] = Vector2(randf(), randf())
		_dr[i] = randf_range(rmin, rmax)
		_dspd[i] = randf_range(smin, smax)
		_dph[i] = randf() * TAU
		if textured:
			# i % parts respects the recipes' own weighting — mixes repeat
			# their lead shape ({petal},{petal},{koi}) exactly for this.
			var part_idx := i % _cast.size()
			_dpi[i] = part_idx
			var part: Dictionary = _cast[part_idx]
			var cols: Array = part.get("colors", [])
			var col := Color.WHITE
			if not cols.is_empty():
				col = cols[randi() % cols.size()]
			_dcol[i] = col
			# The recipe's piece-size band roughly halved: the ambience is the
			# theme breathing behind the board, not the celebration itself.
			_dsc[i] = randf_range(_cast_lo, _cast_hi) * float(part.get("scale", 1.0)) * 0.5
		else:
			_dpi[i] = 0
			_dsc[i] = 1.0
			_dcol[i] = _cols[i % _cols.size()]

## Corner UVs for the hand-rotated piece quads in _draw (shared by every card).
static var _quad_uv := PackedVector2Array([
	Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])

var _acc := 0.0   # 30 Hz step accumulator — see below

func _process(delta: float) -> void:
	# Several previews live in the scrolling Themes list at once. Skip the update
	# and redraw entirely while this card is scrolled off-screen — the biggest win,
	# since off-screen cards otherwise keep animating and re-recording draw calls.
	if not get_global_rect().intersects(get_viewport_rect()):
		return
	# On-screen cards step at 60 Hz (was 30, from when the field was slow soft
	# dots): the casts carry real falling pieces and a breathing photograph
	# now, and half-rate stepping of visible motion reads as judder. The
	# off-screen skip above remains the big win; 120 Hz panels still halve.
	_acc += delta
	if _acc < 1.0 / 60.0:
		return
	var dt := _acc
	_acc = 0.0
	_t += dt
	if _bd_tex != null and _bd_a < 1.0:
		_bd_a = minf(_bd_a + dt * 1.4, 1.0)
	var n := _dp.size()
	for i in n:
		var p: Vector2 = _dp[i]
		var spd: float = _dspd[i]
		var ph: float = _dph[i]
		match _family:
			"fall":
				p.y += spd * dt
				p.x += sin(_t * 1.3 + ph) * dt * 0.04
				if p.y > 1.1:
					p.y -= 1.2
					p.x = randf()
			"rise":
				p.y -= spd * dt
				p.x += sin(_t * 1.1 + ph) * dt * 0.05
				if p.y < -0.1:
					p.y += 1.2
					p.x = randf()
			"drift":
				p.x += spd * dt * 0.5
				p.y += sin(_t * 0.5 + ph) * dt * 0.03
				if p.x > 1.2:
					p.x -= 1.4
			_:
				# Twinkle: even the night sky SIFTS — a whisper of downward
				# drift under the blink, because stars that only pulse in place
				# were the stillest cards on the screen and read as frozen.
				p.y += dt * 0.016
				p.x += sin(_t * 0.5 + ph) * dt * 0.008
				if p.y > 1.05:
					p.y -= 1.1
					p.x = randf()
		_dp[i] = p
	queue_redraw()

func _draw() -> void:
	var s := size
	if s.x <= 0.0 or s.y <= 0.0:
		return
	# Vertical gradient backdrop (theme background top → bottom) — the stand-in
	# the photograph fades in over (and the only backdrop headless ever has).
	var quad := PackedVector2Array([Vector2(0, 0), Vector2(s.x, 0), Vector2(s.x, s.y), Vector2(0, s.y)])
	draw_polygon(quad, PackedColorArray([_bg, _bg, _bg2, _bg2]))
	# The photograph of the theme's real BoardFx world, when it has rendered.
	# It BREATHES — a slow Ken Burns drift (a few percent of zoom and a slight
	# wander, clipped by this control) — so a world whose motion froze in the
	# shot still reads alive under the drifting cast, never as a stuck render.
	if _bd_tex != null and _bd_a > 0.0:
		var z := 1.045 + 0.045 * sin(_t * 0.21 + _kb_ph)
		var ts := s * z
		var off := Vector2(
			(s.x - ts.x) * (0.5 + 0.5 * sin(_t * 0.13 + _kb_ph * 1.7)),
			(s.y - ts.y) * (0.5 + 0.5 * cos(_t * 0.17 + _kb_ph)))
		draw_texture_rect(_bd_tex, Rect2(off, ts), false, Color(1, 1, 1, _bd_a))
	# The accent glow AppScreen hangs near the top of every real screen, so the
	# card's sky is lit the way the app's actually is (same alphas as _paint_background).
	var glow := _glow_tex()
	var gw := s.x * 1.35
	var gcol := Color(_accent.r, _accent.g, _accent.b, 0.16 if _is_light else 0.11)
	draw_texture_rect(glow, Rect2(Vector2(s.x * 0.5 - gw * 0.5, s.y * 0.16 - gw * 0.5), Vector2(gw, gw)), false, gcol)
	var textured := not _cast.is_empty()
	var n := _dp.size()
	for i in n:
		var p: Vector2 = _dp[i]
		var pos := Vector2(p.x * s.x, p.y * s.y)
		var col: Color = _dcol[i]
		var a := 0.6
		match _family:
			"twinkle":
				a = 0.25 + 0.7 * (0.5 + 0.5 * sin(_t * _dspd[i] * 3.0 + _dph[i]))
			"drift":
				a = 0.18
			_:
				a = 0.62
		if textured:
			# Shiny casts (foil / gems / stars) keep their catch-the-light pulse;
			# twinkle already blinks, so it never pulses twice.
			if _cast_shimmer and _family != "twinkle":
				a *= 0.70 + 0.30 * sin(_t * 2.2 + _dph[i])
			var part: Dictionary = _cast[_dpi[i]]
			var tex: Texture2D = part["tex"]
			var ts: Vector2 = tex.get_size() * _dsc[i]
			var m := maxf(ts.x, ts.y)
			if m > 190.0:   # the mist wisps bake huge — cap them to card scale
				ts *= 190.0 / m
			if m > 120.0:
				# Huge pieces stay translucent: a 190px ink wisp at
				# paper-piece alpha is a blotch, not a haze.
				a *= 0.35
			var rot := 0.0
			match _family:
				"fall":
					rot = _dph[i] + _t * (0.7 if i % 2 == 0 else -0.55)
				"rise":
					rot = sin(_t * 0.9 + _dph[i]) * 0.35
				"drift":
					rot = _dph[i] * 0.25
			# Rotated by hand into an explicit quad instead of through
			# draw_set_transform. A command transform is applied AFTER the
			# vertex stage, so a rounded-corner mask (UI.round_clip reads
			# VERTEX) sees every piece sitting at the origin and lets it spill
			# out past the card corner — the one hole in an otherwise clipped
			# card. Hand-rotated corners are real local positions, so the mask
			# holds, and it is two draw commands cheaper per piece.
			var half_p := ts * 0.5
			var ax := Vector2(cos(rot), sin(rot)) * half_p.x
			var ay := Vector2(-sin(rot), cos(rot)) * half_p.y
			var pc := Color(col.r, col.g, col.b, a)
			draw_polygon(
				PackedVector2Array([pos - ax - ay, pos + ax - ay, pos + ax + ay, pos - ax + ay]),
				PackedColorArray([pc, pc, pc, pc]), _quad_uv, tex)
		else:
			var r: float = _dr[i]
			# A soft glow halo behind each mote, then the brighter core — so the effect
			# reads luminous rather than as flat dots. The halo wears the finish's
			# bloom hue: the mote's own colour lifted toward white (painted from the
			# PASSED palette, never the global ThemeManager — previews render
			# non-active themes).
			var halo := col.lerp(Color(1, 1, 1), 0.35)
			draw_circle(pos, r * 2.3, Color(halo.r, halo.g, halo.b, a * 0.30))
			draw_circle(pos, r, Color(col.r, col.g, col.b, a))
	_draw_vignette(s)

## The app-wide cinema vignette in miniature: edges sink toward a deep shade of
## the theme's own base so the mini board pops forward, exactly like the real
## screens' edge grade. Drawn OVER the motes, like the real vignette over the
## living ambience.
func _draw_vignette(s: Vector2) -> void:
	var deep := _bg.darkened(0.55)
	var edge := Color(deep.r, deep.g, deep.b, 0.30)
	var none := Color(deep.r, deep.g, deep.b, 0.0)
	var bh := s.y * 0.26
	var bw := s.x * 0.14
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(s.x, 0), Vector2(s.x, bh), Vector2(0, bh)]),
		PackedColorArray([edge, edge, none, none]))
	draw_polygon(PackedVector2Array([Vector2(0, s.y - bh), Vector2(s.x, s.y - bh), Vector2(s.x, s.y), Vector2(0, s.y)]),
		PackedColorArray([none, none, edge, edge]))
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(bw, 0), Vector2(bw, s.y), Vector2(0, s.y)]),
		PackedColorArray([edge, none, none, edge]))
	draw_polygon(PackedVector2Array([Vector2(s.x - bw, 0), Vector2(s.x, 0), Vector2(s.x, s.y), Vector2(s.x - bw, s.y)]),
		PackedColorArray([none, edge, edge, none]))
	if plate <= 0.0:
		return
	# The plate ground, in two bands down from the top edge: a near-opaque head
	# the caption actually sits on, then a long feather that dissolves it into
	# the sky. One single ramp put the last line of text where the wash was still
	# half transparent, which is how a busy sky swallows a theme's own name.
	var ph := s.y * plate
	var mid_y := ph
	var end_y := ph * 1.55
	var clear := Color(_bg.r, _bg.g, _bg.b, 0.0)
	var mid := Color(_bg.r, _bg.g, _bg.b, 0.55)
	var full := Color(_bg.r, _bg.g, _bg.b, 0.94)
	draw_polygon(PackedVector2Array([
		Vector2(0, 0), Vector2(s.x, 0), Vector2(s.x, mid_y), Vector2(0, mid_y)]),
		PackedColorArray([full, full, mid, mid]))
	draw_polygon(PackedVector2Array([
		Vector2(0, mid_y), Vector2(s.x, mid_y), Vector2(s.x, end_y), Vector2(0, end_y)]),
		PackedColorArray([mid, mid, clear, clear]))

# A soft radial falloff, baked ONCE for the app's lifetime (plain white mask;
# tinted per-card at draw time) — every card shares the same 64px texture.
static var _glow_img: ImageTexture

static func _glow_tex() -> ImageTexture:
	if _glow_img == null:
		var n := 64
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		var c := (float(n) - 1.0) * 0.5
		for y in n:
			for x in n:
				var d := Vector2(float(x) - c, float(y) - c).length() / c
				var a := pow(clampf(1.0 - d, 0.0, 1.0), 1.8)
				img.set_pixelv(Vector2i(x, y), Color(1, 1, 1, a))
		_glow_img = ImageTexture.create_from_image(img)
	return _glow_img
