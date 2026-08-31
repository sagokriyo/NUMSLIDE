extends AppScreen
## Home — the hub, styled to the reference: a gradient "2048" wordmark, a
## Continue card with a live mini-board, a four-stat strip, an "All Time Best"
## hexagon hero, and the game-mode rows (size tile · name · best · play).

const BEST_SECTION := "best_scores"

# A small, vivid accent palette used for the coloured tiles / icons / badges.
# These are deliberately fixed (not theme-derived) so the home keeps the
# reference's playful colour story in every theme.
const C_VIOLET := Color("7B6CF6")
const C_INDIGO := Color("5B57E0")
const C_BLUE := Color("4D8DF0")
const C_SKY := Color("46C7E0")
const C_PINK := Color("F178B6")
const C_MAGENTA := Color("E0529C")
const C_ORANGE := Color("FF8A4C")
const C_AMBER := Color("F4B23E")
const C_TEAL := Color("36C7B8")
const C_GOLD := Color("F4B93E")

## The modes Home itself lists, in order — the grid ladder, 4x4 -> 5x5 -> 6x6.
## Everything else is reached through the "More Modes" row at the foot of the
## list. Mode Select owns the FULL catalog and is unaffected by this shortlist.
## EVERY mode, in teaching order. There is no second modes screen: five boards
## is a list, not a catalogue, and a row the player has to go looking for is a
## row most of them never see.
const FEATURED_MODE_IDS: Array[String] = ["classic", "sprint", "lock", "twist", "fog"]

# Per-mode colour story: [gradient_a, gradient_b] for the size tile + play button.
# Kept complete rather than trimmed to FEATURED_MODE_IDS: a mode's colour story
# belongs to the mode, and Home has promoted and demoted rows before.
const MODE_COLORS := {
	# Gold into amber: the plain tray, and the one every player starts on.
	"classic":     [Color("F4B93E"), Color("FF8A4C")],
	# Hot coral into red: the only board with a clock on it.
	"sprint":      [Color("FF8A5C"), Color("F25C6E")],
	# Magenta into violet: the tiles that weld shut behind you.
	"lock":        [Color("F178B6"), Color("7B6CF6")],
	# Teal into blue: the tray with no hole, turned four tiles at a time.
	"twist":       [Color("36C7B8"), Color("4D8DF0")],
	# Slate into deep indigo: the board you cannot see.
	"fog":         [Color("9A9CC8"), Color("3A3F6B")],
}

var _main_col: VBoxContainer
var _word: Control                 # the hero slot — a playable LineBoard's holder
# The identity capsule's live parts, for the in-place PGS profile refresh
# (_refresh_identity_capsule) — the capsule node itself keeps its identity.
var _capsule_name: Label           # the name line (placeholder → gamer tag)
var _capsule_tier: Label           # the rank line under it
var _capsule_ring: ProgressRing    # tier-progress ring around the badge
var _capsule_glow: TextureRect     # aura glow behind the badge (avatar-tinted)
var _stat_anim: Array = []         # [{label, target}] for the count-up
var _pulse_tile: Control           # highest tile in the Continue mini-board
var _mini_cells: Array = []        # Continue mini-board cells, for the domino wiggle
var _scroll: ScrollContainer       # the main scroll, for the overscroll rubber-band
var _home_fx: BoardFx              # living theme ambience behind the menu
var _tiles_bg: Control             # background layer holding the flowing physics tiles
var _tiles_scrim: ColorRect        # legibility wash between the tiles and the menu
var _parallax := Vector2.ZERO      # smoothed gyro offset for the ambience
var _para_t := 0.0                 # time accumulator for the idle parallax sway
# The backside flowing number-tiles are a live physics field behind the menu: they
# drift, collide and wrap around the edges (never trapped), and any can be grabbed
# and flung. Grabbing is handled in _input, so it works even behind the cards.
var _toys: Array = []              # [{n:Control, v:Vector2, drift:Vector2, r:float}]
var _held: int = -1                # index of the grabbed tile, or -1
var _toy_acc := 0.0                # calm-mode 30 Hz step accumulator (see _process)
var _toy_slot := -1                # last calm 30 Hz slot ticked, on the _para_t clock
var _toys_hot := false             # something is flying fast → full-rate physics
# What counts as "still flying". These are the calm-mode gate, and they are the
# whole reason the post-blast field used to judder to a halt.
#
# The gate used to sit at 260 px/s: below that the field dropped to a 30 Hz step.
# But a tile at 259 px/s still travels 8.6 px per half-rate step, held for two
# frames of a 60 Hz panel — and the shockwave's decay (a ~1.7 s time constant
# from up to 2400 px/s) spends about THREE SECONDS crossing the range between
# 260 px/s and true drift speed. So the exact window the player watches the
# tiles "come to rest" was the one window running at half rate. That is the
# stutter, and it is worse on a 120 Hz panel, where a 30 Hz step holds for four.
#
# Drift itself is at most ~42 px/s (near tiles: 40 vertical + 10 horizontal),
# which is ≤1.4 px per half-rate step — genuinely invisible, and the state the
# throttle was measured saving on. So the bounds sit just above drift: the
# throttle keeps the idle field and gets nothing else. The pair is a HYSTERESIS
# band, not one number, so a tile hovering at the threshold cannot flip the
# whole field between rates every few frames — an oscillation that reads as
# exactly the same stutter it is meant to remove.
const _TOY_HOT_ENTER_SQ := 62.0 * 62.0
const _TOY_HOT_EXIT_SQ := 46.0 * 46.0
var _grab_cand: int = -1           # tile under a press, pending a drag to grab it
var _grab_off: Vector2 = Vector2.ZERO
var _grab_start: Vector2 = Vector2.ZERO

# --- Hero long-press bomb -----------------------------------------------------
# HOLD the hero and a confetti bomb forms mid-screen — pieces sucked into a
# growing glow, stepping up in intensity — then detonates on release, blasting
# the theme's confetti across the whole screen. Hold longer (up to ~2.4s) for a
# bigger blast. A TAP is not this gesture: it belongs to the board underneath,
# which slides a tile. The two never collide, because LineBoard refuses to slide
# on a press that outlived `long_press_s`, and that is the very threshold the
# charge starts at. One number, set in _build_wordmark, so they cannot drift.
const _WM_HOLD_S := 0.26           # presses shorter than this stay a plain tap
const _WM_FULL_S := 2.4            # held this long past the threshold = full power
var _wm_down := false
var _wm_t0 := 0                    # ticks_msec at press (for blast strength)
var _wm_moved := 0.0               # drag distance — a scroll must not charge
var _wm_aborted := false
var _wm_timer: Timer               # fires once the press outlives a tap
var _stage_timer: Timer            # steps the forming bomb's intensity up
var _charge_root: Control = null   # the mid-screen forming-bomb visual
var _charge_glow: TextureRect = null
var _charge_stage := 0
var _charge_ramp: Gradient = null  # tile-colour ramp for the swirl pieces
var _charge_tex: ImageTexture
# Session-scoped (statics survive scene rebuilds, reset on app restart):
# the best tile as of the last Home visit — the cast cheers when it grows —
# and whether the morning greeting has already played today’s hello.
static var _seen_best_tile := -1
static var _greeted_morning := false
var _theme_surprise := false       # theme just changed → the digits gawp at their new coat
## Home builds its own dimmed + parallaxed BoardFx below, so skip AppScreen's shared one.
func has_own_fx() -> bool: return true

func nav_tab() -> String: return "home"

func _on_theme_changed(_palette: Dictionary) -> void:
	_paint_background()
	# The rebuilt wordmark wakes up in a brand-new coat of colours — the digits
	# look around at it, amazed, for a beat.
	_theme_surprise = true
	for c in content.get_children():
		c.queue_free()
	build_content(content)
	# The living background is a sibling of `content`, so it survives the rebuild;
	# it restyles itself via its own theme_changed hook.

func on_ready() -> void:
	custom_entrance = true
	# Re-gate live if entitlement changes (e.g. Play Billing's connect-time
	# restore) while Home is on screen — locked tags and tap behaviour refresh
	# immediately.
	EntitlementManager.premium_changed.connect(func(_p): _on_theme_changed(ThemeManager.palette()))
	AccountManager.auth_changed.connect(func(): _on_theme_changed(ThemeManager.palette()))
	# The gamer tag lands AFTER the session does — swap it into the identity
	# capsule IN PLACE when it arrives. This used to take the theme path's full
	# column teardown, racing the entrance stagger for what is one label's worth
	# of change; premium/auth changes above keep the full rebuild (locked tags
	# and the sign-in banner live all over the column), theme changes keep it in
	# _on_theme_changed.
	AccountManager.profile_changed.connect(_refresh_identity_capsule)
	# Real wins get a reaction from the cast: an achievement unlocking while Home
	# is on screen makes the digits cheer and gawp at the toast.
	Achievements.unlocked.connect(func(_id, _def):
		if _word is ExtrudedWord and is_instance_valid(_word):
			(_word as ExtrudedWord).dance()
			(_word as ExtrudedWord).amaze(1.6))
	# Living theme ambience behind the menu — the same engine the board uses, dimmed
	# so it reads as a calm backdrop. Dropped just beneath the frost snapshot (_bbc)
	# so the glass cards frost the ambience too, exactly like the gameplay cards. It
	# restyles itself on theme change and is a sibling of `content`, so the rebuild
	# on theme change never tears it down.
	_home_fx = BoardFx.new()
	_home_fx.modulate.a = _fx_alpha()
	# Same menu-backdrop thinning the base screens use (see BoardFx) — Home's
	# ambience is a calm backdrop behind cards, not the gameplay field.
	_home_fx.ambience_scale = 0.55
	place_in_backdrop(_home_fx)
	# Keep the dim in step with the theme: motifs that paint their own OPAQUE
	# world (the Rainbow Keys keyboard, the black hole, the metaball fluid) must not
	# be half-faded into the pastel backdrop wash — that is exactly what made
	# the keyboard's keys vanish on Home.
	ThemeManager.theme_changed.connect(func(_p):
		if is_instance_valid(_home_fx):
			_home_fx.modulate.a = _fx_alpha()
		if is_instance_valid(_tiles_scrim):
			_tiles_scrim.color = _scrim_color())

	# Playful identity layer: faint 2/4/8/… number-tiles drifting up behind the menu,
	# so the backdrop is unmistakably "2048". A sibling of `content`, so it survives
	# theme rebuilds; sits above the ambience but still beneath the frost snapshot,
	# so the cards frost it too. ONE layer: every tile lives in the same field —
	# all grabbable, all colliding with all — the small faint ones included.
	_tiles_bg = Control.new()
	_tiles_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tiles_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	place_in_backdrop(_tiles_bg)
	_spawn_toys()

	# Legibility scrim — one soft wash of the theme's own backdrop between the
	# flowing tiles and the menu, so every label keeps its contrast no matter
	# which tile drifts beneath it. The tiles stay untouched below it (grabbing
	# and flinging feel identical); text simply always wins. Skipped alongside
	# the toys under reduce-motion — with no tiles there is nothing to calm.
	if not _toys.is_empty():
		_tiles_scrim = ColorRect.new()
		_tiles_scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_tiles_scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_tiles_scrim.color = _scrim_color()
		place_in_backdrop(_tiles_scrim)

	# (The colour-grade vignette now lives in the base AppScreen, so it grades
	# every screen — see ui/screen.gd _build_vignette.)

	# The hold timers (Timer children, so they die with the screen — no dangling
	# callbacks). _wm_timer decides tap vs hold; _stage_timer steps the forming
	# bomb's intensity while the finger stays down.
	_wm_timer = Timer.new()
	_wm_timer.one_shot = true
	_wm_timer.wait_time = _WM_HOLD_S
	_wm_timer.timeout.connect(_maybe_begin_charge)
	add_child(_wm_timer)
	_stage_timer = Timer.new()
	_stage_timer.one_shot = true
	_stage_timer.wait_time = 0.75
	_stage_timer.timeout.connect(_advance_charge)
	add_child(_stage_timer)

	content.modulate.a = 0.0
	await get_tree().process_frame
	content.modulate.a = 1.0
	if _main_col:
		stagger_in(_main_col.get_children())
	_start_flourishes()
	# Idle prepay: once the entrance has settled, warm the two routes a Home tap
	# reaches next so their scene parse is a cache hit (worker-thread load; a
	# navigation landing mid-warm simply joins the task — see SceneRouter.warm).
	get_tree().create_timer(1.5, true, false, true).timeout.connect(func():
		SceneRouter.warm(SceneRouter.Route["GAMEPLAY"]))

## The entrance micro-animations: a breathing wordmark, counting-up stats, and a
## gently pulsing best tile.
func _start_flourishes() -> void:
	# THE WORD NOTICES YOUR WINS: coming back to Home with a new best tile since
	# the last visit this session, the cast cheers — dance, wide eyes (which
	# also kicks up halo dust) and the full confetti celebration. Session-scoped
	# on purpose: it salutes fresh wins, not history.
	var best_now := int(GameStats.get_stat("games_won"))
	if _seen_best_tile >= 0 and best_now > _seen_best_tile \
			and _word is ExtrudedWord and is_instance_valid(_word):
		var cheer_word := _word as ExtrudedWord
		var ct := create_tween()
		ct.tween_interval(0.9)
		ct.tween_callback(func():
			if is_instance_valid(cheer_word):
				cheer_word.dance()
				cheer_word.amaze(2.2)
				_spawn_celebration())
	_seen_best_tile = best_now
	# THE MORNING GREETING: on the session's first morning visit the cast wakes
	# with the player — sleepy yawns, then a startled hello and a dance.
	var hour := int(Time.get_time_dict_from_system()["hour"])
	if not _greeted_morning and hour >= 5 and hour < 12 \
			and _word is ExtrudedWord and is_instance_valid(_word):
		_greeted_morning = true
		(_word as ExtrudedWord).morning()
	# The slow parallax "turn" that used to rock the hero lives and dies with the
	# wordmark: `turn` is ExtrudedWord's and HeroBoard's property, and the hero
	# slot now holds a MiniBoard, which has no such thing — tweening it would
	# fail on a property that is not there. A board the player is mid-move on
	# should sit still anyway.
	if _word is ExtrudedWord or _word is HeroBoard:
		var bt := _word.create_tween().set_loops()
		bt.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		bt.tween_property(_word, "turn", 6.0, 3.4)
		bt.tween_property(_word, "turn", -6.0, 3.4)
	# Stat strip — count each number up from zero, then a little pop as it lands.
	for entry in _stat_anim:
		var lbl: Label = entry["label"]
		if not is_instance_valid(lbl):
			continue
		var target: int = int(entry["target"])
		lbl.pivot_offset = lbl.size * 0.5
		var t := lbl.create_tween()
		t.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		t.tween_method(func(v: float): lbl.text = str(int(round(v))), 0.0, float(target), 0.7)
		t.tween_property(lbl, "scale", Vector2(1.14, 1.14), 0.12).set_trans(Tween.TRANS_BACK)
		t.tween_property(lbl, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK)
	# Continue mini-board — a quick domino wiggle that invites the tap.
	_mini_wiggle()
	# Continue mini-board — the highest tile breathes.
	if is_instance_valid(_pulse_tile):
		_pulse_tile.pivot_offset = _pulse_tile.size * 0.5
		var pt := _pulse_tile.create_tween().set_loops()
		pt.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		pt.tween_property(_pulse_tile, "scale", Vector2(1.08, 1.08), 1.1)
		pt.tween_property(_pulse_tile, "scale", Vector2.ONE, 1.1)

## A staggered "domino" wiggle across the Continue mini-board's tiles on entrance,
## drawing the eye to the saved game. Skips the breathing best tile to avoid a
## double animation on the same node.
func _mini_wiggle() -> void:
	var i := 0
	for cell in _mini_cells:
		if not (cell is Control) or not is_instance_valid(cell) or cell == _pulse_tile:
			i += 1
			continue
		var c := cell as Control
		c.pivot_offset = c.size * 0.5
		var t := c.create_tween()
		t.tween_interval(0.55 + i * 0.05)
		t.tween_property(c, "scale", Vector2(1.16, 1.16), 0.12).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		t.tween_property(c, "scale", Vector2.ONE, 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		i += 1

## Ambience dim for Home: opaque-world reward motifs read at full strength;
## everything else stays the calm half-faded backdrop.
func _fx_alpha() -> float:
	return 1.0 if ThemeManager.bg_motif() in ["circuit", "blackhole", "metaballs"] else 0.5

## The scrim's wash: the theme's own backdrop colour at low alpha, so it reads
## as atmospheric haze in front of the tiles rather than a grey filter. It is a
## single wash over the ALREADY-COMPOSITED field, so it drops the whole layer's
## contrast against the menu while leaving each shard's own rim, streak and
## specular untouched. Fading the shards themselves does the opposite.
func _scrim_color() -> Color:
	var c: Color = ThemeManager.color("bg0")
	c.a = 0.34
	return c

## The hero's LONG PRESS: a hold charges a confetti bomb mid-screen (pieces
## sucked into a growing glow, stepping up while held) that detonates across the
## whole screen on release. A drag cancels — scrolling stays safe.
##
## Shares `gui_input` with the board's own handler, which owns the quick tap. The
## two divide the gesture at `_WM_HOLD_S`: shorter slides a tile, longer is a bomb.
func _on_wordmark_input(event: InputEvent) -> void:
	var down: bool = (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed) \
		or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT)
	var up: bool = (event is InputEventScreenTouch and not (event as InputEventScreenTouch).pressed) \
		or (event is InputEventMouseButton and not (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT)
	if down:
		_wm_down = true
		_wm_aborted = false
		_wm_moved = 0.0
		_wm_t0 = Time.get_ticks_msec()
		Haptics.light()
		# The charge climaxes in a confetti detonation, which reduce-motion
		# removes — so under reduce-motion a hold stays a plain tap.
		if not bool(SettingsManager.get_value("reduce_motion")):
			_wm_timer.start()
	elif (event is InputEventScreenDrag or event is InputEventMouseMotion) and _wm_down:
		var rel := Vector2.ZERO
		if event is InputEventScreenDrag:
			rel = (event as InputEventScreenDrag).relative
		elif event is InputEventMouseMotion:
			rel = (event as InputEventMouseMotion).relative
		_wm_moved += rel.length()
		# A real drag is a scroll, not a hold — stand down.
		if _wm_moved > 60.0:
			_wm_timer.stop()
			if _charge_root != null:
				_cancel_charge()
				_wm_aborted = true
	elif up and _wm_down:
		_wm_down = false
		_wm_timer.stop()
		_stage_timer.stop()
		if _charge_root != null:
			_detonate()

func _maybe_begin_charge() -> void:
	if not _wm_down or _wm_aborted or _charge_root != null:
		return
	if _wm_moved > 40.0:
		return
	_begin_charge()

## The bomb core: a breathing glow at mid-screen with confetti-coloured pieces
## spiralling INTO it (negative radial acceleration), thickening in stages.
func _begin_charge() -> void:
	_charge_stage = 0
	_charge_ramp = _tile_ramp()
	_charge_root = Control.new()
	_charge_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_charge_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_charge_root)
	var centre := size * Vector2(0.5, 0.44)

	var glow := TextureRect.new()
	glow.texture = _soft_radial_tex()
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	const GSZ := 340.0
	glow.size = Vector2(GSZ, GSZ)
	glow.position = centre - Vector2(GSZ, GSZ) * 0.5
	glow.pivot_offset = Vector2(GSZ, GSZ) * 0.5
	var ac: Color = ThemeManager.color("accent")
	glow.modulate = Color(ac.r, ac.g, ac.b, 0.0)
	glow.scale = Vector2(0.4, 0.4)
	_charge_root.add_child(glow)
	_charge_glow = glow
	var gt := glow.create_tween().set_parallel(true)
	gt.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	gt.tween_property(glow, "modulate:a", 0.55, 0.3)
	gt.tween_property(glow, "scale", Vector2(0.7, 0.7), 0.7)
	# The core breathes while it charges — alpha only, so stage bumps own scale.
	var pulse := glow.create_tween().set_loops()
	pulse.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(glow, "modulate:a", 0.75, 0.45)
	pulse.tween_property(glow, "modulate:a", 0.5, 0.45)

	_add_charge_swirl(centre, 48, 170.0, 340.0)
	Haptics.medium()
	_stage_timer.start()

## Each stage: more pieces sucked in from wider out, a bigger core, a harder tick.
func _advance_charge() -> void:
	if _charge_root == null or not _wm_down:
		return
	_charge_stage += 1
	var centre := size * Vector2(0.5, 0.44)
	match _charge_stage:
		1:
			_add_charge_swirl(centre, 95, 240.0, 470.0)
			_bump_glow(1.2)
			Haptics.medium()
			_stage_timer.start()
		_:
			# Full charge: a dense storm of pieces streaming in from far out.
			_add_charge_swirl(centre, 150, 320.0, 620.0)
			_bump_glow(1.75)
			Haptics.heavy()

func _bump_glow(to_scale: float) -> void:
	if _charge_glow == null or not is_instance_valid(_charge_glow):
		return
	var t := _charge_glow.create_tween()
	t.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	t.tween_property(_charge_glow, "scale", Vector2(to_scale, to_scale), 0.5)

## A continuous ring of tile-coloured pieces spawning around the core and being
## pulled INTO it while swirling — the bomb visibly gathering its confetti.
func _add_charge_swirl(centre: Vector2, amount: int, radius: float, suck: float) -> void:
	if _charge_root == null:
		return
	var ps := CPUParticles2D.new()
	ps.position = centre
	ps.amount = amount
	ps.lifetime = 0.8
	ps.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	ps.emission_sphere_radius = radius
	ps.spread = 180.0
	ps.initial_velocity_min = 0.0
	ps.initial_velocity_max = 30.0
	ps.radial_accel_min = -suck
	ps.radial_accel_max = -suck * 0.7
	ps.orbit_velocity_min = 0.5
	ps.orbit_velocity_max = 0.9
	ps.angle_min = -180.0
	ps.angle_max = 180.0
	ps.angular_velocity_min = -300.0
	ps.angular_velocity_max = 300.0
	ps.scale_amount_min = 0.8
	ps.scale_amount_max = 1.5
	ps.texture = _charge_piece_tex()
	ps.color_initial_ramp = _charge_ramp
	_charge_root.add_child(ps)
	ps.emitting = true

## A rounded shard, baked once: a hard quad reads as a pixel at this size.
func _charge_piece_tex() -> ImageTexture:
	if _charge_tex == null:
		var img := Image.create(12, 12, false, Image.FORMAT_RGBA8)
		for y in 12:
			for x in 12:
				var uv := Vector2(float(x) / 11.0 * 2.0 - 1.0, float(y) / 11.0 * 2.0 - 1.0)
				var q := uv.abs() - Vector2(0.6, 0.6)
				var d := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() \
					+ minf(maxf(q.x, q.y), 0.0) - 0.3
				var a := clampf(0.5 - d / 0.18, 0.0, 1.0)
				var shade := lerpf(1.0, 0.84, clampf((uv.x + uv.y) * 0.25 + 0.5, 0.0, 1.0))
				img.set_pixel(x, y, Color(shade, shade, shade, a))
		_charge_tex = ImageTexture.create_from_image(img)
	return _charge_tex

## The theme's tile ramp as a gradient — the forming bomb wears the same colours
## the blast will.
func _tile_ramp() -> Gradient:
	var pal := ThemeManager.palette()
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	var vals := [8, 32, 128, 512, 2048]
	for i in vals.size():
		offs.append(float(i) / float(vals.size() - 1))
		var c: Color = ThemeManager.tile_style_for(pal, int(vals[i]))["bg"]
		cols.append(Color.from_hsv(c.h, clampf(c.s + 0.1, 0.0, 1.0), clampf(maxf(c.v, 0.72), 0.0, 1.0)))
	g.offsets = offs
	g.colors = cols
	return g

## A wandering finger or an interrupted hold: the forming bomb sighs out.
func _cancel_charge() -> void:
	_stage_timer.stop()
	var root := _charge_root
	_charge_root = null
	_charge_glow = null
	if root != null and is_instance_valid(root):
		var t := root.create_tween()
		t.tween_property(root, "modulate:a", 0.0, 0.2)
		t.tween_callback(root.queue_free)

## Release! The core implodes, then the theme's confetti blasts from mid-screen
## to every edge — strength scales with how long the bomb was allowed to form.
func _detonate() -> void:
	var held := float(Time.get_ticks_msec() - _wm_t0) / 1000.0
	var strength := clampf((held - _WM_HOLD_S) / _WM_FULL_S, 0.15, 1.0)
	if _charge_glow != null and is_instance_valid(_charge_glow):
		var g := _charge_glow
		var it := g.create_tween()
		it.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
		it.tween_property(g, "scale", Vector2(0.12, 0.12), 0.09)
	var root := _charge_root
	_charge_root = null
	_charge_glow = null
	if root != null and is_instance_valid(root):
		var rt := root.create_tween()
		rt.tween_interval(0.1)
		rt.tween_callback(root.queue_free)
	AudioManager.play_boom(strength)   # a synthesized explosion, scaled to the charge
	Haptics.success()
	Haptics.heavy()
	# The dramatic beat: the whole screen dips into slow motion for the first
	# half-second of the explosion, then snaps back to speed. The restore timer
	# ignores time_scale (or it would itself run slow) and is tree-owned, so it
	# fires even if the player navigates away mid-blast.
	Engine.time_scale = 0.45
	get_tree().create_timer(0.5, true, false, true).timeout.connect(func():
		Engine.time_scale = 1.0)
	Confetti.bomb(self, strength)
	# The shockwave is PHYSICAL: every floating background tile is flung outward
	# from the blast centre. They wrap around the screen edges, so the field
	# scatters violently and then drifts back together on its own.
	var centre := size * Vector2(0.5, 0.44)
	for i in _toys.size():
		if i == _held:
			continue   # a grabbed tile stays in the player's hand
		var d := _toys[i] as Dictionary
		var n: Control = d["n"]
		if is_instance_valid(n):
			var dir: Vector2 = n.position + Vector2(d["r"], d["r"]) - centre
			if dir.length() < 1.0:
				dir = Vector2(randf() - 0.5, randf() - 0.5)
			d["v"] = dir.normalized() * lerpf(900.0, 2400.0, strength)
	_toys_hot = true   # the blast is airborne — full-rate physics from this frame
	_bounce_word(1.0 + 0.2 * strength)

func _bounce_word(peak: float) -> void:
	if not is_instance_valid(_word):
		return
	_word.pivot_offset = _word.size * 0.5
	var t := _word.create_tween()
	t.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	t.tween_property(_word, "scale", Vector2(peak, peak), 0.12)
	t.tween_property(_word, "scale", Vector2(0.97, 0.97), 0.1)
	t.tween_property(_word, "scale", Vector2.ONE, 0.14)

# --- The forming bomb ---------------------------------------------------------
## Press outlived a tap and the finger hasn't wandered — start forming the bomb.
## Fires the celebration on every title tap: the same shaped confetti the rest of
## the game uses, as a bottom popper + a top→bottom rain, on TWO layers — one
## behind the cards (shows through the gaps) and one in front — so confetti falls
## both behind and above the menu. A raised cap keeps it responsive to taps.
func _spawn_celebration() -> void:
	# Same two-layer celebration everywhere; phones just cap how many showers can
	# STACK from rapid taps (4 = two full celebrations in flight — looks identical,
	# since overlapping showers blend together anyway).
	var cap := 4 if OS.has_feature("mobile") else 8
	if is_instance_valid(_tiles_bg):
		Confetti.celebrate(_tiles_bg, 156, true, cap)  # behind the menu
	Confetti.celebrate(self, 156, true, cap)           # above the menu

## Gives the main scroll a gentle rubber-band: pulling past the top or bottom and
## releasing springs the content back with a soft elastic squish. Touch-first
## (the primary platform).
func _wire_overscroll(scroll: ScrollContainer) -> void:
	var st := {"pull": 0.0}
	scroll.gui_input.connect(func(e: InputEvent):
		if e is InputEventScreenDrag:
			# Cheap edge test first — mid-list drags (the vast majority) must not
			# pay the scrollbar fetch + max-scroll math on every event.
			var sv: int = scroll.scroll_vertical
			var dy: float = (e as InputEventScreenDrag).relative.y
			var pull: float = float(st["pull"])
			if sv <= 0:
				if pull < 0.0 or dy < 0.0:
					# Needs the real max: an unscrollable list's top IS its
					# bottom (an upward pull there is legitimate); otherwise a
					# leftover bottom pull flung all the way up here is stale.
					var vbar := scroll.get_v_scroll_bar()
					var max_scroll: int = int(maxf(vbar.max_value - vbar.page, 0.0))
					if max_scroll == 0:
						if dy < 0.0:
							st["pull"] = float(st["pull"]) + dy
					elif pull < 0.0:
						st["pull"] = 0.0
				if dy > 0.0:
					st["pull"] = float(st["pull"]) + dy
			else:
				# Off the top edge, a pull gathered there is stale — releasing
				# mid-fling must not fire the squish on top of fling inertia.
				if pull > 0.0:
					st["pull"] = 0.0
				if dy < 0.0 or pull < 0.0:
					var vbar := scroll.get_v_scroll_bar()
					var max_scroll: int = int(maxf(vbar.max_value - vbar.page, 0.0))
					if sv >= max_scroll and dy < 0.0:
						st["pull"] = float(st["pull"]) + dy
					elif pull < 0.0 and sv < max_scroll:
						st["pull"] = 0.0
		elif e is InputEventScreenTouch and not (e as InputEventScreenTouch).pressed:
			_overscroll_release(float(st["pull"]))
			st["pull"] = 0.0)

func _overscroll_release(pull: float) -> void:
	if absf(pull) < 24.0 or not is_instance_valid(_main_col):
		return
	var top: bool = pull > 0.0
	_main_col.pivot_offset = Vector2(_main_col.size.x * 0.5, 0.0 if top else _main_col.size.y)
	var amt: float = clampf(absf(pull) / 600.0, 0.02, 0.06)
	_main_col.scale = Vector2(1.0, 1.0 - amt)
	var t := _main_col.create_tween()
	t.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
	t.tween_property(_main_col, "scale", Vector2.ONE, 0.55)

## Subtle gyro parallax: the living background drifts with the phone's tilt for a
## sense of depth. A no-op on desktop (the accelerometer reads zero there).
func _process(delta: float) -> void:
	if _home_fx == null or not is_instance_valid(_home_fx):
		return
	_para_t += delta
	var a := Input.get_accelerometer()
	# A gentle autonomous sway gives depth motion even without a gyro (desktop); the
	# phone-tilt parallax rides on top. Each layer shifts by a different amount so the
	# bands separate into a foreground / background.
	var idle := Vector2(sin(_para_t * 0.32) * 9.0, cos(_para_t * 0.26) * 5.0)
	var target := Vector2(clampf(-a.x * 6.0, -46.0, 46.0), 0.0) + idle
	_parallax = _parallax.lerp(target, _ease(3.0, delta))
	# Only re-position the two backdrop layers once the sway has actually moved
	# them a visible amount — the idle drift crawls at a few px/second, and a
	# sub-half-pixel write per frame is pure transform churn across two
	# full-screen subtrees for no visible motion.
	if (_parallax * 0.7).distance_to(_home_fx.position) > 0.5:
		_home_fx.position = _parallax * 0.7
		# The tile field rides the same tilt, a touch stronger than the ambience,
		# so the backdrop still separates into layers when the phone moves.
		if is_instance_valid(_tiles_bg):
			_tiles_bg.position = _parallax * 1.0
	# CALM = 30 Hz: at drift speeds the field moves ~1 px per half-rate step, so
	# the throttle is invisible while halving the per-frame cost of the whole toy
	# layer (property churn + the O(n²) collision pass). A grab, a fling or a
	# still-decelerating blast flips it straight back to full-rate physics — see
	# the _TOY_HOT_* band, which is what decides "still moving" and used to let go
	# far too early.
	_toy_acc += delta
	if _held >= 0 or _toys_hot:
		_step_toys(_toy_acc)
		_toy_acc = 0.0
	else:
		# The calm cadence rides the free-running _para_t clock, not the
		# accumulator: the word redraw and the sky ticker run the same 30 Hz
		# seeded a third of a period away, and only a clock no reset touches
		# keeps the three heavy ticks off each other's frame — a hot episode's
		# per-frame resets above would otherwise re-align them.
		var slot: int = int(_para_t * 30.0)
		if slot != _toy_slot:
			_toy_slot = slot
			_step_toys(_toy_acc)
			_toy_acc = 0.0

## A breathing accent-tinted glow that sits behind a CTA and bleeds out as a soft
## halo. Added behind the card's gradient; its loop starts once it's in the tree.
func _add_cta_glow(holder: Control, col: Color) -> void:
	var glow := TextureRect.new()
	glow.texture = _soft_radial_tex()
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.offset_left = -54.0
	glow.offset_right = 54.0
	glow.offset_top = -26.0
	glow.offset_bottom = 26.0
	glow.modulate = Color(col.r, col.g, col.b, 0.0)
	holder.add_child(glow)
	holder.move_child(glow, 0)   # behind the gradient + label
	glow.tree_entered.connect(func():
		var tw := glow.create_tween().set_loops()
		tw.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		tw.tween_property(glow, "modulate:a", 0.5, 1.7)
		tw.tween_property(glow, "modulate:a", 0.2, 1.9))

## A soft white radial (opaque centre → transparent edge) for glows/haloes.
func _soft_radial_tex() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 1.0)
	t.width = 128
	t.height = 128
	return t

# --- Interactive flowing tiles ------------------------------------------------
## The backside flowing number-tiles ARE a live physics field behind the menu: they
## drift, collide and wrap around the edges (never trapped), and any can be grabbed
## and flung. Colours are the fixed accent story so they survive theme rebuilds.
## Grabbing is handled in _input, so the tiles work even behind the cards. Skipped
## under reduce-motion.
func _spawn_toys() -> void:
	if bool(SettingsManager.get_value("reduce_motion")) or _tiles_bg == null:
		return
	var vp := get_viewport_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return
	var values := [2, 4, 8, 16, 32, 64, 128, 256, 512, 1024, 2048]
	var palette := [[C_VIOLET, C_INDIGO], [C_BLUE, C_SKY], [C_TEAL, C_BLUE],
		[C_PINK, C_MAGENTA], [C_ORANGE, C_AMBER], [C_MAGENTA, C_VIOLET]]
	# Fewer live tiles on phones: 15 animated Controls + their collisions are easy
	# on desktop but a steady per-frame tax on a mobile GPU/CPU.
	var count := 10 if OS.has_feature("mobile") else 15
	for i in count:
		# Two depth bands. FAR tiles (~60%) are small, faint and drained toward
		# the backdrop — pure atmosphere that can never fight the menu text.
		# NEAR tiles are bigger and bolder — the grabbable toys — but even they
		# cap well below the old 0.5, so no tile ever outshines a label.
		var far: bool = (i % 5) < 3
		var sz: float = randf_range(46.0, 84.0) if far else randf_range(92.0, 148.0)
		var depth: float = clampf(inverse_lerp(46.0, 84.0, sz) if far \
			else inverse_lerp(92.0, 148.0, sz), 0.0, 1.0)
		var pair: Array = palette[(i * 3 + int(sz)) % palette.size()]
		# Depth is carried by COLOUR, not by opacity. The glass finish is a stack of
		# ~15 overlays (a 0.10 streak, a 0.36 top band, a 0.16 shade) and modulate
		# scales each one's alpha SEPARATELY against the backdrop — at 0.2 the streak
		# composites at 2% white and the whole material dissolves into a flat pale
		# square. So the shards stay near-opaque and recede the way distance actually
		# works: hazed toward the backdrop. Internal contrast survives intact, which
		# is the only reason they read as the same glass the wordmark wears.
		var haze: float = lerpf(0.72, 0.56, depth) if far else lerpf(0.42, 0.24, depth)
		pair = [_depth_tint(pair[0], haze), _depth_tint(pair[1], haze)]
		var alpha: float = lerpf(0.72, 0.85, depth) if far else lerpf(0.90, 1.0, depth)
		var node := _make_toy_tile(sz, values[(i * 2) % values.size()], pair, alpha)
		node.position = Vector2(randf_range(0.0, maxf(0.0, vp.x - sz)),
			randf_range(0.0, maxf(0.0, vp.y - sz)))
		_tiles_bg.add_child(node)
		# Far tiles also drift slower — distance shown through motion, not just tint.
		var drift := Vector2(randf_range(-6.0, 6.0), -lerpf(10.0, 18.0, depth)) if far \
			else Vector2(randf_range(-10.0, 10.0), -lerpf(22.0, 40.0, depth))
		# ph/wr/amp drive the idle tumble; a0 is the resting alpha (grabbing
		# lifts it); sq is the transient collision squish.
		_toys.append({"n": node, "v": drift, "drift": drift, "r": sz * 0.5, "far": far,
			"ph": randf() * TAU, "wr": randf_range(0.4, 0.8),
			"amp": deg_to_rad(randf_range(2.0, 4.0) if far else randf_range(4.0, 7.0)),
			"a0": alpha, "sq": 0.0})

## Aerial perspective: a shard recedes by hazing toward the backdrop it sits in,
## the way distance actually drains a colour — not by going transparent, which
## would take the glass material's overlay contrast down with it (see _spawn_toys).
## The saturation lift first is CandyFace.color's own: the shared painter expects a
## vivid input and builds its body, rim and streak out from there, so feeding it a
## dull colour yields dull glass.
func _depth_tint(c: Color, haze: float) -> Color:
	var vivid := Color.from_hsv(c.h, clampf(c.s * 1.32, 0.0, 1.0), clampf(c.v * 1.08, 0.0, 1.0))
	return vivid.lerp(ThemeManager.color("bg0"), clampf(haze, 0.0, 1.0))

## One flowing tile's face, painted with the BOARD'S OWN glass material — the
## exact painter TileView uses on the grid. It used to be a GradientPanel candy
## pass, whose light runs purely vertically (its terms are functions of UV.y);
## the wordmark beside it is lit from the upper-left, so the two read as
## different materials sharing a screen. CandyFace brings the diagonal glass
## streak, the near-white rim, the wet top band and the tight specular — the
## same cues, from the same code, under the same light.
class ToyFace extends Control:
	var vivid: Color = Color.WHITE
	var number: int = 1
	func _draw() -> void:
		var hw := minf(size.x, size.y) * 0.5
		CandyFace.draw_face_soft(self, size * 0.5, hw, vivid, true)
		# The numeral sits IN the tile, in the tile's own hue lifted toward white
		# so it reads on the glass at every depth haze.
		TileFace.draw_number(self, size * 0.5, hw, number, vivid.lightened(0.35), 1.0, 0.0)

## Builds one flowing piece (a glass tile carrying a number) at the given
## opacity. Input is IGNORED — grabbing is handled centrally in _input, so the
## pieces work even while they live behind the menu.
func _make_toy_tile(sz: float, value: int, pair: Array, alpha: float) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(sz, sz)
	holder.size = Vector2(sz, sz)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.pivot_offset = Vector2(sz, sz) * 0.5
	var face := ToyFace.new()
	face.vivid = (pair[0] as Color).lerp(pair[1] as Color, 0.5)
	# The value is a ramp rung (2, 4, 8 ...); the NUMBER on the tile is its rung,
	# so the field reads as a spill of tiles off a board rather than as a set of
	# unrelated numbers.
	@warning_ignore("integer_division")
	face.number = maxi(1, int(log(maxi(value, 2)) / log(2.0)))
	face.size = Vector2(sz, sz)
	face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(face)
	holder.modulate = Color(1, 1, 1, alpha)
	return holder

# --- Grab / fling handling ----------------------------------------------------
## Handled here (not per-tile) so a tile can be caught even though it sits BEHIND the
## menu: on press we note the tile under the finger; once the drag passes a small
## slop it becomes a grab (we take over and consume the gesture). A plain tap never
## grabs, so it still reaches the menu; a drag on empty space (no tile under it) is
## left alone for the menu to scroll.
const _TOY_SLOP := 12.0
var _tap_glow_at := 0              # ticks of the last press-ripple (echo dedupe)

func _input(event: InputEvent) -> void:
	if _toys.is_empty() or not is_visible_in_tree():
		return
	var down: bool = (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed) \
		or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT)
	var up: bool = (event is InputEventScreenTouch and not (event as InputEventScreenTouch).pressed) \
		or (event is InputEventMouseButton and not (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT)
	if down:
		# Every press answers in light: a neon ripple blooms from the fingertip
		# on the reward themes (their reactive merge hook; a no-op elsewhere).
		# The ticks guard folds a touch and its emulated-mouse echo into one.
		var now := Time.get_ticks_msec()
		if now - _tap_glow_at > 80 and is_instance_valid(_home_fx):
			_tap_glow_at = now
			_home_fx.on_merge(get_global_mouse_position(), 512)
		# The tab bar is opaque glass over the tile field: a press that lands on
		# it must not arm a grab, or a drag across the bar flings a tile the
		# player cannot even see.
		if point_over_nav(get_global_mouse_position()):
			_grab_cand = -1
			return
		_grab_cand = _hit_toy(get_global_mouse_position())
		_grab_start = get_global_mouse_position()
	elif event is InputEventScreenDrag or event is InputEventMouseMotion:
		if _held >= 0:
			get_viewport().set_input_as_handled()
		elif _grab_cand >= 0 and get_global_mouse_position().distance_to(_grab_start) > _TOY_SLOP:
			_begin_grab(_grab_cand)
			get_viewport().set_input_as_handled()
	elif up:
		if _held >= 0:
			var e: Dictionary = _toys[_held]
			e["v"] = (e["v"] as Vector2).limit_length(2800.0)
			_held = -1
			get_viewport().set_input_as_handled()
		_grab_cand = -1

## Index of the top-most flowing tile under `ptr` (global coords), or -1.
func _hit_toy(ptr: Vector2) -> int:
	for i in range(_toys.size() - 1, -1, -1):
		var n: Control = (_toys[i] as Dictionary)["n"]
		if is_instance_valid(n) and n.get_global_rect().has_point(ptr):
			return i
	return -1

## Commit a grab: bring the tile to the front of the field and record the finger offset.
func _begin_grab(idx: int) -> void:
	if idx < 0 or idx >= _toys.size() or _tiles_bg == null:
		return
	_held = idx
	_grab_cand = -1
	var e: Dictionary = _toys[idx]
	var n: Control = e["n"]
	var band := n.get_parent() as Control   # the toy's own depth layer
	band.move_child(n, band.get_child_count() - 1)
	_grab_off = n.position - band.get_local_mouse_position()
	e["v"] = Vector2.ZERO
	Haptics.light()

## The exponential-decay weight for "ease this value toward that one at rate `k`",
## for a step of `delta` seconds.
##
## Every smoother in the toy field used the raw `clampf(delta * k, 0, 1)` form,
## which is NOT frame-rate independent: the fraction it closes per second depends
## on how the step is chopped up. That is normally a background detail — here it
## sat directly under a physics loop that switches between 60 Hz and 30 Hz steps,
## so the tumble, the breath and the ease-back-to-drift all visibly changed pace
## at the moment the rate flipped, on top of the flip itself. `1 - e^(-k·dt)` is
## the same curve at any step size, so the two rates now produce the same motion
## and the handover is invisible. (RULES 9.2.)
func _ease(k: float, delta: float) -> float:
	return 1.0 - exp(-k * delta)

## One physics step: the held tile follows the finger (movement → fling velocity); the
## rest ease back toward a gentle upward flow, wrap around all four edges (never
## trapped inside the screen) and knock into one another.
func _step_toys(delta: float) -> void:
	if _toys.is_empty() or delta <= 0.0 or _tiles_bg == null:
		return
	var vp := get_viewport_rect().size
	# Held tile follows the pointer; its per-frame movement becomes the throw
	# velocity. Grab-juice: it lifts to the finger — scaling up, brightening,
	# and tilting into its own motion like a card carried through the air.
	if _held >= 0 and _held < _toys.size():
		var he: Dictionary = _toys[_held]
		var hn: Control = he["n"]
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			var target: Vector2 = (hn.get_parent() as Control).get_local_mouse_position() + _grab_off
			he["v"] = (target - hn.position) / delta
			hn.position = target
			var k := _ease(10.0, delta)
			hn.rotation = lerpf(hn.rotation,
				clampf((he["v"] as Vector2).x * 0.00022, -0.16, 0.16), k)
			hn.scale = hn.scale.lerp(Vector2(1.1, 1.1), k)
			hn.modulate.a = lerpf(hn.modulate.a, maxf(float(he["a0"]), 0.6), k)
		else:
			he["v"] = (he["v"] as Vector2).limit_length(2800.0)   # fling, capped
			_held = -1
	# Free tiles ease back to their gentle flow, advance, and wrap around the edges.
	var was_hot := _toys_hot
	var hot_lim: float = _TOY_HOT_EXIT_SQ if was_hot else _TOY_HOT_ENTER_SQ
	_toys_hot = false
	for i in _toys.size():
		if i == _held:
			continue
		var e: Dictionary = _toys[i]
		var n: Control = e["n"]
		var v: Vector2 = (e["v"] as Vector2).lerp(e["drift"] as Vector2, _ease(0.6, delta))
		if v.length_squared() > hot_lim:
			_toys_hot = true   # something is flying — keep full-rate physics
		var sz: float = float(e["r"]) * 2.0
		var pos: Vector2 = n.position + v * delta
		if pos.x < -sz:
			pos.x = vp.x
		elif pos.x > vp.x:
			pos.x = -sz
		if pos.y < -sz:
			pos.y = vp.y
		elif pos.y > vp.y:
			pos.y = -sz
		n.position = pos
		e["v"] = v
		# Living-toy juice: a slow tumble and breath (per-tile phase, so the
		# field never moves in unison) plus a brief squish after a collision;
		# everything eases, so a released tile settles back smoothly.
		var sq: float = maxf(float(e["sq"]) - delta * 5.0, 0.0)
		e["sq"] = sq
		var wr: float = float(e["wr"])
		var ph: float = float(e["ph"])
		var k2 := _ease(4.0, delta)
		var k6 := _ease(6.0, delta)
		n.rotation = lerpf(n.rotation, sin(_para_t * wr + ph) * float(e["amp"]), k2)
		var sc: float = (1.0 + 0.02 * sin(_para_t * wr * 1.7 + ph)) * (1.0 - 0.05 * sq)
		n.scale = n.scale.lerp(Vector2(sc, sc), k6)
		n.modulate.a = lerpf(n.modulate.a, float(e["a0"]), k6)
	# Collisions — a thrown tile shoves the others out of its way.
	for i in _toys.size():
		for j in range(i + 1, _toys.size()):
			_collide_toys(i, j)
	# A tile FLUNG through the wordmark's airspace makes the cast flinch and track
	# it — physical comedy tying the two toys together. duck() self-throttles.
	if _word is ExtrudedWord and is_instance_valid(_word) and _word.is_visible_in_tree():
		var wr := (_word as Control).get_global_rect().grow(50.0)
		for e2 in _toys:
			var d2 := e2 as Dictionary
			var n2: Control = d2["n"]
			if is_instance_valid(n2) and (d2["v"] as Vector2).length() > 900.0 \
					and wr.intersects(n2.get_global_rect()):
				(_word as ExtrudedWord).duck(
					n2.global_position.x - (_word as Control).global_position.x)
				break

## Resolve one tile-vs-tile collision (equal-mass, circle approximation). Held tiles
## act as immovable anchors so a grabbed tile can bulldoze the rest.
func _collide_toys(i: int, j: int) -> void:
	var a: Dictionary = _toys[i]
	var b: Dictionary = _toys[j]
	var na: Control = a["n"]
	var nb: Control = b["n"]
	var ra: float = a["r"]
	var rb: float = b["r"]
	var d: Vector2 = (na.position + Vector2(ra, ra)) - (nb.position + Vector2(rb, rb))
	var dist: float = d.length()
	var min_d: float = (ra + rb) * 0.9
	if dist >= min_d or dist <= 0.001:
		return
	var nrm: Vector2 = d / dist
	var overlap: float = min_d - dist
	var a_held: bool = (i == _held)
	var b_held: bool = (j == _held)
	if a_held and not b_held:
		nb.position -= nrm * overlap
	elif b_held and not a_held:
		na.position += nrm * overlap
	else:
		na.position += nrm * (overlap * 0.5)
		nb.position -= nrm * (overlap * 0.5)
	var va: Vector2 = a["v"]
	var vb: Vector2 = b["v"]
	var rel: float = (va - vb).dot(nrm)
	if rel < 0.0:
		var imp: Vector2 = nrm * rel
		if not a_held:
			a["v"] = (va - imp) * 0.98
		if not b_held:
			b["v"] = (vb + imp) * 0.98
		# A real knock: both tiles take a brief squish (eased out in _step_toys).
		a["sq"] = 1.0
		b["sq"] = 1.0

func build_content(root: VBoxContainer) -> void:
	# Reset animation refs — build_content re-runs on every theme change.
	_stat_anim = []
	_pulse_tile = null
	_mini_cells = []
	_word = null
	_capsule_name = null
	_capsule_tier = null
	_capsule_ring = null
	_capsule_glow = null
	root.add_theme_constant_override("separation", int(DesignSystem.SPACE_SM))
	_build_top_bar(root)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode   = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.clip_contents  = true
	scroll.follow_focus   = false
	SmoothWheel.attach(scroll)   # desktop wheel glides instead of stepping
	scroll.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(scroll)
	_scroll = scroll
	_wire_overscroll(scroll)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 34)
	margin.add_theme_constant_override("margin_right", 34)
	margin.add_theme_constant_override("margin_bottom", int(DesignSystem.SPACE_2XL))
	scroll.add_child(margin)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", int(DesignSystem.SPACE_XL))
	# Cap + centre the whole content column on tablets / wide screens so the cards
	# keep their designed proportions; the backdrop still fills the entire screen.
	margin.add_child(UI.constrain_width(col))
	_main_col = col

	_build_hero(col)

	# Prominent sign-in entry (hidden once signed in).
	if AccountManager.is_configured() and not AccountManager.is_signed_in():
		col.add_child(_signin_banner())

	var sessions := _active_sessions()
	if not sessions.is_empty():
		col.add_child(_section("Continue Playing", "accent", _continue_rail(sessions)))
	else:
		# No game in progress — keep play one tap away with a prominent CTA.
		col.add_child(_quick_play_card())

	col.add_child(_stat_strip())

	# "Play a Mode", not "More Modes" — the screen this section's last row opens
	# already owns that title, and two surfaces must not wear the same name.
	col.add_child(_section("Play a Mode", "text_dim", _modes_list()))
	# No Exit button: the bottom tab bar owns this strip now, and quitting was
	# never Home's job to advertise — the hardware back button still raises the
	# very same SceneRouter.request_quit() dialog it always did.

## An eyebrow sitting tightly above its card/body.
func _section(eyebrow_text: String, color_key: String, body: Control) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", int(DesignSystem.SPACE_SM))
	box.add_child(_eyebrow(eyebrow_text, color_key))
	box.add_child(body)
	return box

# ---------------------------------------------------------------------------
# Top bar — profile badge top-left; book + gear circles pinned top-right, with
# the currency strip on its OWN row beneath them: coins and gems under the
# capsule, the leaderboard pill under the gear.
#
# The strip does not share the capsule's row on purpose. Usable width is ~866px
# (UI_SCALE 1.1); the capsule and the two circles already spend most of it, and
# three pills squeezed into what is left would either clip the gear or shrink
# the balances to unreadable. Both rows live OUTSIDE the scroll, so the purse
# stays on screen while the modes list scrolls under it.
# ---------------------------------------------------------------------------
func _build_top_bar(root: VBoxContainer) -> void:
	var bar := HBoxContainer.new()
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_theme_constant_override("separation", int(DesignSystem.SPACE_SM))
	# Profile icon = the player's current tier badge, tracking their progression.
	var ratio: float = GameStats.best_mastery_ratio()["ratio"]
	bar.add_child(_profile_badge(ratio))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(sp)
	# Library icons shown in their own colours (empty tint = no monochrome).
	# The storefront leads the trio. The purse's "+" pills directly below open the
	# Shop FOCUSED on one currency — that is a top-up, and it only exists once the
	# player has already decided what they are short of. This is the way in when
	# they just want the shop, and it is why the icon sits with the other
	# destinations rather than inside the strip. Flat (no baked glow): the token
	# carries its own contour, same as the currency icons under it.
	bar.add_child(UI.circle_button("shop", "",
		func(): SceneRouter.goto(SceneRouter.Route["SHOP"]), 120.0, false))
	bar.add_child(UI.circle_button("how_to_play", "",
		func(): SceneRouter.goto(SceneRouter.Route["HOW_TO_PLAY"]), 120.0))
	# 2048's gear, washed to `text_dim` exactly as 2048 washes it. The PNG itself
	# is violet; the tint is what makes it the quiet grey gear the siblings show,
	# and a gear is chrome, not one of the coloured tokens beside it.
	bar.add_child(UI.circle_button("res://assets/icons/settings.png", "text_dim",
		func(): SceneRouter.goto(SceneRouter.Route["SETTINGS"]), 120.0))
	root.add_child(bar)
	# The purse, directly under the identity it belongs to. CurrencyHud reads
	# Wallet and keeps itself live; Home owns nothing but its placement — and the
	# one placement call it makes: the strip's last pill parks at the RIGHT end,
	# so it lands under the settings gear (this bar ends on the gear and both rows
	# are the same width, so the right edges line up). Coins and gems keep the
	# left, under the identity capsule that earns them; the leaderboard — the one
	# pill that is a destination rather than a balance — takes the far end, beside
	# the other destinations in the row above it.
	var purse := CurrencyHud.new()
	purse.trailing_action = true
	root.add_child(purse)
	# No bounty card here. The daily tasks still run and still pay (Progression
	# owns both) — Home simply does not spend its first screenful listing chores
	# above the wordmark. Where they pay from is spelled out on the Shop's
	# earning card.

## The identity capsule — the top-left corner reads as "this is YOU": the tier
## badge, ringed by its progress toward the next tier on a breathing accent
## glow, beside the player's name and rank inside one glass pill. The whole
## pill routes to the BADGE page (the progression screen this badge belongs to),
## NOT to the Profile tab. A rank earned since the last visit plays a one-time
## flare — pop + shard burst — then is remembered in the profile save section
## so it never replays.
func _profile_badge(ratio: float) -> Control:
	const SZ := 128.0
	const RING_TH := 7.0
	var idx := TierBadge.current_index(ratio)
	var accent: Color = ThemeManager.color("accent") if idx < 0 else TierBadge.tier(idx)["accent"]
	var next_accent: Color = ThemeManager.color("gold") if idx + 1 >= TierBadge.count() \
		else TierBadge.tier(idx + 1)["accent"]
	# The flare must read the persisted tier BEFORE it is re-stamped.
	var rank_up := idx > _seen_tier()
	if rank_up:
		_mark_seen_tier(idx)   # persist NOW so a mid-flare rebuild can't replay it

	# The same frosted shard the mode cards below it are cut from, at a capsule's
	# radius: badge nearly flush left, real air after the text.
	var capsule := UI.glass_pill(1)
	capsule.margin_left = DesignSystem.SPACE_XS
	capsule.margin_right = DesignSystem.SPACE_LG
	capsule.margin_top = DesignSystem.SPACE_XS
	capsule.margin_bottom = DesignSystem.SPACE_XS
	capsule.mouse_filter = Control.MOUSE_FILTER_PASS

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(DesignSystem.SPACE_SM))
	capsule.add_child(row)

	# The badge stack — glow + tier ring + shield — in an inner wrapper that
	# gently floats without fighting the HBox, which owns the box's position.
	var badge_box := Control.new()
	badge_box.custom_minimum_size = Vector2(SZ, SZ)
	badge_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(badge_box)
	var inner := Control.new()
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.pivot_offset = Vector2(SZ, SZ) * 0.5
	badge_box.add_child(inner)

	# The glow wears the player's chosen aura when one is set (profile "avatar").
	var avatar_i := int(SaveManager.get_section("profile", {}).get("avatar", -1))
	var glow := TierBadge.accent_glow(SZ, TierBadge.aura_color(avatar_i, Color(0, 0, 0, 0)))
	inner.add_child(glow)
	_capsule_glow = glow

	# The tier ring — the same "progress to the next tier" arc the Profile hero
	# wears, so the top bar carries live progression at a glance.
	var ring := ProgressRing.new()
	ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	ring.thickness = RING_TH
	ring.track_color = ThemeManager.color("stroke")
	ring.color_a = accent
	ring.color_b = next_accent
	var ring_target := TierBadge.progress_to_next(ratio)
	inner.add_child(ring)
	_capsule_ring = ring

	var view := TierBadge.make_view(SZ, maxi(idx, 0), idx < 0)
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	view.custom_minimum_size = Vector2.ZERO
	var inset := RING_TH + 6.0
	view.offset_left = inset; view.offset_top = inset
	view.offset_right = -inset; view.offset_bottom = -inset
	view.material = TierBadge.shine_material()
	inner.add_child(view)
	# The equipped frame (identity sheet), in the chosen aura colour. Through
	# TierBadge.equipped_frame, so the capsule cannot wear a decoration the Badge
	# page it opens would refuse to draw.
	TierBadge.add_frame(inner, SZ,
		TierBadge.equipped_frame(SaveManager.get_section("profile", {})),
		TierBadge.aura_color(avatar_i, accent))

	# Name + rank beside the badge.
	var namecol := VBoxContainer.new()
	namecol.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	namecol.add_theme_constant_override("separation", 2)
	var name_lbl := _label(_identity_name(), 38)
	# BOUNDED. A Play Games gamer tag is whatever its owner typed, and an
	# unexpanding FitLabel claims its natural width, so a seventeen-letter tag
	# ("Rowan Leaderboard", which flow_currency_hud plants) pushed the top row
	# past the 982-point page budget - whose only visible symptom was the gear
	# clipped at the far end. Past the cap the name shrinks its type, exactly
	# as the leaderboard rows treat the same tag.
	name_lbl.max_width = CAPSULE_NAME_MAX
	name_lbl.add_theme_color_override("font_color", ThemeManager.color("text"))
	if ThemeManager.display_font:
		name_lbl.add_theme_font_override("font", ThemeManager.display_font)
	namecol.add_child(name_lbl)
	_capsule_name = name_lbl
	var tier_text := "UNRANKED" if idx < 0 else String(TierBadge.tier(idx)["name"]).to_upper()
	var tier_lbl := _label(tier_text, 27)
	tier_lbl.add_theme_color_override("font_color",
		accent if idx >= 0 else ThemeManager.color("text_dim"))
	namecol.add_child(tier_lbl)
	_capsule_tier = tier_lbl
	row.add_child(namecol)

	# The whole capsule is one button: squish on press, then the BADGE page.
	#
	# Badge, not Profile. This capsule IS the tier badge, so tapping it opens the
	# page about that badge — the hero shield, the rank ladder, the trophy case
	# and per-mode mastery. The account/membership page is the bottom-nav Profile
	# TAB and is reached there; sending a rank badge to a membership card is the
	# mis-wire this route exists to prevent (see scenes/badge/badge.gd).
	var btn := Button.new()
	btn.flat = true
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for st in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	btn.pressed.connect(func():
		AudioManager.play_sfx("button_tap", 0.04)
		Haptics.light()
		SceneRouter.goto(SceneRouter.Route["BADGE"]))
	capsule.add_child(btn)
	UI.wire_press(capsule, btn)

	# A slow float + breathing glow + the ring filling in — and, the first time
	# a new tier is worn, the flare.
	glow.modulate.a = 0.7
	ring.value = 0.0
	inner.tree_entered.connect(func():
		var bob := inner.create_tween().set_loops()
		bob.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		bob.tween_property(inner, "position:y", -4.0, 1.9)
		bob.tween_property(inner, "position:y", 4.0, 1.9)
		var gt := glow.create_tween().set_loops()
		gt.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		gt.tween_property(glow, "modulate:a", 1.0, 1.6)
		gt.tween_property(glow, "modulate:a", 0.55, 1.7)
		var rt := ring.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		rt.tween_property(ring, "value", ring_target, DesignSystem.DUR_SLOW).set_delay(0.25)
		if rank_up:
			var flare := inner.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
			flare.tween_interval(0.6)
			flare.tween_callback(func():
				if is_instance_valid(inner):
					TierBadge.sparkle_burst(inner, SZ, accent)
					Haptics.success())
			flare.tween_property(inner, "scale", Vector2(1.22, 1.22), 0.16)
			flare.tween_property(inner, "scale", Vector2.ONE, 0.3))
	return capsule

## Who the capsule names: the Play Games gamer tag once it lands, else the
## locally saved profile name — truncated so a long tag can't blow the top bar
## past the ~982 usable width.
func _identity_name() -> String:
	var n := AccountManager.display_name()
	if n.is_empty():
		n = String(SaveManager.get_section("profile", {}).get("name", "Player"))
	return n if n.length() <= 14 else n.substr(0, 13) + "…"

## In-place refresh of the identity capsule for AccountManager.profile_changed —
## the PGS gamer tag lands AFTER the session does, mid-entrance. Only the
## capsule's CONTENTS move (name, rank line, ring/glow tints, all re-derived
## from the same sources _profile_badge reads); every node keeps its identity,
## so the entrance stagger, the bob/breath tweens and the rest of the column are
## never torn down for one label's worth of change. Re-applying an unchanged
## value is a visual no-op, so this is safe however little actually moved.
## PGS v2 doctrine: state is derived live at the moment the signal fires.
## The equipped FRAME is deliberately not re-derived: frames change only on the
## Profile screen, and the trip back rebuilds Home (and this capsule) wholesale.
func _refresh_identity_capsule() -> void:
	if not is_instance_valid(_capsule_name):
		return   # capsule mid-rebuild (theme change) — the rebuild reads the new state
	_capsule_name.text = _identity_name()
	_capsule_name.budget_text = _capsule_name.text
	var ratio: float = GameStats.best_mastery_ratio()["ratio"]
	var idx := TierBadge.current_index(ratio)
	var accent: Color = ThemeManager.color("accent") if idx < 0 else TierBadge.tier(idx)["accent"]
	if is_instance_valid(_capsule_tier):
		_capsule_tier.text = "UNRANKED" if idx < 0 else String(TierBadge.tier(idx)["name"]).to_upper()
		_capsule_tier.add_theme_color_override("font_color",
			accent if idx >= 0 else ThemeManager.color("text_dim"))
	if is_instance_valid(_capsule_ring):
		_capsule_ring.color_a = accent
		_capsule_ring.color_b = ThemeManager.color("gold") if idx + 1 >= TierBadge.count() \
			else TierBadge.tier(idx + 1)["accent"]
		_capsule_ring.value = TierBadge.progress_to_next(ratio)
	if is_instance_valid(_capsule_glow):
		# Retint via TierBadge's own recipe (no duplicated colour math): bake a
		# fresh glow, keep only its texture — the node in the tree, its breathing
		# tween and its layout never change.
		var avatar_i := int(SaveManager.get_section("profile", {}).get("avatar", -1))
		var baked := TierBadge.accent_glow(128.0,   # SZ in _profile_badge
			TierBadge.aura_color(avatar_i, Color(0, 0, 0, 0)))
		_capsule_glow.texture = baked.texture
		baked.free()

## The last tier the flare celebrated (-1 = never ranked / fresh save).
func _seen_tier() -> int:
	return int(SaveManager.get_section("profile", {}).get("seen_tier", -1))

## Remember the flare was played so it can never replay — merged into the
## profile section rather than replacing it (identity lives there too).
func _mark_seen_tier(idx: int) -> void:
	var p: Dictionary = SaveManager.get_section("profile", {"name": "Player", "avatar": -1})
	p["seen_tier"] = idx
	SaveManager.set_section("profile", p)

# ---------------------------------------------------------------------------
# Hero — gradient wordmark + tagline (left aligned).
# ---------------------------------------------------------------------------
func _build_hero(col: VBoxContainer) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(DesignSystem.SPACE_SM))

	# ONE LINE OF THE GAME, PLAYABLE. The hero slot used to carry the app's mark
	# at hero scale — nine letter tiles in a 3x3 block — and at that size it had
	# stopped being a logo and become a second board: a screenful of tiles the
	# player could not play, above the ones they came for. A real 3x3 in its place
	# was no better, because a whole grid in a menu still asks for turns and a
	# finish before the player has even chosen a mode. So the slot holds THREE
	# SOCKETS: tap, tap, tap, the line lights and it clears itself. Something to
	# do on the way past. The MARK still opens the app — it is the whole loading
	# screen (see scenes/splash), which is where a logo belongs and a menu does not.
	# FIT-TO-SCREEN: the app renders at content-scale 1.1 → design width ~982, so
	# the strip is sized off the live viewport, never a hardcoded width.
	var vp_w: float = get_viewport_rect().size.x
	var strip := LineBoard.make(clampf(vp_w * 0.56, 300.0, 480.0))
	strip.setup(ThemeManager.palette())
	# A line made on the hero gets the menu's own celebration — the strip only
	# throws its local confetti.
	strip.line_made.connect(_spawn_celebration)
	# TWO GESTURES on one control: a tap is a MOVE and belongs to the board, a
	# LONG PRESS charges the confetti bomb (_on_wordmark_input). They never
	# collide, because LineBoard refuses to slide on a press that outlived
	# `long_press_s`, and that is the very threshold the charge starts at. One
	# number, set here, so the two cannot drift apart.
	strip.long_press_s = _WM_HOLD_S
	strip.gui_input.connect(_on_wordmark_input)
	# The strip rides in a HOLDER, and the holder is what `_word` points at: the
	# hero is scaled from here (_bounce_word), and the strip draws, so the tween
	# has to land on something that does not — a drawing node re-records its whole
	# draw list every frame it is transformed. Same rule the strip documents.
	var holder := CenterContainer.new()
	holder.mouse_filter = Control.MOUSE_FILTER_PASS
	holder.add_child(strip)
	if _theme_surprise:
		_theme_surprise = false
		holder.tree_entered.connect(func(): _bounce_word(1.12), CONNECT_ONE_SHOT)
	box.add_child(holder)
	_word = holder

	var tagline := _label("Five ways to slide. One order.", 46)
	tagline.add_theme_color_override("font_color", ThemeManager.color("text_dim"))
	tagline.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_text_shadow(tagline)
	box.add_child(tagline)
	col.add_child(box)

# ---------------------------------------------------------------------------
# Quick Play — a big primary CTA shown when there is no game in progress, so the
# main action is always one tap. Starts Classic (the canonical mode); the other
# two featured boards are in the list below, and the rest are one further tap
# away through its "More Modes" row.
# ---------------------------------------------------------------------------
func _quick_play_card() -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(0, 176)
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var a: Color = C_VIOLET
	var b: Color = C_BLUE
	# Premium themes tint the CTA to match their board.
	if ThemeManager.board_style() != "plain":
		var luxe := ThemeManager.board_accent()
		a = luxe.lerp(Color.BLACK, 0.15)
		b = luxe.lerp(Color.WHITE, 0.25)
	# A soft breathing halo behind the hero CTA so the main action glows.
	_add_cta_glow(holder, a.lerp(b, 0.5))
	var grad := GradientPanel.make(a, b, 36.0, Vector2(1, 0))
	grad.set_anchors_preset(Control.PRESET_FULL_RECT)
	grad.sheen = 1.0   # animated specular sweep across the gradient
	holder.add_child(grad)

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", int(DesignSystem.SPACE_MD))
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(row)

	var glyph := Label.new()
	glyph.text = "▶"
	glyph.add_theme_font_size_override("font_size", 52)
	glyph.add_theme_color_override("font_color", Color.WHITE)
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(glyph)

	var lbl := _label("Play", 66)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if ThemeManager.display_font:
		lbl.add_theme_font_override("font", ThemeManager.display_font)
	row.add_child(lbl)

	var btn := Button.new()
	btn.flat = true
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for st in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	btn.pressed.connect(func():
		AudioManager.play_sfx("button_tap", 0.04)
		Haptics.light()
		_start("classic"))
	holder.add_child(btn)
	UI.wire_press(holder, btn)
	return holder

# ---------------------------------------------------------------------------
# Sign-in banner — an unmissable Play Games sign-in entry on Home. Tapping
# fires the PGS prompt inline; if it fails, auth_changed rebuilds Home and the
# banner simply stays (no toast here — Profile/Premium carry that feedback).
# ---------------------------------------------------------------------------
func _signin_banner() -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(0, 140)
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var grad := GradientPanel.make(C_INDIGO, C_VIOLET, 30.0, Vector2(1, 0))
	grad.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(grad)

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", int(DesignSystem.SPACE_MD))
	row.offset_left = 28
	row.offset_right = -28
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(row)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var t := _label("Sign in to Play Games", 42)
	t.add_theme_color_override("font_color", Color.WHITE)
	if ThemeManager.display_font:
		t.add_theme_font_override("font", ThemeManager.display_font)
	col.add_child(t)
	var s := _label("Play with your Google Play Games profile.", 27)
	s.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
	col.add_child(s)
	row.add_child(col)

	var arrow := _label("→", 44)
	arrow.add_theme_color_override("font_color", Color.WHITE)
	arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(arrow)

	var btn := Button.new()
	btn.flat = true
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for st in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	btn.pressed.connect(func():
		AudioManager.play_sfx("button_tap", 0.04)
		Haptics.light()
		AccountManager.sign_in())
	holder.add_child(btn)
	UI.wire_press(holder, btn)
	return holder

# ---------------------------------------------------------------------------
# Continue rail — every mode with a resumable session, most-recent first.
# ---------------------------------------------------------------------------
## Every mode with a resumable in-progress session, most-recently-played first.
## "_last" is Gameplay's Settings-round-trip bookkeeping, not a real session,
## so filtering to real GameModes ids drops it automatically.
##
## A LOCKED mode is dropped too. After a refund revokes premium the save still
## holds the Grand runs, but "Continue →" is a promise this rail cannot
## keep: the tap is correctly diverted to the paywall by _continue_game, so the
## card would advertise a resume that never happens — and it carries no PREMIUM
## marker to warn of it. Hiding beats marking here because a resume shelf whose
## cards cannot resume is the wrong place for an upsell: the mode row below still
## shows the same mode as "PREMIUM · tap to unlock", which is honest about what a
## tap does. This is display-only — the saved run is never touched, so re-owning
## premium brings the card straight back (premium_changed rebuilds Home live).
func _active_sessions() -> Array:
	var raw := SaveManager.get_section("current_game", {})
	var valid_ids := {}
	for m in GameModes.all():
		valid_ids[m.id] = true
	var out: Array = []
	for mode_id in raw.keys():
		if not valid_ids.has(mode_id) or typeof(raw[mode_id]) != TYPE_DICTIONARY:
			continue
		if not EntitlementManager.is_mode_unlocked(String(mode_id)):
			continue
		out.append({"mode_id": mode_id, "session": raw[mode_id]})
	out.sort_custom(func(a, b):
		return int((a["session"] as Dictionary).get("saved_at", 0)) \
			> int((b["session"] as Dictionary).get("saved_at", 0)))
	return out

## Reference-style layout: TWO sessions sit side by side as equal vertical
## cards — everything visible, nothing clipped. One session gets a single
## full-width card; three or more become a swipeable rail of the same cards.
func _continue_rail(sessions: Array) -> Control:
	if sessions.size() == 1:
		var d0 := sessions[0] as Dictionary
		return _continue_card(d0["session"] as Dictionary, String(d0["mode_id"]))
	if sessions.size() == 2:
		var row2 := HBoxContainer.new()
		row2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row2.add_theme_constant_override("separation", int(DesignSystem.SPACE_MD))
		for entry in sessions:
			var d := entry as Dictionary
			var c := _continue_card(d["session"] as Dictionary, String(d["mode_id"]))
			c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			c.size_flags_stretch_ratio = 1.0
			row2.add_child(c)
		return row2
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.clip_contents = true
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(DesignSystem.SPACE_MD))
	for entry in sessions:
		var d := entry as Dictionary
		var c := _continue_card(d["session"] as Dictionary, String(d["mode_id"]))
		# 400 fits TWO full cards + a peek of the third inside the real ~866
		# content width (470 was sized for the imaginary 1080).
		c.custom_minimum_size = Vector2(400, 0)
		row.add_child(c)
	scroll.add_child(row)
	return scroll

## One Continue card, stacked vertically like the reference: mode name, a
## crown + score line, the live glimpse, then a full-width Continue pill.
## The Continue card's score ceiling — see BEST_SCORE_SLOT for the same rule on
## the ladder below it.
const CONTINUE_SCORE_SLOT := 200.0

func _continue_card(session: Dictionary, mode_id: String) -> Control:
	var mode := GameModes.get_mode(mode_id)
	var card := UI.glass_card(2)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", int(DesignSystem.SPACE_SM))
	card.add_child(col)

	# The title must never dictate the card's width (that is what used to shove
	# the second card off-screen). A Label's minimum only collapses when
	# autowrap is ON, so: autowrap + one visible line + ellipsis = a title that
	# fills whatever the card gives it and trims in the extreme.
	var title := _label(mode.title, 48)
	title.add_theme_color_override("font_color", ThemeManager.color("text"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.max_lines_visible = 1
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if ThemeManager.display_font:
		title.add_theme_font_override("font", ThemeManager.display_font)
	col.add_child(title)

	# Crown + score — the run's worth at a glance, in gold.
	var sl := HBoxContainer.new()
	sl.add_theme_constant_override("separation", int(DesignSystem.SPACE_XS))
	sl.add_child(_tex_icon("highest_tile", 48))
	var score := _label(UI.commafy(_session_score(session)), 42)
	# Two of these cards sit side by side on the Continue rail, so the run's worth
	# is capped the same way the ladder's is — past the ceiling it shrinks rather
	# than widening a card that has a twin to fit beside it.
	score.max_width = CONTINUE_SCORE_SLOT
	score.add_theme_color_override("font_color", ThemeManager.color("gold"))
	sl.add_child(score)
	col.add_child(sl)

	# The live glimpse, centred in the card's body.
	var glimpse := _session_glimpse(session, mode.id)
	glimpse.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	glimpse.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(glimpse)

	col.add_child(UI.spacer(DesignSystem.SPACE_XS, false))
	col.add_child(_continue_pill(mode.id))

	UI.make_scroll_tappable(card, func(): _continue_game(mode.id))
	return card

## The run's score. Cube, Orbit and Lattice wrote sessions with no top-level
## "score" until they started mirroring one, so a card for a run worth thousands
## read a flat zero; their board dict still carries it, and that is the fallback
## every save written before this change resumes through.
func _session_score(session: Dictionary) -> int:
	if session.has("score"):
		return int(session["score"])
	var raw: Variant = session.get("board", null)
	if typeof(raw) == TYPE_DICTIONARY:
		return int((raw as Dictionary).get("score", 0))
	return 0

## The picture of the saved run on its card.
##
## A board whose SHAPE is the mode draws itself — the honeycomb, the volume, the
## solid, the globe, matter and void (see ui/components/session_preview.gd, which
## also records what each of them used to look like resolved as a square grid:
## empty, or nearly). Everything else is a square grid of "x,y" cells and gets
## the corner crop below, or the highest-tile chip when there is no grid at all.
func _session_glimpse(session: Dictionary, mode_id: String) -> Control:
	var shaped := SessionPreview.build(mode_id, session)
	if shaped != null:
		return shaped
	if session.has("board"):
		return _mini_board(session)
	return _physics_glimpse(session)

## A simple glimpse for Merge Drop/Fling — a scattered physics field has no
## natural "corner" to preview, so this shows the run's biggest tile instead.
func _physics_glimpse(session: Dictionary) -> Control:
	var highest := int(session.get("highest", 0))
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", int(DesignSystem.SPACE_XS))

	# The full glass-neon face (halo, rim, streak) at 104px — radius stays ~15%
	# via the shared CandyFace mask; the empty state is the boards' glass socket.
	var cell := GlassCell.new(highest, 104.0)
	if highest > 0:
		var lbl := Label.new()
		lbl.text = str(highest)
		lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.add_theme_color_override("font_color",
			CandyFace.text_color(CandyFace.color(highest)))
		lbl.add_theme_font_size_override("font_size", 30 if str(highest).length() <= 3 else 24)
		cell.add_child(lbl)
	col.add_child(cell)
	_pulse_tile = cell   # the entrance flourish breathes this like a grid best tile

	var cap := Label.new()
	cap.text = "Highest"
	cap.add_theme_font_size_override("font_size", 28)
	cap.add_theme_color_override("font_color", ThemeManager.color("text_dim"))
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(cap)
	return col

func _continue_pill(mode_id: String) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(0, 100)
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var grad := GradientPanel.make(C_VIOLET, C_BLUE, 30.0, Vector2(1, 0))
	grad.set_anchors_preset(Control.PRESET_FULL_RECT)
	grad.sheen = 1.0
	holder.add_child(grad)

	var lbl := Label.new()
	lbl.text = "Continue  →"
	lbl.add_theme_font_size_override("font_size", 40)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(lbl)

	var btn := Button.new()
	btn.flat = true
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	btn.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	btn.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.pressed.connect(func():
		AudioManager.play_sfx("button_tap", 0.04)
		Haptics.light()
		_continue_game(mode_id))
	holder.add_child(btn)
	UI.wire_press(holder, btn)
	return holder

## A compact glimpse of the saved board: its centre 3×3, marks and all. The save's
## "board" is {"n": size, "cells": [0 | 1 (X) | 2 (O), row-major]}; a wider board
## (Gravity, Five) shows its middle, which is where the action is.
func _mini_board(saved: Dictionary) -> Control:
	var board: Dictionary = saved.get("board", {})
	var n := int(board.get("n", 3))
	var cells: Array = board.get("cells", [])
	# A board that is not square keeps its cells as one row (the cube's 54
	# stickers are stored 54 x 1), so the centre crop below would index past the
	# end of the array and draw an empty card for a game in progress. Read those
	# as a flat list and show the FIRST nine, which for the cube is the face the
	# tray opens on.
	if n * n > cells.size():
		n = 3
	var x0 := maxi((n - 3) / 2, 0)
	var y0 := x0
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	var last_cell: Control = null
	for y in range(y0, y0 + 3):
		for x in range(x0, x0 + 3):
			var v := 0
			var idx := y * n + x
			if x < n and y < n and idx < cells.size():
				v = int(cells[idx])
			# The BAND is the tile's home row on the real board, not the row of the
			# glimpse, so the colours here are the ones the player is looking at.
			@warning_ignore("integer_division")
			var home_row: int = (v - 1) / n if v > 0 else 0
			var cell := _mini_tile(v, home_row, n)
			grid.add_child(cell)
			_mini_cells.append(cell)
			if v > 0:
				last_cell = cell
	# The most recent mark breathes on the Home screen (set up in _start_flourishes).
	if last_cell != null:
		_pulse_tile = last_cell
	return grid

## One Continue-card glass cell: paints the shared CandyFace glass-neon finish
## for a value tile (hue halo, near-white rim, gradient body, diagonal streak),
## or the boards' luminous empty socket when the cell is empty. Stays a SINGLE
## sized Control — _mini_wiggle and _pulse_tile write pivot_offset + scale on it.
class GlassCell extends Control:
	var value := 0

	func _init(p_value: int, px: float) -> void:
		value = p_value
		custom_minimum_size = Vector2(px, px)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		var hw := minf(size.x, size.y) * 0.5
		if hw <= 0.0:
			return
		var centre := size * 0.5
		if value > 0:
			CandyFace.draw_face(self, centre, hw, CandyFace.color(value))
			return
		# Empty socket — the boards' CellWell recipe at mini scale: a whisper of
		# outer glow, a thin luminous rim, a barely-lifted vertical-gradient well.
		var p := ThemeManager.palette()
		var bg2: Color = p["bg2"]
		var bg0: Color = p["bg0"]
		var well: Color = bg2.lerp(bg0, 0.45)
		var rim: Color = ThemeManager.color("accent").lerp(Color(1, 1, 1), 0.3)
		var tex := CandyFace.mask()
		var uvs := PackedVector2Array([
			Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
		var ge := hw * 1.07
		draw_texture_rect(tex, Rect2(centre - Vector2(ge, ge), Vector2(ge, ge) * 2.0),
			false, Color(rim.r, rim.g, rim.b, 0.08))
		draw_polygon(PackedVector2Array([
			centre + Vector2(-hw, -hw), centre + Vector2(hw, -hw),
			centre + Vector2(hw, hw), centre + Vector2(-hw, hw)]),
			PackedColorArray([
				Color(rim.r, rim.g, rim.b, 0.34), Color(rim.r, rim.g, rim.b, 0.34),
				Color(rim.r, rim.g, rim.b, 0.22), Color(rim.r, rim.g, rim.b, 0.22)]),
			uvs, tex)
		var bw := hw * 0.976
		var ft := well.lightened(0.11)
		var fb := well.lightened(0.05)
		draw_polygon(PackedVector2Array([
			centre + Vector2(-bw, -bw), centre + Vector2(bw, -bw),
			centre + Vector2(bw, bw), centre + Vector2(-bw, bw)]),
			PackedColorArray([ft, ft, fb, fb]), uvs, tex)

## One Continue-card cell: the board's empty glass socket, and the numbered tile
## sitting in it if there is one. A hole is drawn as the bare socket, which is
## what makes a three-by-three glimpse read as a slide board and not a grid.
class TileCell extends GlassCell:
	var number := 0
	## The row the number belongs to, for the band colour.
	var row := 0
	var rows := 3

	func _init(p_number: int, p_row: int, p_rows: int, px: float) -> void:
		super._init(0, px)
		number = p_number
		row = p_row
		rows = p_rows

	func _draw() -> void:
		super._draw()
		if number <= 0:
			return
		var hw := minf(size.x, size.y) * 0.5
		var vivid := CandyFace.color(BoardView.ramp_for_row(row, rows))
		TileFace.draw_tile(self, size * 0.5, hw * 0.94, number, vivid)

func _mini_tile(number: int, row: int = 0, rows: int = 3) -> Control:
	return TileCell.new(number, row, rows, 64.0)

# ---------------------------------------------------------------------------
# Stat strip — one card, four icon columns with hairline dividers.
# ---------------------------------------------------------------------------
func _stat_strip() -> Control:
	var card := UI.glass_card(2)
	card.custom_minimum_size = Vector2(0, 240)
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(row)

	var streak := int(GameStats.get_stat("current_streak_days"))
	var ach := Achievements.unlocked_count()
	var wins := int(GameStats.get_stat("games_won"))
	var games := int(GameStats.get_stat("games_played"))

	# Every tile is a doorway: Achievements opens the achievements gallery, the
	# rest open Statistics (which holds the per-mode bests, win rate and totals).
	# SHORT captions, sized up — "Badges" beats a tiny "Achievements" on a phone.
	row.add_child(_stat_col("day_streak", streak, "Streak", "STATISTICS"))
	row.add_child(_divider())
	row.add_child(_stat_col("rank_badge", ach, "Badges", "ACHIEVEMENTS"))
	row.add_child(_divider())
	row.add_child(_stat_col("games_won", wins, "Wins", "STATISTICS"))
	row.add_child(_divider())
	row.add_child(_stat_col("games_played", games, "Games", "STATISTICS"))
	return card

func _stat_col(icon_path: String, value: int, caption_text: String, route: String = "") -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", int(DesignSystem.SPACE_XS))
	if not route.is_empty():
		box.mouse_filter = Control.MOUSE_FILTER_STOP
		UI.make_scroll_tappable(box, func():
			SceneRouter.goto(SceneRouter.Route[route]))

	var icon := _tex_icon(icon_path, 120)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(icon)

	var v := _label(str(value), 64)
	v.add_theme_color_override("font_color", ThemeManager.color("text"))
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if ThemeManager.display_font:
		v.add_theme_font_override("font", ThemeManager.display_font)
	box.add_child(v)
	# Registered so the entrance flourish can count it up from zero.
	_stat_anim.append({"label": v, "target": value})

	# Big readable captions — the labels are kept SHORT so 32 still clears the
	# four columns on a phone.
	var c := _label(caption_text, 32)
	c.add_theme_color_override("font_color", ThemeManager.color("text_dim"))
	c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(c)
	return box

func _divider() -> Control:
	# A hairline that fades to nothing at top and bottom — softer than a flat bar.
	var line := TextureRect.new()
	line.custom_minimum_size = Vector2(1, 96)
	line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	line.stretch_mode = TextureRect.STRETCH_SCALE
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var col: Color = ThemeManager.color("text")
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([
		Color(col.r, col.g, col.b, 0.0),
		Color(col.r, col.g, col.b, 0.16),
		Color(col.r, col.g, col.b, 0.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_LINEAR
	gt.fill_from = Vector2(0.5, 0.0)
	gt.fill_to = Vector2(0.5, 1.0)
	gt.width = 1
	gt.height = 64
	line.texture = gt
	return line

# ---------------------------------------------------------------------------
# Game modes — the three featured boards, then the doorway to the rest.
#
# Home shows a SHORTLIST, not the catalog. Eleven rows made the hub a scroll
# through everything the game has rather than a place to start playing, so the
# three grid boards (the ladder a new player actually climbs — 4x4, 5x5, 6x6)
# stay here and every other mode lives on Mode Select behind "More Modes".
# Mode Select still lists ALL of them, this one included: it is the full
# catalog, and a player who went looking for Classic there must find it.
# ---------------------------------------------------------------------------
func _modes_list() -> Control:
	var section := VBoxContainer.new()
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section.add_theme_constant_override("separation", int(DesignSystem.SPACE_MD))
	for mode_id in FEATURED_MODE_IDS:
		section.add_child(_mode_row(mode_id))
	# The rest of the catalog lives one tap away rather than eleven rows down.
	return section


func _mode_row(mode_id: String) -> Control:
	var mode := GameModes.get_mode(mode_id)
	var pair: Array = MODE_COLORS.get(mode_id, [C_VIOLET, C_INDIGO])
	var col_a: Color = pair[0]

	var card := UI.glass_card(2)
	card.custom_minimum_size = Vector2(0, 180)
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(DesignSystem.SPACE_MD))
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_child(row)

	# Mode icon — the sheet's own gradient art (each mode has its own).
	var tile_holder := Control.new()
	tile_holder.custom_minimum_size = Vector2(140, 140)
	tile_holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var micon := TextureRect.new()
	micon.texture = UI.icon_tex(mode.icon_path)
	micon.set_anchors_preset(Control.PRESET_FULL_RECT)
	micon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	micon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	micon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile_holder.add_child(micon)
	row.add_child(tile_holder)

	# Middle: title, tagline, best line.
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mid.add_theme_constant_override("separation", 6)

	var title := _label(mode.title, 56)
	title.add_theme_color_override("font_color", ThemeManager.color("text"))
	if ThemeManager.display_font:
		title.add_theme_font_override("font", ThemeManager.display_font)
	mid.add_child(title)

	# Readable on a phone beats one-line purity — 32, wrapping where it must.
	var sub := _label(mode.tagline, 32)
	sub.add_theme_color_override("font_color", ThemeManager.color("text_dim"))
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mid.add_child(sub)

	if EntitlementManager.is_mode_unlocked(mode_id):
		mid.add_child(_mode_best_line(mode_id, col_a))
	else:
		var lock := _label("PREMIUM · tap to unlock", 30)
		lock.add_theme_color_override("font_color", ThemeManager.color("accent"))
		mid.add_child(lock)
	row.add_child(mid)

	# Play button — the sheet's glossy play circles, cycling the colour story.
	row.add_child(UI.play_button(mode.play_icon, func(): _start(mode.id)))

	UI.make_scroll_tappable(card, func(): _start(mode.id))
	return card

## "Best 2048 · Score 20,204" — the player's highest tile in this mode first
## (the metric that matters in 2048), then their best score. Captions are kept
## SHORT: this line's minimum width is what used to shove the whole content
## column past the 982-unit screen, so every word here costs real margin.
## The two numbers' width ceilings. This line is the tightest thing on the app's
## tightest page, so the figures are the one part of it allowed to grow — and a
## seven-figure best score was measured pushing the whole content frame to 1000
## against a 982-unit screen. Past the ceiling they shrink their type instead.
const BEST_TILE_SLOT := 110.0
const BEST_SCORE_SLOT := 148.0
## The widest the capsule's name may claim: the 933-point top row less the
## three circle buttons with their gaps and the capsule's own badge + padding,
## with air to spare. Measured with tools/width_probe.tscn on Home.
const CAPSULE_NAME_MAX := 368.0

func _mode_best_line(mode_id: String, accent: Color) -> Control:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", int(DesignSystem.SPACE_XS))

	var best_d := SaveManager.get_section(BEST_SECTION, {})
	var score: int = int(best_d.get(mode_id, 0))
	var rec := GameStats.mode_record(mode_id)
	var best_tile: int = int(rec.get("series_won", 0))   # series won on this board

	if score <= 0 and best_tile <= 0:
		var none := _label("Not played yet", 34)
		none.add_theme_color_override("font_color", ThemeManager.color("text_faint"))
		line.add_child(none)
		return line

	if best_tile > 0:
		var tcap := _label("Won ", 34)
		tcap.add_theme_color_override("font_color", ThemeManager.color("text_dim"))
		tcap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		line.add_child(tcap)
		var tile_val := _label(str(best_tile), 38)
		tile_val.max_width = BEST_TILE_SLOT
		tile_val.add_theme_color_override("font_color", ThemeManager.color("gold"))
		line.add_child(tile_val)

	if score > 0:
		var scap := _label(("  ·  Score " if best_tile > 0 else "Score "), 34)
		scap.add_theme_color_override("font_color", ThemeManager.color("text_dim"))
		scap.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		line.add_child(scap)
		var score_val := _label(UI.commafy(score), 38)
		score_val.max_width = BEST_SCORE_SLOT
		score_val.add_theme_color_override("font_color", accent)
		line.add_child(score_val)
	return line

# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------
func _eyebrow(text: String, color_key: String) -> Label:
	var l := Label.new()
	l.text = text.to_upper()
	l.add_theme_font_size_override("font_size", 32)
	l.add_theme_color_override("font_color", ThemeManager.color(color_key))
	l.add_theme_constant_override("line_spacing", 0)
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	_text_shadow(l)
	return l

## A soft dark drop shadow under free-floating text (tagline, eyebrows): cheap
## insurance that the words stay readable when a bright toy tile drifts beneath.
func _text_shadow(l: Label) -> void:
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.add_theme_constant_override("shadow_outline_size", 6)

## Every non-wrapping label on Home. A FitLabel rather than a bare Label because
## this page's minimum width is already the tightest in the app (see the notes on
## _continue_card and _mode_best_line — both were written around exactly this),
## and a growing number is the one thing that can add to it after the layout was
## measured. An unexpanding FitLabel claims the same natural width a plain Label
## did, so nothing moves until a value is genuinely too big for its box; sites
## that must be bounded say so with `max_width`.
func _label(text: String, font_sz: int) -> FitLabel:
	var l := FitLabel.make(text, font_sz)
	l.add_theme_font_size_override("font_size", font_sz)
	l.budget_text = text
	return l

func _tex_icon(path: String, box: float) -> TextureRect:
	var t := TextureRect.new()
	t.texture = UI.icon_tex(path)
	t.custom_minimum_size = Vector2(box, box)
	t.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t

func _glass_circle(path: String, on_press: Callable) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(116, 116)

	var bg := Panel.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = ThemeManager.color("glass")
	sb.set_corner_radius_all(58)
	sb.set_border_width_all(1)
	# The finish's thin near-white rim, not the flat stroke.
	sb.border_color = Color(ThemeManager.color("accent").lerp(Color(1, 1, 1), 0.55), 0.4)
	var sh := DesignSystem.shadow(1, ThemeManager.palette().get("shadow", ThemeManager.color("bg0")))
	sb.shadow_color = sh["color"]
	sb.shadow_size = int(sh["size"])
	sb.shadow_offset = sh["offset"]
	bg.add_theme_stylebox_override("panel", sb)
	holder.add_child(bg)

	var icon := TextureRect.new()
	icon.texture = UI.icon_tex(path)
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Library icons already carry their own internal margin (shadow + glow
	# ring), so they get only a whisper of inset; PNGs keep breathing room.
	var inset := 10.0 if IconLibrary.has_icon(path) else 26.0
	icon.offset_left = inset
	icon.offset_top = inset
	icon.offset_right = -inset
	icon.offset_bottom = -inset
	icon.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Native glossy icons (the reference shine).
	holder.add_child(icon)

	var btn := Button.new()
	btn.flat = true
	btn.set_anchors_preset(Control.PRESET_FULL_RECT)
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for st in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	btn.pressed.connect(func():
		AudioManager.play_sfx("button_tap", 0.04)
		Haptics.light()
		on_press.call())
	holder.add_child(btn)
	UI.wire_press(holder, btn)
	return holder

func _start(mode_id: String) -> void:
	# Single launch chokepoint: a locked (premium) mode routes to the paywall
	# instead of starting, so quick-play and the mode rows are all gated by this
	# one guard.
	if not EntitlementManager.is_mode_unlocked(mode_id):
		SceneRouter.goto(SceneRouter.Route["PREMIUM"])
		return
	# The Daily Puzzle opens on its calendar: today, and every past day.
	SceneRouter.goto(SceneRouter.Route["GAMEPLAY"], {"mode": mode_id, "continue": false})

## Resuming a saved game is a launch path too — gate it so a now-locked premium
## mode (e.g. after a refund revoked premium) can't be resumed for free.
func _continue_game(mode_id: String) -> void:
	if not EntitlementManager.is_mode_unlocked(mode_id):
		SceneRouter.goto(SceneRouter.Route["PREMIUM"])
		return
	SceneRouter.goto(SceneRouter.Route["GAMEPLAY"], {"mode": mode_id, "continue": true})
