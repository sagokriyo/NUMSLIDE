class_name RewardFx
extends RefCounted
## RewardFx — the signature effects for the ten badge-earned reward themes.
##
## Unlike every other theme's ambience, these are REACTIVE, not just ambient:
## BoardFx forwards every committed swipe (on_swipe) and every merge (on_merge,
## in BoardFx-local screen coordinates) into the active effect, so the world
## answers the player's hands — pulses race the motherboard, the koi scatter,
## the gear train ratchets, a katana slash follows the swipe. Idle animation
## keeps each alive between moves (they also dress Home / How-to-Play, where no
## gameplay events arrive).
##
##   circuit        Circuit Pulse — a dark motherboard; swipes fire current
##                  pulses along the copper traces, merges flare the nearest via
##   blackhole      Event Horizon — rotating accretion disk (shader) + infalling
##                  dust; merges flare the disk and feed it matter
##   starmap        Starforged — every merge ignites a star and links it into a
##                  growing constellation; swipes streak a comet
##   inkwash        Ink Wash — sumi-e mountains on rice paper; merges bloom ink
##                  drops, swipes drag a brush stroke
##   serpent        Ember Serpent — a living particle-trail dragon that patrols,
##                  dashes with your swipes and flares fire on merges
##   koi            Koi Garden — koi swim under the glass and dart away from
##                  swipes; merges drop a pebble (ripple rings + splash)
##   metaballs      Antigrav — a weightless metaball fluid (shader); swipes shove
##                  the blobs, merges fuse two of them
##   katana         Ronin — every swipe is a razor slash with steel sparks;
##                  merges cross-cut with a flash
##   gears          Clockwork — a brass gear train that ratchets one tick per
##                  swipe; merges vent steam and pop loose cogs
##   stained_glass  Sanctum — a rose window with god-rays; merges send a light
##                  beam from the window that bursts into jewel caustics
##   forge          Nova Forge — a white-hot crucible over a forge bed; merges
##                  throw a spark that flies up and feeds it, swipes are the
##                  hammer, and a full crucible ignites into a newborn star
##   skywriter      Skywriter — luminous vapour trails written across the night
##                  by every swipe; merges pin a glowing node and the high wind
##                  slowly pulls the script apart
##   star_atlas     Star Atlas — an engraved celestial chart turning behind the
##                  board; swipes turn the limb and sweep the index arm, merges
##                  engrave a new star into the constellation being charted
##
## RewardFx itself is only the factory + namespace; every effect extends
## RewardFx.Base (a Control). BoardFx instantiates via RewardFx.make(motif).

static func make(motif: String) -> Base:
	match motif:
		"circuit":       return Circuit.new()
		"origami":       return Origami.new()   # premium, not badge-earned — but fully reactive
		"blackhole":     return Blackhole.new()
		"starmap":       return Starmap.new()
		"inkwash":       return InkWash.new()
		"serpent":       return Serpent.new()
		"koi":           return Koi.new()
		"metaballs":     return Metaballs.new()
		"katana":        return Katana.new()
		"gears":         return Gears.new()
		"stained_glass": return StainedGlass.new()
		"forge":         return Forge.new()
		"skywriter":     return Skywriter.new()
		"star_atlas":    return StarAtlas.new()
	return null


# =============================================================================
# Base — shared plumbing: viewport metrics, cached procedural textures, compact
# particle/ripple/flash helpers, and the reactive contract (on_swipe/on_merge).
# =============================================================================
class Base extends Control:
	var vp: Vector2 = Vector2.ZERO
	var sc: float = 1.0            # scale vs the 1080-wide design reference
	## B2 — the host's clip window (BoardFx.clip_rect, handed through by
	## _m_reward BEFORE add_child). Gameplay keeps a SECOND RewardFx inside the
	## board's FxClip; that window covers a minority of the screen, yet the
	## effect used to re-issue its FULL element list every frame. Motifs whose
	## `_draw` walks element arrays test each element against this window and
	## skip draws that fall wholly outside it — with GENEROUS radii (an
	## element's whole glow/halo footprint plus slack), so nothing whose light
	## could reach the window is ever skipped. FxClip scissors those pixels
	## anyway, so the skip is byte-identical inside the clip — which is why it
	## runs on every platform and the desktop G5 shots hold. Simulation state
	## is NEVER skipped: only draw commands are.
	var clip_win: Callable = Callable()

	# Procedural textures are theme-independent → baked once per app session and
	# shared across every effect instance (same policy as BoardFx._shape_cache).
	static var _cache: Dictionary = {}

	## The clip window in this effect's local (== screen) space, pre-grown 2 px
	## for the antialiased-edge feather; Rect2() (zero size) = unclipped.
	func clip_window() -> Rect2:
		if not clip_win.is_valid():
			return Rect2()
		var r: Rect2 = clip_win.call()
		if r.size.x <= 0.0 or r.size.y <= 0.0:
			return Rect2()
		return r.grow(2.0)

	## True when a point element padded by `pad` could touch window `w`
	## (zero-size w = unclipped instance → always true).
	func win_has_point(w: Rect2, p: Vector2, pad: float) -> bool:
		return w.size.x <= 0.0 or w.grow(pad).has_point(p)

	## Rect/segment-bbox variant of the same test — for links and polylines,
	## whose spans can cross the window even when both endpoints sit outside.
	func win_has_rect(w: Rect2, b: Rect2, pad: float) -> bool:
		return w.size.x <= 0.0 or w.grow(pad).intersects(b)

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		# and_offsets, NOT set_anchors_preset: the latter keeps the node's current
		# 0×0 rect via compensating offsets when the parent is already laid out
		# (Home adds BoardFx after layout), and a degenerate rect gets the whole
		# canvas item culled after a few seconds — the vanishing-keyboard bug.
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		vp = UI.canvas_size(self)
		sc = vp.x / 1080.0
		_build()

	## Override points ----------------------------------------------------------
	func _build() -> void:
		pass

	func on_swipe(_dir: Vector2i) -> void:
		pass

	## `pos` is in this Control's local space (== screen space); `tint` is the
	## merged tile's own colour, pre-brightened for glow use.
	func on_merge(_pos: Vector2, _value: int, _tint: Color) -> void:
		pass

	## A celebration beat (e.g. tapping the Home wordmark) — flare the world.
	func on_celebrate() -> void:
		pass

	## The player's finger, forwarded live from gameplay (press + drag), in this
	## Control's local space (== screen space). Creature effects surface toward it.
	func on_touch(_pos: Vector2) -> void:
		pass

	# --- palette / device helpers ----------------------------------------------
	## The palette this world renders — empty = the active theme. Handed through
	## by BoardFx._m_reward from its own palette_override (the Themes cards'
	## backdrop captures), BEFORE add_child, so _build already paints with it.
	var pal_override: Dictionary = {}

	func pc(key: String) -> Color:
		if not pal_override.is_empty():
			var c: Color = pal_override.get(key, Color.MAGENTA)
			return c
		return ThemeManager.color(key)

	func white(a: float) -> Color:
		return Color(1, 1, 1, a)

	## A point in the VISIBLE frame around the board. The board is an opaque,
	## centred square, so anything drawn behind its ~[0.26..0.74] vertical band is
	## hidden — creatures and marks that want to be SEEN roam here instead: the top
	## and bottom margins and the thin side strips.
	func frame_point() -> Vector2:
		var r := randf()
		if r < 0.42:
			return Vector2(randf_range(0.05, 0.95) * vp.x, randf_range(0.05, 0.24) * vp.y)
		elif r < 0.84:
			return Vector2(randf_range(0.05, 0.95) * vp.x, randf_range(0.76, 0.95) * vp.y)
		var xf := randf_range(0.02, 0.12) if randf() < 0.5 else randf_range(0.88, 0.98)
		return Vector2(xf * vp.x, randf_range(0.30, 0.70) * vp.y)

	## Pull a point out from behind the board to the nearest visible margin band,
	## so a reaction aimed at a central touch still plays where the player can see.
	func to_visible(p: Vector2) -> Vector2:
		var yf: float = p.y / vp.y
		if yf > 0.26 and yf < 0.74:
			yf = 0.21 if yf < 0.5 else 0.79
		return Vector2(p.x, yf * vp.y)

	## Device-tier particle thinning (mirrors BoardFx._particle_scale).
	static var _pscale_cache: float = -1.0
	func pscale() -> float:
		if _pscale_cache < 0.0:
			var cores := OS.get_processor_count()
			var s := 1.0
			if cores <= 4:
				s = 0.6
			elif cores <= 6:
				s = 0.8
			if OS.has_feature("mobile"):
				s = minf(s, 0.7)
			_pscale_cache = s
		return _pscale_cache

	# --- cached textures --------------------------------------------------------
	func tex_dot() -> Texture2D:
		if not _cache.has("dot"):
			var g := Gradient.new()
			g.set_color(0, Color(1, 1, 1, 1))
			g.set_color(1, Color(1, 1, 1, 0))
			var t := GradientTexture2D.new()
			t.gradient = g
			t.fill = GradientTexture2D.FILL_RADIAL
			t.fill_from = Vector2(0.5, 0.5)
			t.fill_to = Vector2(0.5, 1.0)
			t.width = 24
			t.height = 24
			_cache["dot"] = t
		return _cache["dot"]

	func tex_round() -> Texture2D:
		if not _cache.has("round"):
			var g := Gradient.new()
			g.offsets = PackedFloat32Array([0.0, 0.35, 0.7, 1.0])
			g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.55),
				Color(1, 1, 1, 0.18), Color(1, 1, 1, 0)])
			var t := GradientTexture2D.new()
			t.gradient = g
			t.fill = GradientTexture2D.FILL_RADIAL
			t.fill_from = Vector2(0.5, 0.5)
			t.fill_to = Vector2(0.5, 1.0)
			t.width = 128
			t.height = 128
			_cache["round"] = t
		return _cache["round"]

	func tex_streak() -> Texture2D:
		if not _cache.has("streak"):
			var g := Gradient.new()
			g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
			g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
			var t := GradientTexture2D.new()
			t.gradient = g
			t.fill = GradientTexture2D.FILL_LINEAR
			t.fill_from = Vector2(0.5, 0.0)
			t.fill_to = Vector2(0.5, 1.0)
			t.width = 6
			t.height = 64
			_cache["streak"] = t
		return _cache["streak"]

	func tex_ring() -> Texture2D:
		if not _cache.has("ring"):
			var g := Gradient.new()
			g.offsets = PackedFloat32Array([0.0, 0.58, 0.78, 1.0])
			g.colors = PackedColorArray([Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.0),
				Color(1, 1, 1, 0.95), Color(1, 1, 1, 0.0)])
			var t := GradientTexture2D.new()
			t.gradient = g
			t.fill = GradientTexture2D.FILL_RADIAL
			t.fill_from = Vector2(0.5, 0.5)
			t.fill_to = Vector2(0.5, 1.0)
			t.width = 128
			t.height = 128
			_cache["ring"] = t
		return _cache["ring"]

	func tex_square() -> Texture2D:
		if not _cache.has("square"):
			var img := Image.create(6, 6, false, Image.FORMAT_RGBA8)
			img.fill(Color.WHITE)
			_cache["square"] = ImageTexture.create_from_image(img)
		return _cache["square"]

	## Per-pixel bake with a session-wide cache (uv runs -1..1; see BoardFx._shape).
	func bake(id: String, w: int, h: int, fn: Callable) -> Texture2D:
		if _cache.has(id):
			return _cache[id]
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		for y in h:
			for x in w:
				var uv := Vector2(
					float(x) / float(w - 1) * 2.0 - 1.0,
					float(y) / float(h - 1) * 2.0 - 1.0)
				var rgba: Color = fn.call(uv)
				img.set_pixelv(Vector2i(x, y), rgba)
		var tex := ImageTexture.create_from_image(img)
		_cache[id] = tex
		return tex

	# --- compact particle builders (subset of BoardFx._emit) --------------------
	func field(p: Dictionary) -> CPUParticles2D:
		var ps := CPUParticles2D.new()
		var amt: int = int(round(float(int(p.get("amount", 30))) * pscale()))
		# B1 (phones only) — same policy as BoardFx._emit: a clipped instance's
		# ambient fields keep their authored density but only simulate the
		# visible share. Count AND emission region shrink together (the region
		# is the grown clip window; unclipped it is the full screen, exactly
		# the old geometry) — count alone over a full-screen box thins the
		# in-window field to frac² of authored (adversarial-review finding).
		# Stochastic, so it stays behind the clip hint AND lite_gpu(): the
		# desktop G5 motion shots (starmap/serpent/koi/gears all call field())
		# keep their exact sample.
		var region := Rect2(Vector2.ZERO, vp)
		var clipped_lite: bool = clip_win.is_valid() and AppScreen.lite_gpu()
		if clipped_lite:
			var win: Rect2 = clip_win.call()
			if win.size.x > 0.0 and win.size.y > 0.0 and vp.x > 0.0 and vp.y > 0.0:
				region = win.grow(48.0).intersection(Rect2(Vector2.ZERO, vp))
				var frac: float = clampf(
					(region.size.x * region.size.y) / (vp.x * vp.y), 0.0, 1.0)
				amt = int(ceil(float(amt) * frac))
		ps.amount = maxi(amt, 1)
		ps.lifetime = float(p.get("lifetime", 8.0))
		ps.preprocess = minf(ps.lifetime, 1.5 if OS.has_feature("mobile") else 3.0)
		ps.randomness = 0.6
		ps.texture = p.get("tex", tex_dot())
		var rc := region.get_center()
		var box := region.size * 0.5
		match String(p.get("from", "all")):
			"top":
				ps.position = Vector2(rc.x, region.position.y - region.size.y * 0.04)
				box = Vector2(region.size.x * 0.55, region.size.y * 0.04)
			"bottom":
				ps.position = Vector2(rc.x, region.end.y + region.size.y * 0.04)
				box = Vector2(region.size.x * 0.55, region.size.y * 0.04)
			_:
				ps.position = rc
		ps.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		ps.emission_rect_extents = box
		var dir3: Vector3 = p.get("dir", Vector3(0, 1, 0))
		ps.direction = Vector2(dir3.x, dir3.y)
		ps.spread = float(p.get("spread", 10.0))
		ps.gravity = Vector2(0, float(p.get("gravity", 0.0)))
		ps.initial_velocity_min = float(p.get("vmin", 10.0))
		ps.initial_velocity_max = float(p.get("vmax", 30.0))
		var turb: float = float(p.get("turb", 0.0))
		if turb > 0.0:
			ps.orbit_velocity_min = -0.006 * turb
			ps.orbit_velocity_max = 0.006 * turb
		# B1 extends the 30 Hz policy to ALL fields of a clipped instance
		# (phones only) — mirrors BoardFx._emit; device validation owns it.
		if clipped_lite \
				or (OS.has_feature("mobile") and float(p.get("vmax", 30.0)) <= 120.0):
			ps.fixed_fps = 30
		ps.scale_amount_min = float(p.get("smin", 1.0))
		ps.scale_amount_max = float(p.get("smax", 3.0))
		if p.has("spin"):
			var sp: float = float(p["spin"])
			ps.angle_min = -180.0
			ps.angle_max = 180.0
			ps.angular_velocity_min = -sp * 60.0
			ps.angular_velocity_max = sp * 60.0
		var col: Color = p.get("color", Color.WHITE)
		var a: float = float(p.get("alpha", 0.6))
		if p.has("iramp"):
			ps.color_initial_ramp = p["iramp"]
			ps.color_ramp = alpha_ramp(Color(1, 1, 1), a, bool(p.get("twinkle", false)))
		else:
			ps.color_ramp = alpha_ramp(col, a, bool(p.get("twinkle", false)))
		ps.emitting = true
		add_child(ps)
		return ps

	## A radial one-shot burst at `pos` (spark pops, splashes, steam, cogs).
	func burst(pos: Vector2, p: Dictionary) -> CPUParticles2D:
		var ps := CPUParticles2D.new()
		ps.position = pos
		ps.one_shot = true
		ps.explosiveness = 1.0
		ps.amount = maxi(int(p.get("amount", 20)), 1)
		ps.lifetime = float(p.get("lifetime", 0.8))
		ps.texture = p.get("tex", tex_dot())
		ps.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINT
		var dir3: Vector3 = p.get("dir", Vector3(0, -1, 0))
		ps.direction = Vector2(dir3.x, dir3.y)
		ps.spread = float(p.get("spread", 180.0))
		ps.gravity = Vector2(0, float(p.get("gravity", 0.0)))
		ps.initial_velocity_min = float(p.get("vmin", 80.0))
		ps.initial_velocity_max = float(p.get("vmax", 240.0))
		ps.damping_min = 40.0
		ps.damping_max = 110.0
		ps.scale_amount_min = float(p.get("smin", 0.35))
		ps.scale_amount_max = float(p.get("smax", 1.2))
		if p.has("spin"):
			var sp: float = float(p["spin"])
			ps.angle_min = -180.0
			ps.angle_max = 180.0
			ps.angular_velocity_min = -sp * 60.0
			ps.angular_velocity_max = sp * 60.0
		var col: Color = p.get("color", Color.WHITE)
		if p.has("iramp"):
			ps.color_initial_ramp = p["iramp"]
			ps.color_ramp = alpha_ramp(Color(1, 1, 1), float(p.get("alpha", 0.95)), true)
		else:
			ps.color_ramp = alpha_ramp(col, float(p.get("alpha", 0.95)), true)
		ps.emitting = true
		ps.finished.connect(ps.queue_free)
		add_child(ps)
		return ps

	## Lifetime alpha curve: fade in → hold → out (twinkle = in → out).
	func alpha_ramp(col: Color, a: float, twinkle: bool) -> Gradient:
		var g := Gradient.new()
		if twinkle:
			g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
			g.colors = PackedColorArray([Color(col.r, col.g, col.b, 0.0),
				Color(col.r, col.g, col.b, a), Color(col.r, col.g, col.b, 0.0)])
		else:
			g.offsets = PackedFloat32Array([0.0, 0.12, 0.85, 1.0])
			g.colors = PackedColorArray([Color(col.r, col.g, col.b, 0.0),
				Color(col.r, col.g, col.b, a), Color(col.r, col.g, col.b, a),
				Color(col.r, col.g, col.b, 0.0)])
		return g

	func grad(cols: Array) -> Gradient:
		var g := Gradient.new()
		var offs := PackedFloat32Array()
		var pcs := PackedColorArray()
		var n := cols.size()
		for i in n:
			offs.append(float(i) / float(maxi(n - 1, 1)))
			pcs.append(cols[i])
		g.offsets = offs
		g.colors = pcs
		return g

	## An expanding, fading ring (water ripple / shockwave).
	func ripple(pos: Vector2, col: Color, grow: float, dur: float = 0.6, delay: float = 0.0) -> void:
		var ring := TextureRect.new()
		ring.texture = tex_ring()
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ring.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		var start: float = grow * 0.22
		ring.size = Vector2(start, start)
		ring.position = pos - ring.size * 0.5
		ring.modulate = Color(col.r, col.g, col.b, 0.0)
		add_child(ring)
		var tw := ring.create_tween()
		if delay > 0.0:
			tw.tween_interval(delay)
		tw.tween_property(ring, "modulate:a", 0.65, 0.05)
		tw.set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(ring, "size", Vector2(grow, grow), dur)
		tw.tween_property(ring, "position", pos - Vector2(grow, grow) * 0.5, dur)
		tw.tween_property(ring, "modulate:a", 0.0, dur)
		tw.chain().tween_callback(ring.queue_free)

	## A quick full-screen colour flash.
	func flash(col: Color, peak: float, dur: float = 0.3) -> void:
		var f := ColorRect.new()
		f.position = Vector2.ZERO
		f.size = vp
		f.mouse_filter = Control.MOUSE_FILTER_IGNORE
		f.color = Color(col.r, col.g, col.b, 0.0)
		add_child(f)
		var tw := f.create_tween()
		tw.tween_property(f, "color:a", peak, 0.06)
		tw.tween_property(f, "color:a", 0.0, dur)
		tw.tween_callback(f.queue_free)

	## A soft glow band breathing on the top or bottom edge (see BoardFx._edge_glow).
	func edge_glow(col: Color, base_a: float, peak_a: float, top: bool) -> void:
		var g := TextureRect.new()
		g.texture = tex_round()
		g.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var w: float = vp.x * 1.8
		var h: float = vp.y * 0.5
		g.size = Vector2(w, h)
		g.position = Vector2((vp.x - w) * 0.5, (-h * 0.55) if top else (vp.y - h * 0.45))
		g.modulate = Color(col.r, col.g, col.b, base_a)
		add_child(g)
		var tw := g.create_tween().set_loops()
		tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		tw.tween_property(g, "modulate:a", peak_a, 5.5)
		tw.tween_property(g, "modulate:a", base_a, 6.0)

	## Hosts a full-screen procedural shader at reduced resolution (identical
	## rationale + factors to BoardFx._shader_layer: soft shaders survive the
	## shrink and the per-pixel cost drops by the factor squared on phones).
	func shader_layer(mat: ShaderMaterial) -> void:
		var container := SubViewportContainer.new()
		container.position = Vector2.ZERO
		container.size = vp
		container.stretch = true
		container.stretch_shrink = 3 if OS.has_feature("mobile") else 2
		container.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var svp := SubViewport.new()
		svp.disable_3d = true
		svp.transparent_bg = true
		svp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		container.add_child(svp)
		var rect := ColorRect.new()
		rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rect.material = mat
		svp.add_child(rect)
		add_child(container)

	## A child Timer that fires `fn` every wait ∈ [lo, hi] seconds — dies with us,
	## so no generation guards are needed (unlike BoardFx's await loops).
	## Distance from `p` to the segment a→b. The workhorse of every procedural
	## bake in here that draws something with limbs — arms, blades, tubing.
	func seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
		var ab := b - a
		var l2 := ab.length_squared()
		if l2 <= 0.000001:
			return p.distance_to(a)
		var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
		return p.distance_to(a + ab * t)

	## Stand a baked silhouette on the ground line of the bottom band, with the
	## contact shadow that stops it reading as a sticker. Mirrors the helper of
	## the same name in BoardFx — the reward effects need it for exactly the same
	## reason the ambient motifs did.
	func landmark(tex: Texture2D, x_frac: float, height_frac: float, aspect: float,
			tint: Color, alpha: float = 1.0, base_frac: float = 1.005) -> TextureRect:
		var h: float = vp.y * height_frac
		var w: float = h * aspect
		var ground: float = vp.y * base_frac
		var shadow := TextureRect.new()
		shadow.texture = tex_round()
		shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		shadow.stretch_mode = TextureRect.STRETCH_SCALE
		shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		shadow.size = Vector2(w * 1.3, h * 0.16)
		shadow.position = Vector2(vp.x * x_frac - shadow.size.x * 0.5,
			ground - shadow.size.y * 0.55)
		shadow.modulate = Color(0, 0, 0, 0.24 * alpha)
		add_child(shadow)
		var n := TextureRect.new()
		n.texture = tex
		n.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		n.stretch_mode = TextureRect.STRETCH_SCALE
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE
		n.size = Vector2(w, h)
		n.pivot_offset = Vector2(w * 0.5, h)
		n.position = Vector2(vp.x * x_frac - w * 0.5, ground - h)
		n.modulate = Color(tint.r, tint.g, tint.b, alpha)
		add_child(n)
		return n

	func every(lo: float, hi: float, fn: Callable) -> void:
		var t := Timer.new()
		t.one_shot = true
		t.wait_time = randf_range(lo, hi)
		t.timeout.connect(func():
			fn.call()
			t.wait_time = randf_range(lo, hi)
			t.start())
		add_child(t)
		t.start()


# =============================================================================
# Circuit Pulse — a dark motherboard: copper traces run L-shaped routes between
# via pads. QUIET at rest (the vias breathe a dim LED glow, a lone pulse wanders
# now and then); every swipe fires current pulses racing along the traces, and
# every merge flares the nearest via and discharges pulses down its routes, in
# the merged tile's own colour — the board computes the player's moves.
# =============================================================================
class Circuit extends Base:
	## Via geometry, in design px — multiply by `sc`. Named because the static-layer
	## ordering guard below has to reason about all three radii, not just draw them.
	const RING_R := 6.5       # the copper ring
	const HEART_R := 3.4      # the breathing LED heart inside it
	const GLOW_R := 60.0      # a flare's halo: tex_dot() stretched to ±GLOW_R·flare

	var _nodes: Array = []    # {p: Vector2, flare: float, ph: float}
	var _traces: Array = []   # {pts, cum, len, a, b} — polyline + cumulative lengths
	var _pulses: Array = []   # {t: trace idx, t0: float, spd: float, col: Color, rev: bool}
	## Discrete parts soldered to the board — {p, kind, rot, len}. Constant, so
	## they live in the static layer with the traces and never cost a frame.
	var _parts: Array = []
	## Indicator LEDs sprinkled across the whole board — {p, ph, col, r}. These
	## DO animate (each breathes on its own clock), so they are drawn per frame,
	## but they are just two textured rects each.
	var _leds: Array = []
	var _t := 0.0
	## The CONSTANT half of the board — solder mask, copper traces, via rings —
	## painted once into its own canvas item behind this one, so `_draw` re-issues
	## only the parts that actually move. null when `_hoist_margin()` refuses the
	## split, in which case `_draw` paints the whole board exactly as it always did.
	var _static: Control = null

	func _build() -> void:
		# Vias on a jittered grid — enough structure to read as a PCB, enough
		# jitter (and a few dropped pads) to read as organic routing.
		const COLS := 5
		const ROWS := 9
		for gy in ROWS:
			for gx in COLS:
				if randf() < 0.20:
					continue
				var p := Vector2(
					(float(gx) + 0.5 + randf_range(-0.24, 0.24)) / float(COLS) * vp.x,
					(float(gy) + 0.5 + randf_range(-0.24, 0.24)) / float(ROWS) * vp.y)
				_nodes.append({"p": p, "flare": 0.0, "ph": randf() * TAU})
		# Traces: each via runs an L-shaped (Manhattan) route to its two nearest
		# neighbours — the dog-leg corners are what make it read as a PCB.
		var linked := {}
		for i in _nodes.size():
			var dists: Array = []
			for j in _nodes.size():
				if i != j:
					dists.append([_np(i).distance_to(_np(j)), j])
			dists.sort()
			for k in mini(2, dists.size()):
				var j: int = dists[k][1]
				var key := "%d_%d" % [mini(i, j), maxi(i, j)]
				if not linked.has(key):
					linked[key] = true
					_traces.append(_route(i, j))
		_populate_parts()
		# Everything under the LED hearts is CONSTANT: the solder mask, the ~45
		# copper traces, the ~40 via rings and the soldered parts never move and
		# never change colour —
		# all three are literal Colors, none reads the palette, so a theme change
		# cannot stale this layer. Painting them ONCE into their own canvas item
		# behind this one takes ~112 µs/frame/instance of draw_polyline and
		# draw_circle off the per-frame path; `draw_circle` costs the same at
		# r = 3.4 as at r = 200 (fixed tessellation), so the 40 copper rings alone
		# were as expensive as everything else on the board put together.
		if _hoist_margin() >= 0.0:
			_static = Control.new()
			_static.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_static.size = vp
			# A child paints ON TOP of its parent's own commands; this one has to
			# sit UNDER them, which is exactly what show_behind_parent means.
			_static.show_behind_parent = true
			_static.draw.connect(_draw_static.bind(_static))
			add_child(_static)
			_static.queue_redraw()
		# Idle life: a lone pulse wanders the board every few seconds — proof of
		# power without ever becoming busy.
		every(2.6, 6.0, func():
			if not _traces.is_empty():
				_spawn(randi() % _traces.size(), pc("accent"), randf() < 0.5))
		set_process(true)

	## The parts soldered to the board and the indicator lamps sprinkled over it.
	## Called from _build once the vias exist, so nothing lands on top of one.
	func _populate_parts() -> void:
		# Discrete components: resistors, electrolytics and ICs, dropped on a
		# coarse grid and nudged off it, skipping any cell that would collide
		# with a via pad.
		const PC := 4
		const PR := 7
		for gy in PR:
			for gx in PC:
				if randf() < 0.42:
					continue
				var p := Vector2(
					(float(gx) + 0.5 + randf_range(-0.30, 0.30)) / float(PC) * vp.x,
					(float(gy) + 0.5 + randf_range(-0.30, 0.30)) / float(PR) * vp.y)
				var clash := false
				for n_v in _nodes:
					if ((n_v as Dictionary)["p"] as Vector2).distance_to(p) < 34.0 * sc:
						clash = true
						break
				if clash:
					continue
				var roll := randf()
				var kind: int = 0 if roll < 0.44 else (1 if roll < 0.72 else 2)
				_parts.append({"p": p, "kind": kind,
					"rot": 0.0 if randf() < 0.5 else PI * 0.5,
					"len": randf_range(0.85, 1.25)})
		# Indicator lamps: small SMD LEDs all over the board, each breathing on
		# its own clock in its own colour. Denser than the vias and much smaller,
		# so the whole board reads as powered rather than just the routing.
		var lamp_cols: Array = [Color(0.30, 1.00, 0.45), Color(1.00, 0.30, 0.32),
			Color(1.00, 0.78, 0.24), Color(0.35, 0.82, 1.00), Color(1.00, 1.00, 0.92)]
		var lamps := 26
		for i in lamps:
			_leds.append({
				"p": Vector2(randf_range(0.03, 0.97) * vp.x, randf_range(0.03, 0.97) * vp.y),
				"ph": randf() * TAU,
				"spd": randf_range(0.55, 1.9),
				"col": lamp_cols[i % lamp_cols.size()],
				"r": randf_range(3.0, 5.4)})

	func _np(i: int) -> Vector2:
		return (_nodes[i] as Dictionary)["p"]

	## Slack, in px, on the one ordering assumption the static layer makes — negative
	## means "do not split, paint the old way".
	##
	## `_draw` used to interleave per via: ring i, heart i, glow i, ring i+1, …, so
	## ring j sat ON TOP of heart i and glow i for every j > i. Hoisting the rings
	## puts them all UNDERNEATH instead. That is invisible if and only if no via's
	## heart or flare glow can ever reach a NEIGHBOURING via's ring.
	##
	## A flare's glow is `tex_dot()` — a 24×24 radial gradient — stretched into a
	## rect of half-extent GLOW_R·sc·flare. Its alpha is zero outside the inscribed
	## circle (the corners of that rect are transparent), so its real footprint is a
	## DISC of radius GLOW_R·sc·flare, widened by at most one texel of bilinear
	## bleed; half the texture spans 12 texels, so that is GLOW_R·sc/12. With
	## flare ≤ 1.0 and a ring of radius RING_R·sc, the rings stay clear for every
	## flare value iff the closest pair of vias is at least
	## (GLOW_R·13/12 + RING_R)·sc apart — which also covers the heart, since
	## HEART_R + RING_R = 9.9 is an order of magnitude under 71.5.
	##
	## The 5×9 grid with ±0.24-cell jitter clears that on any portrait viewport
	## (and project.godot locks the handheld orientation to portrait), but a square
	## or landscape DESKTOP window can put two vertically-adjacent vias inside the
	## bound. So it is MEASURED on the layout that was actually built, once, rather
	## than assumed — and a negative margin keeps today's single-layer draw.
	func _hoist_margin() -> float:
		var gap := INF
		for i in _nodes.size():
			for j in range(i + 1, _nodes.size()):
				gap = minf(gap, _np(i).distance_to(_np(j)))
		return gap - (GLOW_R * 13.0 / 12.0 + RING_R) * sc

	## The constant half of the board, painted once into `_static`: command for
	## command, and in the same order, the first three groups `_draw` used to
	## re-issue sixty times a second.
	func _draw_static(c: Control) -> void:
		# The board itself — deep solder-mask green, darker at the bottom edge.
		c.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.024, 0.062, 0.045))
		# Traces: dim copper-green runs. Static in colour; the LIGHT comes from
		# the pulses riding them.
		var trace_col := Color(0.34, 0.66, 0.47, 0.45)
		for tr_v in _traces:
			c.draw_polyline((tr_v as Dictionary)["pts"], trace_col, 3.0 * sc, false)
		# The copper ring of every via pad. Its breathing LED heart is NOT here —
		# that one changes every frame and stays in `_draw`.
		for n_v in _nodes:
			c.draw_circle((n_v as Dictionary)["p"], RING_R * sc,
				Color(0.42, 0.60, 0.46, 0.55))
		_paint_parts(c)

	## The soldered parts: axial resistors with colour bands, electrolytic caps
	## with a polarity stripe, and ICs with two rows of pins. Pure geometry, no
	## palette input, so it belongs with the rest of the constant board.
	func _paint_parts(c: CanvasItem) -> void:
		for pt_v in _parts:
			var pt: Dictionary = pt_v
			var p: Vector2 = pt["p"]
			var rot: float = pt["rot"]
			var ln: float = pt["len"]
			var ax := Vector2(cos(rot), sin(rot))        # along the part
			var pe := Vector2(-ax.y, ax.x)               # across it
			match int(pt["kind"]):
				0:   # resistor — beige barrel, two leads, three colour bands
					var hl: float = 22.0 * sc * ln
					var hw: float = 8.4 * sc
					c.draw_line(p - ax * (hl + 13.0 * sc), p + ax * (hl + 13.0 * sc),
						Color(0.68, 0.70, 0.74, 0.8), 2.6 * sc)
					_bar(c, p, ax, pe, hl, hw, Color(0.78, 0.68, 0.48, 0.92))
					var bands: Array = [Color(0.35, 0.22, 0.12), Color(0.85, 0.20, 0.16),
						Color(0.92, 0.76, 0.24)]
					for bi in bands.size():
						var off: float = (float(bi) - 1.0) * hl * 0.44
						_bar(c, p + ax * off, ax, pe, hl * 0.11, hw, bands[bi])
				1:   # electrolytic capacitor — dark can with a pale stripe
					var r: float = 14.0 * sc * ln
					c.draw_circle(p, r, Color(0.12, 0.16, 0.30, 0.95))
					c.draw_circle(p, r * 0.82, Color(0.18, 0.24, 0.42, 0.95))
					_bar(c, p - pe * r * 0.55, ax, pe, r * 0.86, r * 0.18,
						Color(0.72, 0.78, 0.90, 0.85))
				_:   # IC — black package with a pin row down each side
					var hx: float = 28.0 * sc * ln
					var hy: float = 17.0 * sc
					for s_v in [-1.0, 1.0]:
						var s: float = s_v
						for k in 5:
							var along: float = (float(k) - 2.0) * hx * 0.36
							c.draw_line(p + ax * along + pe * (hy * s),
								p + ax * along + pe * ((hy + 7.0 * sc) * s),
								Color(0.76, 0.78, 0.84, 0.85), 2.6 * sc)
					_bar(c, p, ax, pe, hx, hy, Color(0.13, 0.15, 0.19, 0.98))
					# A lit bevel along the package's top edge.
					_bar(c, p - pe * hy * 0.82, ax, pe, hx, hy * 0.16,
						Color(0.26, 0.29, 0.35, 0.9))
					# The pin-1 dimple.
					c.draw_circle(p - ax * hx * 0.66 - pe * hy * 0.4, 3.6 * sc,
						Color(0.40, 0.43, 0.50, 0.95))

	## An oriented filled rectangle: centre, its two unit axes, and half-extents.
	func _bar(c: CanvasItem, centre: Vector2, ax: Vector2, pe: Vector2,
			hl: float, hw: float, col: Color) -> void:
		c.draw_colored_polygon(PackedVector2Array([
			centre - ax * hl - pe * hw, centre + ax * hl - pe * hw,
			centre + ax * hl + pe * hw, centre - ax * hl + pe * hw]), col)

	## An L-shaped run from a to b (horizontal-then-vertical or the reverse).
	func _route(a: int, b: int) -> Dictionary:
		var pa := _np(a)
		var pb := _np(b)
		var corner := Vector2(pb.x, pa.y) if randf() < 0.5 else Vector2(pa.x, pb.y)
		var l1 := pa.distance_to(corner)
		var l2 := corner.distance_to(pb)
		return {"pts": PackedVector2Array([pa, corner, pb]),
			"cum": PackedFloat32Array([0.0, l1, l1 + l2]), "len": l1 + l2, "a": a, "b": b}

	## The point a distance `d` along a trace's polyline.
	func _sample(tr: Dictionary, d: float) -> Vector2:
		var cum: PackedFloat32Array = tr["cum"]
		var pts: PackedVector2Array = tr["pts"]
		d = clampf(d, 0.0, float(tr["len"]))
		var i := 1 if d <= cum[1] else 2
		var seg: float = cum[i] - cum[i - 1]
		var f: float = 0.0 if seg <= 0.0 else (d - cum[i - 1]) / seg
		return pts[i - 1].lerp(pts[i], f)

	func _spawn(trace: int, col: Color, rev: bool) -> void:
		_pulses.append({"t": trace, "t0": _t, "spd": randf_range(720.0, 1150.0) * sc,
			"col": col, "rev": rev})

	func on_swipe(_dir: Vector2i) -> void:
		# A committed move = current draw: a few pulses fire across the board.
		for i in 3:
			if not _traces.is_empty():
				_spawn(randi() % _traces.size(),
					pc("accent") if i % 2 == 0 else pc("accent2"), randf() < 0.5)

	func on_merge(pos: Vector2, _value: int, tint: Color) -> void:
		# The nearest via takes the hit: it flares and discharges down every
		# trace that touches it, in the merged tile's own colour (saturated so
		# it reads as an LED, not pastel plastic).
		var col := Color.from_hsv(tint.h, maxf(tint.s, 0.8), 1.0)
		var ni := _nearest(pos)
		if ni < 0:
			return
		(_nodes[ni] as Dictionary)["flare"] = 1.0
		for ti in _traces.size():
			var tr: Dictionary = _traces[ti]
			if int(tr["a"]) == ni or int(tr["b"]) == ni:
				_spawn(ti, col, int(tr["b"]) == ni)

	func on_celebrate() -> void:
		# The whole board powers up: every via flares, pulses everywhere.
		for n_v in _nodes:
			(n_v as Dictionary)["flare"] = 1.0
		for i in mini(10, _traces.size()):
			_spawn(randi() % _traces.size(),
				pc("accent") if i % 2 == 0 else pc("accent2"), randf() < 0.5)

	func _nearest(pos: Vector2) -> int:
		var best := -1
		var bd := 1e12
		for i in _nodes.size():
			var d := _np(i).distance_squared_to(pos)
			if d < bd:
				bd = d
				best = i
		return best

	func _process(delta: float) -> void:
		var scoped: bool = Engine.has_meta("bench_scope")  # perf-bench scope, regression/perf/SPEC.md #4.2
		if scoped:
			Engine.get_meta("bench_scope").call(true, "RewardFx._process")
		_t += delta
		for n_v in _nodes:
			var n: Dictionary = n_v
			n["flare"] = maxf(float(n["flare"]) - delta * 1.4, 0.0)
		var alive: Array = []
		for p_v in _pulses:
			var p: Dictionary = p_v
			var tr: Dictionary = _traces[int(p["t"])]
			if float(p["spd"]) * (_t - float(p["t0"])) < float(tr["len"]) + 40.0:
				alive.append(p)
			else:
				# The pulse arrives: the destination via blinks in acknowledgement.
				var ni: int = int(tr["a"]) if bool(p["rev"]) else int(tr["b"])
				var n: Dictionary = _nodes[ni]
				n["flare"] = maxf(float(n["flare"]), 0.55)
		_pulses = alive
		queue_redraw()
		if scoped:
			Engine.get_meta("bench_scope").call(false, "RewardFx._process")

	func _draw() -> void:
		var scoped: bool = Engine.has_meta("bench_scope")  # perf-bench scope, regression/perf/SPEC.md #4.2
		if scoped:
			Engine.get_meta("bench_scope").call(true, "RewardFx._draw")
		var accent := pc("accent")
		# B2 — the grid-clipped instance skips elements wholly outside its window.
		# Pads are generous: a via's furthest light is its flare glow (disc of
		# GLOW_R·sc·flare, flare ≤ 1, plus a texel of bilinear bleed — the same
		# bound `_hoist_margin` reasons with), a pulse's is its 5-dot tail
		# (≤ 36·sc back along the trace + a 13·sc dot). Draw-skip only: `_process`
		# still advances every flare and pulse, so state stays byte-identical.
		var cw := clip_window()
		# `_static` (built in `_build`) already holds the board, the traces and the
		# via rings, and sits directly behind this canvas item. When the ordering
		# guard refused that split, `_static` is null and this paints all of it.
		var solo: bool = _static == null
		if solo:
			# The board itself — deep solder-mask green, darker at the bottom edge.
			draw_rect(Rect2(Vector2.ZERO, vp), Color(0.016, 0.045, 0.032))
			# Traces: dim copper-green runs. Static in colour; the LIGHT comes from
			# the pulses riding them.
			var trace_col := Color(0.30, 0.58, 0.42, 0.30)
			for tr_v in _traces:
				var tr_pts: PackedVector2Array = (tr_v as Dictionary)["pts"]
				# A trace can cross the window with both vias outside → bbox test.
				if not win_has_rect(cw,
						Rect2(tr_pts[0], Vector2.ZERO).expand(tr_pts[1]).expand(tr_pts[2]),
						4.0 * sc):
					continue
				draw_polyline(tr_pts, trace_col, 2.0 * sc, false)
			_paint_parts(self)
		# Indicator lamps: small SMD LEDs all over the board, each breathing on
		# its own clock, each a bright point inside a soft halo.
		for l_v in _leds:
			var l: Dictionary = l_v
			var lp: Vector2 = l["p"]
			if not win_has_point(cw, lp, 14.0 * sc):
				continue
			var lit: float = 0.30 + 0.70 * pow(0.5 + 0.5 * sin(_t * float(l["spd"]) + float(l["ph"])), 2.2)
			var lc: Color = l["col"]
			var lr: float = float(l["r"]) * sc
			draw_texture_rect(tex_dot(),
				Rect2(lp - Vector2.ONE * lr * 4.5, Vector2.ONE * lr * 9.0),
				false, Color(lc.r, lc.g, lc.b, 0.40 * lit))
			draw_circle(lp, lr, Color(lc.r, lc.g, lc.b, minf(0.35 + lit * 0.65, 1.0)))
		# Via pads: a copper ring with a breathing LED heart; flares blaze.
		for n_v in _nodes:
			var n: Dictionary = n_v
			var p: Vector2 = n["p"]
			if not win_has_point(cw, p, GLOW_R * 1.25 * sc):
				continue
			var flare: float = n["flare"]
			var breathe: float = 0.10 + 0.06 * sin(_t * 1.1 + float(n["ph"]))
			if solo:
				draw_circle(p, RING_R * sc, Color(0.42, 0.60, 0.46, 0.55))
			draw_circle(p, HEART_R * sc, Color(accent.r, accent.g, accent.b,
				minf(breathe + flare, 1.0)))
			if flare > 0.01:
				draw_texture_rect(tex_dot(),
					Rect2(p - Vector2.ONE * GLOW_R * sc * flare,
						Vector2.ONE * GLOW_R * 2.0 * sc * flare),
					false, Color(accent.r, accent.g, accent.b, 0.85 * flare))
		# Pulses: a bright head racing the trace with a fading tail behind it.
		for p_v in _pulses:
			var p: Dictionary = p_v
			var tr: Dictionary = _traces[int(p["t"])]
			var d: float = float(p["spd"]) * (_t - float(p["t0"]))
			if bool(p["rev"]):
				d = float(tr["len"]) - d
			# Head + whole tail live within ~49·sc of the clamped head sample.
			if not win_has_point(cw, _sample(tr, d), 80.0 * sc):
				continue
			var col: Color = p["col"]
			for k in 5:
				var back: float = float(k) * 9.0 * sc * (-1.0 if bool(p["rev"]) else 1.0)
				var pos := _sample(tr, d - back)
				var a: float = 1.0 - float(k) * 0.18
				var r: float = (13.0 - float(k) * 1.8) * sc
				draw_texture_rect(tex_dot(), Rect2(pos - Vector2.ONE * r, Vector2.ONE * r * 2.0),
					false, Color(col.r, col.g, col.b, a))
		if scoped:
			Engine.get_meta("bench_scope").call(false, "RewardFx._draw")

# =============================================================================
# Origami Sky — a dusk sky of folded paper, and the folds answer the game:
# skeins of cranes cross while butterflies flutter between them, cranes rest on
# the board's shoulder until a swipe startles them off, and EVERY move folds a
# fresh sheet midair — visible creases — that springs open as a paper animal
# and departs in its own way: cranes/butterflies/koi fly with the swipe, frogs
# hop away, boats sail the bottom edge, pinwheels spin in place. Merges fold at
# the merge point in the tile's colour, growing with the tile; 1024+ folds a
# GOLDEN DRAGON, the first 2048 of a session folds a giant golden crane; fast
# merge combos release a garland of linked cranes. As the session wears on the
# sky sinks into night and the paper birds glow like lanterns.
# =============================================================================
class Origami extends Base:
	const _PAPERS: Array = [Color(1, 1, 1), Color(1.0, 0.72, 0.62), Color(0.72, 0.80, 1.0),
		Color(1.0, 0.88, 0.62), Color(0.80, 1.0, 0.84), Color(0.94, 0.76, 1.0)]
	const _GOLD := Color(1.0, 0.84, 0.35)
	# Weighted fold outcomes: the classics dominate, the specials stay special.
	const _POOL: Array = ["crane", "crane", "crane", "butterfly", "butterfly",
		"fish", "fish", "star", "fox", "fox", "pinwheel", "frog", "boat"]

	var _dusk := 0.0            # 0 = daylight … 1 = deep night (session clock)
	var _perched: Array = []    # cranes resting on the board's shoulder
	var _combo_n := 0           # fast-merge counter for the garland
	var _combo_ms := 0
	var _epic_done := false     # the giant first-2048 crane fires once a session

	func _build() -> void:
		# Night falls over the session: a slow dusk wash deepens for five
		# minutes; fliers born after dark carry their own lantern glow.
		var night := ColorRect.new()
		night.color = Color(0.05, 0.04, 0.14, 0.0)
		night.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		night.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(night)
		var nt := night.create_tween()
		nt.set_parallel(true)
		nt.tween_property(night, "color:a", 0.30, 300.0)
		nt.tween_method(func(v: float): _dusk = v, 0.0, 1.0, 300.0)
		# The sky is busy from the first frame: two skeins immediately, then
		# unhurried waves of cranes with butterflies fluttering between them.
		for i in 5:
			_flier(float(i), i % 3 == 2)
		every(1.8, 3.6, func():
			for i in randi_range(1, 3):
				_flier(float(i), false))
		every(2.6, 5.0, func(): _flier(randf_range(0.0, 1.5), true))
		# Now and then a crane descends and rests on the board's shoulder.
		every(6.0, 11.0, func():
			if _perched.size() < 3 and randf() < 0.65:
				_perch())

	# --- The reactive folds ------------------------------------------------------
	func on_swipe(dir: Vector2i) -> void:
		# The resting flock startles first — then the move folds its sheet.
		_flush_perched(Vector2(dir))
		var pos := Vector2(randf_range(0.20, 0.80) * vp.x, randf_range(0.18, 0.62) * vp.y)
		_fold(pos, 74.0 * sc, _paper(), Vector2(dir))

	func on_merge(pos: Vector2, value: int, tint: Color) -> void:
		# The giant golden crane: once a session, for the 2048 moment.
		if value >= 2048 and not _epic_done:
			_epic_done = true
			_fold(vp * Vector2(0.5, 0.42), vp.x * 0.34, _GOLD, Vector2(1, -0.4), "crane", 2.2)
			return
		# 1024 and up folds the GOLDEN DRAGON.
		if value >= 1024:
			_fold(pos, (96.0 + 20.0 * float(value >= 2048)) * sc, _GOLD, Vector2(0, -1), "dragon")
			return
		# Fast combo: three quick merges release a garland of linked cranes.
		var now := Time.get_ticks_msec()
		_combo_n = (_combo_n + 1) if (now - _combo_ms < 1400) else 1
		_combo_ms = now
		if _combo_n >= 3:
			_combo_n = 0
			_garland(pos, tint.lightened(0.15))
			return
		# The everyday fold: bigger tiles fold bigger sheets.
		var steps := clampf(log(float(maxi(value, 16)) / 16.0) / log(2.0), 0.0, 6.0)
		_fold(pos, (64.0 + steps * 13.0) * sc, tint.lightened(0.15), Vector2(0, -1))

	func on_celebrate() -> void:
		for i in 6:
			var tw := create_tween()
			tw.tween_interval(float(i) * 0.11)
			tw.tween_callback(func():
				_fold(Vector2(randf_range(0.15, 0.85) * vp.x, randf_range(0.15, 0.70) * vp.y),
					72.0 * sc, _paper(), Vector2(randf_range(-0.8, 0.8), -1.0)))

	func _paper() -> Color:
		return _PAPERS[randi() % _PAPERS.size()]

	## A sheet folds itself into an animal: the square spins in, creases in
	## half, in half again, then springs open as the finished animal — which
	## departs in its own way (see _depart). `kind` forces a species; `tempo`
	## stretches the whole performance for the epic folds.
	func _fold(pos: Vector2, d: float, col: Color, dir: Vector2,
			kind: String = "", tempo: float = 1.0) -> void:
		if kind.is_empty():
			kind = _POOL[randi() % _POOL.size()]
		var sheet := TextureRect.new()
		sheet.texture = _tex_paper()
		sheet.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sheet.stretch_mode = TextureRect.STRETCH_SCALE
		sheet.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sheet.size = Vector2(d, d)
		sheet.position = pos - Vector2(d, d) * 0.5
		sheet.pivot_offset = Vector2(d, d) * 0.5
		sheet.modulate = Color(col.r, col.g, col.b, 0.0)
		add_child(sheet)
		var t := sheet.create_tween()
		t.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		t.tween_property(sheet, "modulate:a", 1.0, 0.10 * tempo)
		t.parallel().tween_property(sheet, "rotation", 0.785, 0.16 * tempo)
		t.tween_property(sheet, "scale:y", 0.5, 0.12 * tempo).set_trans(Tween.TRANS_SINE)
		t.tween_property(sheet, "scale:x", 0.55, 0.11 * tempo).set_trans(Tween.TRANS_SINE)
		t.tween_callback(func():
			if not is_instance_valid(sheet):
				return
			var asz := _animal_size(kind, d)
			sheet.texture = _animal(kind)
			sheet.rotation = 0.0
			sheet.size = asz
			sheet.pivot_offset = asz * 0.5
			sheet.position = pos - asz * 0.5
			sheet.flip_h = dir.x < -0.1
			_night_glow(sheet)
			if kind in ["crane", "butterfly", "fish", "dragon"]:
				var flap := sheet.create_tween().set_loops()
				flap.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
				flap.tween_property(sheet, "scale:y", 0.80, randf_range(0.28, 0.4) * tempo)
				flap.tween_property(sheet, "scale:y", 1.0, randf_range(0.28, 0.4) * tempo))
		t.tween_property(sheet, "scale", Vector2(1.15, 1.15), 0.14 * tempo) \
			.from(Vector2(0.55, 0.55)).set_trans(Tween.TRANS_BACK)
		t.tween_property(sheet, "scale", Vector2.ONE, 0.10 * tempo)
		t.tween_interval(0.08 * tempo)
		t.tween_callback(func(): _depart(sheet, kind, pos, d, dir, tempo))

	func _animal_size(kind: String, d: float) -> Vector2:
		match kind:
			"dragon":   return Vector2(d * 2.2, d * 1.1)
			"pinwheel": return Vector2(d * 1.1, d * 1.1)
			"frog":     return Vector2(d * 1.1, d * 0.9)
			"boat":     return Vector2(d * 1.3, d * 0.9)
		return Vector2(d * 1.5, d * 1.0)

	## How each species leaves the stage.
	func _depart(sheet: TextureRect, kind: String, pos: Vector2, d: float,
			dir: Vector2, tempo: float) -> void:
		if not is_instance_valid(sheet):
			return
		var t := sheet.create_tween()
		match kind:
			"pinwheel":
				# Stays where it was folded, spinning down like a wound toy.
				t.tween_property(sheet, "rotation", TAU * 2.4, 3.0) \
					.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
				var f := sheet.create_tween()
				f.tween_interval(2.2)
				f.tween_property(sheet, "modulate:a", 0.0, 0.8)
				f.tween_callback(sheet.queue_free)
			"frog":
				# Three hops toward the bottom edge, squashing on each landing.
				var hx := (1.0 if randf() < 0.5 else -1.0) * d * 1.5
				t.set_trans(Tween.TRANS_QUAD)
				for i in 3:
					t.tween_property(sheet, "position:y", sheet.position.y - d * (0.9 - 0.2 * float(i)), 0.22) \
						.set_ease(Tween.EASE_OUT).set_delay(0.05)
					t.parallel().tween_property(sheet, "position:x", sheet.position.x + hx * float(i + 1) * 0.8, 0.44)
					t.chain().tween_property(sheet, "position:y",
						minf(sheet.position.y + d * (1.6 + 0.9 * float(i)), vp.y * 0.94), 0.24) \
						.set_ease(Tween.EASE_IN)
					t.tween_property(sheet, "scale:y", 0.72, 0.07)
					t.tween_property(sheet, "scale:y", 1.0, 0.09)
				t.tween_property(sheet, "modulate:a", 0.0, 0.5)
				t.tween_callback(sheet.queue_free)
			"boat":
				# Settles to the water line, then sails off rocking gently.
				var ltr := dir.x >= 0.0
				t.tween_property(sheet, "position:y", vp.y * 0.88, 1.0) \
					.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
				t.tween_property(sheet, "position:x",
					(vp.x + d * 2.0) if ltr else (-d * 2.0), 6.0).set_trans(Tween.TRANS_LINEAR)
				t.parallel().tween_property(sheet, "modulate:a", 0.0, 1.2).set_delay(4.6)
				t.tween_callback(sheet.queue_free)
				var rock := sheet.create_tween().set_loops()
				rock.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
				rock.tween_property(sheet, "rotation", 0.10, 0.7)
				rock.tween_property(sheet, "rotation", -0.10, 0.7)
			"dragon":
				# The dragon carves a slow S across the whole sky.
				var ltr2 := dir.x >= 0.0 if absf(dir.x) > 0.1 else randf() < 0.5
				var exit_x := (vp.x + d * 2.5) if ltr2 else (-d * 2.5)
				sheet.flip_h = not ltr2
				t.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
				t.tween_property(sheet, "position:y", pos.y - vp.y * 0.14, 1.1 * tempo)
				t.parallel().tween_property(sheet, "position:x",
					lerpf(sheet.position.x, exit_x, 0.4), 1.1 * tempo)
				t.tween_property(sheet, "position:y", pos.y - vp.y * 0.05, 1.0 * tempo)
				t.parallel().tween_property(sheet, "position:x", exit_x, 1.9 * tempo)
				t.parallel().tween_property(sheet, "modulate:a", 0.0, 0.8).set_delay(1.4 * tempo)
				t.tween_callback(sheet.queue_free)
			_:
				# Cranes, butterflies, koi, stars, foxes: away with the move.
				var fly := dir
				if fly.length() < 0.1:
					fly = Vector2(randf_range(-0.5, 0.5), -1.0)
				fly = fly.normalized()
				var target := pos + fly * vp.y * randf_range(0.34, 0.52) + Vector2(0, -vp.y * 0.08)
				t.tween_property(sheet, "position", target - Vector2(d * 0.75, d * 0.5), 1.6 * tempo) \
					.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
				t.parallel().tween_property(sheet, "modulate:a", 0.0, 0.9 * tempo).set_delay(0.7 * tempo)
				t.tween_callback(sheet.queue_free)

	## The combo garland: a V of five small cranes rising together, the flock
	## your streak just set free.
	func _garland(pos: Vector2, col: Color) -> void:
		for i in 5:
			var k := float(i) - 2.0
			var crane := TextureRect.new()
			crane.texture = _animal("crane")
			crane.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			crane.stretch_mode = TextureRect.STRETCH_SCALE
			crane.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var w := 44.0 * sc
			crane.size = Vector2(w, w * 0.66)
			crane.pivot_offset = crane.size * 0.5
			var start := pos + Vector2(k * w * 0.9, absf(k) * w * 0.55)
			crane.position = start - crane.size * 0.5
			crane.modulate = Color(col.r, col.g, col.b, 0.0)
			add_child(crane)
			_night_glow(crane)
			var t := crane.create_tween()
			t.tween_interval(float(i) * 0.06)
			t.tween_property(crane, "modulate:a", 1.0, 0.12)
			t.tween_property(crane, "position",
				start + Vector2(k * w * 1.6, -vp.y * 0.55) - crane.size * 0.5, 1.9) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			t.parallel().tween_property(crane, "modulate:a", 0.0, 0.8).set_delay(1.1)
			t.tween_callback(crane.queue_free)
			var flap := crane.create_tween().set_loops()
			flap.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
			flap.tween_property(crane, "scale:y", 0.78, 0.3 + float(i) * 0.03)
			flap.tween_property(crane, "scale:y", 1.0, 0.3 + float(i) * 0.03)

	# --- The resting flock ---------------------------------------------------------
	## A crane glides down and settles just above the board's shoulder, folding
	## its wings; it rests there — gently bobbing — until a swipe startles it.
	func _perch() -> void:
		var ltr := randf() < 0.5
		var w := randf_range(58.0, 84.0) * sc
		var b := TextureRect.new()
		b.texture = _animal("crane")
		b.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		b.stretch_mode = TextureRect.STRETCH_SCALE
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.size = Vector2(w, w * 0.66)
		b.pivot_offset = b.size * 0.5
		b.flip_h = not ltr
		var col := _paper()
		b.modulate = Color(col.r, col.g, col.b, 0.92)
		var seat := Vector2(randf_range(0.16, 0.84) * vp.x, vp.y * 0.243 - b.size.y * 0.5)
		b.position = Vector2((-90.0) if ltr else (vp.x + 90.0), seat.y - vp.y * 0.18)
		add_child(b)
		_night_glow(b)
		_perched.append(b)
		var t := b.create_tween()
		t.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		t.tween_property(b, "position", Vector2(seat.x - b.size.x * 0.5, seat.y), 2.2)
		# Wings beat on approach, then still into a soft breathing bob.
		var flap := b.create_tween().set_loops(5)
		flap.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		flap.tween_property(b, "scale:y", 0.80, 0.30)
		flap.tween_property(b, "scale:y", 1.0, 0.30)
		flap.finished.connect(func():
			if not is_instance_valid(b):
				return
			var bob := b.create_tween().set_loops()
			bob.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
			bob.tween_property(b, "position:y", seat.y - 4.0 * sc, 1.2)
			bob.tween_property(b, "position:y", seat.y, 1.2))

	## The swipe startles every resting crane into the air at once.
	func _flush_perched(dir: Vector2) -> void:
		if _perched.is_empty():
			return
		var fly := dir
		if fly.length() < 0.1:
			fly = Vector2(0, -1)
		fly = fly.normalized()
		for b_v in _perched:
			var b: TextureRect = b_v
			if not is_instance_valid(b):
				continue
			var t := b.create_tween()
			t.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			t.tween_property(b, "position",
				b.position + fly * vp.y * 0.4 + Vector2(randf_range(-60, 60) * sc, -vp.y * 0.12), 1.4)
			t.parallel().tween_property(b, "modulate:a", 0.0, 0.8).set_delay(0.5)
			t.tween_callback(b.queue_free)
			var flap := b.create_tween().set_loops()
			flap.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
			flap.tween_property(b, "scale:y", 0.76, 0.22)
			flap.tween_property(b, "scale:y", 1.0, 0.22)
		_perched.clear()

	# --- The ambient sky ---------------------------------------------------------
	## One flier crossing the sky: a crane in a slow glide, or a butterfly — a
	## smaller sheet on a wavier path with a quicker wingbeat.
	func _flier(idx: float, butterfly: bool) -> void:
		var ltr := randf() < 0.5
		var w: float = (randf_range(40.0, 62.0) if butterfly else randf_range(64.0, 118.0)) * sc
		var b := TextureRect.new()
		b.texture = _animal("butterfly" if butterfly else "crane")
		b.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		b.stretch_mode = TextureRect.STRETCH_SCALE
		b.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.size = Vector2(w, w * 0.66)
		b.pivot_offset = b.size * 0.5
		b.flip_h = not ltr
		var col: Color = _paper()
		b.modulate = Color(col.r, col.g, col.b, 0.92)
		var y0: float = vp.y * randf_range(0.05, 0.60) + idx * 40.0
		b.position = Vector2((-90.0 - idx * 64.0) if ltr else (vp.x + 90.0 + idx * 64.0), y0)
		add_child(b)
		_night_glow(b)
		var dur: float = randf_range(11.0, 16.0) if butterfly else randf_range(8.0, 13.0)
		var fly := b.create_tween()
		fly.tween_property(b, "position:x", (vp.x + 110.0) if ltr else -110.0, dur)
		fly.tween_callback(b.queue_free)
		var wander: float = 42.0 if butterfly else 24.0
		var bob := b.create_tween().set_loops()
		bob.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		bob.tween_property(b, "position:y", y0 - randf_range(0.6, 1.4) * wander,
			randf_range(0.5, 0.9) if butterfly else randf_range(1.1, 1.6))
		bob.tween_property(b, "position:y", y0 + randf_range(0.5, 1.0) * wander,
			randf_range(0.5, 0.9) if butterfly else randf_range(1.1, 1.6))
		var flap := b.create_tween().set_loops()
		flap.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		var beat: float = randf_range(0.18, 0.26) if butterfly else randf_range(0.5, 0.7)
		flap.tween_property(b, "scale:y", 0.72 if butterfly else 0.78, beat)
		flap.tween_property(b, "scale:y", 1.0, beat)

	## After dark every paper thing carries its own lantern: a warm glow that
	## rides behind the sprite, scaled to how deep the night is at its birth.
	func _night_glow(b: TextureRect) -> void:
		if _dusk < 0.35:
			return
		var g := TextureRect.new()
		g.texture = tex_dot()
		g.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		g.stretch_mode = TextureRect.STRETCH_SCALE
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		g.show_behind_parent = true
		g.size = b.size * 2.1
		g.position = -b.size * 0.55
		g.modulate = Color(1.0, 0.78, 0.45, 0.55 * _dusk)
		b.add_child(g)

	# --- Baked paper shapes --------------------------------------------------------
	## A sheet of paper: soft-cornered square with a faint diagonal crease.
	func _tex_paper() -> Texture2D:
		return bake("ori_paper", 48, 48, func(uv: Vector2) -> Color:
			if absf(uv.x) > 0.92 or absf(uv.y) > 0.92:
				return Color(0, 0, 0, 0)
			var b := 0.97 - (uv.x + uv.y) * 0.03
			if absf(uv.x - uv.y) < 0.05:
				b -= 0.08   # the first crease, already scored
			return Color(b, b, b, 1.0))

	func _animal(kind: String) -> Texture2D:
		match kind:
			"butterfly": return bake("ori_butterfly", 72, 56, _fn_butterfly)
			"fish":      return bake("ori_fish", 84, 52, _fn_fish)
			"star":      return bake("ori_star", 64, 64, _fn_star)
			"fox":       return bake("ori_fox", 72, 64, _fn_fox)
			"frog":      return bake("ori_frog", 72, 56, _fn_frog)
			"boat":      return bake("ori_boat", 84, 56, _fn_boat)
			"pinwheel":  return bake("ori_pinwheel", 64, 64, _fn_pinwheel)
			"dragon":    return bake("ori_dragon", 128, 64, _fn_dragon)
		return bake("ori_crane", 96, 64, _fn_crane)

	## Facet-triangle silhouettes: each facet gets its own paper brightness so
	## the folds read even as small tinted sprites. First hit wins.
	func _facets(uv: Vector2, facets: Array) -> Color:
		for f_v in facets:
			var f: Array = f_v
			if _tri(uv, f[1], f[2], f[3]):
				var b: float = f[0]
				return Color(b, b, b, 1.0)
		return Color(0, 0, 0, 0)

	func _fn_crane(uv: Vector2) -> Color:
		return _facets(uv, [
			[0.72, Vector2(0.85, -0.45), Vector2(1.0, -0.30), Vector2(0.80, -0.26)],
			[0.94, Vector2(0.38, 0.08), Vector2(0.85, -0.45), Vector2(0.55, 0.24)],
			[1.00, Vector2(-0.10, 0.12), Vector2(0.28, -0.88), Vector2(0.46, 0.12)],
			[0.78, Vector2(-0.33, 0.22), Vector2(-0.95, -0.28), Vector2(-0.28, 0.44)],
			[0.88, Vector2(-0.36, 0.20), Vector2(0.46, 0.06), Vector2(0.06, 0.58)]])

	func _fn_butterfly(uv: Vector2) -> Color:
		return _facets(uv, [
			[1.00, Vector2(-0.06, -0.05), Vector2(-0.95, -0.85), Vector2(-0.60, 0.20)],
			[0.90, Vector2(0.06, -0.05), Vector2(0.95, -0.85), Vector2(0.60, 0.20)],
			[0.82, Vector2(-0.05, 0.10), Vector2(-0.62, 0.80), Vector2(-0.08, 0.55)],
			[0.74, Vector2(0.05, 0.10), Vector2(0.62, 0.80), Vector2(0.08, 0.55)],
			[0.58, Vector2(-0.07, -0.45), Vector2(0.07, -0.45), Vector2(0.0, 0.60)]])

	func _fn_fish(uv: Vector2) -> Color:
		return _facets(uv, [
			[0.95, Vector2(-0.55, 0.0), Vector2(0.40, -0.42), Vector2(0.40, 0.42)],
			[0.82, Vector2(0.40, -0.42), Vector2(0.90, 0.0), Vector2(0.40, 0.42)],
			[0.72, Vector2(-0.50, 0.0), Vector2(-1.0, -0.48), Vector2(-0.68, 0.0)],
			[0.64, Vector2(-0.50, 0.0), Vector2(-1.0, 0.48), Vector2(-0.68, 0.0)],
			[1.00, Vector2(-0.10, -0.42), Vector2(0.22, -0.78), Vector2(0.30, -0.40)]])

	func _fn_fox(uv: Vector2) -> Color:
		# The classic origami fox head: two tall ears over a diamond face with
		# a bright folded snout.
		return _facets(uv, [
			[0.80, Vector2(-0.72, -0.30), Vector2(-0.52, -0.95), Vector2(-0.28, -0.30)],
			[0.72, Vector2(0.28, -0.30), Vector2(0.52, -0.95), Vector2(0.72, -0.30)],
			[0.94, Vector2(-0.80, -0.32), Vector2(0.80, -0.32), Vector2(0.0, 0.30)],
			[1.00, Vector2(-0.30, 0.06), Vector2(0.30, 0.06), Vector2(0.0, 0.62)]])

	func _fn_frog(uv: Vector2) -> Color:
		# Squat folded frog: haunches, back plate, and the tucked head.
		return _facets(uv, [
			[0.78, Vector2(-0.95, 0.55), Vector2(-0.55, -0.30), Vector2(-0.15, 0.55)],
			[0.72, Vector2(0.15, 0.55), Vector2(0.55, -0.30), Vector2(0.95, 0.55)],
			[0.95, Vector2(-0.60, 0.20), Vector2(0.0, -0.75), Vector2(0.60, 0.20)],
			[0.86, Vector2(-0.40, 0.55), Vector2(0.0, -0.05), Vector2(0.40, 0.55)]])

	func _fn_boat(uv: Vector2) -> Color:
		# The paper boat every child folds: hull, and the little sail peak.
		return _facets(uv, [
			[0.92, Vector2(-0.90, 0.10), Vector2(0.90, 0.10), Vector2(0.45, 0.72)],
			[0.80, Vector2(-0.90, 0.10), Vector2(0.45, 0.72), Vector2(-0.45, 0.72)],
			[1.00, Vector2(-0.06, 0.10), Vector2(0.0, -0.85), Vector2(0.42, 0.10)],
			[0.86, Vector2(-0.42, 0.10), Vector2(0.0, -0.85), Vector2(-0.06, 0.10)]])

	func _fn_pinwheel(uv: Vector2) -> Color:
		# Four swept blades around a hub, alternating light like a real toy.
		for k in 4:
			var a := float(k) * PI * 0.5
			var tip := Vector2(cos(a), sin(a)) * 0.95
			var edge := Vector2(cos(a + 0.5), sin(a + 0.5)) * 0.55
			if _tri(uv, Vector2.ZERO, tip, edge):
				var b := 0.95 - float(k % 2) * 0.18
				return Color(b, b, b, 1.0)
		if uv.length() < 0.14:
			return Color(0.55, 0.55, 0.55, 1.0)
		return Color(0, 0, 0, 0)

	func _fn_dragon(uv: Vector2) -> Color:
		# A long serpentine dragon: three body waves, a swept wing, horned head.
		return _facets(uv, [
			[0.70, Vector2(0.78, -0.40), Vector2(0.98, -0.60), Vector2(0.92, -0.22)],
			[0.95, Vector2(0.55, 0.05), Vector2(0.92, -0.45), Vector2(0.82, 0.25)],
			[1.00, Vector2(-0.05, 0.05), Vector2(0.28, -0.90), Vector2(0.45, 0.10)],
			[0.90, Vector2(-0.45, 0.30), Vector2(-0.10, -0.35), Vector2(0.60, 0.20)],
			[0.80, Vector2(-0.85, -0.10), Vector2(-0.40, -0.30), Vector2(-0.30, 0.36)],
			[0.66, Vector2(-1.0, -0.42), Vector2(-0.72, -0.28), Vector2(-0.80, 0.05)]])

	func _fn_star(uv: Vector2) -> Color:
		# Five kites around a pentagon heart, alternating facet light.
		var tips: Array = []
		var inner: Array = []
		for k in 5:
			var a := float(k) / 5.0 * TAU - PI * 0.5
			tips.append(Vector2(cos(a), sin(a)) * 0.95)
			var ia := a + PI / 5.0
			inner.append(Vector2(cos(ia), sin(ia)) * 0.42)
		for k in 5:
			var i2 := (k + 4) % 5
			if _tri(uv, tips[k], inner[k], inner[i2]):
				var b := 0.95 - float(k % 2) * 0.14
				return Color(b, b, b, 1.0)
			if _tri(uv, Vector2.ZERO, inner[k], inner[i2]):
				return Color(0.78, 0.78, 0.78, 1.0)
		return Color(0, 0, 0, 0)

	func _tri(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> bool:
		var d1 := (p - b).cross(a - b)
		var d2 := (p - c).cross(b - c)
		var d3 := (p - a).cross(c - a)
		var neg := d1 < 0.0 or d2 < 0.0 or d3 < 0.0
		var pos := d1 > 0.0 or d2 > 0.0 or d3 > 0.0
		return not (neg and pos)

# =============================================================================
# Event Horizon — a slowly rotating accretion disk (shader) around a pure-black
# core, with dust spiralling in. Swipes spin the disk up; merges flare it and
# tumble a few motes of "matter" from the merge point into the hole.
# =============================================================================
class Blackhole extends Base:
	const CENTRE := Vector2(0.5, 0.34)   # normalized screen position of the hole
	var _mat: ShaderMaterial
	var _ring: TextureRect               # the Einstein ring, flared by every plunge

	const _CODE := """
shader_type canvas_item;
uniform vec4 base : source_color = vec4(0.01, 0.01, 0.03, 1.0);
uniform vec4 col_in : source_color = vec4(1.0, 0.55, 0.18, 1.0);
uniform vec4 col_out : source_color = vec4(0.45, 0.25, 0.85, 1.0);
uniform vec2 centre = vec2(0.5, 0.34);
uniform float aspect = 0.46;
uniform float speed = 0.55;
uniform float flare = 0.0;
uniform float jet = 0.0;
void fragment() {
	vec2 p = (UV - centre) * vec2(aspect, 1.0);
	float r = length(p);
	float ang = atan(p.y, p.x);
	float t = TIME * speed;
	// Spiral arms: angle + 1/r phase makes the arms wind tighter toward the core
	// and stream forever; two frequencies so the disk never looks like a stamp.
	float arm = 0.55 + 0.45 * sin(ang * 2.0 + 1.1 / (r + 0.085) - t * 2.4);
	arm *= 0.70 + 0.30 * sin(ang * 5.0 - 1.6 / (r + 0.10) + t * 1.7);
	// NB: keep smoothstep edges ASCENDING (invert with 1.0-…) — reversed edges
	// are undefined in GLSL and collapse to 0 on the D3D12 driver.
	float disk = (1.0 - smoothstep(0.10, 0.42, r)) * smoothstep(0.050, 0.088, r);
	float ring = exp(-pow((r - 0.072) * 72.0, 2.0));      // photon ring
	float hole = 1.0 - smoothstep(0.042, 0.060, r);       // the void itself
	vec3 c = base.rgb;
	vec3 dcol = mix(col_out.rgb, col_in.rgb, 1.0 - smoothstep(0.09, 0.34, r));
	// Doppler beaming: the side of the disk spinning toward you burns brighter.
	float beam = 1.0 + 0.45 * cos(ang - 0.6);
	c += dcol * disk * arm * beam * (0.85 + flare * 1.6);
	// Gravitational lensing: the disk's far side bent into an arc over the poles.
	float arc = exp(-pow((length(vec2(p.x, p.y * 0.55)) - 0.145) * 30.0, 2.0))
		* smoothstep(0.05, 0.20, abs(p.y));
	c += mix(dcol, vec3(1.0, 0.9, 0.75), 0.35) * arc * (0.5 + flare * 0.8);
	c += vec3(1.0, 0.92, 0.78) * ring * (0.9 + flare);
	// Relativistic jets: twin beams fire from the poles when the hole feeds.
	float jt = jet * exp(-pow(p.x * 24.0, 2.0)) * (1.0 - smoothstep(0.08, 0.52, r))
		* smoothstep(0.02, 0.09, abs(p.y));
	c += vec3(0.72, 0.84, 1.0) * jt * 2.0;
	c = mix(c, vec3(0.0), hole);
	COLOR = vec4(c, 1.0);
}
"""

	# Compiled once per process (ui/screen.gd pattern); _mat stays per-instance.
	static var _shader: Shader

	func _build() -> void:
		if _shader == null:
			_shader = Shader.new()
			_shader.code = _CODE
		_mat = ShaderMaterial.new()
		_mat.shader = _shader
		_mat.set_shader_parameter("base", pc("bg0"))
		_mat.set_shader_parameter("col_in", pc("accent"))
		_mat.set_shader_parameter("col_out", pc("accent2"))
		_mat.set_shader_parameter("centre", CENTRE)
		_mat.set_shader_parameter("aspect", vp.x / vp.y)
		_mat.set_shader_parameter("speed", 0.55)
		_mat.set_shader_parameter("flare", 0.0)
		_mat.set_shader_parameter("jet", 0.0)
		shader_layer(_mat)
		# A sparse starfield over the disk, and dust spiralling into the hole.
		field({"tex": tex_dot(), "color": white(1.0), "alpha": 0.75, "amount": 90,
			"lifetime": 9.0, "dir": Vector3(0, 1, 0), "spread": 180.0,
			"vmin": 1.0, "vmax": 4.0, "smin": 0.2, "smax": 0.6, "twinkle": true})
		var dust := field({"tex": tex_dot(),
			"iramp": grad([pc("accent"), pc("accent2"), white(1.0)]),
			"alpha": 0.8, "amount": 46, "lifetime": 5.0, "dir": Vector3(0, 1, 0),
			"spread": 180.0, "vmin": 4.0, "vmax": 16.0, "smin": 0.25, "smax": 0.7,
			"twinkle": true})
		dust.position = Vector2(vp.x * CENTRE.x, vp.y * CENTRE.y)
		dust.emission_rect_extents = Vector2(vp.x * 0.42, vp.x * 0.42)
		dust.radial_accel_min = -160.0
		dust.radial_accel_max = -70.0
		dust.tangential_accel_min = 40.0
		dust.tangential_accel_max = 95.0
		_infall()
		_lens_ring()
		# The plunge: every so often the whole field accelerates inward and the
		# view narrows to a tunnel, then eases. This is what turns "a black hole
		# is on screen" into "you are going in".
		every(9.0, 17.0, _plunge)

	## The starfield seen from something falling: stars streaming radially in,
	## stretched along their own motion by aberration, accelerating the whole way.
	## Emitted on a ring well outside the frame so they arrive already moving.
	func _infall() -> void:
		var hole := Vector2(vp.x * CENTRE.x, vp.y * CENTRE.y)
		var f := field({"tex": tex_streak(), "color": white(1.0), "alpha": 0.7,
			"amount": 54, "lifetime": 3.2, "dir": Vector3(0, 1, 0), "spread": 180.0,
			"vmin": 10.0, "vmax": 40.0, "smin": 0.35, "smax": 1.5})
		f.position = hole
		f.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE_SURFACE
		f.emission_sphere_radius = maxf(vp.x, vp.y) * 0.85
		# Hard inward pull plus a little swirl, and the streak lies along its
		# velocity — which is what makes each star a line rather than a dot.
		f.radial_accel_min = -900.0
		f.radial_accel_max = -420.0
		f.tangential_accel_min = 30.0
		f.tangential_accel_max = 120.0
		f.particle_flag_align_y = true
		f.scale_amount_min = 0.4
		f.scale_amount_max = 2.2

	## The Einstein ring: light from behind the hole bent right around it into a
	## thin bright circle sitting just outside the shadow. It breathes, and the
	## plunge brightens it.
	func _lens_ring() -> void:
		var hole := Vector2(vp.x * CENTRE.x, vp.y * CENTRE.y)
		var ring := TextureRect.new()
		ring.texture = tex_ring()
		ring.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ring.stretch_mode = TextureRect.STRETCH_SCALE
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var d: float = vp.x * 0.46
		ring.size = Vector2(d, d)
		ring.pivot_offset = ring.size * 0.5
		ring.position = hole - ring.size * 0.5
		var hot: Color = pc("accent").lerp(Color(1.0, 0.92, 0.72), 0.6)
		ring.modulate = Color(hot.r, hot.g, hot.b, 0.30)
		add_child(ring)
		_ring = ring
		var tw := ring.create_tween().set_loops()
		tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		tw.tween_property(ring, "modulate:a", 0.46, 3.0)
		tw.tween_property(ring, "modulate:a", 0.24, 3.4)

	## One dive. The disk spins up, the ring flares, and a dark iris closes in
	## from the edges of the screen — tunnel vision, the oldest and most honest
	## way to draw acceleration you cannot otherwise feel.
	func _plunge() -> void:
		_pulse("speed", 2.4, 0.55, 2.6)
		var hole := Vector2(vp.x * CENTRE.x, vp.y * CENTRE.y)
		var iris := TextureRect.new()
		iris.texture = tex_ring()
		iris.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		iris.stretch_mode = TextureRect.STRETCH_SCALE
		iris.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# A ring of pure dark: as it shrinks, its hole shrinks with it and the
		# frame closes down to the singularity.
		var big: float = maxf(vp.x, vp.y) * 5.0
		iris.size = Vector2(big, big)
		iris.pivot_offset = iris.size * 0.5
		iris.position = hole - iris.size * 0.5
		iris.modulate = Color(0.0, 0.0, 0.02, 0.0)
		add_child(iris)
		var tw := iris.create_tween()
		tw.set_parallel(true).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		tw.tween_property(iris, "scale", Vector2(0.42, 0.42), 1.4)
		tw.tween_property(iris, "modulate:a", 0.85, 1.0)
		if is_instance_valid(_ring):
			tw.tween_property(_ring, "modulate:a", 0.95, 1.0)
			tw.tween_property(_ring, "scale", Vector2(1.22, 1.22), 1.4)
		tw.chain().set_parallel(true).set_ease(Tween.EASE_OUT)
		tw.tween_property(iris, "scale", Vector2(1.0, 1.0), 1.6)
		tw.tween_property(iris, "modulate:a", 0.0, 1.5)
		if is_instance_valid(_ring):
			tw.tween_property(_ring, "modulate:a", 0.30, 1.5)
			tw.tween_property(_ring, "scale", Vector2.ONE, 1.6)
		tw.chain().tween_callback(iris.queue_free)

	func _pulse(param: String, peak: float, base_v: float, dur: float) -> void:
		var tw := create_tween()
		tw.tween_method(func(v: float): _mat.set_shader_parameter(param, v),
			base_v, peak, dur * 0.3).set_ease(Tween.EASE_OUT)
		tw.tween_method(func(v: float): _mat.set_shader_parameter(param, v),
			peak, base_v, dur * 0.7).set_ease(Tween.EASE_IN_OUT)

	func on_swipe(_dir: Vector2i) -> void:
		_pulse("speed", 1.5, 0.55, 0.9)

	func on_merge(pos: Vector2, value: int, tint: Color) -> void:
		_pulse("flare", 0.5 + minf(float(value) / 2048.0, 1.0) * 0.5, 0.0, 0.9)
		# A heavy feed lights the relativistic jets from both poles.
		if value >= 512:
			_pulse("jet", 1.0, 0.0, 1.2)
		ripple(pos, pc("accent"), 320.0 * sc, 0.55)
		# Matter falls in: a few motes tumble from the merge point into the void.
		var hole := Vector2(vp.x * CENTRE.x, vp.y * CENTRE.y)
		for i in 5:
			var m := TextureRect.new()
			m.texture = tex_dot()
			m.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			m.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var d: float = randf_range(8.0, 16.0) * sc
			m.size = Vector2(d, d)
			m.position = pos - m.size * 0.5 + Vector2(randf_range(-30, 30), randf_range(-30, 30)) * sc
			m.modulate = tint
			add_child(m)
			var tw := m.create_tween()
			tw.set_parallel(true).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
			var dur := randf_range(0.55, 0.9)
			tw.tween_property(m, "position", hole - m.size * 0.5, dur)
			tw.tween_property(m, "scale", Vector2(0.1, 0.1), dur)
			tw.chain().tween_callback(m.queue_free)


# =============================================================================
# Starforged — the sky is a constellation the player is drawing. Every merge
# ignites a new star and links it to the nearest one; a full constellation
# flashes gold and a fresh one begins. Swipes streak a comet in the swipe
# direction.
# =============================================================================
class Starmap extends Base:
	const MAX_STARS := 26
	var _pts: Array = []           # Vector2 star positions
	var _born: Array = []          # float birth times
	var _links: Array = []         # Vector2i index pairs
	var _t: float = 0.0
	var _link_flash: float = -10.0 # time of the last completed-constellation flash
	var _morph_from: Array = []    # star positions when the morph began
	var _morph_to: Array = []      # their targets on the ∞ sigil
	var _morph_k: float = -1.0     # morph progress; -1 = inactive

	func _build() -> void:
		field({"tex": tex_dot(), "color": white(1.0), "alpha": 0.9, "amount": 120,
			"lifetime": 9.0, "dir": Vector3(0, 1, 0), "spread": 180.0,
			"vmin": 1.0, "vmax": 4.0, "smin": 0.25, "smax": 0.65})
		field({"tex": tex_dot(), "color": white(1.0).lerp(pc("accent"), 0.4), "alpha": 1.0,
			"amount": 34, "lifetime": 4.5, "dir": Vector3(0, 1, 0), "spread": 180.0,
			"vmin": 1.0, "vmax": 4.0, "smin": 0.5, "smax": 1.1, "twinkle": true})
		# Faint nebula breath behind the map.
		for i in 2:
			var blob := TextureRect.new()
			blob.texture = tex_round()
			blob.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			blob.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var d: float = vp.x * randf_range(0.8, 1.2)
			blob.size = Vector2(d, d)
			blob.position = Vector2(vp.x * (0.05 + 0.5 * float(i)) - d * 0.5, vp.y * 0.2 * float(i))
			var col: Color = pc("accent") if i == 0 else pc("accent2")
			blob.modulate = Color(col.r, col.g, col.b, 0.08)
			add_child(blob)
			var tw := blob.create_tween().set_loops()
			tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
			tw.tween_property(blob, "modulate:a", 0.14, randf_range(6.0, 9.0))
			tw.tween_property(blob, "modulate:a", 0.06, randf_range(6.0, 9.0))
		# The sky lives on its own: a stray shooting star between moves.
		every(6.0, 11.0, func():
			_comet(Vector2(randf_range(-1.0, 1.0), randf_range(0.35, 0.9)).normalized()))
		set_process(true)
		_armillary()

	func on_swipe(dir: Vector2i) -> void:
		_comet(Vector2(dir).normalized())

	## A comet streak — ridden by swipes, and drifting past on its own now and then.
	func _comet(d: Vector2) -> void:
		var comet := TextureRect.new()
		comet.texture = tex_streak()
		comet.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		comet.mouse_filter = Control.MOUSE_FILTER_IGNORE
		comet.size = Vector2(5.0, vp.x * 0.3)
		comet.pivot_offset = comet.size * 0.5
		comet.rotation = d.angle() + PI * 0.5
		var start := Vector2(
			clampf(vp.x * randf_range(0.2, 0.8), 0.0, vp.x),
			vp.y * randf_range(0.06, 0.30)) - d * vp.x * 0.4
		comet.position = start
		comet.modulate = Color(1, 1, 1, 0.0)
		add_child(comet)
		var tw := comet.create_tween().set_parallel(true)
		tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
		tw.tween_property(comet, "position", start + d * vp.x * 0.85, 0.8)
		tw.tween_property(comet, "modulate:a", 0.95, 0.14)
		tw.parallel().tween_property(comet, "modulate:a", 0.0, 0.5).set_delay(0.35)
		tw.chain().tween_callback(comet.queue_free)

	func on_merge(pos: Vector2, value: int, _tint: Color) -> void:
		# The new star lands in the sky band, roughly over the merge column.
		var p := Vector2(
			clampf(pos.x / vp.x + randf_range(-0.05, 0.05), 0.05, 0.95) * vp.x,
			randf_range(0.05, 0.42) * vp.y)
		# While a completed constellation is gliding into the ∞ sigil, hold the
		# figure: still flash a ripple for merge feedback, but don't spawn a new
		# star — adding one pushes _pts past _morph_to's count (freezing the glide
		# in _process) and would re-arm a second clear tween that wipes the next
		# sky early. Normal spawning resumes when the clear tween resets _morph_k.
		if _morph_k >= 0.0:
			ripple(p, pc("accent").lerp(white(1.0), 0.5), (90.0 + minf(float(value), 2048.0) * 0.05) * sc, 0.5)
			return
		var nearest := -1
		var best := INF
		for i in _pts.size():
			var d: float = (Vector2(_pts[i]) - p).length_squared()
			if d < best:
				best = d
				nearest = i
		_pts.append(p)
		_born.append(_t)
		if nearest >= 0:
			_links.append(Vector2i(nearest, _pts.size() - 1))
		# Bigger merges ignite brighter: a small flare at the newborn star.
		ripple(p, pc("accent").lerp(white(1.0), 0.5), (90.0 + minf(float(value), 2048.0) * 0.05) * sc, 0.5)
		if _pts.size() >= MAX_STARS:
			# Constellation complete — the stars glide into the ∞ sigil (the
			# game's own mark), flash gold, hold the figure, then a new sky begins.
			_link_flash = _t
			flash(pc("gold"), 0.10, 0.5)
			_morph_from = _pts.duplicate()
			_morph_to.clear()
			var c := Vector2(vp.x * 0.5, vp.y * 0.24)
			var ax: float = vp.x * 0.34
			for i in _pts.size():
				var u: float = float(i) / float(_pts.size()) * TAU
				_morph_to.append(c + Vector2(ax * cos(u), ax * 0.62 * sin(2.0 * u)))
			_morph_k = 0.0
			var clear := create_tween()
			clear.tween_interval(2.2)
			clear.tween_callback(func():
				_morph_k = -1.0
				_pts.clear()
				_born.clear()
				_links.clear())

	func _process(delta: float) -> void:
		var scoped: bool = Engine.has_meta("bench_scope")  # perf-bench scope, regression/perf/SPEC.md #4.2
		if scoped:
			Engine.get_meta("bench_scope").call(true, "RewardFx._process")
		_t += delta
		# Glide every star toward its ∞-sigil seat while a morph is running.
		if _morph_k >= 0.0 and _morph_k < 1.0 and _pts.size() == _morph_to.size():
			_morph_k = minf(_morph_k + delta / 0.8, 1.0)
			var k: float = smoothstep(0.0, 1.0, _morph_k)
			for i in _pts.size():
				_pts[i] = Vector2(_morph_from[i]).lerp(Vector2(_morph_to[i]), k)
		queue_redraw()
		if scoped:
			Engine.get_meta("bench_scope").call(false, "RewardFx._process")

	func _draw() -> void:
		var scoped: bool = Engine.has_meta("bench_scope")  # perf-bench scope, regression/perf/SPEC.md #4.2
		if scoped:
			Engine.get_meta("bench_scope").call(true, "RewardFx._draw")
		var accent: Color = pc("accent")
		var gold: Color = pc("gold")
		var flash_k := clampf(1.0 - (_t - _link_flash) / 0.6, 0.0, 1.0)
		# B2 — grid-clip cull, draw-skip only (positions/ages evolve unchanged).
		# A star's furthest light is its halo (r·2.6, r ≤ 36·sc); a link can
		# cross the window with both stars outside, hence the segment-bbox test.
		var cw := clip_window()
		for li in _links.size():
			var l: Vector2i = _links[li]
			if l.x >= _pts.size() or l.y >= _pts.size():
				continue
			var a: Vector2 = _pts[l.x]
			var b: Vector2 = _pts[l.y]
			if not win_has_rect(cw, Rect2(a, Vector2.ZERO).expand(b), 8.0 * sc):
				continue
			var lcol := accent.lerp(gold, flash_k)
			# Starlight runs along the threads: each link shimmers on its own beat.
			var shim: float = 0.75 + 0.25 * sin(_t * 2.1 + float(li) * 1.9)
			draw_line(a, b, Color(lcol.r, lcol.g, lcol.b, (0.22 + 0.5 * flash_k) * shim), 4.0 * sc)
			draw_line(a, b, Color(1, 1, 1, (0.30 + 0.4 * flash_k) * shim), 1.5 * sc)
		var dot := tex_dot()
		for i in _pts.size():
			var p: Vector2 = _pts[i]
			if not win_has_point(cw, p, 110.0 * sc):
				continue
			var age: float = _t - float(_born[i])
			var newborn := clampf(1.0 - age / 1.2, 0.0, 1.0)
			var tw := 0.75 + 0.25 * sin(_t * 2.2 + float(i) * 1.7)
			var r: float = (10.0 + 26.0 * newborn) * sc
			draw_texture_rect(dot, Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), false,
				Color(1, 1, 1, (0.55 + 0.45 * newborn) * tw))
			var halo: float = r * 2.6
			var hcol := accent.lerp(white(1.0), 0.4)
			draw_texture_rect(dot, Rect2(p - Vector2(halo, halo), Vector2(halo, halo) * 2.0), false,
				Color(hcol.r, hcol.g, hcol.b, 0.20 * tw + 0.4 * newborn))
		if scoped:
			Engine.get_meta("bench_scope").call(false, "RewardFx._draw")

	## The instrument the constellations are being charted with: an armillary
	## sphere standing on the horizon, its rings turning very slowly against the
	## sky it measures.
	func _armillary() -> void:
		var brass: Color = pc("accent").lerp(Color(0.92, 0.80, 0.46), 0.62)
		var host := Control.new()
		host.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(host)
		var cx: float = vp.x * 0.50
		var cy: float = vp.y * 0.855
		var r: float = vp.x * 0.20
		# The stand and its foot.
		var post := ColorRect.new()
		post.mouse_filter = Control.MOUSE_FILTER_IGNORE
		post.color = Color(brass.r, brass.g, brass.b, 0.55)
		post.size = Vector2(maxf(vp.x * 0.016, 3.0), vp.y * 0.115)
		post.position = Vector2(cx - post.size.x * 0.5, cy + r * 0.55)
		host.add_child(post)
		var foot := TextureRect.new()
		foot.texture = tex_round()
		foot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		foot.stretch_mode = TextureRect.STRETCH_SCALE
		foot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		foot.size = Vector2(vp.x * 0.20, vp.y * 0.022)
		foot.position = Vector2(cx - foot.size.x * 0.5, cy + r * 0.55 + vp.y * 0.105)
		foot.modulate = Color(brass.r, brass.g, brass.b, 0.5)
		host.add_child(foot)
		# The rings: three hoops at different tilts, each turning at its own rate.
		for e_v in [[1.00, 0.30, 34.0], [0.82, 0.90, -46.0], [0.62, 0.16, 62.0]]:
			var e: Array = e_v
			var ring := TextureRect.new()
			ring.texture = tex_ring()
			ring.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ring.stretch_mode = TextureRect.STRETCH_SCALE
			ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var d: float = r * 2.0 * float(e[0])
			ring.size = Vector2(d, d * float(e[1]))
			ring.pivot_offset = ring.size * 0.5
			ring.position = Vector2(cx - ring.size.x * 0.5, cy - ring.size.y * 0.5)
			ring.modulate = Color(brass.r, brass.g, brass.b, 0.55)
			host.add_child(ring)
			var tw := ring.create_tween().set_loops()
			tw.tween_property(ring, "rotation", TAU * (1.0 if float(e[2]) > 0.0 else -1.0),
				absf(float(e[2]))).from(0.0)
		# The little world at the centre of it.
		var core := TextureRect.new()
		core.texture = tex_dot()
		core.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		core.mouse_filter = Control.MOUSE_FILTER_IGNORE
		core.size = Vector2(r * 0.34, r * 0.34)
		core.position = Vector2(cx - core.size.x * 0.5, cy - core.size.y * 0.5)
		core.modulate = Color(brass.r, brass.g, brass.b, 0.8)
		host.add_child(core)
		var pulse := core.create_tween().set_loops()
		pulse.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		pulse.tween_property(core, "modulate:a", 1.0, 2.2)
		pulse.tween_property(core, "modulate:a", 0.55, 2.6)
		# A hazed horizon under it, so the instrument stands ON something.
		edge_glow(pc("accent"), 0.05, 0.12, false)

# =============================================================================
# Ink Wash — a real dip pen on aged paper. The whole page is warm handmade
# paper (cloudy mottle, fibre tooth, a little foxing, a lamp-lit vignette). A
# steel nib hovers over it at a writer's angle, a wet bead trembling at its
# point. Every move brings the nib DOWN to the board and touches: fresh ink
# blooms into the paper, feathering along the fibres, glistens while wet, then
# dries to a ghost and fades. Swipes drag a faint wet stroke; lifting the nib
# snaps a thread of ink and flicks a droplet; left alone the well-inked pen
# sheds the odd heavy drop that falls and blooms on its own.
# =============================================================================
class InkWash extends Base:
	var _ink_layer: Control        # every ink mark lives here, UNDER the nib
	var _nib: NibPen
	var _stains: Array = []         # live marks, oldest first (hard cap + auto-fade)
	var _t: float = 0.0
	var _last_strike: float = -10.0 # groups a multi-merge move into one nib move
	var _touch_t: float = -10.0     # throttles the follow-the-finger dab
	var _rest: Vector2              # where the pen hovers between moves
	## Poke bookkeeping. The pen is a character, and a character that is jabbed
	## at repeatedly says something about it: `_pokes` counts jabs inside a short
	## window, `_poke_last` ages that window out, `_scold_t` keeps it from
	## nagging twice in a row.
	var _pokes: int = 0
	var _poke_last: float = -10.0
	var _scold_t: float = -10.0
	var _writing: bool = false      # one phrase on the page at a time
	var _phrase_i: int = 0

	## The things the pen writes to itself between moves — encouragement, and a
	## few small reminders worth reading twice. Written in order (shuffled once
	## at build) rather than at random, so the same line never lands twice
	## running the way pure randf() will.
	const _PHRASES: Array[String] = [
		"Good luck", "Well done", "Nicely played", "Keep going",
		"Breathe, then move", "Unclench your jaw", "Sit up straight",
		"Rest your eyes a moment", "Drink some water", "Patience wins",
		"Steady hands", "Take your time", "You are doing fine",
		"One move at a time", "Almost there",
	]
	## What it writes when it has been poked once too often.
	const _SCOLDS: Array[String] = [
		"Stop that", "Enough, please", "I am working", "Mind the ink",
		"That tickles", "You will smudge it",
	]

	const _PAPER := """
shader_type canvas_item;
uniform vec4 paper : source_color = vec4(0.96, 0.94, 0.89, 1.0);
uniform vec4 paper2 : source_color = vec4(0.85, 0.81, 0.72, 1.0);
uniform float aspect = 0.46;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}
float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) { s += a * vnoise(p); p *= 2.03; a *= 0.5; }
	return s;
}
void fragment() {
	vec2 uv = UV;
	vec2 ar = vec2(1.0, 1.0 / max(aspect, 0.001));   // keep grain roughly square
	// cloudy handmade-paper mottle
	float m = fbm(uv * vec2(3.0, 3.0 / max(aspect, 0.001)));
	vec3 col = mix(paper.rgb, paper2.rgb, clamp(m * 0.7, 0.0, 1.0) * 0.5);
	// fibre tooth + long fibres
	col *= 0.975 + 0.025 * vnoise(uv * ar * 220.0);
	col *= 0.99 + 0.014 * vnoise(vec2(uv.x * ar.x * 520.0, uv.y * 30.0));
	// foxing — sparse warm age spots
	float fx = smoothstep(0.66, 0.82, fbm(uv * ar * 6.0 + 21.0));
	col = mix(col, col * vec3(0.82, 0.72, 0.58), fx * 0.30);
	// lamp-lit vignette (the page sits a touch darker at the edges)
	vec2 dd = uv - 0.5;
	float vig = 1.0 - smoothstep(0.30, 0.95, length(dd * vec2(1.0, 0.72)));
	col *= mix(0.86, 1.02, vig);
	COLOR = vec4(col, 1.0);
}
"""

	# Compiled once per process (ui/screen.gd pattern); the material stays per-instance.
	static var _paper_shader: Shader

	func _build() -> void:
		# 1. The page — a static paper shader fills the screen. It is soft and
		#    low-frequency, so it survives the SubViewport shrink cleanly.
		if _paper_shader == null:
			_paper_shader = Shader.new()
			_paper_shader.code = _PAPER
		var mat := ShaderMaterial.new()
		mat.shader = _paper_shader
		mat.set_shader_parameter("paper", pc("bg1"))
		mat.set_shader_parameter("paper2", pc("bg0").darkened(0.12))
		mat.set_shader_parameter("aspect", vp.x / vp.y)
		shader_layer(mat)
		# 1b. The page is RULED — feints and a red margin, printed under the ink.
		_ruled_page()
		# 2. Ink sits on the page; the pen hovers above the ink.
		_ink_layer = Control.new()
		_ink_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_ink_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		add_child(_ink_layer)
		_rest = Vector2(vp.x * 0.63, vp.y * 0.28)
		_nib = NibPen.new()
		_nib.setup(pc("text"), sc, vp, _rest)
		# B2: the pen re-records its whole quill every frame — hand it the clip
		# window so the grid instance can skip the draw when the pen (plus its
		# full feather reach) sits wholly outside the board window.
		_nib.clip_win = clip_win
		add_child(_nib)
		# 3. A well-inked pen sheds the odd heavy drop between moves, and idly jots
		#    a stray number in the margins — the page fills with practised figures.
		every(7.0, 14.0, _spontaneous_drip)
		every(4.5, 9.0, _idle_number)
		# 4. ...and every so often it writes itself a line worth reading. One goes
		#    down shortly after the page opens, so the first thing the pen does
		#    is greet you rather than make you wait out a full idle window.
		_phrase_i = randi() % _PHRASES.size()
		var hello := get_tree().create_timer(2.4)
		hello.timeout.connect(func() -> void:
			if is_inside_tree():
				_write_phrase("Good luck", Color(pc("text"), 0.85), 3.0))
		every(9.0, 17.0, _idle_phrase)
		set_process(true)

	## The ruled page the pen writes on: faint blue feints across the sheet and a
	## red margin down the left, laid straight onto the paper shader and never
	## redrawn. Deliberately a touch uneven — a ruled page printed slightly off
	## true is what stops this reading as a spreadsheet.
	func _ruled_page() -> void:
		var page := Control.new()
		page.mouse_filter = Control.MOUSE_FILTER_IGNORE
		page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		page.draw.connect(_draw_rules.bind(page))
		add_child(page)
		page.queue_redraw()

	func _draw_rules(c: CanvasItem) -> void:
		var ink: Color = pc("text")
		var feint := Color(ink.r, ink.g, ink.b, 0.10).lerp(Color(0.30, 0.45, 0.75, 0.14), 0.7)
		var gap: float = maxf(vp.y * 0.052, 26.0 * sc)
		var y: float = gap * 1.4
		var i := 0
		while y < vp.y - gap * 0.4:
			# Each rule sags a hair toward the middle of the sheet, as printed
			# feints do on a page that has been leaned on.
			var sag: float = sin(float(i) * 0.7) * 0.8 * sc
			c.draw_line(Vector2(vp.x * 0.055, y + sag), Vector2(vp.x * 0.965, y - sag),
				feint, maxf(1.0 * sc, 1.0))
			y += gap
			i += 1
		# The margin rule, in red, with the faint second line beside it that
		# ruled paper always seems to have.
		var red := Color(0.72, 0.24, 0.26, 0.26)
		c.draw_line(Vector2(vp.x * 0.135, gap * 0.5), Vector2(vp.x * 0.132, vp.y - gap * 0.3),
			red, maxf(1.4 * sc, 1.0))
		c.draw_line(Vector2(vp.x * 0.147, gap * 0.5), Vector2(vp.x * 0.144, vp.y - gap * 0.3),
			Color(red.r, red.g, red.b, 0.10), maxf(1.0 * sc, 1.0))

	## Write a line on the page in the pen's own hand: the nib travels along the
	## words while the ink appears behind it, the line sits and dries, then fades.
	## `visible_ratio` is what makes it read as WRITING rather than as a label
	## fading in — the letters arrive left to right at the speed of the nib.
	func _write_phrase(text: String, tint: Color, dwell: float) -> void:
		if _writing or not is_inside_tree():
			return
		_writing = true
		var lbl := Label.new()
		lbl.text = text
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.add_theme_color_override("font_color", tint)
		var fs := int(maxf(vp.x * 0.062, 20.0))
		lbl.add_theme_font_size_override("font_size", fs)
		# The UI face, not the display one: the display font is an all-caps
		# geometric that turns "Good luck" into a SIGN. Nunito's round lowercase
		# is the closest thing in the bundle to a hand.
		if ThemeManager.ui_font:
			lbl.add_theme_font_override("font", ThemeManager.ui_font)
		lbl.visible_ratio = 0.0
		# Sit the line ON a rule, indented past the red margin, and give the whole
		# line the slight rise a right-hander's writing has.
		var gap: float = maxf(vp.y * 0.052, 26.0 * sc)
		var rules := int((vp.y - gap * 1.8) / gap)
		var row := randi_range(2, maxi(rules - 3, 3))
		var base_y: float = gap * 1.4 + float(row) * gap
		lbl.position = Vector2(vp.x * 0.175, base_y - float(fs) * 0.92)
		lbl.rotation = randf_range(-0.035, -0.008)
		_ink_layer.add_child(lbl)
		_stains.append(lbl)
		_cap_stains()
		# The nib rides the line as it is written.
		var chars := maxi(text.length(), 1)
		var dur: float = clampf(float(chars) * 0.075, 0.7, 2.4)
		var x0: float = lbl.position.x
		var x1: float = x0 + float(chars) * float(fs) * 0.46
		if is_instance_valid(_nib):
			_nib.write_along(Vector2(x0, base_y), Vector2(x1, base_y), dur)
		var tw := lbl.create_tween()
		tw.tween_property(lbl, "visible_ratio", 1.0, dur).set_trans(Tween.TRANS_LINEAR)
		# The flourish: once the words are down, the pen sweeps back under them.
		tw.tween_callback(func() -> void:
			if is_inside_tree():
				_stroke(Vector2(x0 - fs * 0.1, base_y + fs * 0.20),
					Vector2(x1 * 0.96, base_y + fs * 0.26))
				if is_instance_valid(_nib):
					_nib.write_along(Vector2(x1, base_y), Vector2(x0, base_y + fs * 0.24), 0.32))
		tw.tween_interval(dwell)
		tw.tween_property(lbl, "modulate:a", 0.0, 2.2)
		tw.tween_callback(func() -> void:
			_writing = false
			_free_stain(lbl))
		# A little ink spatter where the pen first bit the page.
		_splashes(Vector2(x0 - fs * 0.15, base_y), 2)

	## The idle line: encouragement, in order, so it never repeats back to back.
	func _idle_phrase() -> void:
		if _writing:
			return
		var text := _PHRASES[_phrase_i % _PHRASES.size()]
		_phrase_i += 1
		_write_phrase(text, Color(pc("text"), 0.82), randf_range(2.2, 3.6))

	func _process(delta: float) -> void:
		var scoped: bool = Engine.has_meta("bench_scope")  # perf-bench scope, regression/perf/SPEC.md #4.2
		if scoped:
			Engine.get_meta("bench_scope").call(true, "RewardFx._process")
		_t += delta
		if scoped:
			Engine.get_meta("bench_scope").call(false, "RewardFx._process")

	# --- reactive contract -----------------------------------------------------
	func on_swipe(dir: Vector2i) -> void:
		var d := Vector2(dir).normalized()
		var mid := Vector2(vp.x * 0.5, vp.y * randf_range(0.34, 0.56))
		var half := vp.x * 0.17
		var a := mid - d * half
		var b := mid + d * half
		# the nib grazes across the page in the swipe direction
		if _t - _last_strike > 0.2:
			_nib.strike(b, 0.55)
		_last_strike = _t
		_stroke(a, b)

	func on_merge(pos: Vector2, value: int, _tint: Color) -> void:
		var grouped := _t - _last_strike < 0.2
		_last_strike = _t
		if grouped:
			# same move, another merge — a quick secondary blot near the writing.
			_bloom(to_visible(pos), value, 0.02)
			return
		# The pen RECORDS the merge: it writes the number where you can see it —
		# a visible margin over the merge's column — flicking ink as it writes.
		var wp := to_visible(pos)
		wp.x = clampf(wp.x, vp.x * 0.12, vp.x * 0.88)
		_write_number(wp, str(value))
		if randf() < 0.6:
			var tt := create_tween()
			tt.tween_interval(0.32)
			tt.tween_callback(_lift_thread.bind(wp))

	## The player's finger: the nib follows it and dabs a small blot where it
	## rests, so a touch always leaves ink. Throttled against the drag stream.
	func on_touch(pos: Vector2) -> void:
		if _t - _touch_t < 0.28:
			return
		# A jab that lands well after the last one starts the count over; jabs
		# that keep coming inside the window add up, and past the threshold the
		# pen says so. The window is what separates "the player is playing" from
		# "the player is poking the pen", which is the whole point of the gag.
		if _t - _poke_last > 2.4:
			_pokes = 0
		_poke_last = _t
		_pokes += 1
		_touch_t = _t
		var p := to_visible(pos)
		_nib.strike(p, 0.5)
		_bloom(p, 4, 0.08)
		if randf() < 0.5:
			_splashes(p, 1)
		if _pokes >= 5 and _t - _scold_t > 12.0:
			_pokes = 0
			_scold_t = _t
			# It recoils, flicks ink, and writes what it thinks of that.
			_nib.recoil()
			_splashes(p, 4)
			var red := Color(0.66, 0.16, 0.18)
			_write_phrase(_SCOLDS[randi() % _SCOLDS.size()], red, 2.6)

	func on_celebrate() -> void:
		# a flourish: the pen flicks and sprays ink across the page.
		_nib.strike(Vector2(vp.x * 0.5, vp.y * 0.34), 1.0)
		var origin := Vector2(vp.x * 0.5, vp.y * 0.30)
		burst(origin, {"tex": tex_dot(), "color": pc("text"), "alpha": 0.6, "amount": 26,
			"lifetime": 1.0, "vmin": 200.0, "vmax": 620.0, "spread": 60.0, "dir": Vector3(0, 1, 0),
			"gravity": 300.0, "smin": 0.2, "smax": 0.8})
		for i in 6:
			var p := origin + Vector2(randf_range(-0.4, 0.4) * vp.x, randf_range(0.05, 0.5) * vp.y)
			_bloom(p, 16, randf() * 0.25)

	# --- written numbers -------------------------------------------------------
	## The pen writes a number at `pos`: it strikes the paper there, the ink flows
	## on with a springy settle and a tilt (handwritten), sits wet, then dries to a
	## ghost and fades — plus a scatter of splashes as the nib bites the page.
	func _write_number(pos: Vector2, text: String) -> void:
		var ink := pc("text")
		_nib.strike(pos, 0.85)
		var fsize := int((78.0 + 6.0 * float(text.length())) * sc)
		var box := Vector2(fsize * 2.6, fsize * 1.5)
		var lbl := Label.new()
		lbl.text = text
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var font: Font = ThemeManager.display_font_heavy
		if font != null:
			lbl.add_theme_font_override("font", font)
		lbl.add_theme_font_size_override("font_size", fsize)
		lbl.add_theme_color_override("font_color", Color(ink.r, ink.g, ink.b, 1.0))
		lbl.size = box
		lbl.pivot_offset = box * 0.5
		lbl.position = pos - box * 0.5
		lbl.rotation = randf_range(-0.13, 0.13)     # a handwritten tilt
		lbl.scale = Vector2(0.82, 0.82)
		lbl.modulate = Color(1, 1, 1, 0.0)
		_ink_layer.add_child(lbl)
		var tw := lbl.create_tween()
		tw.tween_interval(0.1)                       # let the nib arrive
		tw.tween_property(lbl, "modulate:a", 0.94, 0.18)   # ink flows on
		tw.parallel().tween_property(lbl, "scale", Vector2.ONE, 0.28) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tw.tween_interval(2.6)                        # sits wet
		tw.tween_property(lbl, "modulate:a", 0.26, 2.4)    # dries to a ghost
		tw.tween_property(lbl, "modulate:a", 0.0, 2.4)     # and fades
		tw.tween_callback(_free_stain.bind(lbl))
		_stains.append(lbl)
		_cap_stains()
		_splashes(pos, 2 + randi() % 3)

	## Now and then the pen idly jots a stray power-of-two in the margins.
	func _idle_number() -> void:
		var powers := [2, 4, 8, 16, 32, 64, 128, 256, 512, 1024]
		_write_number(frame_point(), str(powers[randi() % powers.size()]))

	## Several ink splashes at once around `pos`: fine spatter bursts plus a couple
	## of tiny stray blots, as ink flicks off a dip pen.
	func _splashes(pos: Vector2, n: int) -> void:
		var ink := pc("text")
		for i in n:
			var off := Vector2(randf_range(-70, 70), randf_range(-60, 60)) * sc
			burst(pos + off, {"tex": tex_dot(), "color": ink, "alpha": randf_range(0.4, 0.7),
				"amount": 5 + randi() % 8, "lifetime": randf_range(0.5, 0.9),
				"vmin": 40.0, "vmax": 220.0, "gravity": randf_range(180.0, 320.0),
				"spread": 180.0, "smin": 0.15, "smax": randf_range(0.5, 0.9)})
		for i in maxi(n - 1, 1):
			_bloom(pos + Vector2(randf_range(-95, 95), randf_range(-75, 75)) * sc,
				2 + (randi() % 3) * 4, randf_range(0.0, 0.2))

	# --- ink marks -------------------------------------------------------------
	## A drop blooms out into a soft stain that spreads, glistens, then dries and
	## fades — `value` sets its size, `delay` syncs it to the descending nib.
	func _bloom(pos: Vector2, value: int, delay: float = 0.1) -> void:
		var ink := pc("text")
		var step := int(round(log(maxf(float(value), 2.0)) / log(2.0)))
		var d := minf((90.0 + 11.0 * float(step)) * sc, 260.0 * sc)
		var blot := TextureRect.new()
		blot.texture = _blot_tex(randi() % 3)
		blot.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		blot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		blot.size = Vector2(d, d)
		blot.pivot_offset = blot.size * 0.5
		blot.position = pos - blot.size * 0.5
		blot.rotation = randf() * TAU
		blot.scale = Vector2(0.18, 0.18)
		blot.modulate = Color(ink.r, ink.g, ink.b, 0.0)
		_ink_layer.add_child(blot)
		var tw := blot.create_tween()
		if delay > 0.0:
			tw.tween_interval(delay)
		# bloom: the ink spreads into the fibres and darkens (wet).
		tw.tween_property(blot, "scale", Vector2.ONE, 0.6).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.parallel().tween_property(blot, "modulate:a", 0.72, 0.22)
		# dwell wet, then dry to a faint ghost, then vanish — "fade after a while".
		tw.tween_interval(2.4)
		tw.tween_property(blot, "modulate:a", 0.24, 3.0).set_ease(Tween.EASE_IN)
		tw.tween_property(blot, "modulate:a", 0.0, 3.5)
		tw.tween_callback(_free_stain.bind(blot))
		_wet_sheen(blot, d)
		_stains.append(blot)
		_cap_stains()
		# a scatter of fine droplets, as a dip pen sheds.
		burst(pos, {"tex": tex_dot(), "color": ink, "alpha": 0.5, "amount": 6 + step,
			"lifetime": 0.7, "vmin": 50.0, "vmax": 190.0, "gravity": 240.0, "smin": 0.15, "smax": 0.55})

	## A glossy highlight that fades over the first second — the wet ink drying.
	func _wet_sheen(blot: TextureRect, d: float) -> void:
		var sheen := TextureRect.new()
		sheen.texture = tex_round()
		sheen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sheen.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var s := d * 0.4
		sheen.size = Vector2(s, s)
		sheen.position = blot.size * 0.5 - Vector2(s, s) * 0.5 - Vector2(d * 0.12, d * 0.14)
		sheen.modulate = Color(1, 1, 1, 0.0)
		blot.add_child(sheen)   # rides the blot as it spreads
		var tw := sheen.create_tween()
		tw.tween_property(sheen, "modulate:a", 0.3, 0.25)
		tw.tween_property(sheen, "modulate:a", 0.0, 0.9)
		tw.tween_callback(sheen.queue_free)

	## A quick wet drag of the nib in the swipe direction, drawn on from the start.
	func _stroke(a: Vector2, b: Vector2) -> void:
		var ink := pc("text")
		var stroke := TextureRect.new()
		stroke.texture = _stroke_tex()
		stroke.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		stroke.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var seg := (b - a).length()
		var h := 22.0 * sc
		stroke.size = Vector2(seg, h)
		stroke.pivot_offset = Vector2(0.0, h * 0.5)   # pivot at the start, centred
		stroke.position = a - Vector2(0.0, h * 0.5)
		stroke.rotation = (b - a).angle()
		stroke.scale = Vector2(0.0, 1.0)              # grows from the start point
		stroke.modulate = Color(ink.r, ink.g, ink.b, 0.0)
		_ink_layer.add_child(stroke)
		var tw := stroke.create_tween()
		tw.tween_property(stroke, "scale", Vector2.ONE, 0.22).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(stroke, "modulate:a", 0.17, 0.12)
		tw.tween_interval(1.4)
		tw.tween_property(stroke, "modulate:a", 0.0, 2.2)
		tw.tween_callback(_free_stain.bind(stroke))
		_stains.append(stroke)
		_cap_stains()

	## The classic ink "string" that stretches and snaps as the pen lifts, and a
	## tiny satellite droplet that flicks off it.
	func _lift_thread(pos: Vector2) -> void:
		var ink := pc("text")
		var thread := TextureRect.new()
		thread.texture = tex_streak()
		thread.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		thread.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var h := 46.0 * sc
		thread.size = Vector2(3.0 * sc, h)
		thread.pivot_offset = Vector2(1.5 * sc, h)    # pinned to the paper end
		thread.position = pos - Vector2(1.5 * sc, h)
		thread.modulate = Color(ink.r, ink.g, ink.b, 0.5)
		_ink_layer.add_child(thread)
		var tw := thread.create_tween()
		tw.tween_property(thread, "scale", Vector2(0.4, 1.7), 0.16).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(thread, "modulate:a", 0.0, 0.16)
		tw.tween_callback(thread.queue_free)
		if randf() < 0.7:
			_bloom(pos + Vector2(randf_range(-30, 30), -randf_range(20, 50)) * sc, 4, 0.16)

	## A heavy drop falls from the pen's tip and blooms where it lands.
	func _spontaneous_drip() -> void:
		if _nib == null or not is_instance_valid(_nib):
			return
		var from: Vector2 = _nib.tip
		var ink := pc("text")
		var drop := TextureRect.new()
		drop.texture = tex_round()
		drop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		drop.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var s := 12.0 * sc
		drop.size = Vector2(s, s)
		drop.position = from - drop.size * 0.5
		drop.modulate = Color(ink.r, ink.g, ink.b, 0.9)
		_ink_layer.add_child(drop)
		var land := from + Vector2(randf_range(-14, 14) * sc, randf_range(60, 120) * sc)
		var tw := drop.create_tween()
		tw.tween_property(drop, "position", land - drop.size * 0.5, 0.4).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tw.parallel().tween_property(drop, "scale", Vector2(0.7, 1.4), 0.4)   # stretches as it falls
		tw.tween_callback(_drip_land.bind(drop, land))

	func _drip_land(drop: TextureRect, land: Vector2) -> void:
		if is_instance_valid(drop):
			drop.queue_free()
		_bloom(land, 8, 0.0)

	# --- housekeeping ----------------------------------------------------------
	func _free_stain(node: Node) -> void:
		_stains.erase(node)
		if is_instance_valid(node):
			node.queue_free()

	func _cap_stains() -> void:
		while _stains.size() > 22:
			var old_v = _stains.pop_front()
			var node := old_v as CanvasItem
			if node != null and is_instance_valid(node):
				var fade := node.create_tween()
				fade.tween_property(node, "modulate:a", 0.0, 0.6)
				fade.tween_callback(node.queue_free)

	# --- baked textures --------------------------------------------------------
	## An irregular ink blot: a wet plateau, a feathered rim, capillary tendrils
	## reaching into the paper, and a faintly darker dried edge. Three phase
	## variants (+ random rotation per instance) keep them from repeating.
	func _blot_tex(v: int) -> Texture2D:
		var ph := float(v) * 2.7
		return bake("ink_blot_%d" % v, 128, 128, func(uv: Vector2) -> Color:
			var r := uv.length()
			var ang := atan2(uv.y, uv.x)
			# a gently irregular blob — LOW-frequency lobes only, so it reads as a
			# pool of ink and not a star.
			var edge := 0.64 + 0.06 * sin(ang * 3.0 + ph) + 0.04 * sin(ang * 5.0 - ph * 1.3) \
				+ 0.03 * sin(ang * 7.0 + ph)
			var body := smoothstep(edge, edge - 0.3, r)                  # solid core, soft rim
			var pool := smoothstep(0.34, 0.0, r) * 0.22                  # denser, wetter centre
			# a few short, faint capillary threads wicking into the fibres
			var thread := pow(maxf(sin(ang * 6.0 + ph), 0.0), 10.0) * 0.07 \
				* smoothstep(edge + 0.08, edge - 0.06, r)
			var mott := 0.92 + 0.08 * sin(uv.x * 14.0 + ph) * sin(uv.y * 12.0 - ph)
			var a := clampf(body * mott + pool + thread, 0.0, 1.0)
			return Color(1, 1, 1, a))

	## A wavy tapered wet stroke — darker down the core, ragged at the edges.
	func _stroke_tex() -> Texture2D:
		return bake("ink_stroke", 256, 48, func(uv: Vector2) -> Color:
			var x := uv.x
			var y := uv.y
			var th := 0.72 + 0.14 * sin(x * 9.0) + 0.08 * sin(x * 21.0 + 1.0)
			var body := smoothstep(th, th - 0.5, absf(y))
			var taper := smoothstep(1.0, 0.72, absf(x))
			var a := body * taper * (0.7 + 0.3 * smoothstep(0.9, 0.0, absf(y)))
			return Color(1, 1, 1, clampf(a, 0.0, 1.0)))


# =============================================================================
# NibPen — the writing instrument for Ink Wash: a feather quill tipped with a
# procedurally-baked GOLD nib (rounded shoulders, breather hole, a slit between
# the tines, side vents, a specular spine and an ink-stained point), a golden
# plume rising above it. Held at a writer's lean, it springs to each touch
# point, dips on a strike, bobs gently at rest, casts a soft contact shadow,
# and carries a trembling wet ink bead at its point.
# =============================================================================
class NibPen extends Base:
	var tip: Vector2               # current point position (public: the ink hooks read it)
	var _ink: Color
	var _rest: Vector2
	var _target: Vector2
	var _vel := Vector2.ZERO
	var _t: float = 0.0
	var _dip: float = 0.0          # 0..1 press, decays after each strike
	var _bead: float = 0.7         # wet ink load at the tip
	var _last: float = -10.0
	var _tex: Texture2D            # the gold nib
	var _feather: Texture2D        # the plume above it
	var _len: float                # nib length on screen
	var _flen: float               # feather length on screen
	const _LEAN := 0.42            # body leans up-right from vertical (right-hand pose)

	func setup(ink: Color, _scl: float, _vp: Vector2, rest: Vector2) -> void:
		_ink = ink
		_rest = rest

	func _build() -> void:
		_tex = _bake_nib()
		_feather = _bake_feather()
		_len = 224.0 * sc
		_flen = 2.05 * _len
		tip = _rest
		_target = _rest
		set_process(true)

	## Bring the point to `p` and press (0..1); tops up the ink bead.
	func strike(p: Vector2, press: float) -> void:
		_target = p
		_dip = maxf(_dip, press)
		_bead = minf(1.0, _bead + 0.12)
		_last = _t

	## Ride the point from `a` to `b` over `dur`, so the pen travels the line it
	## is writing. The spring chase in `_process` still does the moving — this
	## only walks the TARGET along, which keeps the hand-held wobble intact
	## instead of sliding the nib on a rail.
	func write_along(a: Vector2, b: Vector2, dur: float) -> void:
		strike(a, 0.55)
		var tw := create_tween()
		tw.tween_method(func(f: float) -> void:
			_target = a.lerp(b, f)
			_last = _t
			# The point rises and falls a little between letters.
			_dip = maxf(_dip, 0.30 + 0.20 * absf(sin(f * 22.0))), 0.0, 1.0, dur)
		tw.tween_callback(func() -> void: _last = _t)

	## Jerk back from the page, as if the hand holding it had been jogged.
	func recoil() -> void:
		_vel += Vector2(randf_range(-1.0, 1.0), -1.0).normalized() * 900.0 * sc
		_dip = 0.0
		_bead = minf(1.0, _bead + 0.25)
		_last = _t

	func _process(delta: float) -> void:
		var scoped: bool = Engine.has_meta("bench_scope")  # perf-bench scope, regression/perf/SPEC.md #4.2
		if scoped:
			Engine.get_meta("bench_scope").call(true, "RewardFx._process")
		_t += delta
		if _t - _last > 1.4:
			_target = _rest                       # drift home once the move is over
		# a springy, slightly damped chase so the nib glides between touches.
		var k := 30.0
		var damp := 2.0 * sqrt(k)
		_vel += ((_target - tip) * k - _vel * damp) * delta
		tip += _vel * delta
		_dip = maxf(_dip - delta * 2.4, 0.0)
		queue_redraw()
		if scoped:
			Engine.get_meta("bench_scope").call(false, "RewardFx._process")

	func _draw() -> void:
		var scoped: bool = Engine.has_meta("bench_scope")  # perf-bench scope, regression/perf/SPEC.md #4.2
		if scoped:
			Engine.get_meta("bench_scope").call(true, "RewardFx._draw")
		# B2 — grid-clip cull: every command (shadow, feather, nib, bead) lies
		# within 2.95·_len of the point (feather top = 0.9·_len + 2.05·_len up
		# the shaft), and the bob/dip offsets stay under 14·sc; 3.2·_len covers
		# it all with slack. The spring chase in `_process` keeps running, so
		# the pen re-enters the window exactly where an unculled one would.
		if not win_has_point(clip_window(), tip, _len * 3.2):
			if scoped:
				Engine.get_meta("bench_scope").call(false, "RewardFx._draw")
			return
		# idle life: a slow bob + sway so the pen reads as hand-held, plus the
		# extra drop from a fresh press.
		var bob := sin(_t * 1.7) * 3.0 * sc
		var sway := sin(_t * 0.8) * 0.03
		var t := tip + Vector2(sin(_t * 0.8) * 2.0 * sc, bob + _dip * 10.0 * sc)
		var w := _len * (float(_tex.get_width()) / float(_tex.get_height()))
		var fw := _flen * (float(_feather.get_width()) / float(_feather.get_height()))
		# soft contact shadow on the paper, just past the point.
		draw_texture_rect(tex_round(),
			Rect2(t + Vector2(6.0 * sc, 10.0 * sc) - Vector2(w * 0.6, w * 0.35),
				Vector2(w * 1.2, w * 0.7)), false, Color(0.12, 0.12, 0.16, 0.12))
		# origin at the point, canonical tip at each texture's bottom edge; the pen
		# leans up-right. Feather first, then the nib overlaps its quill base.
		draw_set_transform(t, _LEAN + sway, Vector2.ONE)
		var fbot := -_len * 0.9        # the quill base tucks into the nib shoulders
		draw_texture_rect(_feather, Rect2(Vector2(-fw * 0.5, fbot - _flen), Vector2(fw, _flen)),
			false, Color(1, 1, 1, 0.98))
		draw_texture_rect(_tex, Rect2(Vector2(-w * 0.5, -_len), Vector2(w, _len)), false, Color(1, 1, 1, 0.98))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# the wet bead clinging to the point (shrinks as a press deposits ink).
		var bd := (7.0 + 6.0 * _bead) * sc * (1.0 - 0.3 * _dip)
		draw_texture_rect(tex_round(), Rect2(t - Vector2(bd, bd), Vector2(bd, bd) * 2.0), false,
			Color(_ink.r, _ink.g, _ink.b, 0.9))
		var gl := bd * 0.5
		draw_texture_rect(tex_dot(),
			Rect2(t + Vector2(-bd * 0.35, -bd * 0.5) - Vector2(gl, gl) * 0.5, Vector2(gl, gl)),
			false, Color(1, 1, 1, 0.6))
		if scoped:
			Engine.get_meta("bench_scope").call(false, "RewardFx._draw")

	## A gold nib baked once (session cache): rounded shoulders waisting to a
	## sharp point, a breather hole, the tine slit, decorative side vents, a lit
	## spine and an ink-stained writing tip. Canonical: tip at bottom-centre.
	func _bake_nib() -> Texture2D:
		return bake("nib_gold", 160, 300, func(uv: Vector2) -> Color:
			var x := uv.x
			var y := uv.y
			# --- silhouette: rounded top, waisted body, tapering to the point ---
			var max_hw := 0.66
			var shoulder := -0.32
			var hw: float
			if y < shoulder:
				var ty := (y + 1.0) / (shoulder + 1.0)         # 0 top .. 1 shoulder
				hw = max_hw * sqrt(clampf(ty * (2.0 - ty), 0.0, 1.0))
			else:
				var tb := (y - shoulder) / (1.0 - shoulder)    # 0 shoulder .. 1 tip
				hw = max_hw * (1.0 - tb) * (1.0 + 0.14 * sin(tb * PI))
			var edge := hw - absf(x)
			var alpha := smoothstep(-0.02, 0.02, edge)
			if alpha <= 0.003:
				return Color(0, 0, 0, 0)
			# --- polished-gold shading: bright spine, darker toward the edges ---
			var gold_hi := Color(1.0, 0.94, 0.68)
			var gold := Color(0.86, 0.67, 0.27)
			var gold_lo := Color(0.4, 0.28, 0.08)
			var curv := 1.0 - pow(clampf(absf(x) / maxf(hw, 0.001), 0.0, 1.0), 1.6)
			var b := (0.36 + 0.64 * curv) * (0.82 - 0.2 * y)   # cross-curve * length light
			var spec := exp(-pow((absf(x) - 0.16) * 7.0, 2.0)) * (0.55 - 0.4 * y)
			var col := gold_lo.lerp(gold, clampf(b, 0.0, 1.0)).lerp(gold_hi, clampf(spec, 0.0, 1.0))
			col = col.darkened(0.05 * (0.5 + 0.5 * sin(x * 46.0)) * (1.0 - curv))   # brushing
			col = col.darkened((1.0 - smoothstep(0.0, 0.06, edge)) * 0.4)           # rim
			# --- the breather hole (vent) near the shoulder ---
			var hd := Vector2(x, y - 0.02).length()
			if hd < 0.11:
				col = col.darkened(0.72).lerp(gold_hi, clampf((hd - 0.06) / 0.05, 0.0, 1.0) * 0.5)
			# --- the slit between the tines, hole -> point ---
			if y > 0.02 and absf(x) < 0.012 + 0.02 * clampf((y - 0.02) / 0.98, 0.0, 1.0):
				col = col.darkened(0.82)
			# --- two decorative side vents (the nib's "wings") ---
			if y > -0.3 and y < -0.02 and absf(absf(x) - (0.3 + 0.12 * y)) < 0.016:
				col = col.darkened(0.3)
			# --- the writing tip is stained with ink ---
			if y > 0.42:
				col = col.lerp(Color(0.1, 0.11, 0.16), clampf((y - 0.42) / 0.58, 0.0, 1.0) * 0.9)
			return Color(col.r, col.g, col.b, alpha))

	## A golden feather quill baked once (session cache): a curved rachis with
	## barbs fanning up-and-out into two vanes, a bare calamus at the base, and a
	## couple of splits. Canonical: the plume tip at top, the quill base at bottom.
	func _bake_feather() -> Texture2D:
		return bake("quill_feather", 220, 620, func(uv: Vector2) -> Color:
			var x := uv.x
			var y := uv.y
			var tnorm := (y + 1.0) * 0.5                       # 0 tip .. 1 base
			var cx := 0.12 * sin(y * 1.4 + 0.4)                # the shaft's gentle S-curve
			var dxs := absf(x - cx)
			# vane envelope: narrow at the tip, full through the middle, bare at base
			var vane := 0.62 * pow(smoothstep(0.0, 0.26, tnorm), 0.8) * (1.0 - smoothstep(0.8, 1.0, tnorm))
			var ragged := vane + 0.02 * sin(y * 85.0) + 0.014 * sin(y * 43.0 + 1.0)   # barb-tip edge
			var edge := ragged - dxs
			var alpha := smoothstep(-0.015, 0.015, edge)
			# the bare shaft (calamus) runs the whole length down to the nib
			var shaft_w := 0.045 - 0.02 * tnorm
			alpha = maxf(alpha, smoothstep(shaft_w + 0.012, shaft_w - 0.006, dxs))
			if alpha <= 0.004:
				return Color(0, 0, 0, 0)
			# --- golden-feather shading ---
			var vane_hi := Color(0.95, 0.85, 0.58)
			var vane_mid := Color(0.78, 0.62, 0.34)
			var vane_lo := Color(0.44, 0.33, 0.15)
			var shaft_col := Color(0.98, 0.86, 0.5)
			var side := signf(x - cx)
			var barb := 0.5 + 0.5 * sin((y * 34.0 + dxs * 15.0) * PI)   # diagonal barbs
			var shade := 1.0 - 0.24 * (1.0 - barb) - 0.14 * clampf(side, 0.0, 1.0) \
				- (1.0 - smoothstep(0.0, 0.05, edge)) * 0.28
			var col := vane_lo.lerp(vane_hi, clampf(shade, 0.0, 1.0)).lerp(vane_mid, 0.25)
			# the bright, harder shaft down the middle
			if dxs < shaft_w + 0.02:
				col = col.lerp(shaft_col, smoothstep(shaft_w + 0.02, 0.0, dxs) * 0.9)
			# a couple of splits (missing barbs) for character
			if absf(y + 0.12) < 0.02 or absf(y - 0.34) < 0.015:
				alpha *= 0.28
			return Color(col.r, col.g, col.b, alpha))


# =============================================================================
# Ember Serpent — a dragon of embers patrols the board's edges as a flowing
# particle trail. Swipes send it dashing in the swipe direction; merges pull it
# to the merge point where it flares fire.
# =============================================================================
class Serpent extends Base:
	## A BROOD, not a snake. Each serpent keeps its own spine, its own errand and
	## its own heat, so they read as several creatures sharing the cave rather
	## than one snake drawn three times — and the body of each is built out of
	## flying SPARKS rather than a smooth tube, which is what makes it read as a
	## firework rather than a lava lamp.
	var _snakes: Array = []        # {pos, vel, target, dash, trail, embers, len, thick, heat, ph}
	var _t: float = 0.0
	const SEG := 10.0              # min px between body points, so it never bunches
	const CRUISE := 240.0

	func _build() -> void:
		edge_glow(pc("accent").lerp(pc("gold"), 0.3), 0.06, 0.16, false)
		field({"tex": tex_dot(), "color": pc("accent").lerp(pc("gold"), 0.4), "alpha": 0.75,
			"amount": 40, "lifetime": 6.0, "dir": Vector3(0, -1, 0), "spread": 24.0,
			"from": "bottom", "vmin": 30.0, "vmax": 85.0, "smin": 0.35, "smax": 1.1,
			"turb": 0.7, "twinkle": true})
		# One big one and two lesser ones — a size ladder reads as a brood, three
		# equals read as a bug. The third is dropped on weaker hardware, where the
		# per-point spark passes are the cost.
		var brood := [[36, 1.0, 1.0], [26, 0.70, 0.72], [22, 0.55, 0.45]]
		if pscale() < 0.8:
			brood.resize(2)
		for b_v in brood:
			var b: Array = b_v
			_add_snake(int(b[0]), float(b[1]), float(b[2]))
		set_process(true)

	func _add_snake(length: int, thick: float, heat: float) -> void:
		var em := CPUParticles2D.new()
		em.amount = maxi(int(22.0 * pscale() * thick), 6)
		em.lifetime = 0.9
		em.local_coords = false
		em.texture = tex_dot()
		em.direction = Vector2(0, -1)
		em.spread = 180.0
		em.initial_velocity_min = 10.0
		em.initial_velocity_max = 60.0
		em.scale_amount_min = 0.25 * thick
		em.scale_amount_max = 0.85 * thick
		em.color_initial_ramp = grad([Color(1.0, 0.94, 0.5), Color(1.0, 0.52, 0.14),
			Color(0.6, 0.1, 0.02)])
		em.color_ramp = alpha_ramp(Color(1, 1, 1), 0.9, true)
		em.emitting = true
		add_child(em)
		_snakes.append({
			"pos": frame_point(), "vel": Vector2.ZERO, "target": frame_point(),
			"dash": 0.0, "trail": [], "embers": em, "len": length,
			"thick": thick, "heat": heat, "ph": randf() * TAU,
			"speed": randf_range(0.85, 1.2)})

	## A cheap sinless hash — the spark scatter is re-rolled several times a
	## second for every body point, so this runs in the hot path and must not be
	## a trig call. (See the hashing note on the gameplay perf work.)
	func _h(n: float) -> float:
		var x: float = fposmod(n * 0.1031, 1.0)
		x *= x + 33.33
		x *= x + x
		return fposmod(x, 1.0)

	func on_swipe(dir: Vector2i) -> void:
		var d := Vector2(dir)
		for s_v in _snakes:
			var s: Dictionary = s_v
			var p: Vector2 = s["pos"]
			s["target"] = to_visible(Vector2(
				clampf(p.x + d.x * vp.x * randf_range(0.5, 0.9), vp.x * 0.06, vp.x * 0.94),
				clampf(p.y + d.y * vp.y * randf_range(0.35, 0.6), vp.y * 0.05, vp.y * 0.95)))
			s["dash"] = 900.0 * float(s["speed"])

	## The brood chases the finger — the nearest one commits, the rest drift in.
	func on_touch(pos: Vector2) -> void:
		var vt := to_visible(pos)
		var best := -1
		var bd := INF
		for i in _snakes.size():
			var d: float = (vt - ((_snakes[i] as Dictionary)["pos"] as Vector2)).length_squared()
			if d < bd:
				bd = d
				best = i
		for i in _snakes.size():
			var s: Dictionary = _snakes[i]
			if i == best:
				s["target"] = vt
				s["dash"] = maxf(float(s["dash"]), 520.0)
			elif randf() < 0.4:
				s["target"] = vt + Vector2(randf_range(-1.0, 1.0),
					randf_range(-1.0, 1.0)) * vp.x * 0.2

	func on_merge(pos: Vector2, value: int, _tint: Color) -> void:
		var vt := to_visible(pos)
		var boost := 1.0 + minf(float(value) / 1024.0, 1.5)
		for s_v in _snakes:
			var s: Dictionary = s_v
			s["target"] = vt + Vector2(randf_range(-1.0, 1.0),
				randf_range(-1.0, 1.0)) * vp.x * 0.12
			s["dash"] = maxf(float(s["dash"]), 700.0)
		burst(vt, {"tex": tex_dot(),
			"iramp": grad([Color(1, 0.45, 0.12), Color(1, 0.72, 0.2), Color(1, 0.9, 0.45)]),
			"amount": int(22.0 * boost), "lifetime": 0.8, "vmin": 120.0, "vmax": 360.0,
			"gravity": -140.0, "smin": 0.3, "smax": 1.1})

	func on_celebrate() -> void:
		for s_v in _snakes:
			var s: Dictionary = s_v
			s["dash"] = 1100.0
			burst(s["pos"], {"tex": tex_dot(),
				"iramp": grad([Color(1, 0.95, 0.6), Color(1, 0.55, 0.15), Color(1, 0.3, 0.05)]),
				"amount": 26, "lifetime": 0.9, "vmin": 140.0, "vmax": 420.0,
				"gravity": -120.0, "smin": 0.3, "smax": 1.2})

	func _process(delta: float) -> void:
		var scoped: bool = Engine.has_meta("bench_scope")  # perf-bench scope, regression/perf/SPEC.md #4.2
		if scoped:
			Engine.get_meta("bench_scope").call(true, "RewardFx._process")
		_t += delta
		for s_v in _snakes:
			var s: Dictionary = s_v
			s["dash"] = maxf(float(s["dash"]) - 1400.0 * delta, 0.0)
			var pos: Vector2 = s["pos"]
			var target: Vector2 = s["target"]
			# a playful, breathing cruise speed on top of the swipe/merge dash
			var speed: float = (CRUISE * float(s["speed"])
				* (0.82 + 0.30 * sin(_t * 1.3 + float(s["ph"]))) + float(s["dash"])) * sc
			if (target - pos).length() < 90.0 * sc:
				target = frame_point()
				s["target"] = target
			var desired := (target - pos).normalized() * speed
			var vel: Vector2 = (s["vel"] as Vector2).lerp(desired, clampf(2.4 * delta, 0.0, 1.0))
			pos += vel * delta
			s["vel"] = vel
			s["pos"] = pos
			# Lay body points at a fixed spacing (not per-frame), so each snake
			# keeps a constant length even when its head slows or stops.
			var trail: Array = s["trail"]
			if trail.is_empty() or (pos - Vector2(trail[0])).length() >= SEG * sc:
				trail.push_front(pos)
				if trail.size() > int(s["len"]):
					trail.resize(int(s["len"]))
			(s["embers"] as CPUParticles2D).position = pos
		queue_redraw()
		if scoped:
			Engine.get_meta("bench_scope").call(false, "RewardFx._process")

	func _draw() -> void:
		var scoped: bool = Engine.has_meta("bench_scope")  # perf-bench scope, regression/perf/SPEC.md #4.2
		if scoped:
			Engine.get_meta("bench_scope").call(true, "RewardFx._draw")
		for s_v in _snakes:
			_draw_snake(s_v as Dictionary)
		if scoped:
			Engine.get_meta("bench_scope").call(false, "RewardFx._draw")

	func _draw_snake(s: Dictionary) -> void:
		var trail: Array = s["trail"]
		var n := trail.size()
		if n < 2:
			return
		var dot := tex_dot()
		var thick: float = s["thick"]
		var heat: float = s["heat"]
		var ph: float = s["ph"]
		# B2 — grid-clip cull: one visibility bit per spine point, tested on the
		# raw trail point with a pad covering the undulation, the widest body
		# halo, the spark scatter and the head cluster with its tongue.
		var cw := clip_window()
		var clipped := cw.size.x > 0.0
		var vis := PackedByteArray()
		if clipped:
			vis.resize(n)
		# Undulate the spine: a travelling sine pushes each point sideways, so the
		# body SLITHERS like a snake instead of merely trailing the head.
		var pts: Array = []
		for i in n:
			var here: Vector2 = trail[i]
			if clipped:
				var on := cw.grow(128.0 * sc).has_point(here)
				vis[i] = 1 if on else 0
				if not on:
					pts.append(here)
					continue
			var f := float(i) / float(n - 1)
			var ahead: Vector2 = trail[maxi(i - 1, 0)]
			var back: Vector2 = trail[mini(i + 1, n - 1)]
			var dir := ahead - back
			dir = dir.normalized() if dir.length() > 0.001 else Vector2(0, -1)
			var perp := Vector2(-dir.y, dir.x)
			var amp := smoothstep(0.0, 0.16, f) * 26.0 * sc * thick
			pts.append(here + perp * sin(_t * 8.0 + ph - float(i) * 0.5) * amp)
		# Fire gradient, white-hot head -> smoky tail. `heat` shifts the whole
		# brood apart: the alpha burns white, the lesser ones burn deep orange.
		var white_hot := Color(1.0, 0.97, 0.82).lerp(Color(1.0, 0.72, 0.30), 1.0 - heat)
		var yellow := Color(1.0, 0.82, 0.28).lerp(Color(1.0, 0.55, 0.16), 1.0 - heat)
		var orange := Color(1.0, 0.46, 0.1)
		var deep := Color(0.78, 0.14, 0.03)
		# The spark clock: the scatter is re-rolled ~14 times a second, which is
		# what makes the body crackle instead of shimmer smoothly.
		var tick := floorf(_t * 14.0)
		# Pass 1: tail -> head so the hot head layers on top.
		for i in range(n - 1, -1, -1):
			if clipped and vis[i] == 0:
				continue
			var f := float(i) / float(n - 1)
			var p: Vector2 = pts[i]
			var flick := 0.85 + 0.15 * sin(_t * 20.0 + float(i) * 1.3)
			var r := lerpf(19.0, 5.0, f) * sc * flick * thick
			var body_col := yellow.lerp(orange, clampf(f * 1.6, 0.0, 1.0)) \
				.lerp(deep, clampf((f - 0.5) * 2.0, 0.0, 1.0))
			var halo := r * 2.8
			draw_texture_rect(dot, Rect2(p - Vector2(halo, halo), Vector2(halo, halo) * 2.0),
				false, Color(deep.r, deep.g, deep.b, (1.0 - f) * 0.16 + 0.04))
			draw_texture_rect(dot, Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0),
				false, Color(body_col.r, body_col.g, body_col.b, (1.0 - f * 0.5) * 0.88))
			var cr := r * 0.55
			var core := white_hot.lerp(yellow, f)
			draw_texture_rect(dot, Rect2(p - Vector2(cr, cr), Vector2(cr, cr) * 2.0),
				false, Color(core.r, core.g, core.b, clampf((1.0 - f) * 1.2, 0.0, 1.0) * 0.9))
			# The sparks: two per body point, thrown clear of the spine on a
			# scatter re-rolled on the spark clock. This is the whole firework
			# read — a body made of loose burning grains.
			if i % 2 == 0:
				for k in 2:
					var seed_v := float(i) * 7.13 + float(k) * 31.7 + tick * 3.77
					var ang: float = _h(seed_v) * TAU
					var rad: float = (0.7 + _h(seed_v + 5.1) * 2.6) * r
					var sp := p + Vector2(cos(ang), sin(ang)) * rad
					var sr: float = (1.1 + _h(seed_v + 11.3) * 2.4) * sc * thick
					var sa: float = (1.0 - f) * (0.60 + _h(seed_v + 2.7) * 0.40)
					draw_texture_rect(dot,
						Rect2(sp - Vector2(sr, sr) * 2.6, Vector2(sr, sr) * 5.2),
						false, Color(orange.r, orange.g, orange.b, sa * 0.22))
					draw_texture_rect(dot, Rect2(sp - Vector2(sr, sr), Vector2(sr, sr) * 2.0),
						false, Color(white_hot.r, white_hot.g, white_hot.b, sa))
		# Pass 2: flame licks flickering up off the hotter half of the body.
		for i in range(0, n, 3):
			if clipped and vis[i] == 0:
				continue
			var f := float(i) / float(n - 1)
			if f > 0.62:
				continue
			var p: Vector2 = pts[i]
			var fh := (26.0 + 14.0 * sin(_t * 14.0 + ph + float(i) * 2.1)) * sc * (1.0 - f) * thick
			var fw := 9.0 * sc * (1.0 - f * 0.5) * thick
			var sway := sin(_t * 8.0 + ph + float(i)) * 6.0 * sc
			var lc := yellow.lerp(orange, f + 0.2)
			draw_texture_rect(dot, Rect2(p + Vector2(sway - fw, -fh * 1.6),
				Vector2(fw * 2.0, fh * 1.8)), false, Color(lc.r, lc.g, lc.b, 0.5 * (1.0 - f)))
		# The head: a hot skull with two glowing eyes, facing the way it travels;
		# a forked tongue flicks out when it dashes.
		if clipped and vis[0] == 0:
			return
		var head: Vector2 = pts[0]
		var hd: Vector2 = trail[0] - trail[mini(3, n - 1)]
		var hdir: Vector2 = hd.normalized() if hd.length() > 0.001 else Vector2(0, -1)
		var hperp := Vector2(-hdir.y, hdir.x)
		var hr := 22.0 * sc * thick
		draw_texture_rect(dot, Rect2(head - Vector2(hr, hr), Vector2(hr, hr) * 2.0),
			false, Color(white_hot.r, white_hot.g, white_hot.b, 0.95))
		var eye_r := 4.5 * sc * thick
		for s_i in [-1.0, 1.0]:
			var ep := head + hdir * 6.0 * sc * thick + hperp * float(s_i) * 8.0 * sc * thick
			draw_texture_rect(dot, Rect2(ep - Vector2(eye_r, eye_r) * 2.2,
				Vector2(eye_r, eye_r) * 4.4), false, Color(1.0, 0.9, 0.5, 0.85))
			draw_texture_rect(dot, Rect2(ep - Vector2(eye_r, eye_r), Vector2(eye_r, eye_r) * 2.0),
				false, Color(0.2, 0.02, 0.0, 0.9))
		if float(s["dash"]) > 150.0:
			var tl := 24.0 * sc * thick
			var base := head + hdir * hr * 0.7
			var fork := base + hdir * tl * 0.6
			var tongue := Color(0.95, 0.1, 0.05, 0.9)
			draw_line(base, fork, tongue, 3.0 * sc * thick)
			for s_i in [-1.0, 1.0]:
				draw_line(fork, fork + hdir * tl * 0.4 + hperp * float(s_i) * 7.0 * sc * thick,
					tongue, 3.0 * sc * thick)


# =============================================================================
# Koi Garden — playing on frosted glass over a pond. Koi wander beneath, dart
# away from swipes; merges drop a pebble: staggered ripple rings + a splash and
# any nearby fish flee. Rain-free rings keep the pond alive between moves.
# =============================================================================
class Koi extends Base:
	var _fish: Array = []          # {node, vel: Vector2, target: Vector2, phase: float, speed: float}
	var _t: float = 0.0
	var _touch_t: float = -10.0    # throttles the follow-the-finger reaction

	func _build() -> void:
		# The pond: deep-water washes + drifting plankton motes + lily pads.
		for i in 2:
			var blob := TextureRect.new()
			blob.texture = tex_round()
			blob.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			blob.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var d: float = vp.x * 1.25
			blob.size = Vector2(d, d)
			blob.position = Vector2(vp.x * float(i) - d * 0.5, vp.y * (0.1 + 0.4 * float(i)))
			var col: Color = pc("accent2")
			blob.modulate = Color(col.r, col.g, col.b, 0.10)
			add_child(blob)
			var tw := blob.create_tween().set_loops()
			tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
			tw.tween_property(blob, "position:y", blob.position.y + vp.y * 0.06, 11.0)
			tw.tween_property(blob, "position:y", blob.position.y, 12.0)
		field({"tex": tex_dot(), "color": pc("accent2").lerp(white(1.0), 0.3), "alpha": 0.30,
			"amount": 30, "lifetime": 11.0, "dir": Vector3(0, -1, 0), "spread": 180.0,
			"vmin": 3.0, "vmax": 10.0, "smin": 0.2, "smax": 0.55, "turb": 0.5, "twinkle": true})
		_lily_pads()
		_pond_lights()
		for i in 15:
			_spawn_fish(i)
		# The pond breathes: a soft ring blooms somewhere every few seconds.
		every(2.2, 4.5, func():
			ripple(Vector2(randf_range(0.1, 0.9) * vp.x, randf_range(0.1, 0.9) * vp.y),
				pc("accent2"), randf_range(90.0, 170.0) * sc, 1.4))
		set_process(true)

	## The light on the water. A pond at night is only majestic if something is
	## LIT: floating paper lanterns drifting on the surface with their reflections
	## smeared under them, lotus blossoms open on the pads, fireflies over the
	## water, and a shaft of moonlight lying across it all.
	func _pond_lights() -> void:
		var warm := Color(1.0, 0.72, 0.34)
		# The moon's light lying on the water, breathing.
		var shaft := TextureRect.new()
		shaft.texture = tex_round()
		shaft.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		shaft.stretch_mode = TextureRect.STRETCH_SCALE
		shaft.mouse_filter = Control.MOUSE_FILTER_IGNORE
		shaft.size = Vector2(vp.x * 0.55, vp.y * 1.25)
		shaft.pivot_offset = shaft.size * 0.5
		shaft.rotation = deg_to_rad(12.0)
		shaft.position = Vector2(vp.x * 0.62 - shaft.size.x * 0.5, -vp.y * 0.12)
		shaft.modulate = Color(0.86, 0.94, 1.0, 0.05)
		add_child(shaft)
		var mt := shaft.create_tween().set_loops()
		mt.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		mt.tween_property(shaft, "modulate:a", 0.11, 5.0)
		mt.tween_property(shaft, "modulate:a", 0.04, 5.5)
		# Floating paper lanterns, each with a reflection under it.
		var lantern := bake("pond_lantern", 56, 72, func(uv: Vector2) -> Color:
			var a := 0.0
			var b := 0.6
			# The paper body: a barrel with ribs.
			if uv.y > -0.62 and uv.y < 0.56:
				var t := (uv.y + 0.62) / 1.18
				var hw: float = 0.42 + 0.40 * sin(t * PI)
				if absf(uv.x) < hw:
					a = 1.0
					b = 0.55 + 0.45 * (1.0 - absf(uv.x) / maxf(hw, 0.01))
					# Rib hoops round the paper.
					if absf(fposmod(t * 7.0, 1.0) - 0.5) > 0.40:
						b *= 0.78
			# The cap and the base ring.
			if absf(uv.y + 0.68) < 0.10 and absf(uv.x) < 0.34:
				a = 1.0
				b = 0.35
			if absf(uv.y - 0.62) < 0.09 and absf(uv.x) < 0.30:
				a = 1.0
				b = 0.30
			if a <= 0.02:
				return Color(0, 0, 0, 0)
			return Color(b, b, b, a))
		for i in 5:
			var x: float = vp.x * (0.10 + 0.20 * float(i)) + randf_range(-14.0, 14.0) * sc
			var y: float = vp.y * randf_range(0.10, 0.90)
			var w: float = vp.x * randf_range(0.075, 0.115)
			var h: float = w * (72.0 / 56.0)
			# Its glow on the water, laid down first.
			var pool := TextureRect.new()
			pool.texture = tex_dot()
			pool.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			pool.stretch_mode = TextureRect.STRETCH_SCALE
			pool.mouse_filter = Control.MOUSE_FILTER_IGNORE
			pool.size = Vector2(w * 4.2, w * 3.0)
			pool.position = Vector2(x - pool.size.x * 0.5, y - pool.size.y * 0.5)
			pool.modulate = Color(warm.r, warm.g, warm.b, 0.14)
			add_child(pool)
			# The reflection: a soft vertical smear below it, the way a light on
			# still water always trails toward the viewer.
			var refl := TextureRect.new()
			refl.texture = tex_dot()
			refl.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			refl.stretch_mode = TextureRect.STRETCH_SCALE
			refl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			refl.size = Vector2(w * 0.55, h * 2.1)
			refl.position = Vector2(x - refl.size.x * 0.5, y + h * 0.25)
			refl.modulate = Color(warm.r, warm.g, warm.b, 0.22)
			add_child(refl)
			var lam := TextureRect.new()
			lam.texture = lantern
			lam.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			lam.stretch_mode = TextureRect.STRETCH_SCALE
			lam.mouse_filter = Control.MOUSE_FILTER_IGNORE
			lam.size = Vector2(w, h)
			lam.position = Vector2(x - w * 0.5, y - h * 0.5)
			lam.modulate = Color(1.0, 0.80, 0.44, 0.95)
			add_child(lam)
			# The candle inside gutters, and the pool and reflection gutter with it.
			var ph := randf_range(0.0, 2.0)
			for n_v in [[pool, 0.14, 0.26], [refl, 0.22, 0.38]]:
				var n: Array = n_v
				var node := n[0] as TextureRect
				var lo: float = n[1]
				var hi: float = n[2]
				var t2 := node.create_tween().set_loops()
				t2.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
				t2.tween_interval(ph)
				t2.tween_property(node, "modulate:a", hi, randf_range(1.1, 1.9))
				t2.tween_property(node, "modulate:a", lo, randf_range(1.2, 2.1))
			# ...and the whole lantern drifts on the pond.
			var drift := lam.create_tween().set_loops()
			drift.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
			var dx: float = randf_range(-1.0, 1.0) * vp.x * 0.04
			var dy: float = randf_range(-1.0, 1.0) * vp.y * 0.025
			drift.tween_property(lam, "position", lam.position + Vector2(dx, dy),
				randf_range(7.0, 11.0))
			drift.tween_property(lam, "position", lam.position, randf_range(7.0, 11.0))
		# Lotus blossoms open on the water, catching the lantern light.
		var lotus := bake("pond_lotus", 56, 56, func(uv: Vector2) -> Color:
			var r := uv.length()
			if r > 1.0:
				return Color(0, 0, 0, 0)
			var ang := atan2(uv.y, uv.x)
			# Eight petals: a rosette whose radius wobbles with the angle.
			var petal: float = 0.62 + 0.34 * absf(cos(ang * 4.0))
			if r > petal:
				return Color(0, 0, 0, 0)
			var a: float = 1.0 - smoothstep(petal - 0.10, petal, r)
			# Bright at the heart, deepening toward the petal tips.
			var b: float = lerpf(1.0, 0.45, clampf(r / maxf(petal, 0.01), 0.0, 1.0))
			b = maxf(b, 1.0 - smoothstep(0.0, 0.18, r))
			return Color(b, b, b, clampf(a, 0.0, 1.0)))
		for s_v in [Vector2(0.16, 0.14), Vector2(0.84, 0.80), Vector2(0.90, 0.20)]:
			var s: Vector2 = s_v
			var f := TextureRect.new()
			f.texture = lotus
			f.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			f.stretch_mode = TextureRect.STRETCH_SCALE
			f.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var d: float = vp.x * randf_range(0.055, 0.085)
			f.size = Vector2(d, d)
			f.pivot_offset = f.size * 0.5
			f.position = Vector2(s.x * vp.x, s.y * vp.y) - f.size * 0.5
			f.rotation = randf() * TAU
			f.modulate = Color(1.0, 0.78, 0.86, 0.9)
			add_child(f)
			var bt := f.create_tween().set_loops()
			bt.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
			bt.tween_property(f, "scale", Vector2(1.06, 1.06), randf_range(3.0, 4.5))
			bt.tween_property(f, "scale", Vector2.ONE, randf_range(3.2, 4.8))
		# Fireflies over the water, and their faint doubles in it.
		field({"tex": tex_dot(), "color": Color(1.0, 0.88, 0.46), "alpha": 0.85,
			"amount": 20, "lifetime": 5.0, "dir": Vector3(0, -1, 0), "spread": 180.0,
			"vmin": 5.0, "vmax": 18.0, "smin": 0.35, "smax": 0.9, "turb": 0.9,
			"twinkle": true})

	func _lily_pads() -> void:
		var pad := bake("lilypad", 48, 48, func(uv: Vector2) -> Color:
			var r := uv.length()
			var ang := atan2(uv.y, uv.x)
			# A disc with a notch wedge cut out (the classic pad silhouette).
			var notch := 1.0 - smoothstep(0.28, 0.34, absf(ang - 0.5))
			var a := (1.0 - smoothstep(0.88, 1.0, r)) * (1.0 - notch)
			if a <= 0.02:
				return Color(0, 0, 0, 0)
			var b := clampf(0.60 + (-uv.y) * 0.14 - r * 0.18, 0.2, 1.0)
			return Color(b, b, b, a))
		var spots := [Vector2(0.12, 0.10), Vector2(0.88, 0.16), Vector2(0.08, 0.88), Vector2(0.90, 0.84)]
		for s_v in spots:
			var s: Vector2 = s_v
			var p := TextureRect.new()
			p.texture = pad
			p.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			p.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var d: float = vp.x * randf_range(0.10, 0.16)
			p.size = Vector2(d, d)
			p.pivot_offset = p.size * 0.5
			p.position = Vector2(s.x * vp.x, s.y * vp.y) - p.size * 0.5
			p.rotation = randf() * TAU
			p.modulate = Color(0.28, 0.55, 0.34, 0.85)
			add_child(p)
			var tw := p.create_tween().set_loops()
			tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
			tw.tween_property(p, "rotation", p.rotation + 0.12, randf_range(3.0, 5.0))
			tw.tween_property(p, "rotation", p.rotation - 0.10, randf_range(3.0, 5.0))

	func _tex_koi(variant: int) -> Texture2D:
		return bake("koi_v%d" % variant, 60, 110, func(uv: Vector2) -> Color:
			# A REAL top-down koi, baked in FULL COLOUR: rounded head with black
			# eyes, a body that swells at the shoulders and tapers to the
			# peduncle, swept pectoral + pelvic fin pairs, a curving veil tail,
			# and kohaku markings. variant 0 = white with orange patches;
			# variant 1 = orange with white patches.
			var x := uv.x
			var y := uv.y
			# Body silhouette: a width profile down the spine (t: head -> peduncle).
			var body_a := 0.0
			var t := (y + 0.92) / 1.44
			if t >= 0.0 and t <= 1.0:
				var w := 0.34 * sqrt(clampf(t * 5.0, 0.0, 1.0)) \
					* (1.0 - smoothstep(0.45, 1.0, t) * 0.72) \
					+ 0.22 * exp(-pow((t - 0.32) / 0.30, 2.0))
				body_a = 1.0 - smoothstep(maxf(w - 0.06, 0.0), w + 0.025, absf(x))
			# Caudal fin: a flowing veil that CURVES as it streams back, opening
			# into a fan with a slim forked notch.
			var tail_a := 0.0
			if y > 0.30:
				var ty := (y - 0.30) / 0.70
				var xa := x - 0.10 * sin(ty * 2.4)   # the swimmer's curve
				var spread := 0.07 + 0.34 * ty
				var lobe := 1.0 - smoothstep(spread * 0.9, spread + 0.10, absf(xa))
				var fork := maxf(smoothstep(0.02 * ty, 0.09 * ty, absf(xa)),
					1.0 - smoothstep(0.0, 0.5, ty))
				tail_a = lobe * fork * (1.0 - smoothstep(0.85, 1.0, y))
			# Pectoral fins: rounded blades angled ~35° out from the shoulders.
			var pf := Vector2(absf(x) - 0.47, y + 0.18)
			var pr := Vector2(pf.x * 0.82 - pf.y * 0.57, pf.x * 0.57 + pf.y * 0.82)
			var pe := pow(pr.x / 0.30, 2.0) + pow(pr.y / 0.13, 2.0)
			var pect_a := 1.0 - smoothstep(0.7, 1.05, pe)
			# Pelvic fins: a smaller pair further down the body.
			var vf := Vector2(absf(x) - 0.30, y - 0.16)
			var vr := Vector2(vf.x * 0.90 - vf.y * 0.44, vf.x * 0.44 + vf.y * 0.90)
			var ve := pow(vr.x / 0.18, 2.0) + pow(vr.y / 0.085, 2.0)
			var pelv_a := 1.0 - smoothstep(0.7, 1.05, ve)
			var fin_a := maxf(pect_a, pelv_a * 0.9)
			var a := clampf(maxf(body_a, maxf(tail_a, fin_a)), 0.0, 1.0)
			if a <= 0.03:
				return Color(0, 0, 0, 0)
			# Eyes: two black beads at the head's sides.
			var eye := minf((uv - Vector2(-0.155, -0.72)).length(),
				(uv - Vector2(0.155, -0.72)).length())
			if eye < 0.055 and body_a > 0.4:
				return Color(0.05, 0.05, 0.07, a)
			# Kohaku markings: three soft-edged blotches down the back.
			var white_c := Color(0.97, 0.95, 0.90)
			var orange_c := Color(0.94, 0.42, 0.10)
			var m := 0.0
			m = maxf(m, 1.0 - smoothstep(0.10, 0.34, (uv - Vector2(0.03, -0.60)).length()))
			m = maxf(m, 1.0 - smoothstep(0.12, 0.38, (uv - Vector2(-0.16, -0.08)).length()))
			m = maxf(m, 1.0 - smoothstep(0.08, 0.30, (uv - Vector2(0.13, 0.26)).length()))
			m = clampf(m * 1.4, 0.0, 1.0)
			var col := white_c.lerp(orange_c, m)
			if variant == 1:
				col = orange_c.lerp(white_c, m * 0.85)
			# Fins + tail: translucent membranes, whiter than the body, warmed at
			# the base by the body colour.
			if body_a < 0.5:
				var wash := 0.15
				if y > 0.30:
					wash = 0.30 * (1.0 - clampf((y - 0.30) / 0.70, 0.0, 1.0))
				var fin_col := Color(0.99, 0.97, 0.94).lerp(orange_c, wash)
				return Color(fin_col.r, fin_col.g, fin_col.b, a * 0.62)
			# Flank shading + a bright dorsal ridge along the spine.
			var shade := 0.80 + 0.20 * clampf(1.0 - absf(x) * 1.3, 0.0, 1.0)
			shade += (1.0 - smoothstep(0.0, 0.10, absf(x))) * 0.06
			return Color(clampf(col.r * shade, 0.0, 1.0), clampf(col.g * shade, 0.0, 1.0),
				clampf(col.b * shade, 0.0, 1.0), a))

	func _spawn_fish(i: int) -> void:
		# The colours are BAKED into the koi texture now (white/orange kohaku);
		# per-fish modulate only warms or cools each individual slightly.
		var tints := [Color(1, 1, 1), Color(1.0, 0.92, 0.85), Color(0.93, 0.97, 1.0),
			Color(1.0, 0.85, 0.78), Color(0.98, 0.98, 0.94)]
		var tex := _tex_koi(i % 2)
		# A school with depth: sizes range from small fry deep down to the big
		# show koi near the glass.
		var w: float = vp.x * randf_range(0.06, 0.125)
		var fsize := Vector2(w, w * 1.83)   # matches the 60×110 bake's aspect
		# A soft dark shadow swims beneath the fish — sells the depth of the pond.
		var shadow := TextureRect.new()
		shadow.texture = tex
		shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		shadow.size = fsize
		shadow.pivot_offset = fsize * 0.5
		shadow.modulate = Color(0.0, 0.05, 0.06, 0.30)
		add_child(shadow)
		var node := TextureRect.new()
		node.texture = tex
		node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		node.size = fsize
		node.pivot_offset = fsize * 0.5
		node.position = frame_point() - fsize * 0.5
		var tint: Color = tints[i % tints.size()]
		node.modulate = Color(tint.r, tint.g, tint.b, 0.94)
		add_child(node)
		_fish.append({"node": node, "shadow": shadow, "vel": Vector2.ZERO,
			"target": frame_point(),
			"phase": randf() * TAU, "speed": randf_range(55.0, 85.0),
			"feed": 0.0, "base_a": 0.94})

	func on_swipe(dir: Vector2i) -> void:
		# The water answers with rings drifting on the current, and the fish nearest
		# the passing shadow flick their tails and scoot along with it.
		var d := Vector2(dir).normalized()
		for i in 3:
			var p := Vector2(randf_range(0.2, 0.8) * vp.x, randf_range(0.2, 0.8) * vp.y)
			ripple(p + d * float(i) * 60.0 * sc, pc("accent2"), 130.0 * sc, 0.9, float(i) * 0.08)
		for f_v in _fish:
			var f: Dictionary = f_v
			var node: TextureRect = f["node"]
			var fp: Vector2 = node.position + node.size * 0.5
			if (fp - vp * 0.5).length() < vp.x * 0.34:
				var v: Vector2 = f["vel"]
				f["vel"] = v + d * randf_range(45.0, 85.0) * sc

	func on_merge(pos: Vector2, value: int, _tint: Color) -> void:
		# The pebble drop: three staggered rings + a small splash.
		var col: Color = pc("accent2").lerp(white(1.0), 0.3)
		var base_d: float = (170.0 + minf(float(value), 2048.0) * 0.06) * sc
		for i in 3:
			ripple(pos, col, base_d * (0.7 + 0.35 * float(i)), 0.8, float(i) * 0.12)
		burst(pos, {"tex": tex_dot(), "color": white(0.9), "alpha": 0.8, "amount": 12,
			"lifetime": 0.6, "vmin": 60.0, "vmax": 190.0, "gravity": 300.0,
			"smin": 0.2, "smax": 0.6})
		# Koi RUSH toward the drop — the classic feeding response: they turn to
		# face it, rise toward the surface (brightening) and crowd in, then drift
		# back off. The pond comes alive at your touch instead of scattering.
		var vt := to_visible(pos)   # surface the frenzy to a visible band
		for f_v in _fish:
			var f: Dictionary = f_v
			var node: TextureRect = f["node"]
			var fp: Vector2 = node.position + node.size * 0.5
			if absf(fp.x - pos.x) < vp.x * 0.45:
				f["target"] = vt + Vector2(randf_range(-45, 45), randf_range(-45, 45)) * sc
				f["feed"] = randf_range(1.6, 2.8)
				var v: Vector2 = f["vel"]
				f["vel"] = v.lerp((vt - fp).normalized() * 150.0 * sc, 0.28)

	## The fish are curious: the nearest one turns and swims over to the finger,
	## rising to the surface (a peek) as it comes. Throttled so a drag never jerks
	## the whole school.
	func on_touch(pos: Vector2) -> void:
		if _t - _touch_t < 0.22:
			return
		_touch_t = _t
		var vt := to_visible(pos)
		var best := INF
		var chosen: Dictionary = {}
		for f_v in _fish:
			var f: Dictionary = f_v
			var node: TextureRect = f["node"]
			var fp: Vector2 = node.position + node.size * 0.5
			var d := absf(fp.x - pos.x) + absf(fp.y - vt.y) * 0.6
			if d < best:
				best = d
				chosen = f
		if not chosen.is_empty():
			chosen["target"] = vt
			chosen["feed"] = maxf(float(chosen["feed"]), 1.4)

	func _process(delta: float) -> void:
		var scoped: bool = Engine.has_meta("bench_scope")  # perf-bench scope, regression/perf/SPEC.md #4.2
		if scoped:
			Engine.get_meta("bench_scope").call(true, "RewardFx._process")
		_t += delta
		for f_v in _fish:
			var f: Dictionary = f_v
			var node: TextureRect = f["node"]
			var centre: Vector2 = node.position + node.size * 0.5
			var target: Vector2 = f["target"]
			if (target - centre).length() < 70.0 * sc:
				target = frame_point()
				f["target"] = target
			var feed: float = f["feed"]
			var vel: Vector2 = f["vel"]
			# a gently breathing per-fish speed keeps the school playful, not robotic
			var desired := (target - centre).normalized() * float(f["speed"]) \
				* (1.0 + 0.9 * clampf(feed, 0.0, 1.0)) \
				* (0.9 + 0.18 * sin(_t * 0.9 + float(f["phase"]))) * sc
			vel = vel.lerp(desired, clampf(1.4 * delta, 0.0, 1.0))
			node.position += vel * delta
			# Keep the school in sight: a fleeing fish bounces softly off the
			# pond edges (and picks a fresh target inside) instead of drifting
			# off-screen and slowly steering back.
			var c2 := node.position + node.size * 0.5
			if c2.x < 0.0 or c2.x > vp.x:
				vel.x = -vel.x * 0.8
				node.position.x = clampf(node.position.x, -node.size.x * 0.5,
					vp.x - node.size.x * 0.5)
				f["target"] = frame_point()
			if c2.y < 0.0 or c2.y > vp.y:
				vel.y = -vel.y * 0.8
				node.position.y = clampf(node.position.y, -node.size.y * 0.5,
					vp.y - node.size.y * 0.5)
				f["target"] = frame_point()
			f["vel"] = vel
			# Nose into the current + a playful swim wiggle, eased so turns never snap.
			var want_rot := vel.angle() + PI * 0.5 + sin(_t * 7.0 + float(f["phase"])) * 0.14
			node.rotation = lerp_angle(node.rotation, want_rot, clampf(6.0 * delta, 0.0, 1.0))
			# The shadow trails below-right, deeper in the water.
			var shadow: TextureRect = f["shadow"]
			shadow.position = node.position + Vector2(10.0, 16.0) * sc
			shadow.rotation = node.rotation
			# Feeding: koi rise and brighten as they crowd the drop, then settle.
			if feed > 0.0:
				f["feed"] = maxf(feed - delta, 0.0)
			var k := clampf(feed, 0.0, 1.0)
			var sm := clampf(5.0 * delta, 0.0, 1.0)
			var want := 1.0 + 0.16 * k
			node.scale = node.scale.lerp(Vector2(want, want), sm)
			shadow.scale = node.scale
			var m: Color = node.modulate
			node.modulate = Color(m.r, m.g, m.b, lerpf(m.a, lerpf(float(f["base_a"]), 1.0, k), sm))
		if scoped:
			Engine.get_meta("bench_scope").call(false, "RewardFx._process")


# =============================================================================
# Antigrav — a weightless metaball fluid (shader): blobs drift, wobble and fuse.
# Swipes shove the whole fluid; merges pull two blobs together — the world does
# what the tiles just did.
# =============================================================================
class Metaballs extends Base:
	const COUNT := 7
	var _mat: ShaderMaterial
	var _bpos: Array = []          # Vector2, normalized 0..1
	var _bvel: Array = []          # Vector2, normalized units/sec
	var _brad: Array = []          # float, base radius (normalized)
	var _t: float = 0.0
	var _fuse_a: int = -1
	var _fuse_b: int = -1
	var _fuse_t: float = 0.0

	const _CODE := """
shader_type canvas_item;
uniform vec4 base : source_color = vec4(0.03, 0.01, 0.08, 1.0);
uniform vec4 col_a : source_color = vec4(1.0, 0.26, 0.62, 1.0);
uniform vec4 col_b : source_color = vec4(0.45, 0.25, 0.9, 1.0);
uniform vec2 balls[7];
uniform float radii[7];
uniform float aspect = 0.46;
uniform float glow = 0.0;
float fld(vec2 p) {
	float f = 0.0;
	for (int i = 0; i < 7; i++) {
		vec2 d = p - balls[i] * vec2(aspect, 1.0);
		f += radii[i] * radii[i] / max(dot(d, d), 1e-5);
	}
	return f;
}
void fragment() {
	vec2 p = UV * vec2(aspect, 1.0);
	float f = fld(p);
	float body = smoothstep(1.0, 1.3, f);
	float rim = smoothstep(0.72, 1.0, f) * (1.0 - smoothstep(1.0, 1.5, f));
	// Glassy highlight: sample the field a touch toward the light (up-left);
	// where it climbs fastest, the blob's surface faces the light.
	float fl = fld(p + vec2(-0.016, -0.022));
	float spec = pow(clamp((fl - f) * 0.9, 0.0, 1.0), 2.0) * body;
	vec3 c = base.rgb;
	vec3 fill = mix(col_b.rgb, col_a.rgb, clamp(f * 0.30, 0.0, 1.0));
	c = mix(c, fill * (0.45 + glow * 0.4), body);
	c += col_a.rgb * rim * (0.55 + glow);
	c += vec3(1.0) * spec * 0.5;
	COLOR = vec4(c, 1.0);
}
"""

	# Compiled once per process (ui/screen.gd pattern); _mat stays per-instance.
	static var _shader: Shader

	func _build() -> void:
		for i in COUNT:
			_bpos.append(Vector2(randf_range(0.15, 0.85), randf_range(0.12, 0.88)))
			_bvel.append(Vector2(randf_range(-0.03, 0.03), randf_range(-0.03, 0.03)))
			_brad.append(randf_range(0.038, 0.072))
		if _shader == null:
			_shader = Shader.new()
			_shader.code = _CODE
		_mat = ShaderMaterial.new()
		_mat.shader = _shader
		_mat.set_shader_parameter("base", pc("bg0"))
		_mat.set_shader_parameter("col_a", pc("accent"))
		_mat.set_shader_parameter("col_b", pc("accent2"))
		_mat.set_shader_parameter("aspect", vp.x / vp.y)
		_mat.set_shader_parameter("glow", 0.0)
		_push_uniforms()
		shader_layer(_mat)
		# A few weightless sparkle motes floating over the fluid.
		field({"tex": tex_dot(), "color": pc("accent").lerp(white(1.0), 0.5), "alpha": 0.6,
			"amount": 26, "lifetime": 7.0, "dir": Vector3(0, -1, 0), "spread": 180.0,
			"vmin": 3.0, "vmax": 12.0, "smin": 0.25, "smax": 0.6, "turb": 0.8, "twinkle": true})
		_containment()
		_zero_g_debris()
		_shed_droplets()
		set_process(true)

	## The field the fluid is held in: a slow hexagonal lattice breathing behind
	## everything, plus two containment rings turning against each other. Without
	## it the blobs are just lava; with it they are lava that something is HOLDING.
	func _containment() -> void:
		var hex := bake("antigrav_hex", 128, 128, func(uv: Vector2) -> Color:
			# Distance to the nearest edge of a hex lattice, cheaply: three
			# rotated stripe fields, minimum taken.
			var d := 1e9
			for k in 3:
				var ang: float = float(k) * PI / 3.0
				var proj: float = uv.x * cos(ang) + uv.y * sin(ang)
				var g: float = absf(fposmod(proj * 6.0, 1.0) - 0.5)
				d = minf(d, g)
			var line: float = 1.0 - smoothstep(0.02, 0.09, d)
			# Fade the lattice out toward the corners so it has no hard edge.
			line *= 1.0 - smoothstep(0.55, 1.15, uv.length())
			if line <= 0.02:
				return Color(0, 0, 0, 0)
			return Color(1, 1, 1, clampf(line, 0.0, 1.0)))
		var lat := TextureRect.new()
		lat.texture = hex
		lat.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		lat.stretch_mode = TextureRect.STRETCH_SCALE
		lat.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var d0: float = maxf(vp.x, vp.y) * 1.5
		lat.size = Vector2(d0, d0)
		lat.pivot_offset = lat.size * 0.5
		lat.position = vp * 0.5 - lat.size * 0.5
		var lc: Color = pc("accent2").lerp(white(1.0), 0.35)
		lat.modulate = Color(lc.r, lc.g, lc.b, 0.04)
		add_child(lat)
		var lt := lat.create_tween().set_loops()
		lt.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		lt.tween_property(lat, "modulate:a", 0.085, 4.0)
		lt.tween_property(lat, "modulate:a", 0.03, 4.6)
		var spin := lat.create_tween().set_loops()
		spin.tween_property(lat, "rotation", TAU, 160.0).from(0.0)
		# The rings.
		for i in 2:
			var ring := TextureRect.new()
			ring.texture = tex_ring()
			ring.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ring.stretch_mode = TextureRect.STRETCH_SCALE
			ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var d: float = vp.x * (0.86 + 0.34 * float(i))
			ring.size = Vector2(d, d * 0.94)
			ring.pivot_offset = ring.size * 0.5
			ring.position = vp * 0.5 - ring.size * 0.5
			var rc: Color = pc("accent") if i == 0 else pc("accent2")
			ring.modulate = Color(rc.r, rc.g, rc.b, 0.10)
			add_child(ring)
			var rt := ring.create_tween().set_loops()
			rt.tween_property(ring, "rotation", TAU * (1.0 if i == 0 else -1.0),
				randf_range(50.0, 80.0)).from(0.0)

	## Debris adrift in zero g: small hard-edged shards tumbling slowly on their
	## own axes and drifting on straight lines, because nothing here falls.
	func _zero_g_debris() -> void:
		var shard := bake("antigrav_shard", 40, 40, func(uv: Vector2) -> Color:
			# An irregular quad — a chip of something, not a polished gem.
			var pts := [Vector2(-0.72, -0.30), Vector2(0.10, -0.80),
				Vector2(0.78, 0.18), Vector2(-0.18, 0.80)]
			var inside := true
			for i in 4:
				var a: Vector2 = pts[i]
				var b: Vector2 = pts[(i + 1) % 4]
				if (b - a).cross(uv - a) < 0.0:
					inside = false
					break
			if not inside:
				return Color(0, 0, 0, 0)
			# A bright facet edge on the lit side, dark body.
			var d := 1e9
			for i in 4:
				d = minf(d, seg_dist(uv, pts[i], pts[(i + 1) % 4]))
			var rim: float = 1.0 - smoothstep(0.0, 0.14, d)
			var b2: float = 0.22 + rim * 0.75 * clampf(0.5 - uv.x * 0.5 - uv.y * 0.5, 0.0, 1.0) * 2.0
			return Color(clampf(b2, 0.0, 1.0), clampf(b2, 0.0, 1.0), clampf(b2, 0.0, 1.0), 1.0))
		for i in 7:
			var s := TextureRect.new()
			s.texture = shard
			s.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			s.stretch_mode = TextureRect.STRETCH_SCALE
			s.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var d: float = vp.x * randf_range(0.030, 0.085)
			s.size = Vector2(d, d)
			s.pivot_offset = s.size * 0.5
			s.position = Vector2(randf() * vp.x, randf() * vp.y) - s.size * 0.5
			var col: Color = pc("accent2").lerp(white(1.0), randf_range(0.2, 0.6))
			s.modulate = Color(col.r, col.g, col.b, randf_range(0.3, 0.7))
			add_child(s)
			# Tumble: a constant angular rate, the way an object spins in vacuum.
			var tumble := s.create_tween().set_loops()
			tumble.tween_property(s, "rotation", TAU * (1.0 if randf() < 0.5 else -1.0),
				randf_range(9.0, 26.0)).from(randf() * TAU)
			# Drift: a straight run across the frame, wrapping when it leaves.
			var dir := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
			var travel: float = maxf(vp.x, vp.y) * randf_range(0.5, 1.1)
			var drift := s.create_tween().set_loops()
			drift.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
			drift.tween_property(s, "position", s.position + dir * travel,
				randf_range(14.0, 26.0))
			drift.tween_property(s, "position", s.position, randf_range(14.0, 26.0))

	## The fluid sheds: every few seconds a droplet pinches off, floats free on a
	## lazy arc, and is drawn back in. Surface tension, with nowhere to fall to.
	func _shed_droplets() -> void:
		every(2.2, 5.0, func() -> void:
			var from := Vector2(_bpos[randi() % COUNT]) * vp
			var drop := TextureRect.new()
			drop.texture = tex_dot()
			drop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			drop.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var d: float = vp.x * randf_range(0.030, 0.070)
			drop.size = Vector2(d, d)
			drop.position = from - drop.size * 0.5
			var col: Color = pc("accent").lerp(pc("accent2"), randf())
			drop.modulate = Color(col.r, col.g, col.b, 0.0)
			add_child(drop)
			var away := from + Vector2(randf_range(-1.0, 1.0),
				randf_range(-1.0, 1.0)).normalized() * vp.x * randf_range(0.18, 0.36)
			var tw := drop.create_tween()
			tw.set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
			tw.tween_property(drop, "position", away - drop.size * 0.5, 1.6)
			tw.tween_property(drop, "modulate:a", 0.85, 0.5)
			tw.chain().set_parallel(true).set_ease(Tween.EASE_IN)
			tw.tween_property(drop, "position", from - drop.size * 0.5, 2.0)
			tw.tween_property(drop, "modulate:a", 0.0, 1.9)
			tw.chain().tween_callback(drop.queue_free))

	func _push_uniforms() -> void:
		var pts := PackedVector2Array()
		var rads := PackedFloat32Array()
		for i in COUNT:
			pts.append(_bpos[i])
			var rr: float = float(_brad[i]) * (1.0 + 0.12 * sin(_t * 1.3 + float(i) * 2.1))
			# Surface tension: the fusing pair shivers as it snaps together.
			if _fuse_t > 0.0 and (i == _fuse_a or i == _fuse_b):
				rr *= 1.0 + 0.22 * sin((0.55 - _fuse_t) * 30.0) * (_fuse_t / 0.55)
			rads.append(rr)
		_mat.set_shader_parameter("balls", pts)
		_mat.set_shader_parameter("radii", rads)

	func on_swipe(dir: Vector2i) -> void:
		var d := Vector2(dir)
		for i in COUNT:
			_bvel[i] = Vector2(_bvel[i]) + d * randf_range(0.12, 0.22)

	func on_merge(_pos: Vector2, _value: int, _tint: Color) -> void:
		# Two blobs snap together — the fluid mirrors the merge.
		_fuse_a = randi() % COUNT
		_fuse_b = (_fuse_a + 1 + randi() % (COUNT - 1)) % COUNT
		_fuse_t = 0.55
		var tw := create_tween()
		tw.tween_method(func(v: float): _mat.set_shader_parameter("glow", v), 0.0, 0.9, 0.15)
		tw.tween_method(func(v: float): _mat.set_shader_parameter("glow", v), 0.9, 0.0, 0.6)

	func _process(delta: float) -> void:
		var scoped: bool = Engine.has_meta("bench_scope")  # perf-bench scope, regression/perf/SPEC.md #4.2
		if scoped:
			Engine.get_meta("bench_scope").call(true, "RewardFx._process")
		_t += delta
		_fuse_t = maxf(_fuse_t - delta, 0.0)
		for i in COUNT:
			var p: Vector2 = _bpos[i]
			var v: Vector2 = _bvel[i]
			# Gentle centre attraction + damping keeps the fluid loosely gathered.
			v += (Vector2(0.5, 0.5) - p) * 0.02 * delta
			v *= 1.0 - 0.35 * delta
			if _fuse_t > 0.0 and (i == _fuse_a or i == _fuse_b):
				var other: Vector2 = _bpos[_fuse_b if i == _fuse_a else _fuse_a]
				v += (other - p) * 3.2 * delta
			p += v * delta
			if p.x < 0.06 or p.x > 0.94:
				v.x = -v.x * 0.9
				p.x = clampf(p.x, 0.06, 0.94)
			if p.y < 0.06 or p.y > 0.94:
				v.y = -v.y * 0.9
				p.y = clampf(p.y, 0.06, 0.94)
			_bpos[i] = p
			_bvel[i] = v
		_push_uniforms()
		if scoped:
			Engine.get_meta("bench_scope").call(false, "RewardFx._process")


# =============================================================================
# Ronin — flawless technique. Near-still darkness: drifting steel dust and a
# slow glint. Every swipe is a katana slash along the swipe line with steel
# sparks; merges cross-cut at the merge point with a white flash.
# =============================================================================
class Katana extends Base:
	func _build() -> void:
		field({"tex": tex_dot(), "color": pc("accent2").lerp(white(1.0), 0.2), "alpha": 0.22,
			"amount": 30, "lifetime": 11.0, "dir": Vector3(0, -1, 0), "spread": 180.0,
			"vmin": 3.0, "vmax": 10.0, "smin": 0.2, "smax": 0.55, "turb": 0.4})
		# Sakura drifting through the dark — the duel garden between strikes.
		field({"tex": _tex_petal(), "color": Color(1.0, 0.76, 0.83), "alpha": 0.42,
			"amount": 14, "lifetime": 9.0, "dir": Vector3(0.3, 1, 0), "spread": 20.0,
			"vmin": 20.0, "vmax": 55.0, "smin": 0.6, "smax": 1.3, "spin": 1.1, "turb": 0.6})
		edge_glow(pc("accent"), 0.03, 0.09, false)
		_ronin_relics()
		_virtue_words()
		# The blade at rest: an occasional cold glint sweeping the dark.
		every(5.0, 10.0, func(): _glint())

	## What the ronin left behind: the sword planted in the ground with his kasa
	## hung on the grip, and a second hat lying in the grass beside it.
	##
	## There is no FIGURE here on purpose. A person rendered as a silhouette is
	## either good enough to read as a person or it is a toy, and at this size it
	## was a toy — while a sword standing in the earth under a hat says
	## everything about a masterless samurai without drawing one.
	func _ronin_relics() -> void:
		_ronin_moon()
		_bamboo_row()
		var kasa := _tex_kasa()
		var ink := Color(0.06, 0.05, 0.09)
		# --- the planted sword ---
		var host := Control.new()
		host.mouse_filter = Control.MOUSE_FILTER_IGNORE
		host.position = Vector2(vp.x * 0.68, vp.y * 0.955)
		host.rotation = 0.07                       # driven a little off true
		add_child(host)
		var blade := TextureRect.new()
		blade.texture = _tex_saya()
		blade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		blade.stretch_mode = TextureRect.STRETCH_SCALE
		blade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bl: float = vp.y * 0.34                # length, standing
		blade.size = Vector2(bl, bl * 0.105)       # slim: a blade, not a post
		blade.pivot_offset = Vector2(0.0, blade.size.y * 0.5)
		blade.rotation = -PI * 0.5                 # tip down, into the ground
		blade.position = Vector2(-blade.size.y * 0.5, 0.0)
		var steel: Color = pc("accent2").lerp(Color(0.07, 0.07, 0.11), 0.74)
		blade.modulate = Color(steel.r, steel.g, steel.b, 0.95)
		host.add_child(blade)
		# --- his hat, hung on the grip ---
		var hat := TextureRect.new()
		hat.texture = kasa
		hat.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		hat.stretch_mode = TextureRect.STRETCH_SCALE
		hat.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var hw: float = vp.x * 0.30
		hat.size = Vector2(hw, hw * (96.0 / 160.0))
		hat.pivot_offset = Vector2(hw * 0.5, 0.0)
		hat.rotation = -0.22
		hat.position = Vector2(-hw * 0.44, -bl * 0.86)
		hat.modulate = Color(ink.r, ink.g, ink.b, 0.96)
		host.add_child(hat)
		# It swings a few degrees where it hangs, and the whole marker leans on
		# the wind — the only motion in the scene besides the petals.
		var sw := hat.create_tween().set_loops()
		sw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		sw.tween_property(hat, "rotation", -0.14, 3.6)
		sw.tween_property(hat, "rotation", -0.28, 4.2)
		var lean := host.create_tween().set_loops()
		lean.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		lean.tween_property(host, "rotation", 0.085, 6.0)
		lean.tween_property(host, "rotation", 0.055, 6.6)
		# --- a second hat, laid down in the grass ---
		var rest := TextureRect.new()
		rest.texture = kasa
		rest.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rest.stretch_mode = TextureRect.STRETCH_SCALE
		rest.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var rw: float = vp.x * 0.26
		rest.size = Vector2(rw, rw * (96.0 / 160.0) * 0.62)   # squashed: seen flat
		rest.pivot_offset = rest.size * 0.5
		rest.rotation = 0.14
		rest.position = Vector2(vp.x * 0.30 - rw * 0.5, vp.y * 0.935 - rest.size.y)
		rest.modulate = Color(ink.r, ink.g, ink.b, 0.88)
		add_child(rest)

	## A kasa: the conical straw hat, seen from slightly below so the brim is an
	## ellipse and the crown a cone standing on it.
	func _tex_kasa() -> Texture2D:
		return bake("ronin_kasa", 160, 96, func(uv: Vector2) -> Color:
			const AR := 0.6       # bake 160x96
			var sy := uv.y * AR
			var a := 0.0
			var b := 0.0
			# The brim, an ellipse lying almost edge-on.
			var e := Vector2(uv.x / 0.97, (sy - 0.20) / 0.30).length()
			if e < 1.0:
				a = 1.0
				b = 0.16 + 0.30 * (1.0 - e)
			# The crown: a cone rising off the middle of it.
			var r: float = absf(uv.x) / 0.60
			var top: float = -0.55 + 0.75 * pow(clampf(r, 0.0, 1.0), 1.35)
			if r < 1.0 and sy > top and sy < 0.26:
				a = 1.0
				# Lit from the left, so it is a cone and not a triangle.
				b = 0.40 - 0.26 * clampf((uv.x + 0.6) / 1.2, 0.0, 1.0)
			if a <= 0.02:
				return Color(0, 0, 0, 0)
			# The straw: fine radial banding, only just visible.
			b += 0.06 * sin(atan2(sy - 0.20, uv.x) * 18.0)
			return Color(clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), a))

	## The moon he is cut out against: low, huge and pale, with the haze of a
	## damp night around it. It replaced a formless warm blob that was doing the
	## same job without ever saying what it was.
	func _ronin_moon() -> void:
		var disc := bake("ronin_moon", 96, 96, func(uv: Vector2) -> Color:
			var r := uv.length()
			var a: float = 1.0 - smoothstep(0.93, 1.0, r)
			if a <= 0.01:
				return Color(0, 0, 0, 0)
			# Maria: a couple of faint darker patches, so it is a moon and not
			# a lamp. Kept very low contrast — it is behind a rainy night.
			var m: float = 1.0 - smoothstep(0.0, 0.34, (uv - Vector2(-0.22, -0.18)).length())
			m = maxf(m, (1.0 - smoothstep(0.0, 0.26, (uv - Vector2(0.26, 0.16)).length())) * 0.8)
			var b: float = clampf(0.96 - m * 0.10, 0.0, 1.0)
			return Color(b, b, b, a))
		var halo := TextureRect.new()
		halo.texture = tex_round()
		halo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		halo.stretch_mode = TextureRect.STRETCH_SCALE
		halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var d: float = vp.x * 0.34
		halo.size = Vector2(d * 3.2, d * 3.2)
		halo.position = Vector2(vp.x * 0.66 - halo.size.x * 0.5, vp.y * 0.30 - halo.size.y * 0.5)
		var hc: Color = white(1.0).lerp(pc("accent"), 0.35)
		halo.modulate = Color(hc.r, hc.g, hc.b, 0.10)
		add_child(halo)
		var moon := TextureRect.new()
		moon.texture = disc
		moon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		moon.stretch_mode = TextureRect.STRETCH_SCALE
		moon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		moon.size = Vector2(d, d)
		moon.position = Vector2(vp.x * 0.66 - d * 0.5, vp.y * 0.30 - d * 0.5)
		moon.modulate = Color(0.94, 0.90, 0.86, 0.80)
		add_child(moon)
		var t := halo.create_tween().set_loops()
		t.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		t.tween_property(halo, "modulate:a", 0.18, 6.0)
		t.tween_property(halo, "modulate:a", 0.08, 6.5)

	## A stand of bamboo along the bottom — the duel garden he is standing in.
	## Thin, dark and swaying out of step with each other, so the lower band of
	## the frame has depth instead of ending at a horizon line.
	func _bamboo_row() -> void:
		var stalk := bake("ronin_bamboo", 24, 220, func(uv: Vector2) -> Color:
			var hw: float = lerpf(0.62, 0.40, (uv.y + 1.0) * 0.5)
			var a: float = 1.0 - smoothstep(hw - 0.10, hw, absf(uv.x))
			# Nodes: the joints, drawn as a thin swell every so often.
			var seg: float = fposmod((uv.y + 1.0) * 3.5, 1.0)
			var node: float = 1.0 - smoothstep(0.0, 0.06, absf(seg - 0.5))
			a = maxf(a, (1.0 - smoothstep(hw + 0.06 * node - 0.10, hw + 0.06 * node,
				absf(uv.x))) * node)
			if a <= 0.02:
				return Color(0, 0, 0, 0)
			# A hint of edge light down one side, so a stalk is a cylinder.
			var b: float = 0.10 + 0.55 * (1.0 - smoothstep(0.0, 0.22, absf(uv.x - hw * 0.55)))
			return Color(b, b, b, clampf(a, 0.0, 1.0)))
		# Tinted from the GROVE, not from the background: bg0 here is near-black,
		# and a dark bake times a near-black tint renders nothing.
		var ink := Color(0.13, 0.19, 0.15)
		for i in 9:
			var h: float = vp.y * randf_range(0.14, 0.30)
			var w: float = h * (24.0 / 220.0) * randf_range(1.6, 2.6)
			var pivot := Control.new()
			pivot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			pivot.position = Vector2(vp.x * (float(i) + randf_range(0.05, 0.95)) / 7.0, vp.y * 1.01)
			add_child(pivot)
			var s := TextureRect.new()
			s.texture = stalk
			s.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			s.stretch_mode = TextureRect.STRETCH_SCALE
			s.mouse_filter = Control.MOUSE_FILTER_IGNORE
			s.size = Vector2(w, h)
			s.position = Vector2(-w * 0.5, -h)
			s.modulate = Color(ink.r, ink.g, ink.b, randf_range(0.55, 0.95))
			pivot.add_child(s)
			var sw := pivot.create_tween().set_loops()
			sw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
			var amp: float = randf_range(0.012, 0.032) * (1.0 if i % 2 == 0 else -1.0)
			sw.tween_property(pivot, "rotation", amp, randf_range(4.5, 7.0))
			sw.tween_property(pivot, "rotation", -amp * 0.6, randf_range(5.0, 7.5))

	## The words he lives by, brushed down the screen in a vertical column the
	## way Japanese calligraphy is written — one virtue at a time, inked on,
	## held, and allowed to fade. The romaji sits beside it in small type, so
	## the column reads as a scroll rather than as decoration.
	func _virtue_words() -> void:
		var virtues := [["RECTITUDE", "gi"], ["COURAGE", "yu"], ["BENEVOLENCE", "jin"],
			["RESPECT", "rei"], ["HONESTY", "makoto"], ["HONOUR", "meiyo"],
			["LOYALTY", "chugi"], ["SELF-CONTROL", "jisei"]]
		# A one-slot Array, not an int: a lambda cannot write back to a captured
		# local, so the cursor has to live somewhere shared by reference or every
		# firing would write the same virtue.
		var cursor := [randi() % virtues.size()]
		var first := get_tree().create_timer(1.8)
		first.timeout.connect(func() -> void:
			if is_inside_tree():
				var p0: Array = virtues[int(cursor[0]) % virtues.size()]
				cursor[0] = int(cursor[0]) + 1
				_brush_word(String(p0[0]), String(p0[1])))
		every(6.5, 12.0, func() -> void:
			var pair: Array = virtues[int(cursor[0]) % virtues.size()]
			cursor[0] = int(cursor[0]) + 1
			_brush_word(String(pair[0]), String(pair[1])))

	## One virtue, written as a vertical column of letters with its romaji under
	## it, over a wet brush stroke that is painted on first.
	func _brush_word(word: String, romaji: String) -> void:
		var col := Control.new()
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(col)
		var ink: Color = white(1.0).lerp(pc("accent2"), 0.55)
		var x: float = vp.x * (0.11 if randf() < 0.5 else 0.89)
		var top: float = vp.y * randf_range(0.10, 0.26)
		var fs := int(maxf(vp.x * 0.036, 13.0))
		# The wet stroke the characters are written over.
		var stroke := TextureRect.new()
		stroke.texture = tex_round()
		stroke.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		stroke.stretch_mode = TextureRect.STRETCH_SCALE
		stroke.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stroke.size = Vector2(fs * 2.1, float(word.length()) * fs * 1.12 + fs)
		stroke.position = Vector2(x - stroke.size.x * 0.5, top - fs * 0.5)
		stroke.modulate = Color(ink.r, ink.g, ink.b, 0.0)
		col.add_child(stroke)
		# One letter per line, down the column — vertical writing.
		var letters: Array = []
		for i in word.length():
			var lbl := Label.new()
			lbl.text = word[i]
			lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			lbl.add_theme_color_override("font_color", ink)
			lbl.add_theme_font_size_override("font_size", fs)
			lbl.modulate = Color(1, 1, 1, 0.0)
			if ThemeManager.display_font:
				lbl.add_theme_font_override("font", ThemeManager.display_font)
			lbl.position = Vector2(x - fs * 0.34, top + float(i) * fs * 1.12)
			lbl.rotation = randf_range(-0.05, 0.05)
			col.add_child(lbl)
			letters.append(lbl)
		var rom := Label.new()
		rom.text = romaji
		rom.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rom.add_theme_color_override("font_color", ink)
		rom.add_theme_font_size_override("font_size", int(float(fs) * 0.52))
		rom.modulate = Color(1, 1, 1, 0.0)
		if ThemeManager.ui_font:
			rom.add_theme_font_override("font", ThemeManager.ui_font)
		rom.position = Vector2(x - fs * 0.5, top + float(word.length()) * fs * 1.12 + fs * 0.2)
		col.add_child(rom)
		# The brush lands, the letters come down one after another, the whole
		# column holds, then the ink is allowed to dry out of sight.
		var tw := col.create_tween()
		tw.tween_property(stroke, "modulate:a", 0.08, 0.25)
		# Written FAINT. At full alpha in the game's rounded display face this
		# was a bright cartoon word standing next to a samurai; a virtue is a
		# thing brushed on a scroll and left there, not a headline.
		for i in letters.size():
			var lbl := letters[i] as Label
			tw.tween_property(lbl, "modulate:a", 0.30, 0.09)
		tw.tween_property(rom, "modulate:a", 0.26, 0.25)
		tw.tween_interval(2.4)
		tw.set_parallel(true)
		tw.tween_property(col, "modulate:a", 0.0, 1.8)
		tw.chain().tween_callback(col.queue_free)


	## A five-petaled sakura petal (single petal, notched tip) for the drift.
	func _tex_petal() -> Texture2D:
		return bake("ktn_petal", 24, 24, func(uv: Vector2) -> Color:
			var pxy := Vector2(uv.x, uv.y * 1.35)
			var a := 1.0 - smoothstep(0.68, 0.95, pxy.length())
			# the petal's heart-notch at its tip
			a *= smoothstep(0.08, 0.28, (uv - Vector2(0.0, -0.85)).length())
			if a <= 0.03:
				return Color(0, 0, 0, 0)
			var b := 0.85 + 0.15 * (-uv.y)
			return Color(clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), a))

	## The ronin's katana resting sheathed near the bottom edge — the still centre
	## the slashes explode out of. Breathes almost imperceptibly.
	## The sheathed katana silhouette: tsuka (wrapped grip), tsuba (guard), and
	## the gently curved saya sweeping to the kojiri tip. Tip at the right.
	func _tex_saya() -> Texture2D:
		return bake("ktn_saya", 256, 44, func(uv: Vector2) -> Color:
			var t := (uv.x + 1.0) * 0.5             # 0 = pommel, 1 = tip
			# centreline curves gently upward toward the tip
			var cy := 0.25 - 0.55 * pow(maxf(t - 0.24, 0.0) / 0.76, 1.5)
			var hw := 0.30                           # the grip
			var b := 0.30                            # grip: dark wrap
			if absf(t - 0.25) < 0.025:
				hw = 0.62                            # the tsuba disc
				b = 0.55
			elif t > 0.275:
				hw = 0.30 - 0.16 * (t - 0.275) / 0.725   # the saya, tapering
				b = 0.42
			var dy := uv.y - cy
			var a := 1.0 - smoothstep(hw - 0.14, hw + 0.05, absf(dy))
			if a <= 0.03:
				return Color(0, 0, 0, 0)
			# lit along the top edge, like lacquer catching the moon
			b += 0.30 * (1.0 - smoothstep(-hw, hw * 0.4, dy))
			# the grip's diamond wrap
			if t < 0.225:
				b *= 0.75 + 0.25 * absf(sin(t * 90.0))
			return Color(clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), a))

	func _glint() -> void:
		var g := TextureRect.new()
		g.texture = tex_round()
		g.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		g.stretch_mode = TextureRect.STRETCH_SCALE
		g.mouse_filter = Control.MOUSE_FILTER_IGNORE
		g.size = Vector2(vp.x * 0.35, vp.y * 1.6)
		g.pivot_offset = g.size * 0.5
		g.rotation = deg_to_rad(24.0)
		g.position = Vector2(-g.size.x, -vp.y * 0.3)
		var steel: Color = pc("accent2")
		g.modulate = Color(steel.r, steel.g, steel.b, 0.0)
		add_child(g)
		var tw := g.create_tween().set_parallel(true)
		tw.set_trans(Tween.TRANS_SINE)
		tw.tween_property(g, "position:x", vp.x + g.size.x * 0.5, 2.2)
		tw.tween_property(g, "modulate:a", 0.08, 1.1)
		tw.parallel().tween_property(g, "modulate:a", 0.0, 1.1).set_delay(1.1)
		tw.chain().tween_callback(g.queue_free)

	func _slash(centre: Vector2, angle: float, length: float, strong: bool) -> void:
		var crimson: Color = pc("accent")
		# The blade, chased by two motion-blur afterimages a beat behind it.
		for gi in 3:
			var blade := TextureRect.new()
			blade.texture = tex_streak()
			blade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			blade.mouse_filter = Control.MOUSE_FILTER_IGNORE
			blade.size = Vector2(9.0 * sc, length)
			blade.pivot_offset = blade.size * 0.5
			blade.rotation = angle + PI * 0.5   # the streak texture is vertical
			var ghost_off := Vector2.from_angle(angle + PI * 0.5) * float(gi) * 8.0 * sc
			blade.position = centre - blade.size * 0.5 + ghost_off
			blade.modulate = Color(1, 1, 1, 0.0)
			add_child(blade)
			var peak: float = [0.95, 0.34, 0.15][gi]
			var tw := blade.create_tween()
			if gi > 0:
				tw.tween_interval(float(gi) * 0.04)
			tw.tween_property(blade, "modulate:a", peak, 0.04)
			tw.set_parallel(true)
			tw.tween_property(blade, "modulate", Color(crimson.r, crimson.g, crimson.b, 0.0), 0.28)
			tw.tween_property(blade, "scale", Vector2(2.6, 1.0), 0.28)
			tw.chain().tween_callback(blade.queue_free)
		# A bright edge-point racing along the cut.
		var tip := TextureRect.new()
		tip.texture = tex_dot()
		tip.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var d: float = 26.0 * sc
		tip.size = Vector2(d, d)
		var axis := Vector2.from_angle(angle)
		tip.position = centre - axis * length * 0.5 - tip.size * 0.5
		tip.modulate = white(1.0)
		add_child(tip)
		var tt := tip.create_tween().set_parallel(true)
		tt.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tt.tween_property(tip, "position", centre + axis * length * 0.5 - tip.size * 0.5, 0.14)
		tt.tween_property(tip, "modulate:a", 0.0, 0.20)
		tt.chain().tween_callback(tip.queue_free)
		# Steel sparks off the edge.
		var sparks := burst(centre, {"tex": tex_dot(),
			"iramp": grad([white(1.0), Color(0.85, 0.9, 1.0), crimson]),
			"amount": 22 if strong else 14, "lifetime": 0.55,
			"vmin": 140.0, "vmax": 420.0, "gravity": 380.0, "smin": 0.2, "smax": 0.7})
		sparks.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		sparks.emission_rect_extents = Vector2(length * 0.4, 2.0)
		sparks.rotation = angle
		if strong:
			flash(white(1.0), 0.10, 0.22)
			# The world PARTS along the cut: a sliver of light opens, then seals.
			var gap := ColorRect.new()
			gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
			gap.size = Vector2(length, 3.0 * sc)
			gap.pivot_offset = gap.size * 0.5
			gap.rotation = angle
			gap.position = centre - gap.size * 0.5
			gap.color = Color(1, 1, 1, 0.0)
			add_child(gap)
			var gt := gap.create_tween()
			gt.tween_property(gap, "color:a", 0.85, 0.05)
			gt.set_parallel(true)
			gt.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			gt.tween_property(gap, "scale", Vector2(1.0, 5.0), 0.16)
			gt.tween_property(gap, "color:a", 0.0, 0.30)
			gt.chain().tween_callback(gap.queue_free)

	func on_swipe(dir: Vector2i) -> void:
		var angle := Vector2(dir).angle()
		_slash(vp * 0.5 + Vector2(randf_range(-60, 60), randf_range(-40, 40)) * sc,
			angle, vp.length() * 1.05, true)

	func on_merge(pos: Vector2, value: int, _tint: Color) -> void:
		var l: float = (240.0 + minf(float(value), 2048.0) * 0.08) * sc
		_slash(pos, deg_to_rad(-38.0), l, false)
		var second := create_tween()
		second.tween_interval(0.07)
		second.tween_callback(func(): _slash(pos, deg_to_rad(42.0), l * 0.9, value >= 256))
		# A master's stroke earns the ensō — the brush ring, drawn in one breath.
		if value >= 512:
			_enso(pos)

	## The ensō flash: an imperfect ink circle blooming at the cut, then gone.
	func _enso(pos: Vector2) -> void:
		var ring := TextureRect.new()
		ring.texture = _tex_enso()
		ring.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var d: float = 300.0 * sc
		ring.size = Vector2(d, d)
		ring.pivot_offset = ring.size * 0.5
		ring.position = pos - ring.size * 0.5
		ring.rotation = randf_range(-0.4, 0.4)
		ring.scale = Vector2(0.6, 0.6)
		var ink: Color = pc("text")
		ring.modulate = Color(ink.r, ink.g, ink.b, 0.0)
		add_child(ring)
		var tw := ring.create_tween()
		tw.set_parallel(true).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(ring, "scale", Vector2.ONE, 0.5)
		tw.tween_property(ring, "modulate:a", 0.5, 0.10)
		tw.parallel().tween_property(ring, "modulate:a", 0.0, 0.55).set_delay(0.25)
		tw.chain().tween_callback(ring.queue_free)

	## An ensō: a brush ring whose stroke swells and thins, left open at the top
	## right — the classic single-breath circle.
	func _tex_enso() -> Texture2D:
		return bake("ktn_enso", 96, 96, func(uv: Vector2) -> Color:
			var r := uv.length()
			var ang := atan2(uv.y, uv.x)
			var th := 0.09 + 0.05 * sin(ang + 1.3)                     # brush pressure
			var band := exp(-pow((r - 0.68) / maxf(th, 0.02), 2.0))
			var open := smoothstep(0.10, 0.55, absf(atan2(sin(ang + 0.9), cos(ang + 0.9))))
			var a := band * open
			if a <= 0.03:
				return Color(0, 0, 0, 0)
			return Color(1, 1, 1, clampf(a, 0.0, 1.0)))


# =============================================================================
# Clockwork — a brass gear train fills the backdrop's corners, a pendulum swings
# below, steam breathes from the works. Swipes ratchet every gear one tick in
# the swipe's direction; merges vent steam and pop loose cogs.
# =============================================================================
class Gears extends Base:
	var _gears: Array = []         # {node, speed: float, rot: float, kick: float}
	## The dials. Each is {sec, min, hour, rate} — three hand nodes plus how fast
	## this clock runs, because clocks that all agree are furniture and clocks
	## that disagree are a THREAT. The second hand steps once a second rather
	## than sweeping: the tick is the whole point of the room.
	var _faces: Array = []
	var _pendulums: Array = []     # {node, period, amp, ph}
	var _t: float = 0.0
	var _strain: float = 0.0       # 0..1 — the works hesitating before they snap on

	func _tex_gear(id: String, teeth: float) -> Texture2D:
		return bake(id, 72, 72, func(uv: Vector2) -> Color:
			var r := uv.length()
			var ang := atan2(uv.y, uv.x)
			var tooth := 0.74 + 0.16 * smoothstep(-0.35, 0.35, sin(ang * teeth))
			var a := 1.0 - smoothstep(tooth - 0.035, tooth + 0.02, r)
			a *= smoothstep(0.13, 0.18, r)   # the axle hole
			# Spoke windows: four arcs cut from the mid-face.
			var window := smoothstep(0.32, 0.38, r) * (1.0 - smoothstep(0.54, 0.60, r)) \
				* smoothstep(-0.2, 0.2, sin(ang * 4.0 + 0.6))
			a *= 1.0 - window * 0.9
			if a <= 0.03:
				return Color(0, 0, 0, 0)
			var b := clampf(0.62 + (-uv.y) * 0.16 - smoothstep(0.55, 0.95, r) * 0.14, 0.25, 1.0)
			b += (1.0 - smoothstep(0.18, 0.30, r)) * 0.18   # bright hub
			return Color(clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), a))

	func _build() -> void:
		var brass: Color = pc("accent")
		# [x, y, diameter (of vp.x), teeth, tint-shift, escapement?] — corners +
		# edges, never the middle. The first TWO gears actually MESH: tangent,
		# counter-rotating, speeds in exact inverse ratio to their diameters (the
		# speed formula below already guarantees the ratio). The mid-left gear is
		# the ESCAPEMENT: it dwells, then snaps one tooth — the clock's tick.
		var layout := [
			[0.10, 0.085, 0.34, 8.0, 0.0], [0.247, 0.145, 0.14, 6.0, 0.02],
			[0.32, 0.030, 0.20, 6.0, 0.12],
			[0.92, 0.060, 0.26, 8.0, -0.08], [0.04, 0.52, 0.18, 6.0, 0.10, 1.0],
			[0.10, 0.93, 0.30, 8.0, -0.06], [0.90, 0.90, 0.36, 8.0, 0.06],
			[0.66, 0.975, 0.18, 6.0, 0.14],
		]
		var mesh_dir := 1.0
		for e_v in layout:
			var e: Array = e_v
			var node := TextureRect.new()
			node.texture = _tex_gear("gear%d" % int(float(e[3])), float(e[3]))
			node.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			node.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var d: float = vp.x * float(e[2])
			node.size = Vector2(d, d)
			node.pivot_offset = node.size * 0.5
			node.position = Vector2(float(e[0]) * vp.x, float(e[1]) * vp.y) - node.size * 0.5
			node.rotation = randf() * TAU
			var tint := brass.lerp(pc("gold"), 0.3 + float(e[4]))
			node.modulate = Color(tint.r, tint.g, tint.b, 0.55)
			add_child(node)
			# Meshing look: adjacent gears counter-rotate, small gears spin faster
			# (ω ∝ 1/d — exactly what real meshing demands).
			_gears.append({"node": node, "speed": mesh_dir * 0.55 * (0.30 / float(e[2])),
				"rot": node.rotation, "kick": 0.0, "escape": e.size() > 5})
			mesh_dir = -mesh_dir
		_pendulum()
		_clock_faces()
		_extra_pendulums()
		_watchroom()
		edge_glow(pc("gold"), 0.04, 0.11, false)
		# The works breathe: steam sighs from a bottom vent every so often.
		every(4.0, 8.0, func():
			burst(Vector2(vp.x * (0.2 if randf() < 0.5 else 0.8), vp.y * 1.02),
				{"tex": tex_round(), "color": white(0.8), "alpha": 0.16, "amount": 6,
				"lifetime": 2.2, "vmin": 40.0, "vmax": 110.0, "spread": 26.0,
				"smin": 0.6, "smax": 1.6}))
		set_process(true)

	func _pendulum() -> void:
		var pivot := Control.new()
		pivot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pivot.position = Vector2(vp.x * 0.5, vp.y * 0.70)
		add_child(pivot)
		var rod := ColorRect.new()
		rod.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var brass: Color = pc("accent")
		rod.color = Color(brass.r, brass.g, brass.b, 0.40)
		rod.size = Vector2(5.0 * sc, vp.y * 0.22)
		rod.position = Vector2(-2.5 * sc, 0)
		pivot.add_child(rod)
		var bob := TextureRect.new()
		bob.texture = tex_dot()
		bob.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bob.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var d: float = 54.0 * sc
		bob.size = Vector2(d, d)
		bob.position = Vector2(-d * 0.5, vp.y * 0.22 - d * 0.4)
		bob.modulate = Color(brass.r, brass.g, brass.b, 0.75)
		pivot.add_child(bob)
		pivot.rotation = -0.30
		var tw := pivot.create_tween().set_loops()
		tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		tw.tween_property(pivot, "rotation", 0.30, 1.2)
		tw.tween_property(pivot, "rotation", -0.30, 1.2)

	## The dials on the wall. Four clocks at four depths, each running at its own
	## rate and each showing a different time — the second hands STEP rather than
	## sweep, and because the rates differ the ticks drift in and out of unison.
	## That drift is the suspense: a room of clocks that agree is a shop window.
	func _clock_faces() -> void:
		var face := bake("clock_face", 128, 128, func(uv: Vector2) -> Color:
			var r := uv.length()
			if r > 1.0:
				return Color(0, 0, 0, 0)
			var ang := atan2(uv.y, uv.x)
			# The bezel ring.
			if r > 0.90:
				var bz: float = 0.55 + 0.45 * clampf(0.5 - uv.y * 0.6 - uv.x * 0.3, 0.0, 1.0)
				return Color(bz, bz, bz, 1.0 - smoothstep(0.97, 1.0, r))
			# The dial, dark in the middle and lifting toward the rim.
			var b: float = 0.12 + 0.10 * r
			# Minute ticks, and longer hour marks every fifth.
			var mt: float = absf(fposmod(ang * 60.0 / TAU + 0.5, 1.0) - 0.5) * 2.0
			var ht: float = absf(fposmod(ang * 12.0 / TAU + 0.5, 1.0) - 0.5) * 2.0
			if r > 0.80 and mt > 0.86:
				b = 0.55
			if r > 0.70 and ht > 0.90:
				b = 0.92
			# A glass highlight across the upper left.
			b += (1.0 - smoothstep(0.10, 0.75,
				Vector2(uv.x + 0.34, uv.y + 0.40).length())) * 0.13
			return Color(clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0), clampf(b, 0.0, 1.0),
				1.0 - smoothstep(0.97, 1.0, r)))
		var brass: Color = pc("accent").lerp(pc("gold"), 0.4)
		# [x-frac, y-frac, diameter-frac of vp.x, alpha, rate]
		var spots := [[0.30, 0.135, 0.30, 0.85, 1.00], [0.80, 0.30, 0.20, 0.62, 0.93],
			[0.18, 0.72, 0.235, 0.72, 1.08], [0.78, 0.86, 0.17, 0.55, 0.87]]
		for e_v in spots:
			var e: Array = e_v
			var d: float = vp.x * float(e[2])
			var centre := Vector2(float(e[0]) * vp.x, float(e[1]) * vp.y)
			var a: float = float(e[3])
			var dial := TextureRect.new()
			dial.texture = face
			dial.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			dial.stretch_mode = TextureRect.STRETCH_SCALE
			dial.mouse_filter = Control.MOUSE_FILTER_IGNORE
			dial.size = Vector2(d, d)
			dial.position = centre - dial.size * 0.5
			dial.modulate = Color(brass.r, brass.g, brass.b, a)
			add_child(dial)
			# The three hands. Each is a bar pivoting on the dial's centre, so
			# its rotation is simply the time it is showing.
			var hands: Dictionary = {"rate": float(e[4])}
			var specs := [["hour", 0.44, 0.030, 0.95], ["min", 0.70, 0.022, 0.95],
				["sec", 0.80, 0.011, 0.75]]
			for h_v in specs:
				var h: Array = h_v
				var pivot := Control.new()
				pivot.mouse_filter = Control.MOUSE_FILTER_IGNORE
				pivot.position = centre
				pivot.rotation = randf() * TAU
				add_child(pivot)
				var bar := ColorRect.new()
				bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
				var hc: Color = brass if String(h[0]) != "sec" else Color(0.82, 0.28, 0.22)
				bar.color = Color(hc.r, hc.g, hc.b, a * float(h[3]))
				bar.size = Vector2(d * float(h[2]), d * float(h[1]) * 0.5)
				bar.position = Vector2(-bar.size.x * 0.5, -bar.size.y)
				pivot.add_child(bar)
				hands[String(h[0])] = pivot
			# The cap over the hand roots.
			var cap := TextureRect.new()
			cap.texture = tex_dot()
			cap.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cap.size = Vector2(d * 0.10, d * 0.10)
			cap.position = centre - cap.size * 0.5
			cap.modulate = Color(brass.r, brass.g, brass.b, a)
			add_child(cap)
			# Every clock starts at a different time, which is the other half of
			# why the room reads as wrong.
			hands["off"] = randf() * 43200.0
			_faces.append(hands)

	## Two more pendulums, longer and slower than the main one, hung at the edges.
	## Their periods are deliberately incommensurate with each other, so the room
	## never settles into one rhythm.
	func _extra_pendulums() -> void:
		var brass: Color = pc("accent").lerp(pc("gold"), 0.35)
		# [x-frac, length-frac of vp.y, period, amplitude, alpha]
		for e_v in [[0.055, 0.46, 2.30, 0.20, 0.55], [0.945, 0.36, 1.73, 0.26, 0.48]]:
			var e: Array = e_v
			var pivot := Control.new()
			pivot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			pivot.position = Vector2(float(e[0]) * vp.x, -vp.y * 0.02)
			add_child(pivot)
			var ln: float = vp.y * float(e[1])
			var a: float = float(e[4])
			var rod := ColorRect.new()
			rod.mouse_filter = Control.MOUSE_FILTER_IGNORE
			rod.color = Color(brass.r, brass.g, brass.b, a * 0.8)
			rod.size = Vector2(maxf(vp.x * 0.006, 1.5), ln)
			rod.position = Vector2(-rod.size.x * 0.5, 0.0)
			pivot.add_child(rod)
			var bob := TextureRect.new()
			bob.texture = tex_dot()
			bob.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			bob.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var bd: float = vp.x * 0.075
			bob.size = Vector2(bd, bd)
			bob.position = Vector2(-bd * 0.5, ln - bd * 0.35)
			bob.modulate = Color(brass.r, brass.g, brass.b, a)
			pivot.add_child(bob)
			_pendulums.append({"node": pivot, "period": float(e[2]),
				"amp": float(e[3]), "ph": randf() * TAU})

	## The room they hang in: a dim vignette that breathes, a shaft of light with
	## dust turning in it, and the occasional shiver as the works take up slack.
	func _watchroom() -> void:
		# The shaft — one hard light in a dark room is the whole genre.
		var shaft := TextureRect.new()
		shaft.texture = tex_round()
		shaft.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		shaft.stretch_mode = TextureRect.STRETCH_SCALE
		shaft.mouse_filter = Control.MOUSE_FILTER_IGNORE
		shaft.size = Vector2(vp.x * 0.42, vp.y * 1.5)
		shaft.pivot_offset = shaft.size * 0.5
		shaft.rotation = deg_to_rad(-17.0)
		shaft.position = Vector2(vp.x * 0.30 - shaft.size.x * 0.5, -vp.y * 0.22)
		shaft.modulate = Color(1.0, 0.94, 0.78, 0.05)
		add_child(shaft)
		var st := shaft.create_tween().set_loops()
		st.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		st.tween_property(shaft, "modulate:a", 0.10, 6.0)
		st.tween_property(shaft, "modulate:a", 0.04, 6.5)
		# Dust turning in the light.
		field({"tex": tex_dot(), "color": Color(1.0, 0.93, 0.76), "alpha": 0.22,
			"amount": 26, "lifetime": 12.0, "dir": Vector3(0.1, -1, 0), "spread": 60.0,
			"vmin": 3.0, "vmax": 12.0, "smin": 0.16, "smax": 0.5, "turb": 0.5})
		# The shiver: every so often the train binds, hesitates, and lets go.
		every(7.0, 15.0, func() -> void:
			var tw := create_tween()
			tw.tween_method(func(v: float) -> void: _strain = v, 0.0, 1.0, 0.9)
			tw.tween_method(func(v: float) -> void: _strain = v, 1.0, 0.0, 0.18)
			# ...and when it lets go, every gear takes the jolt at once.
			tw.tween_callback(func() -> void:
				for g_v in _gears:
					(g_v as Dictionary)["kick"] = 1.2))

	func on_swipe(dir: Vector2i) -> void:
		# One hard tick through the whole train, direction taken from the swipe.
		var s: float = 1.0 if (dir.x + dir.y) > 0 else -1.0
		for g_v in _gears:
			var g: Dictionary = g_v
			var target: float = s * signf(float(g["speed"]))
			var tw := create_tween()
			tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
			tw.tween_method(func(v: float): g["kick"] = v, target * 0.5, 0.0, 0.45)

	func on_merge(pos: Vector2, value: int, _tint: Color) -> void:
		# Steam bursts from the merge + a few loose cogs pop and tumble.
		burst(pos, {"tex": tex_round(), "color": white(0.9), "alpha": 0.22,
			"amount": 7, "lifetime": 1.4, "vmin": 60.0, "vmax": 160.0, "spread": 40.0,
			"smin": 0.5, "smax": 1.3})
		var brass: Color = pc("accent")
		burst(pos, {"tex": _tex_gear("gear6", 6.0), "color": brass, "alpha": 0.95,
			"amount": 4 + mini(int(float(value) / 512.0), 4), "lifetime": 1.1,
			"vmin": 120.0, "vmax": 300.0, "gravity": 560.0, "spin": 5.0,
			"smin": 0.25, "smax": 0.6})
		# The nearest gear takes the jolt — a springy coil bounce.
		var nearest: Dictionary = {}
		var best := INF
		for g_v in _gears:
			var g: Dictionary = g_v
			var node: TextureRect = g["node"]
			var d2: float = (node.position + node.size * 0.5 - pos).length_squared()
			if d2 < best:
				best = d2
				nearest = g
		if not nearest.is_empty():
			var node: TextureRect = nearest["node"]
			node.scale = Vector2(1.14, 1.14)
			var tw := node.create_tween()
			tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
			tw.tween_property(node, "scale", Vector2.ONE, 0.7)

	func _process(delta: float) -> void:
		var scoped: bool = Engine.has_meta("bench_scope")  # perf-bench scope, regression/perf/SPEC.md #4.2
		if scoped:
			Engine.get_meta("bench_scope").call(true, "RewardFx._process")
		_t += delta
		# B2 — gear positions are FIXED (corners and edges, set once in _build),
		# so a gear whose rect sits wholly outside the grid window can never
		# enter it: the clipped instance skips its per-frame rotation write —
		# the write dirties the canvas item for pixels FxClip scissors anyway.
		# The pad covers the rotating texture's AABB growth (the gear disc is
		# inscribed, but sqrt(2)·size is the hard bound), the merge-jolt scale
		# (×1.14) and bilinear bleed; the escapement's rotation is a pure
		# function of _t, and a stopped plain gear is never visible again, so
		# nothing inside the clip can diverge.
		# The dials. A second hand STEPS — quantising to whole seconds is what
		# makes a clock tick instead of glide, and the ticking is the theme.
		# `_strain` drags every clock in the room at once when the train binds.
		var drag := 1.0 - _strain * 0.92
		for f_v in _faces:
			var f: Dictionary = f_v
			var clock: float = float(f["off"]) + _t * float(f["rate"]) * drag
			(f["sec"] as Control).rotation = floorf(clock) * (TAU / 60.0)
			(f["min"] as Control).rotation = clock * (TAU / 3600.0)
			(f["hour"] as Control).rotation = clock * (TAU / 43200.0)
		# The extra pendulums swing on their own periods — driven here rather
		# than by tweens so `_strain` can slow them with everything else.
		for p_v in _pendulums:
			var pd: Dictionary = p_v
			var w: float = TAU / maxf(float(pd["period"]), 0.01)
			(pd["node"] as Control).rotation = \
				sin(_t * w * drag + float(pd["ph"])) * float(pd["amp"])
		var cw := clip_window()
		var clipped := cw.size.x > 0.0
		for g_v in _gears:
			var g: Dictionary = g_v
			var node: TextureRect = g["node"]
			if clipped and not cw.grow(node.size.x * 0.5 + 8.0 * sc) \
					.intersects(Rect2(node.position, node.size)):
				continue
			if bool(g["escape"]):
				# The escapement: dwell … then snap one tooth. Tick. Tock.
				var period := 0.9
				var ph: float = fposmod(_t, period) / period
				var steps: float = floor(_t / period)
				var snap: float = smoothstep(0.82, 0.96, ph)
				node.rotation = float(g["rot"]) \
					+ (steps + snap) * (TAU / 6.0) * signf(float(g["speed"])) + float(g["kick"])
				continue
			var rot: float = float(g["rot"]) + float(g["speed"]) * delta
			g["rot"] = rot
			node.rotation = rot + float(g["kick"])
		if scoped:
			Engine.get_meta("bench_scope").call(false, "RewardFx._process")


# =============================================================================
# Sanctum — a stained-glass rose window high over the board, god-rays sweeping
# through drifting dust. Merges send a beam of light from the window to the
# merge point, bursting into jewel-toned caustics; swipes sway the rays.
# =============================================================================
class StainedGlass extends Base:
	const JEWELS := [Color("E84A5F"), Color("F0A83C"), Color("46B87A"),
		Color("3E8FE0"), Color("8A5BD6"), Color("E070B0")]
	var _window: TextureRect
	var _rays: Array = []          # ray TextureRects (for the swipe sway)
	var _wc: Vector2               # window centre, px

	## Baked at 320px (it covers ~2/3 of the screen width) so the lead lines and
	## pane edges stay crisp instead of upscale-blocky.
	func _tex_rose() -> Texture2D:
		return bake("rosewin_hd", 320, 320, func(uv: Vector2) -> Color:
			var r := uv.length()
			if r > 0.99:
				return Color(0, 0, 0, 0)
			var ang := atan2(uv.y, uv.x) + PI
			var sector := int(floor(ang / TAU * 12.0)) % 12
			var ring := int(floor(r * 3.2))
			# Lead lines between panes + the stone rim + the hub rosette.
			var sec_f := absf(fposmod(ang, TAU / 12.0) - TAU / 24.0)
			var ring_f := absf(fposmod(r * 3.2, 1.0) - 0.5)
			var lead := 1.0 - minf(smoothstep(0.0, 0.05, sec_f * r), smoothstep(0.0, 0.10, ring_f))
			var rim := smoothstep(0.90, 0.93, r)
			if rim > 0.5 or (lead > 0.5 and r > 0.16):
				return Color(0.08, 0.05, 0.13, 1.0)
			if r < 0.16:
				return Color(0.95, 0.78, 0.42, 1.0)   # the golden heart
			var jewel: Color = JEWELS[(sector + ring * 2) % JEWELS.size()]
			# Glassy variation so panes read lit, not flat.
			var b := 0.72 + 0.28 * sin(float(sector) * 2.3 + float(ring) * 1.7)
			return Color(jewel.r * b, jewel.g * b, jewel.b * b, 1.0))

	func _build() -> void:
		var d: float = vp.x * 0.62
		_wc = Vector2(vp.x * 0.5, vp.y * 0.16)
		# The halo breathing behind the glass.
		var halo := TextureRect.new()
		halo.texture = tex_round()
		halo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var hd: float = d * 2.1
		halo.size = Vector2(hd, hd)
		halo.position = _wc - halo.size * 0.5
		var acc: Color = pc("accent")
		halo.modulate = Color(acc.r, acc.g, acc.b, 0.12)
		add_child(halo)
		var htw := halo.create_tween().set_loops()
		htw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		htw.tween_property(halo, "modulate:a", 0.20, 5.0)
		htw.tween_property(halo, "modulate:a", 0.10, 5.5)
		_window = TextureRect.new()
		_window.texture = _tex_rose()
		_window.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_window.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_window.size = Vector2(d, d)
		_window.pivot_offset = _window.size * 0.5
		_window.position = _wc - _window.size * 0.5
		_window.modulate = Color(1, 1, 1, 0.9)
		add_child(_window)
		var wtw := _window.create_tween().set_loops()
		wtw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		wtw.tween_property(_window, "modulate:a", 1.0, 4.0)
		wtw.tween_property(_window, "modulate:a", 0.85, 4.5)
		# God-rays falling from the window through the nave.
		for rot in [-0.34, -0.02, 0.30]:
			var ray := TextureRect.new()
			ray.texture = tex_round()
			ray.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ray.stretch_mode = TextureRect.STRETCH_SCALE
			ray.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var w: float = vp.x * 0.17
			var h: float = vp.y * 1.15
			ray.size = Vector2(w, h)
			ray.pivot_offset = Vector2(w * 0.5, 0.0)
			ray.position = _wc - Vector2(w * 0.5, 0.0)
			ray.rotation = float(rot)
			var warm: Color = pc("gold").lerp(white(1.0), 0.3)
			ray.modulate = Color(warm.r, warm.g, warm.b, 0.05)
			add_child(ray)
			_rays.append(ray)
			var rtw := ray.create_tween().set_loops()
			rtw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
			rtw.tween_property(ray, "modulate:a", 0.11, randf_range(4.0, 6.0))
			rtw.tween_property(ray, "modulate:a", 0.04, randf_range(4.0, 6.5))
		# Dust hanging in the light.
		field({"tex": tex_dot(), "color": pc("gold").lerp(white(1.0), 0.4), "alpha": 0.30,
			"amount": 40, "lifetime": 12.0, "dir": Vector3(0.1, -1, 0), "spread": 180.0,
			"vmin": 3.0, "vmax": 10.0, "smin": 0.2, "smax": 0.6, "turb": 0.5, "twinkle": true})
		_nave()

	func on_swipe(dir: Vector2i) -> void:
		# The light leans with the player's hand, then settles home.
		var lean: float = float(dir.x) * 0.10 + float(dir.y) * 0.04
		for i in _rays.size():
			var ray: TextureRect = _rays[i]
			var home: float = [-0.34, -0.02, 0.30][i]
			var tw := ray.create_tween()
			tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			tw.tween_property(ray, "rotation", home + lean, 0.35)
			tw.set_trans(Tween.TRANS_SINE)
			tw.tween_property(ray, "rotation", home, 1.4)

	func on_merge(pos: Vector2, value: int, _tint: Color) -> void:
		# A beam from the rose window to the merge, refracting into jewels.
		var to := pos - _wc
		var beam := TextureRect.new()
		beam.texture = tex_round()
		beam.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		beam.stretch_mode = TextureRect.STRETCH_SCALE
		beam.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var w: float = 54.0 * sc
		beam.size = Vector2(w, to.length())
		beam.pivot_offset = Vector2(w * 0.5, 0.0)
		beam.position = _wc - Vector2(w * 0.5, 0.0)
		beam.rotation = to.angle() - PI * 0.5
		var warm: Color = pc("gold").lerp(white(1.0), 0.45)
		beam.modulate = Color(warm.r, warm.g, warm.b, 0.0)
		add_child(beam)
		var tw := beam.create_tween()
		tw.tween_property(beam, "modulate:a", 0.5, 0.08)
		tw.tween_property(beam, "modulate:a", 0.0, 0.45)
		tw.tween_callback(beam.queue_free)
		# The window flares as the light passes through it.
		if is_instance_valid(_window):
			var ftw := _window.create_tween()
			ftw.tween_property(_window, "modulate", Color(1.25, 1.2, 1.1, 1.0), 0.08)
			ftw.tween_property(_window, "modulate", Color(1, 1, 1, 0.9), 0.4)
		# Jewel caustics scatter at the merge.
		burst(pos, {"tex": tex_square(), "iramp": grad(JEWELS),
			"amount": 18 + mini(int(float(value) / 256.0), 14), "lifetime": 0.8,
			"vmin": 90.0, "vmax": 280.0, "gravity": 160.0, "spin": 4.0,
			"smin": 0.6, "smax": 1.5})
		ripple(pos, pc("accent").lerp(white(1.0), 0.3), 260.0 * sc, 0.55)

	## The nave the rose window is set into: a colonnade of gothic arches
	## receding into the dark, a stone floor, and the pool of coloured light the
	## window throws onto it. Without this the window hung in an empty void.
	func _nave() -> void:
		var stone := Color(0.16, 0.15, 0.24)
		var arch := bake("sanctum_arch", 140, 300, func(uv: Vector2) -> Color:
			const AR := 2.143
			var sy := uv.y * AR
			var a := 0.0
			var b := 0.5
			# A gothic bay is mostly VOID: two slim piers with a pointed opening
			# between them. Filling the arch band solid (the first pass) turned
			# the colonnade into a row of blocks.
			var pier_x := 0.82
			var pier_w := 0.17
			for s_v in [-1.0, 1.0]:
				var sgn: float = s_v
				# The pier, with a slight batter and a moulded cap.
				var t := clampf((sy + 2.143) / 4.286, 0.0, 1.0)
				var w := pier_w * lerpf(0.88, 1.12, t)
				if absf(uv.x - sgn * pier_x) < w and sy > -1.34:
					a = 1.0
					b = 0.34 + 0.34 * clampf(0.5 - (uv.x - sgn * pier_x) / w * 0.5, 0.0, 1.0)
				# The capital.
				if absf(uv.x - sgn * pier_x) < w * 1.5 and absf(sy + 1.30) < 0.11:
					a = 1.0
					b = 0.62
			# The pointed arch: two arcs springing from the capitals, meeting at
			# a point. Only the BAND is stone; inside it is the opening.
			var spring := -1.30
			var lc := Vector2(uv.x + 0.40, sy - spring)
			var rc := Vector2(uv.x - 0.40, sy - spring)
			var ring := minf(absf(lc.length() - 1.10), absf(rc.length() - 1.10))
			var inside_head: bool = sy < spring
			if inside_head and ring < 0.19 and absf(uv.x) < 1.0:
				a = 1.0
				b = 0.46 + 0.24 * clampf(0.5 - uv.x * 0.9, 0.0, 1.0)
			# The hood mould over the arch.
			if inside_head and absf(minf(lc.length(), rc.length()) - 1.36) < 0.07:
				a = 1.0
				b = 0.58
			# The plinth the piers stand on.
			if sy > 1.88 and absf(uv.x) < 1.0:
				a = 1.0
				b = 0.26
			if a <= 0.02:
				return Color(0, 0, 0, 0)
			return Color(b, b, b, a))
		# Three bays across the nave, the centre one nearest.
		#
		# SIZE IS A CONTRACT HERE. BoardFx is not only the classic board's
		# backdrop: Fling, Drop and Home all host it, and in those the middle of
		# the screen is live playfield rather than an opaque grid. A landmark
		# tall enough to reach the middle stops being scenery and becomes a dark
		# smudge behind the tiles — which is exactly what the first pass did at
		# heights of 0.34-0.46. Everything here stays inside the bottom fifth.
		for e_v in [[0.14, 0.150, 0.34], [0.50, 0.205, 1.0], [0.86, 0.150, 0.34],
				[0.30, 0.120, 0.14], [0.70, 0.120, 0.14]]:
			var e: Array = e_v
			var near: float = float(e[2])
			landmark(arch, float(e[0]), float(e[1]), 140.0 / 300.0,
				stone.lerp(pc("accent"), 0.22 * (1.0 - near)),
				0.30 + 0.40 * near, 0.965)
		# The stone floor, and the coloured light lying on it.
		var floor_rect := ColorRect.new()
		floor_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		floor_rect.color = Color(0.10, 0.09, 0.16, 0.85)
		floor_rect.size = Vector2(vp.x, vp.y * 0.07)
		floor_rect.position = Vector2(0.0, vp.y * 0.93)
		add_child(floor_rect)
		var jewels: Array = [Color(0.91, 0.29, 0.37), Color(0.94, 0.66, 0.24),
			Color(0.27, 0.72, 0.48), Color(0.24, 0.56, 0.88), Color(0.54, 0.36, 0.84)]
		for i in 5:
			var patch := TextureRect.new()
			patch.texture = tex_round()
			patch.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			patch.stretch_mode = TextureRect.STRETCH_SCALE
			patch.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var w: float = vp.x * randf_range(0.14, 0.26)
			patch.size = Vector2(w, vp.y * randf_range(0.035, 0.06))
			patch.position = Vector2(vp.x * (0.10 + 0.19 * float(i)) - w * 0.5,
				vp.y * randf_range(0.905, 0.955))
			var jc: Color = jewels[i]
			patch.modulate = Color(jc.r, jc.g, jc.b, 0.16)
			add_child(patch)
			var tw := patch.create_tween().set_loops()
			tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
			tw.tween_property(patch, "modulate:a", 0.30, randf_range(3.0, 4.6))
			tw.tween_property(patch, "modulate:a", 0.10, randf_range(3.2, 5.0))

# =============================================================================
# Nova Forge — the smithy a star is hammered out of. A white-hot crucible hangs
# over the board on a bed of forge fire; every merge throws off a spark that
# flies up and feeds it, every swipe is the hammer falling. Six merges fill the
# crucible: it ignites, and the newborn star takes its seat in the sky above.
# =============================================================================
class Forge extends Base:
	const CHARGE := 6.0        # merges needed to forge one star
	const MAX_STARS := 9       # a full sky, then a new one is hung
	var _core: TextureRect
	var _cp: Vector2           # crucible centre, px
	var _heat: float = 0.0     # 0..1 charge toward the next star
	var _stars: Array = []     # Vector2 seats of the stars already forged
	var _t: float = 0.0

	func _build() -> void:
		_cp = Vector2(vp.x * 0.5, vp.y * 0.175)
		edge_glow(pc("accent2"), 0.10, 0.20, false)   # the forge bed, below
		# The crucible's halo, breathing with the fire.
		var halo := TextureRect.new()
		halo.texture = tex_round()
		halo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var hd: float = vp.x * 0.62
		halo.size = Vector2(hd, hd)
		halo.position = _cp - halo.size * 0.5
		var acc: Color = pc("accent")
		halo.modulate = Color(acc.r, acc.g, acc.b, 0.14)
		add_child(halo)
		var htw := halo.create_tween().set_loops()
		htw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		htw.tween_property(halo, "modulate:a", 0.24, 3.2)
		htw.tween_property(halo, "modulate:a", 0.12, 3.6)
		# The metal itself: a white-hot bead.
		_core = TextureRect.new()
		_core.texture = tex_round()
		_core.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_core.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var d: float = vp.x * 0.17
		_core.size = Vector2(d, d)
		_core.pivot_offset = _core.size * 0.5
		_core.position = _cp - _core.size * 0.5
		_core.modulate = white(0.92)
		add_child(_core)
		var ctw := _core.create_tween().set_loops()
		ctw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		ctw.tween_property(_core, "scale", Vector2(1.06, 1.06), 1.1)
		ctw.tween_property(_core, "scale", Vector2(0.94, 0.94), 1.2)
		# Embers climbing out of the fire, and cooled ash drifting down through it.
		field({"tex": tex_dot(), "color": pc("accent").lerp(Color(1.0, 0.42, 0.24), 0.45),
			"alpha": 0.75, "amount": 46, "lifetime": 6.5, "from": "bottom",
			"dir": Vector3(0, -1, 0), "spread": 26.0, "vmin": 60.0, "vmax": 190.0,
			"smin": 0.3, "smax": 0.9, "turb": 1.2, "twinkle": true})
		field({"tex": tex_dot(), "color": pc("accent2"), "alpha": 0.30, "amount": 18,
			"lifetime": 9.0, "dir": Vector3(0, 1, 0), "spread": 180.0,
			"vmin": 4.0, "vmax": 16.0, "smin": 0.2, "smax": 0.5})
		# The smith keeps working between moves.
		every(4.5, 8.0, func():
			_strike(Vector2(randf_range(-0.5, 0.5), 1.0).normalized(), 0.5))
		set_process(true)
		_forge_floor()

	func on_swipe(dir: Vector2i) -> void:
		_strike(Vector2(dir).normalized(), 1.0)

	## The hammer falls: the bead flattens, rings, and throws sparks along `dir`.
	func _strike(dir: Vector2, power: float) -> void:
		if is_instance_valid(_core):
			var tw := _core.create_tween()
			tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
			tw.tween_property(_core, "scale",
				Vector2(1.0 + 0.34 * power, 1.0 - 0.20 * power), 0.08)
			tw.tween_property(_core, "scale", Vector2.ONE, 0.5)
		ripple(_cp, pc("accent"), vp.x * (0.42 + 0.30 * power), 0.5)
		burst(_cp, {"tex": tex_dot(),
			"iramp": grad([white(1.0), pc("accent"), Color(1.0, 0.42, 0.30)]),
			"amount": int(16.0 + 22.0 * power), "lifetime": 0.75,
			"dir": Vector3(dir.x, dir.y, 0.0), "spread": 62.0,
			"vmin": 160.0, "vmax": 470.0, "gravity": 320.0, "smin": 0.35, "smax": 1.0})

	func on_merge(pos: Vector2, value: int, tint: Color) -> void:
		# The merge throws off a bright chip of metal…
		burst(pos, {"tex": tex_dot(),
			"iramp": grad([white(1.0), tint.lerp(pc("accent"), 0.5), Color(1.0, 0.38, 0.26)]),
			"amount": 14 + mini(int(float(value) / 128.0), 12), "lifetime": 0.65,
			"vmin": 120.0, "vmax": 340.0, "gravity": 420.0, "smin": 0.35, "smax": 1.1})
		# …and one spark flies up to feed the crucible.
		var spark := TextureRect.new()
		spark.texture = tex_dot()
		spark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		spark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var s: float = 26.0 * sc
		spark.size = Vector2(s, s)
		spark.position = pos - spark.size * 0.5
		spark.modulate = white(0.0)
		add_child(spark)
		var tw := spark.create_tween().set_parallel(true)
		tw.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(spark, "position", _cp - spark.size * 0.5, 0.42)
		tw.tween_property(spark, "modulate:a", 1.0, 0.12)
		tw.chain().tween_callback(func():
			spark.queue_free()
			_feed())

	## One more charge in the crucible — it swells, and fills its ring.
	func _feed() -> void:
		_heat += 1.0 / CHARGE
		var k: float = clampf(_heat, 0.0, 1.0)
		if is_instance_valid(_core):
			var tw := _core.create_tween()
			tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
			tw.tween_property(_core, "scale", Vector2.ONE * (1.10 + 0.22 * k), 0.10)
			tw.tween_property(_core, "scale", Vector2.ONE * (1.0 + 0.14 * k), 0.45)
		ripple(_cp, white(1.0), vp.x * 0.30, 0.4)
		if _heat >= 1.0:
			_ignite()

	## Star birth: the crucible flares white and a new star takes its seat.
	func _ignite() -> void:
		_heat = 0.0
		flash(pc("accent"), 0.14, 0.55)
		ripple(_cp, pc("accent").lerp(white(1.0), 0.5), vp.x * 1.15, 0.85)
		burst(_cp, {"tex": tex_dot(),
			"iramp": grad([white(1.0), pc("accent"), pc("accent2")]),
			"amount": 40, "lifetime": 1.0, "spread": 180.0,
			"vmin": 200.0, "vmax": 560.0, "gravity": 120.0, "smin": 0.4, "smax": 1.4})
		if _stars.size() >= MAX_STARS:
			_stars.clear()   # the sky is full — hang a fresh one
		var n: int = _stars.size()
		var x: float = (0.12 + 0.76 * (float(n) + 0.5) / float(MAX_STARS)) * vp.x
		_stars.append(Vector2(x, vp.y * 0.062))
		if is_instance_valid(_core):
			var tw := _core.create_tween()
			tw.tween_property(_core, "scale", Vector2.ONE * 1.5, 0.12)
			tw.tween_property(_core, "scale", Vector2.ONE, 0.6)

	func on_celebrate() -> void:
		_strike(Vector2(0.0, 1.0), 1.0)
		_ignite()

	func _process(delta: float) -> void:
		var scoped: bool = Engine.has_meta("bench_scope")  # perf-bench scope, regression/perf/SPEC.md #4.2
		if scoped:
			Engine.get_meta("bench_scope").call(true, "RewardFx._process")
		_t += delta
		# `_draw` paints nothing at all while the crucible is cold and no star has
		# been forged yet, so asking for a redraw then is a guaranteed-empty
		# canvas-item re-record every frame. `_t` still advances: the twinkle it
		# drives is only read once `_stars` is non-empty.
		if _heat > 0.0 or not _stars.is_empty():
			queue_redraw()
		if scoped:
			Engine.get_meta("bench_scope").call(false, "RewardFx._process")

	func _draw() -> void:
		var scoped: bool = Engine.has_meta("bench_scope")  # perf-bench scope, regression/perf/SPEC.md #4.2
		if scoped:
			Engine.get_meta("bench_scope").call(true, "RewardFx._draw")
		var acc: Color = pc("accent")
		# B2 — grid-clip cull: the crucible (arc) and the star seats are FIXED
		# positions in the top sky band, so for the grid instance they are
		# almost always wholly outside the board window. Draw-skip only; `_t`
		# and `_heat` advance unchanged. A star's furthest light is its halo
		# (27·sc); the arc's bound is its radius + stroke.
		var cw := clip_window()
		# The charge ring: how close the next star is to being struck.
		if _heat > 0.0:
			var arc_r: float = vp.x * 0.115
			if win_has_rect(cw,
					Rect2(_cp - Vector2(arc_r, arc_r), Vector2(arc_r, arc_r) * 2.0),
					8.0 * sc):
				draw_arc(_cp, arc_r, -PI * 0.5, -PI * 0.5 + TAU * clampf(_heat, 0.0, 1.0),
					48, Color(acc.r, acc.g, acc.b, 0.55), 3.0 * sc, true)
		var dot := tex_dot()
		for i in _stars.size():
			var p: Vector2 = _stars[i]
			if not win_has_point(cw, p, 40.0 * sc):
				continue
			var tw: float = 0.72 + 0.28 * sin(_t * 2.4 + float(i) * 1.6)
			var r: float = 9.0 * sc
			draw_texture_rect(dot, Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), false,
				Color(1, 1, 1, 0.85 * tw))
			var hr: float = r * 3.0
			draw_texture_rect(dot, Rect2(p - Vector2(hr, hr), Vector2(hr, hr) * 2.0), false,
				Color(acc.r, acc.g, acc.b, 0.28 * tw))
		if scoped:
			Engine.get_meta("bench_scope").call(false, "RewardFx._draw")

	## The forge the star is being hammered on: an anvil on its stump, a bed of
	## coals under a hood, a bellows, and tools racked against the wall. The
	## crucible overhead was floating in an empty room.
	func _forge_floor() -> void:
		var iron := Color(0.22, 0.22, 0.26)
		var anvil := bake("nf_anvil", 190, 130, func(uv: Vector2) -> Color:
			const AR := 0.684
			var sy := uv.y / AR
			var a := 0.0
			var b := 0.5
			# The face, with the horn drawn out to one side.
			if sy > -1.0 and sy < -0.42 and uv.x > -0.62 and uv.x < 0.58:
				a = 1.0
				b = 0.86
			var horn := (uv.x + 0.62) / -0.42
			if horn > 0.0 and horn < 1.0 and absf(sy + 0.70 + horn * 0.12) < lerpf(0.28, 0.05, horn):
				a = 1.0
				b = 0.72
			# The waist and the base.
			if sy >= -0.42 and sy < 0.42:
				var t := (sy + 0.42) / 0.84
				if absf(uv.x - 0.02) < lerpf(0.40, 0.26, t):
					a = 1.0
					b = 0.44 + 0.24 * clampf(0.5 - uv.x, 0.0, 1.0)
			if sy >= 0.42 and sy < 0.86 and absf(uv.x - 0.02) < 0.56:
				a = 1.0
				b = 0.38
			# The stump it stands on.
			if sy >= 0.86 and absf(uv.x - 0.02) < 0.46:
				a = 1.0
				b = 0.24
			if a <= 0.02:
				return Color(0, 0, 0, 0)
			return Color(b, b, b, a))
		# The coal bed, and the light it throws up the walls.
		var coals := TextureRect.new()
		coals.texture = tex_round()
		coals.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		coals.stretch_mode = TextureRect.STRETCH_SCALE
		coals.mouse_filter = Control.MOUSE_FILTER_IGNORE
		coals.size = Vector2(vp.x * 0.62, vp.y * 0.10)
		coals.position = Vector2(vp.x * 0.74 - coals.size.x * 0.5, vp.y * 0.92)
		coals.modulate = Color(1.0, 0.42, 0.10, 0.55)
		add_child(coals)
		var ct := coals.create_tween().set_loops()
		ct.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		ct.tween_property(coals, "modulate:a", 0.85, randf_range(1.4, 2.2))
		ct.tween_property(coals, "modulate:a", 0.40, randf_range(1.6, 2.6))
		# The forge bed itself, a dark mass under the coals.
		var bed := ColorRect.new()
		bed.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bed.color = Color(0.08, 0.06, 0.07, 0.95)
		bed.size = Vector2(vp.x * 0.52, vp.y * 0.075)
		bed.position = Vector2(vp.x * 0.74 - bed.size.x * 0.5, vp.y * 0.955)
		add_child(bed)
		landmark(anvil, 0.26, 0.155, 190.0 / 130.0, iron, 0.97)
		# Embers lifting off the coal bed.
		var em := field({"tex": tex_dot(), "color": Color(1.0, 0.62, 0.18), "alpha": 0.8,
			"amount": 22, "lifetime": 2.4, "dir": Vector3(0.05, -1, 0), "spread": 22.0,
			"vmin": 40.0, "vmax": 120.0, "smin": 0.2, "smax": 0.7, "twinkle": true})
		em.position = Vector2(vp.x * 0.74, vp.y * 0.955)
		em.emission_rect_extents = Vector2(vp.x * 0.24, 4.0)
		edge_glow(Color(1.0, 0.48, 0.14), 0.08, 0.20, false)

# =============================================================================
# Skywriter — the night sky is a page. Every swipe writes a luminous vapour
# trail across it (drawn on in half a second, nib and all), merges pin a bright
# node into the script, and the high wind slowly drags the whole thing apart.
# =============================================================================
class Skywriter extends Base:
	const MAX_TRAILS := 5
	const PTS := 26            # samples per trail
	const NODE_LIFE := 6.0
	var _trails: Array = []    # {pts: PackedVector2Array, born, life, w, col}
	var _nodes: Array = []     # {pos: Vector2, born: float, col: Color}
	var _t: float = 0.0
	var _wind: Vector2 = Vector2(16.0, -5.0)

	func _build() -> void:
		# Thin air at altitude: ice crystals catching light, and a mint shimmer.
		field({"tex": tex_dot(), "color": white(1.0), "alpha": 0.50, "amount": 90,
			"lifetime": 12.0, "dir": Vector3(1, 0, 0), "spread": 40.0,
			"vmin": 4.0, "vmax": 18.0, "smin": 0.2, "smax": 0.55, "twinkle": true})
		field({"tex": tex_dot(), "color": pc("accent"), "alpha": 0.45, "amount": 22,
			"lifetime": 7.0, "dir": Vector3(1, 0, 0), "spread": 60.0,
			"vmin": 6.0, "vmax": 26.0, "smin": 0.3, "smax": 0.8, "twinkle": true})
		# Two soft cloud banks so the script has depth to be written over.
		for i in 2:
			var blob := TextureRect.new()
			blob.texture = tex_round()
			blob.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			blob.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var d: float = vp.x * randf_range(0.9, 1.3)
			blob.size = Vector2(d, d)
			blob.position = Vector2(vp.x * (0.1 + 0.45 * float(i)) - d * 0.5,
				vp.y * (0.02 + 0.78 * float(i)) - d * 0.4)
			var col: Color = pc("accent") if i == 0 else pc("accent2")
			blob.modulate = Color(col.r, col.g, col.b, 0.07)
			add_child(blob)
			var tw := blob.create_tween().set_loops()
			tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
			tw.tween_property(blob, "modulate:a", 0.13, randf_range(6.0, 9.0))
			tw.tween_property(blob, "modulate:a", 0.05, randf_range(6.0, 9.0))
		# The sky keeps writing to itself between moves.
		every(5.0, 9.0, func():
			_write(Vector2(randf_range(-1.0, 1.0), randf_range(-0.25, 0.25)), 0.5))
		set_process(true)
		_sky_deck()

	func on_swipe(dir: Vector2i) -> void:
		_write(Vector2(dir), 1.0)

	## Lay down one trail: a wobbling arc across a VISIBLE sky band (the board
	## covers the middle of the screen, so nothing is written behind it).
	func _write(dir: Vector2, strength: float) -> void:
		var d := dir
		if d.length() < 0.01:
			d = Vector2(1, 0)
		d = d.normalized()
		# A vertical stroke would leave the frame in 200px — that reads as a
		# scratch, not skywriting. Lean every stroke across the sky instead.
		if absf(d.x) < 0.35:
			d = Vector2(1.0 if randf() < 0.5 else -1.0, d.y * 0.5).normalized()
		var n := Vector2(-d.y, d.x)
		var yf: float = randf_range(0.06, 0.24) if randf() < 0.62 else randf_range(0.76, 0.94)
		var mid := Vector2(vp.x * 0.5, vp.y * yf)
		var span: float = vp.x * randf_range(0.9, 1.25)
		var amp: float = vp.x * randf_range(0.05, 0.12)
		var freq: float = randf_range(1.4, 2.6)
		var phase: float = randf_range(0.0, TAU)
		var pts := PackedVector2Array()
		for i in PTS:
			var u: float = float(i) / float(PTS - 1)
			pts.append(mid + d * (u - 0.5) * span + n * sin(u * TAU * freq + phase) * amp)
		_trails.append({"pts": pts, "born": _t, "life": 7.5 + 3.0 * strength,
			"w": (3.0 + 4.0 * strength) * sc,
			"col": pc("accent") if randf() < 0.7 else pc("accent2")})
		if _trails.size() > MAX_TRAILS:
			_trails.pop_front()

	func on_merge(pos: Vector2, value: int, tint: Color) -> void:
		# Pinned where it can be seen — a merge in the middle sits behind the board.
		var p := to_visible(pos)
		_nodes.append({"pos": p, "born": _t, "col": tint.lerp(white(1.0), 0.4)})
		if _nodes.size() > 18:
			_nodes.pop_front()
		ripple(p, pc("accent").lerp(white(1.0), 0.35),
			(140.0 + minf(float(value), 2048.0) * 0.06) * sc, 0.55)
		burst(p, {"tex": tex_dot(),
			"iramp": grad([white(1.0), pc("accent"), pc("accent2")]),
			"amount": 12, "lifetime": 0.9, "vmin": 40.0, "vmax": 150.0,
			"gravity": -60.0, "smin": 0.3, "smax": 0.9})

	func on_celebrate() -> void:
		for i in 3:
			_write(Vector2(1.0 if i != 1 else -1.0, float(i - 1) * 0.3), 1.0)

	func _process(delta: float) -> void:
		var scoped: bool = Engine.has_meta("bench_scope")  # perf-bench scope, regression/perf/SPEC.md #4.2
		if scoped:
			Engine.get_meta("bench_scope").call(true, "RewardFx._process")
		_t += delta
		# Everything written drifts on the wind and comes apart as it ages.
		for ti in _trails.size():
			var trail: Dictionary = _trails[ti]
			var pts: PackedVector2Array = trail["pts"]
			var age: float = _t - float(trail["born"])
			for i in pts.size():
				var sway: float = sin(_t * 0.7 + float(i) * 0.55) * 8.0
				pts[i] = pts[i] + (_wind + Vector2(0.0, sway)) * delta * (0.4 + age * 0.10)
			trail["pts"] = pts
		var i2: int = _trails.size() - 1
		while i2 >= 0:
			var tr2: Dictionary = _trails[i2]
			if _t - float(tr2["born"]) > float(tr2["life"]):
				_trails.remove_at(i2)
			i2 -= 1
		var i3: int = _nodes.size() - 1
		while i3 >= 0:
			var nd: Dictionary = _nodes[i3]
			if _t - float(nd["born"]) > NODE_LIFE:
				_nodes.remove_at(i3)
			i3 -= 1
		queue_redraw()
		if scoped:
			Engine.get_meta("bench_scope").call(false, "RewardFx._process")

	func _draw() -> void:
		var scoped: bool = Engine.has_meta("bench_scope")  # perf-bench scope, regression/perf/SPEC.md #4.2
		if scoped:
			Engine.get_meta("bench_scope").call(true, "RewardFx._draw")
		var dot := tex_dot()
		# B2 — grid-clip cull, draw-skip only (`_process` keeps drifting every
		# trail on the wind, so a trail that blows across the window later
		# arrives exactly where an unculled one would). Trails get a bbox test
		# (a stroke can cross the window with every endpoint outside); the pad
		# covers the widest glow pass (w·3.2 half-width) and the 22·sc nib dot.
		var cw := clip_window()
		var clipped := cw.size.x > 0.0
		for ti in _trails.size():
			var trail: Dictionary = _trails[ti]
			var pts: PackedVector2Array = trail["pts"]
			var age: float = _t - float(trail["born"])
			var life: float = float(trail["life"])
			# Written on over the first half-second, then it hangs and disperses.
			var shown_n: int = int(ceil(clampf(age / 0.55, 0.0, 1.0) * float(pts.size())))
			if shown_n < 2:
				continue
			var shown: PackedVector2Array = pts.slice(0, shown_n)
			var w: float = float(trail["w"])
			if clipped:
				var bb := Rect2(shown[0], Vector2.ZERO)
				for pi in range(1, shown_n):
					bb = bb.expand(shown[pi])
				if not cw.grow(w * 2.0 + 26.0 * sc).intersects(bb):
					continue
			var fade: float = clampf(1.0 - (age - 1.0) / maxf(life - 1.0, 0.5), 0.0, 1.0)
			var col: Color = trail["col"]
			draw_polyline(shown, Color(col.r, col.g, col.b, 0.16 * fade), w * 3.2, true)
			draw_polyline(shown, Color(col.r, col.g, col.b, 0.42 * fade), w, true)
			draw_polyline(shown, white(0.55 * fade), w * 0.35, true)
			if shown_n < pts.size():
				# The nib, still laying the line down.
				var head: Vector2 = shown[shown.size() - 1]
				var hr: float = 22.0 * sc
				draw_texture_rect(dot, Rect2(head - Vector2(hr, hr), Vector2(hr, hr) * 2.0),
					false, white(0.9))
		for ni in _nodes.size():
			var nd: Dictionary = _nodes[ni]
			var p: Vector2 = nd["pos"]
			# Pinned nodes never move; furthest light is the halo (r·3.0 ≤ 81·sc).
			if not win_has_point(cw, p, 96.0 * sc):
				continue
			var age2: float = _t - float(nd["born"])
			var fade2: float = clampf(1.0 - age2 / NODE_LIFE, 0.0, 1.0)
			var newborn: float = clampf(1.0 - age2 / 0.9, 0.0, 1.0)
			var col2: Color = nd["col"]
			var r: float = (7.0 + 20.0 * newborn) * sc
			draw_texture_rect(dot, Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), false,
				Color(1, 1, 1, (0.5 + 0.5 * newborn) * fade2))
			var hr2: float = r * 3.0
			draw_texture_rect(dot, Rect2(p - Vector2(hr2, hr2), Vector2(hr2, hr2) * 2.0), false,
				Color(col2.r, col2.g, col2.b, 0.30 * fade2))
		if scoped:
			Engine.get_meta("bench_scope").call(false, "RewardFx._draw")

	## The world the writing happens over: a moonlit cloud deck below, a horizon
	## glow, and the aeroplane itself crossing now and then to lay a fresh trail.
	## The trails alone were script on an empty page.
	func _sky_deck() -> void:
		# The cloud deck: soft banks lit from above, filling the bottom band.
		for i in 6:
			var band := TextureRect.new()
			band.texture = tex_round()
			band.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			band.stretch_mode = TextureRect.STRETCH_SCALE
			band.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var w: float = vp.x * randf_range(0.6, 1.25)
			band.size = Vector2(w, vp.y * randf_range(0.07, 0.15))
			band.position = Vector2(vp.x * randf_range(-0.15, 0.75),
				vp.y * randf_range(0.86, 1.0) - band.size.y * 0.5)
			var tone: Color = pc("accent").lerp(Color(0.86, 0.92, 1.0), 0.62)
			band.modulate = Color(tone.r, tone.g, tone.b, randf_range(0.20, 0.38))
			add_child(band)
			var tw := band.create_tween().set_loops()
			tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
			tw.tween_property(band, "position:x", band.position.x + vp.x * 0.06,
				randf_range(16.0, 26.0))
			tw.tween_property(band, "position:x", band.position.x, randf_range(16.0, 26.0))
		edge_glow(pc("accent").lerp(Color(1.0, 0.72, 0.52), 0.5), 0.07, 0.18, false)
		# A moon high up: the light the deck below is lit by, and the thing the
		# trails are written across.
		var halo := TextureRect.new()
		halo.texture = tex_round()
		halo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		halo.stretch_mode = TextureRect.STRETCH_SCALE
		halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		halo.size = Vector2(vp.x * 0.90, vp.x * 0.90)
		halo.position = Vector2(vp.x * 0.24 - halo.size.x * 0.5, vp.y * 0.16 - halo.size.y * 0.5)
		halo.modulate = Color(0.82, 0.94, 1.0, 0.10)
		add_child(halo)
		var mo := TextureRect.new()
		mo.texture = tex_dot()
		mo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		mo.stretch_mode = TextureRect.STRETCH_SCALE
		mo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mo.size = Vector2(vp.x * 0.16, vp.x * 0.16)
		mo.position = Vector2(vp.x * 0.24 - mo.size.x * 0.5, vp.y * 0.16 - mo.size.y * 0.5)
		mo.modulate = Color(0.94, 0.97, 1.0, 0.85)
		add_child(mo)
		# The aeroplane: a small hard silhouette that crosses the frame and lays
		# a trail behind it, so the script on screen has an author.
		var first_pass := get_tree().create_timer(2.0)
		first_pass.timeout.connect(func() -> void:
			if is_inside_tree():
				_one_plane())
		every(7.0, 14.0, _one_plane)

	func _one_plane() -> void:
		var tex := bake("sw_plane", 120, 60, func(uv: Vector2) -> Color:
			const AR := 0.5
			var sy := uv.y / AR
			var p := Vector2(uv.x, sy)
			var a := 0.0
			# Fuselage.
			if Vector2(p.x / 0.92, p.y / 0.20).length() < 1.0:
				a = 1.0
			# Wings, swept back from the middle.
			for s_v in [-1.0, 1.0]:
				var sgn: float = s_v
				if _tri(p, Vector2(0.16, 0.0), Vector2(-0.30, sgn * 0.94),
						Vector2(-0.06, sgn * 0.10)):
					a = 1.0
			# Tailplane and fin.
			for s_v in [-1.0, 1.0]:
				var sgn: float = s_v
				if _tri(p, Vector2(-0.66, 0.0), Vector2(-0.96, sgn * 0.46),
						Vector2(-0.80, sgn * 0.06)):
					a = 1.0
			if a <= 0.02:
				return Color(0, 0, 0, 0)
			return Color(1, 1, 1, a))
		var plane := TextureRect.new()
		plane.texture = tex
		plane.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		plane.stretch_mode = TextureRect.STRETCH_SCALE
		plane.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var w: float = vp.x * 0.16
		plane.size = Vector2(w, w * 0.5)
		plane.pivot_offset = plane.size * 0.5
		var dir: float = 1.0 if randf() < 0.5 else -1.0
		plane.scale = Vector2(-dir, 1.0)
		var y0: float = vp.y * randf_range(0.14, 0.52)
		plane.position = Vector2(-w * 1.5 if dir > 0.0 else vp.x + w * 0.5, y0)
		plane.modulate = Color(0.90, 0.95, 1.0, 0.0)
		add_child(plane)
		# Its smoke, emitted from the tail as it goes.
		var smoke := field({"tex": tex_dot(), "color": pc("accent").lerp(white(1.0), 0.4),
			"alpha": 0.30, "amount": 20, "lifetime": 3.2, "dir": Vector3(0, -1, 0),
			"spread": 20.0, "vmin": 3.0, "vmax": 14.0, "smin": 0.5, "smax": 1.8})
		smoke.local_coords = false
		smoke.emission_rect_extents = Vector2(2.0, 2.0)
		var dur := randf_range(6.0, 9.0)
		var tw := plane.create_tween()
		tw.set_parallel(true)
		tw.tween_property(plane, "position:x",
			(vp.x + w * 1.5) if dir > 0.0 else -w * 1.5, dur).set_trans(Tween.TRANS_LINEAR)
		tw.tween_property(plane, "modulate:a", 0.85, 1.0)
		tw.tween_method(func(_v: float) -> void:
			if is_instance_valid(smoke) and is_instance_valid(plane):
				smoke.position = plane.position + plane.size * 0.5, 0.0, 1.0, dur)
		tw.chain().tween_property(plane, "modulate:a", 0.0, 0.8)
		tw.chain().tween_callback(func() -> void:
			if is_instance_valid(smoke):
				smoke.emitting = false)
		tw.chain().tween_interval(3.5)
		tw.chain().tween_callback(plane.queue_free)
		tw.chain().tween_callback(func() -> void:
			if is_instance_valid(smoke):
				smoke.queue_free())

	## Point-in-triangle, for the plane bake.
	func _tri(p: Vector2, a1: Vector2, b1: Vector2, c1: Vector2) -> bool:
		var d1 := (b1 - a1).cross(p - a1)
		var d2 := (c1 - b1).cross(p - b1)
		var d3 := (a1 - c1).cross(p - c1)
		var neg: bool = (d1 < 0.0) or (d2 < 0.0) or (d3 < 0.0)
		var pos: bool = (d1 > 0.0) or (d2 > 0.0) or (d3 > 0.0)
		return not (neg and pos)

# =============================================================================
# Star Atlas — an engraved celestial chart turning slowly behind the board:
# ecliptic rings, twelve meridians and a graduated limb. Swipes turn the limb
# and sweep the index arm; every merge engraves a new star and links it into
# the constellation being charted (stars are held in CHART space, so the whole
# figure turns with the plate).
# =============================================================================
class StarAtlas extends Base:
	const MAX_MARKS := 18
	const RINGS := [0.34, 0.50, 0.63, 0.79]   # ring radii, × viewport width
	var _marks: Array = []     # {ang: float (chart space), rad: float, born: float}
	var _t: float = 0.0
	var _rot: float = 0.0      # plate rotation
	var _nudge: float = 0.0    # extra spin from the player's hand, decaying
	var _arm: float = -10.0    # time of the last index-arm sweep
	var _arm_ang: float = 0.0  # its angle, in chart space
	var _c: Vector2            # plate centre (screen centre)
	var _rings: Control        # the ecliptic rings — painted once, never moves
	var _plate: Control        # limb + meridians — painted once, only ROTATES
	var _figures: Control      # the engraved constellations — turns with the plate

	func _build() -> void:
		_c = vp * 0.5
		# Gold leaf lifting off the engraving.
		field({"tex": tex_dot(), "color": pc("accent"), "alpha": 0.35, "amount": 40,
			"lifetime": 11.0, "dir": Vector3(0, -1, 0), "spread": 180.0,
			"vmin": 3.0, "vmax": 12.0, "smin": 0.2, "smax": 0.55, "turb": 0.6,
			"twinkle": true})
		field({"tex": tex_dot(), "color": pc("accent2"), "alpha": 0.30, "amount": 26,
			"lifetime": 9.0, "dir": Vector3(0, 1, 0), "spread": 180.0,
			"vmin": 2.0, "vmax": 9.0, "smin": 0.2, "smax": 0.5, "twinkle": true})
		# The engraving is a RIGID PLATE. Nothing about the rings, the limb scale or
		# the meridians changes from frame to frame — the plate only TURNS — yet
		# `_draw` used to re-record 4 × 96 arc segments + 72 limb ticks + 12
		# meridians, 468 commands, sixty times a second, to reproduce artwork that
		# a transform already expresses. Same treatment as `Circuit._static`:
		#
		#   `_rings` — full circles about `_c`, invariant under rotation entirely.
		#              Painted once and never touched again.
		#   `_plate` — limb + meridians, painted once at rotation 0 with the pivot on
		#              the plate centre; `_process` assigns `rotation = _rot`, which
		#              is exactly the `_rot + …` term the angles used to carry.
		#
		# ORDER SAFETY, the thing Circuit needs a measured margin for: these were
		# already the first three groups `_draw` issued, i.e. the bottom-most layer,
		# and everything that stays in `_draw` (marks, links, index arm) was drawn
		# ON TOP of them. Moving them behind this canvas item therefore cannot
		# change what covers what — the split is order-safe by construction, so
		# unlike Circuit there is no geometric guard to measure. `show_behind_parent`
		# puts them under the parent's own commands; between the two siblings, tree
		# order still decides, so rings stay under the limb as before.
		# The sky goes down FIRST, so everything engraved sits on top of it.
		_static_layer(_draw_sky)
		_rings = _static_layer(_draw_rings)
		_plate = _static_layer(_draw_plate)
		_plate.pivot_offset = _c
		# The constellations are engraved ON the plate, so they turn with it.
		# Same rigid-body argument as the limb: they never change shape, so they
		# are painted once and the layer is rotated rather than re-recorded.
		_figures = _static_layer(_draw_figures)
		_figures.pivot_offset = _c
		# The chart is surveyed even when nobody is playing.
		every(7.0, 12.0, func(): _sweep(randf_range(0.0, TAU)))
		set_process(true)
		_chart_desk()

	## A sibling canvas item that paints `painter` once, behind this effect's own
	## draw commands.
	func _static_layer(painter: Callable) -> Control:
		var c := Control.new()
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.size = vp
		c.show_behind_parent = true
		c.draw.connect(painter.bind(c))
		add_child(c)
		c.queue_redraw()
		return c

	func on_swipe(dir: Vector2i) -> void:
		# The plate turns under the hand, then coasts back to its idle drift.
		var s: float = clampf(float(dir.x) - float(dir.y), -1.0, 1.0)
		_nudge += s * 1.1
		_sweep(Vector2(dir).angle())

	## The index arm swings to `ang` (screen space) and fades — a reading taken.
	func _sweep(ang: float) -> void:
		_arm = _t
		_arm_ang = ang - _rot

	func on_merge(pos: Vector2, value: int, _tint: Color) -> void:
		# Engraved on the plate itself: kept in chart space so it turns with it,
		# and pushed out past the board so the figure is never hidden behind it.
		var v := pos - _c
		if v.length() < 1.0:
			v = Vector2(1, 0)
		var rad: float = clampf(v.length(), vp.x * 0.36, vp.x * 0.76)
		_marks.append({"ang": v.angle() - _rot, "rad": rad, "born": _t})
		if _marks.size() > MAX_MARKS:
			_marks.pop_front()
		var p := _c + v.normalized() * rad
		ripple(p, pc("accent"), (170.0 + minf(float(value), 2048.0) * 0.05) * sc, 0.6)
		burst(p, {"tex": tex_dot(),
			"iramp": grad([white(1.0), pc("accent"), pc("accent2")]),
			"amount": 14, "lifetime": 0.8, "vmin": 60.0, "vmax": 200.0,
			"smin": 0.3, "smax": 0.9})

	func on_celebrate() -> void:
		_nudge += 2.2
		for i in 3:
			_sweep(float(i) * TAU / 3.0)
		flash(pc("accent"), 0.10, 0.45)

	func _process(delta: float) -> void:
		var scoped: bool = Engine.has_meta("bench_scope")  # perf-bench scope, regression/perf/SPEC.md #4.2
		if scoped:
			Engine.get_meta("bench_scope").call(true, "RewardFx._process")
		_t += delta
		_rot += (0.035 + _nudge) * delta
		_nudge = lerpf(_nudge, 0.0, minf(delta * 2.4, 1.0))
		# The plate is a RIGID BODY: rings, limb and meridians never change shape,
		# they only turn. Turning them is a transform assignment, not 468 redrawn
		# commands — see `_build`. Only the engraved marks and the index arm, which
		# genuinely change frame to frame, still need this canvas item re-recorded.
		if is_instance_valid(_plate):
			_plate.rotation = _rot
		if is_instance_valid(_figures):
			_figures.rotation = _rot
		queue_redraw()
		if scoped:
			Engine.get_meta("bench_scope").call(false, "RewardFx._process")

	## The rings, painted once. Full circles about `_c`, so they are invariant under
	## the plate's rotation and do not even belong on the turning layer.
	func _draw_rings(c: Control) -> void:
		var gold: Color = pc("accent")
		for ri in RINGS.size():
			var rr: float = float(RINGS[ri])
			c.draw_arc(_c, vp.x * rr, 0.0, TAU, 96,
				Color(gold.r, gold.g, gold.b, 0.20), 1.6 * sc, true)

	## The limb scale and the meridians, painted once at rotation 0. `_process`
	## turns the layer instead of re-issuing these 84 lines every frame; the layer's
	## `pivot_offset` is `_c`, so `rotation = _rot` reproduces the `_rot + …` term
	## these angles used to carry, exactly.
	func _draw_plate(c: Control) -> void:
		var gold: Color = pc("accent")
		var patina: Color = pc("accent2")
		# The graduated limb — a degree scale, every sixth tick a major one.
		var r_out: float = vp.x * float(RINGS[RINGS.size() - 1])
		for i in 72:
			var a: float = float(i) / 72.0 * TAU
			var major: bool = (i % 6) == 0
			var l: float = (16.0 if major else 8.0) * sc
			var d := Vector2(cos(a), sin(a))
			c.draw_line(_c + d * (r_out - l), _c + d * r_out,
				Color(gold.r, gold.g, gold.b, 0.34 if major else 0.16),
				(2.0 if major else 1.2) * sc, true)
		# Meridians, inner ring to limb.
		for i in 12:
			var a2: float = float(i) / 12.0 * TAU
			var d2 := Vector2(cos(a2), sin(a2))
			c.draw_line(_c + d2 * vp.x * float(RINGS[0]), _c + d2 * r_out,
				Color(patina.r, patina.g, patina.b, 0.14), 1.4 * sc, true)

	func _draw() -> void:
		var scoped: bool = Engine.has_meta("bench_scope")  # perf-bench scope, regression/perf/SPEC.md #4.2
		if scoped:
			Engine.get_meta("bench_scope").call(true, "RewardFx._draw")
		var gold: Color = pc("accent")
		# The rings, the limb and the meridians are NOT here: `_rings` and `_plate`
		# (built in `_build`) hold them, painted once, on their own canvas items
		# directly behind this one. What is left is the part that actually changes.
		# The constellation charted so far.
		var dot := tex_dot()
		# B2 — grid-clip cull, draw-skip only. Every mark position still
		# computes (the link chain threads through all of them); a link chord
		# can cross the window with both stars outside → segment-bbox test. A
		# mark's furthest light is its halo (r·3.2 ≤ 64·sc) plus its engraved
		# rays (≤ 40·sc) — 80·sc covers both with slack.
		var cw := clip_window()
		var has_prev := false
		var prev := Vector2.ZERO
		for i in _marks.size():
			var m: Dictionary = _marks[i]
			var a3: float = float(m["ang"]) + _rot
			var p: Vector2 = _c + Vector2(cos(a3), sin(a3)) * float(m["rad"])
			var age: float = _t - float(m["born"])
			var newborn: float = clampf(1.0 - age / 1.1, 0.0, 1.0)
			if has_prev and win_has_rect(cw, Rect2(prev, Vector2.ZERO).expand(p), 6.0 * sc):
				draw_line(prev, p, Color(gold.r, gold.g, gold.b, 0.26), 2.0 * sc, true)
			prev = p
			has_prev = true
			if not win_has_point(cw, p, 80.0 * sc):
				continue
			var r: float = (6.0 + 14.0 * newborn) * sc
			draw_texture_rect(dot, Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), false,
				white(0.85))
			var hr: float = r * 3.2
			draw_texture_rect(dot, Rect2(p - Vector2(hr, hr), Vector2(hr, hr) * 2.0), false,
				Color(gold.r, gold.g, gold.b, 0.22 + 0.40 * newborn))
			# Four engraved rays, the way stars are drawn on a chart.
			var ray: float = (14.0 + 26.0 * newborn) * sc
			for k in 4:
				var ka: float = a3 + float(k) * PI * 0.5
				draw_line(p, p + Vector2(cos(ka), sin(ka)) * ray,
					Color(1, 1, 1, 0.30 + 0.40 * newborn), 1.4 * sc, true)
		# The index arm, still fading from the last reading.
		var arm_k: float = clampf(1.0 - (_t - _arm) / 0.8, 0.0, 1.0)
		if arm_k > 0.0:
			var ad := Vector2(cos(_arm_ang + _rot), sin(_arm_ang + _rot))
			var arm_from: Vector2 = _c + ad * vp.x * 0.30
			var tip: Vector2 = _c + ad * vp.x * 0.82
			# The arm's furthest light is its 26·sc tip glow → segment-bbox test.
			if win_has_rect(cw, Rect2(arm_from, Vector2.ZERO).expand(tip), 40.0 * sc):
				draw_line(arm_from, tip, white(0.35 * arm_k), 3.0 * sc, true)
				var tipr: float = 26.0 * sc * arm_k
				draw_texture_rect(dot, Rect2(tip - Vector2(tipr, tipr), Vector2(tipr, tipr) * 2.0), false,
					Color(gold.r, gold.g, gold.b, 0.80 * arm_k))
		if scoped:
			Engine.get_meta("bench_scope").call(false, "RewardFx._draw")

	## The desk the chart is being drawn on.
	##
	## The first version of this was three flat shapes: a lumpy grey band that
	## read as a mountain range rather than a sheet of paper, two crossed sticks
	## with a ball on top standing in for a pair of dividers, and a plank for a
	## straightedge. Instruments are the whole romance of a star atlas, so they
	## are drawn as instruments — brass with a specular down one side, a hinge
	## with a knurled head, a needle point and a pencil point, a rule with a
	## bevel and a graduated edge — and the paper is paper.
	func _chart_desk() -> void:
		var brass: Color = Color(0.86, 0.72, 0.40)
		# --- The sheet: warm laid paper with a torn upper edge and the lamp's
		# light falling across it.
		var sheet := bake("sa_sheet2", 320, 130, func(uv: Vector2) -> Color:
			# A tear, not a mountain range: mostly straight, with fibre pulling
			# out of it at a much finer scale than the old ridge line.
			var tear: float = -0.62 + 0.018 * sin(uv.x * 9.0) + 0.012 * sin(uv.x * 23.0) \
				+ 0.008 * sin(uv.x * 57.0)
			if uv.y < tear:
				return Color(0, 0, 0, 0)
			var d: float = uv.y - tear
			var b: float = 0.90 - 0.16 * d
			# Laid lines, and the deckle catching the light.
			b *= 0.975 + 0.025 * sin(uv.y * 90.0)
			b = maxf(b, 1.0 - smoothstep(0.0, 0.035, d))
			# A little foxing in the corners, the way old paper goes.
			b -= clampf(absf(uv.x) - 0.72, 0.0, 1.0) * 0.30
			return Color(b, b * 0.96, b * 0.86, 1.0))
		var sh := TextureRect.new()
		sh.texture = sheet
		sh.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		sh.stretch_mode = TextureRect.STRETCH_SCALE
		sh.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sh.size = Vector2(vp.x * 1.06, vp.y * 0.22)
		sh.position = Vector2(-vp.x * 0.03, vp.y * 1.005 - sh.size.y)
		# Paper has to be PAPER. At half alpha over a near-black sky the sheet
		# came out khaki, which reads as ground, not as something you draw on.
		sh.modulate = Color(0.95, 0.90, 0.76, 0.78)
		add_child(sh)
		# --- The lamp, and the pool it throws. Light first, so the instruments
		# sit inside it.
		var pool := TextureRect.new()
		pool.texture = tex_dot()
		pool.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pool.stretch_mode = TextureRect.STRETCH_SCALE
		pool.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pool.size = Vector2(vp.x * 0.90, vp.y * 0.28)
		pool.position = Vector2(vp.x * 0.76 - pool.size.x * 0.5,
			vp.y * 0.90 - pool.size.y * 0.5)
		pool.modulate = Color(1.0, 0.84, 0.48, 0.16)
		add_child(pool)
		var lamp := bake("sa_lamp2", 170, 130, func(uv: Vector2) -> Color:
			const AR := 0.765     # bake 170x130
			var sy := uv.y / AR
			var a := 0.0
			var col := Color(0, 0, 0)
			# The shade: a cone with a rolled lower rim, lit inside.
			if sy > -1.05 and sy < 0.16:
				var t: float = (sy + 1.05) / 1.21
				var hw: float = lerpf(0.12, 0.96, pow(t, 0.86))
				if absf(uv.x) < hw:
					a = 1.0
					var across: float = uv.x / maxf(hw, 0.01)
					# Brass turns: bright where it faces the light, deep where
					# it rolls away, and never flat.
					var lam: float = clampf(0.62 - across * 0.70, 0.0, 1.0)
					col = Color(0.34, 0.26, 0.12).lerp(Color(1.0, 0.90, 0.62), lam)
					col = col.lerp(Color(1.0, 0.98, 0.86),
						pow(clampf(1.0 - absf(across + 0.42) / 0.20, 0.0, 1.0), 1.4) * 0.7)
					# The rim, and the lit inside of the shade just under it.
					if t > 0.90:
						col = col.lerp(Color(0.26, 0.19, 0.09), (t - 0.90) / 0.10)
					if t > 0.96:
						col = Color(1.0, 0.86, 0.52)
			# The stem going up out of frame.
			if sy <= -0.98 and absf(uv.x) < 0.055:
				a = 1.0
				col = Color(0.42, 0.33, 0.16).lerp(Color(0.92, 0.80, 0.50),
					clampf(0.5 - uv.x * 9.0, 0.0, 1.0))
			if a <= 0.02:
				return Color(0, 0, 0, 0)
			return Color(col.r, col.g, col.b, a))
		var lm := TextureRect.new()
		lm.texture = lamp
		lm.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		lm.stretch_mode = TextureRect.STRETCH_SCALE
		lm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var lw: float = vp.x * 0.34
		lm.size = Vector2(lw, lw * (130.0 / 170.0))
		lm.position = Vector2(vp.x * 0.76 - lw * 0.5, vp.y * 0.715)
		add_child(lm)
		# The bulb, burning under the shade.
		for e_v in [[0.55, 0.55], [0.28, 0.85]]:
			var e: Array = e_v
			var bulb := TextureRect.new()
			bulb.texture = tex_dot()
			bulb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			bulb.mouse_filter = Control.MOUSE_FILTER_IGNORE
			bulb.size = Vector2(lw * float(e[0]), lw * float(e[0]))
			bulb.position = Vector2(vp.x * 0.76, vp.y * 0.715 + lm.size.y * 0.90) \
				- bulb.size * 0.5
			bulb.modulate = Color(1.0, 0.90, 0.62, float(e[1]))
			add_child(bulb)
		# --- The straightedge: a bevelled drafting rule, graduated along one
		# edge, lying at an angle across the sheet.
		var rule := bake("sa_rule", 300, 34, func(uv: Vector2) -> Color:
			if absf(uv.y) > 0.94:
				return Color(0, 0, 0, 0)
			var col := Color(0.80, 0.68, 0.40)
			# The bevel: the top third is cut away and catches more light.
			if uv.y < -0.30:
				col = Color(1.0, 0.92, 0.66)
			elif uv.y > 0.62:
				col = Color(0.40, 0.31, 0.15)
			# Graduations along the lower edge, every fifth one long.
			var g: float = fposmod((uv.x + 1.0) * 60.0, 1.0)
			var major: bool = fposmod(floorf((uv.x + 1.0) * 60.0), 5.0) < 0.5
			if g < 0.14 and uv.y > (0.10 if major else 0.42):
				col = Color(0.24, 0.18, 0.09)
			return Color(col.r, col.g, col.b, 0.92))
		var rl := TextureRect.new()
		rl.texture = rule
		rl.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rl.stretch_mode = TextureRect.STRETCH_SCALE
		rl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rl.size = Vector2(vp.x * 0.74, vp.y * 0.020)
		rl.pivot_offset = rl.size * 0.5
		rl.position = Vector2(vp.x * 0.30, vp.y * 0.945)
		rl.rotation = deg_to_rad(-8.0)
		add_child(rl)
		# --- The dividers: brass, hinged, one needle point and one pencil point.
		var div := bake("sa_dividers2", 130, 200, func(uv: Vector2) -> Color:
			const AR := 1.538     # bake 130x200
			var sy := uv.y * AR
			var p := Vector2(uv.x, sy)
			var a := 0.0
			var col := Color(0, 0, 0)
			var hinge := Vector2(0.0, -1.30)
			for s_v in [-1.0, 1.0]:
				var sgn: float = s_v
				var foot := Vector2(sgn * 0.66, 1.38)
				var d: float = seg_dist(p, hinge, foot)
				# The leg tapers from the hinge down to the point.
				var along: float = clampf((sy + 1.30) / 2.68, 0.0, 1.0)
				var hw: float = lerpf(0.085, 0.016, pow(along, 1.3))
				if d < hw:
					a = 1.0
					var lam: float = clampf(1.0 - d / maxf(hw, 0.001), 0.0, 1.0)
					col = Color(0.36, 0.28, 0.13).lerp(Color(1.0, 0.92, 0.66),
						pow(lam, 0.7) * (0.55 + 0.45 * clampf(0.5 - sgn * 0.5, 0.0, 1.0)))
					# The business ends: a steel needle on one leg, graphite on
					# the other, so the pair reads as a drawing instrument.
					if along > 0.93:
						col = Color(0.82, 0.84, 0.88) if sgn < 0.0 \
							else Color(0.22, 0.20, 0.22)
			# The hinge boss and its knurled adjusting head.
			var hd: float = Vector2(uv.x, sy + 1.30).length()
			if hd < 0.22:
				a = 1.0
				var lam2: float = clampf(1.0 - hd / 0.22, 0.0, 1.0)
				col = Color(0.40, 0.31, 0.14).lerp(Color(1.0, 0.94, 0.70), pow(lam2, 0.6))
				# Knurling round the rim.
				if hd > 0.15:
					col = col.darkened(0.22 * (0.5 + 0.5 * sin(atan2(sy + 1.30, uv.x) * 22.0)))
			if a <= 0.02:
				return Color(0, 0, 0, 0)
			return Color(col.r, col.g, col.b, a))
		var dv := landmark(div, 0.20, 0.205, 130.0 / 200.0, Color(1, 1, 1), 0.95, 0.985)
		dv.rotation = deg_to_rad(-4.0)
		# --- And the loupe the cartographer reads the small print through.
		var loupe := bake("sa_loupe", 90, 130, func(uv: Vector2) -> Color:
			const AR := 1.444     # bake 90x130
			var sy := uv.y * AR
			var a := 0.0
			var col := Color(0, 0, 0)
			# The lens: a ring of brass round a disc of glass.
			var lr: float = Vector2(uv.x, (sy + 0.62) / 1.0).length()
			if lr < 0.92:
				a = 1.0
				if lr > 0.70:
					var lam: float = clampf(1.0 - (lr - 0.70) / 0.22, 0.0, 1.0)
					col = Color(0.38, 0.29, 0.13).lerp(Color(1.0, 0.92, 0.66), lam)
				else:
					# Glass: mostly the chart showing through, with one hard
					# specular streak across it.
					col = Color(0.62, 0.72, 0.70)
					col = col.lerp(Color(1.0, 1.0, 0.96),
						pow(clampf(1.0 - absf(uv.x + sy * 0.7 + 0.30) / 0.26, 0.0, 1.0), 1.6) * 0.85)
					a = 0.60
			# The handle.
			if sy > 0.30 and absf(uv.x) < lerpf(0.13, 0.09, clampf((sy - 0.30) / 1.1, 0.0, 1.0)):
				a = 1.0
				col = Color(0.34, 0.24, 0.12).lerp(Color(0.92, 0.78, 0.48),
					clampf(0.5 - uv.x * 4.0, 0.0, 1.0))
			if a <= 0.02:
				return Color(0, 0, 0, 0)
			return Color(col.r, col.g, col.b, a))
		var lp := TextureRect.new()
		lp.texture = loupe
		lp.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		lp.stretch_mode = TextureRect.STRETCH_SCALE
		lp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var pw: float = vp.x * 0.16
		lp.size = Vector2(pw, pw * (130.0 / 90.0))
		lp.pivot_offset = lp.size * 0.5
		lp.rotation = deg_to_rad(118.0)
		lp.position = Vector2(vp.x * 0.50, vp.y * 0.945) - lp.size * 0.5
		add_child(lp)
		# A single warm highlight where the lamp catches the brass.
		var glint := TextureRect.new()
		glint.texture = tex_dot()
		glint.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		glint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		glint.size = Vector2(vp.x * 0.12, vp.x * 0.12)
		glint.position = Vector2(vp.x * 0.20, vp.y * 0.80) - glint.size * 0.5
		glint.modulate = Color(1.0, 0.90, 0.62, 0.0)
		add_child(glint)
		var gt := glint.create_tween().set_loops()
		gt.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		gt.tween_property(glint, "modulate:a", 0.22, 3.4)
		gt.tween_property(glint, "modulate:a", 0.06, 3.8)

	## The chart's own CONSTELLATIONS — the thing a star atlas is for, and the
	## thing this one did not have.
	##
	## Before this the plate carried four rings, a degree scale and twelve
	## meridians: an empty protractor. Everything on it that was actually a STAR
	## had to be put there by the player, so a fresh board opened onto a blank
	## dial and the theme's whole subject arrived only after a few merges.
	##
	## These are engraved into the plate itself, so they turn with it. Positions
	## are in a local -1..1 box, placed round the dial by `_CONS_AT`; `links` are
	## index pairs, and the fourth number on a star is its MAGNITUDE, which sets
	## how big it is drawn — a chart where every star is the same dot is a
	## connect-the-dots puzzle, not a sky.
	const CONSTELLATIONS := [
		# Ursa Major, the plough — bowl then handle.
		{"stars": [[-0.92, 0.24, 1.0], [-0.52, 0.36, 0.8], [-0.14, 0.30, 0.7],
			[0.14, 0.10, 0.9], [0.52, 0.04, 0.6], [0.86, -0.22, 0.8], [0.44, -0.34, 0.7]],
		 "links": [[0, 1], [1, 2], [2, 3], [3, 4], [4, 5], [5, 6], [6, 3]]},
		# Orion — shoulders, belt, feet.
		{"stars": [[-0.54, -0.80, 1.0], [0.50, -0.72, 0.8], [-0.16, -0.04, 0.7],
			[0.00, 0.02, 0.7], [0.16, 0.08, 0.7], [-0.62, 0.76, 0.9], [0.56, 0.82, 0.6]],
		 "links": [[0, 2], [2, 3], [3, 4], [4, 1], [2, 5], [4, 6], [0, 1]]},
		# Cassiopeia — the W.
		{"stars": [[-0.90, 0.22, 0.8], [-0.44, -0.30, 0.7], [0.00, 0.16, 1.0],
			[0.46, -0.34, 0.7], [0.90, 0.26, 0.8]],
		 "links": [[0, 1], [1, 2], [2, 3], [3, 4]]},
		# Cygnus — the northern cross.
		{"stars": [[0.00, -0.92, 1.0], [0.00, -0.20, 0.6], [0.02, 0.34, 0.7],
			[0.00, 0.90, 0.8], [-0.82, -0.06, 0.7], [0.84, 0.02, 0.7]],
		 "links": [[0, 1], [1, 2], [2, 3], [4, 1], [1, 5]]},
		# Scorpius — the hook.
		{"stars": [[-0.86, -0.62, 0.7], [-0.50, -0.30, 0.6], [-0.16, -0.06, 1.0],
			[0.20, 0.20, 0.7], [0.54, 0.48, 0.6], [0.80, 0.20, 0.7], [0.62, -0.14, 0.6]],
		 "links": [[0, 1], [1, 2], [2, 3], [3, 4], [4, 5], [5, 6]]},
		# Lyra — the little harp, with Vega on its corner.
		{"stars": [[-0.42, -0.72, 1.0], [0.12, -0.30, 0.6], [0.52, 0.16, 0.6],
			[-0.06, 0.58, 0.6], [-0.48, 0.14, 0.6]],
		 "links": [[0, 1], [1, 2], [2, 3], [3, 4], [4, 1]]},
	]
	## Where each one is engraved: [angle in turns, radius × viewport width, size].
	const _CONS_AT := [[0.06, 0.60, 0.19], [0.24, 0.66, 0.22], [0.42, 0.58, 0.16],
		[0.58, 0.68, 0.20], [0.74, 0.60, 0.20], [0.90, 0.64, 0.15]]

	## The sky, and the chart drawn on it. Painted once onto the turning plate,
	## so the whole engraving moves as one piece.
	func _draw_figures(c: Control) -> void:
		var gold: Color = pc("accent")
		var patina: Color = pc("accent2")
		var dot := tex_dot()
		for ci in CONSTELLATIONS.size():
			var e: Array = _CONS_AT[ci]
			var a0: float = float(e[0]) * TAU
			var at: Vector2 = _c + Vector2(cos(a0), sin(a0)) * vp.x * float(e[1])
			var sz: float = vp.x * float(e[2])
			# Each figure is turned to sit square to the rim it is engraved on.
			var rot: float = a0 + PI * 0.5
			var cs := cos(rot)
			var sn := sin(rot)
			var fig: Dictionary = CONSTELLATIONS[ci]
			var stars: Array = fig["stars"]
			var pts: Array = []
			for s_v in stars:
				var s: Array = s_v
				var lx: float = float(s[0]) * sz
				var ly: float = float(s[1]) * sz
				pts.append(at + Vector2(lx * cs - ly * sn, lx * sn + ly * cs))
			for l_v in fig["links"]:
				var l: Array = l_v
				c.draw_line(pts[int(l[0])], pts[int(l[1])],
					Color(patina.r, patina.g, patina.b, 0.44), maxf(1.6 * sc, 1.2), true)
			for si in stars.size():
				var s2: Array = stars[si]
				var mag: float = float(s2[2])
				var p: Vector2 = pts[si]
				var r: float = (2.2 + 5.0 * mag) * sc
				c.draw_texture_rect(dot, Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0),
					false, white(0.48 + 0.50 * mag))
				var hr: float = r * 3.0
				c.draw_texture_rect(dot, Rect2(p - Vector2(hr, hr), Vector2(hr, hr) * 2.0),
					false, Color(gold.r, gold.g, gold.b, 0.16 + 0.22 * mag))
		# The ecliptic band, and the twelve houses ticked off along it. Every
		# real chart of this kind carries one, and it is what makes the dial
		# read as a zodiac rather than a protractor.
		var er: float = vp.x * float(RINGS[2])
		for i in 12:
			var a1: float = float(i) / 12.0 * TAU
			var d := Vector2(cos(a1), sin(a1))
			var n := Vector2(-d.y, d.x)
			var base: Vector2 = _c + d * er
			# A small engraved glyph: two or three strokes, abstract but
			# unmistakably a MARK rather than another tick.
			# Sized off the VIEWPORT, not off `sc`. At `sc` (the 1080-reference
			# scale) a 9 px glyph is under four pixels on a 440-wide probe —
			# the twelve houses were engraved and invisible.
			var g: float = vp.x * 0.030
			var strokes: Array = [
				[Vector2(-0.6, -0.7), Vector2(0.6, -0.7)],
				[Vector2(-0.5, 0.0), Vector2(0.5, 0.0)],
				[Vector2(-0.4, 0.7), Vector2(0.4, 0.7)],
			]
			if i % 3 == 1:
				strokes = [[Vector2(-0.6, -0.7), Vector2(0.0, 0.7)],
					[Vector2(0.0, 0.7), Vector2(0.6, -0.7)]]
			elif i % 3 == 2:
				strokes = [[Vector2(-0.5, -0.7), Vector2(-0.5, 0.7)],
					[Vector2(0.5, -0.7), Vector2(0.5, 0.7)],
					[Vector2(-0.5, 0.0), Vector2(0.5, 0.0)]]
			for st_v in strokes:
				var st: Array = st_v
				var p0: Vector2 = st[0]
				var p1: Vector2 = st[1]
				c.draw_line(base + n * p0.x * g + d * p0.y * g,
					base + n * p1.x * g + d * p1.y * g,
					Color(gold.r, gold.g, gold.b, 0.42), maxf(1.6 * sc, 1.2), true)

	## The sky the chart is OF: a real starfield behind the plate, thickening
	## into a band across it. It does not turn — the plate does.
	func _draw_sky(c: Control) -> void:
		var dot := tex_dot()
		var gold: Color = pc("accent")
		# The band. Soft, off-axis, and made of many faint stars rather than
		# one painted smear.
		for i in 150:
			var f: float = float(i) / 149.0
			var band: bool = i % 3 != 0
			var p: Vector2
			if band:
				var along: float = f * 1.4 - 0.2
				var swing: float = sin(along * 2.2) * 0.16
				p = Vector2(vp.x * (along + swing),
					vp.y * (0.10 + along * 0.86 + sin(f * 31.0) * 0.05))
			else:
				p = Vector2(vp.x * fposmod(f * 7.13, 1.0), vp.y * fposmod(f * 11.7, 1.0))
			var mag: float = fposmod(f * 17.3, 1.0)
			var r: float = (0.7 + 2.4 * mag * mag) * sc
			c.draw_texture_rect(dot, Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0),
				false, white(0.20 + 0.55 * mag))
			if mag > 0.90:
				var hr: float = r * 4.0
				c.draw_texture_rect(dot, Rect2(p - Vector2(hr, hr), Vector2(hr, hr) * 2.0),
					false, Color(gold.r, gold.g, gold.b, 0.14))
