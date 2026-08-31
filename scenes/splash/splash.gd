extends Control
## Splash — the loading sequence. THE LOADING SCREEN SOLVES A PUZZLE.
##
## Eight numbered tiles drop into a 3x3 tray, scrambled. Then the board slides
## itself home, one tile a beat, until every number is in order. The finished
## board sweeps with light, bursts, and hands over to the lockup. ~5 s, then
## Sign In. Any tap skips.
##
## The board, the scramble and the solution are the REAL ones: SlideRules deals
## it, SlideSolver finds the way home. So it cannot show a slide the rules would
## refuse, or a board that does not come out.
##
## Scheduled as a chain of BEATS, not absolute times, so a longer solve cannot
## run past the hand-off. Everything that moves is a pivot holder, never a node
## that draws (engine gotcha).

const T_DROP0 := 0.30
const DROP_EVERY := 0.10
const DROP_DUR := 0.30
const T_BEFORE_SOLVE := 0.34
const SLIDE_DUR := 0.17
const SOLVE_EVERY := 0.19
## How far from home the tray is dealt. Short: the solve has to fit a loading
## screen and stay followable.
const SCRAMBLE_STEPS := 5
## Fixed, so the loading screen is the same every launch. It is a logo.
const DEAL_SEED := 0x5105E
const T_AFTER_SOLVE := 0.62
const T_AFTER_BURST := 0.12
const T_LOCKUP_HOLD := 1.45

# Midnight, the sequence's own palette (not the player's theme: the theme lands
# on the sign-in page, faded in behind the lockup).
const BG_SOLID := Color("#0C0A1E")
const BG_G0 := Color("#221B52")
const BG_G1 := Color("#131029")
## One hue per row, as the board bands its rows. Fixed: the sequence keeps its
## Midnight palette whatever theme the player wears.
const BAND := [Color("#E56AD6"), Color("#8F7CF0"), Color("#5BD6E5")]
const WELL := Color("#1A1640")
const WELL_RIM := Color("#8F7CF0")
const RING_COL := Color(0.84, 0.88, 1.0, 0.85)
const TAG_COL := Color("#B5A9EA")
const NAME := "NUMSLIDE"
const TAGLINE := "Five ways to slide. One order."

## Middle, corners, edges. Reading order looks typed; this looks assembled.
const FILL_ORDER := [4, 0, 8, 2, 6, 1, 7, 3, 5]

var _done := false
var _stage: Control
var _stage_pivot: Control
var _cells: Array[Control] = []
var _pieces: Dictionary = {}     # cell index -> piece holder
var _flash: ColorRect
var _lockup: Control
var _dots: Dots
var _cell_px := 150.0
var _gap := 16.0
var _rules: SlideRules
var _sboard: SlideBoard
var _path: Array[Dictionary] = []

# --- Drawing nodes -------------------------------------------------------------
## An empty glass socket.
class Well extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)
	func _draw() -> void:
		var hw := minf(size.x, size.y) * 0.5
		if hw <= 0.0:
			return
		var c := size * 0.5
		var tex := CandyFace.mask()
		var uvs := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
		var ge := hw * 1.07
		draw_texture_rect(tex, Rect2(c - Vector2(ge, ge), Vector2(ge, ge) * 2.0), false,
			Color(WELL_RIM.r, WELL_RIM.g, WELL_RIM.b, 0.10))
		draw_polygon(PackedVector2Array([
			c + Vector2(-hw, -hw), c + Vector2(hw, -hw), c + Vector2(hw, hw), c + Vector2(-hw, hw)]),
			PackedColorArray([
				Color(WELL_RIM.r, WELL_RIM.g, WELL_RIM.b, 0.36), Color(WELL_RIM.r, WELL_RIM.g, WELL_RIM.b, 0.36),
				Color(WELL_RIM.r, WELL_RIM.g, WELL_RIM.b, 0.20), Color(WELL_RIM.r, WELL_RIM.g, WELL_RIM.b, 0.20)]),
			uvs, tex)
		var bw := hw * 0.976
		draw_polygon(PackedVector2Array([
			c + Vector2(-bw, -bw), c + Vector2(bw, -bw), c + Vector2(bw, bw), c + Vector2(-bw, bw)]),
			PackedColorArray([WELL.lightened(0.12), WELL.lightened(0.12), WELL.lightened(0.04), WELL.lightened(0.04)]),
			uvs, tex)

## A glass tile carrying a number.
class Piece extends Control:
	var vivid := Color.WHITE
	var number := 1
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)
	func _draw() -> void:
		var hw := minf(size.x, size.y) * 0.5
		if hw <= 0.0:
			return
		TileFace.draw_tile(self, size * 0.5, hw, number, vivid)

## The landing ping: a ring that grows and fades. `t` is tweened 0 → 1.
class Ring extends Control:
	var t := 0.0:
		set(v):
			t = v
			queue_redraw()
	var max_r := 120.0
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		if t <= 0.0 or t >= 1.0:
			return
		var r := 10.0 + max_r * t
		var a := (1.0 - t) * RING_COL.a
		draw_arc(size * 0.5, r, 0.0, TAU, 64, Color(RING_COL.r, RING_COL.g, RING_COL.b, a), 4.0, true)

## Three loader dots, breathing one after another.
class Dots extends Control:
	var phase := 0.0
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _process(delta: float) -> void:
		phase += delta
		queue_redraw()
	func _draw() -> void:
		var c := size * 0.5
		for i in 3:
			var p := 0.5 + 0.5 * sin((phase - float(i) * 0.22) * 4.2)
			var r := 7.0 + 3.0 * p
			draw_circle(c + Vector2((i - 1) * 30.0, 0.0), r, Color(TAG_COL, 0.35 + 0.65 * p), true, -1.0, true)

# --- Lifecycle -----------------------------------------------------------------
func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_background()
	# Sign In is this screen's one destination; parse it (and Home behind it)
	# on the loader thread across the hold so the hand-off finds a cache hit.
	SceneRouter.warm(SceneRouter.Route["SIGN_IN"])
	SceneRouter.warm(SceneRouter.Route["HOME"])
	AudioManager.play_sfx("opening")
	var vp := get_viewport_rect().size
	var side: float = clampf(vp.x * 0.62, 300.0, 560.0)
	_gap = side * 0.05
	_cell_px = (side - 2.0 * _gap) / 3.0
	_deal()
	_build_stage(vp, side)
	_build_lockup(vp, side)
	if bool(SettingsManager.get_value("reduce_motion")):
		_stage.visible = false
		_lockup.modulate.a = 1.0
		await _hold(1.2)
		if _done or not is_inside_tree(): return
		_advance()
		return
	_schedule()

func _input(event: InputEvent) -> void:
	var tapped: bool = (event is InputEventScreenTouch and event.pressed) \
		or (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventKey and event.pressed)
	if tapped:
		_advance()

func _advance() -> void:
	if _done or SceneRouter.is_busy():
		return
	_done = true
	SceneRouter.goto(SceneRouter.Route["SIGN_IN"])

## A hold that DIES WITH THIS NODE (a tree timer would resume into a freed
## instance after tap-to-skip).
func _hold(sec: float) -> void:
	var tw := create_tween()
	tw.tween_interval(sec)
	await tw.finished

# --- Build ---------------------------------------------------------------------
func _build_background() -> void:
	var bg := ColorRect.new()
	bg.color = BG_SOLID
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	grad.colors = PackedColorArray([BG_G0, BG_G1, BG_SOLID])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.42)
	tex.fill_to = Vector2(0.5, 1.0)
	tex.width = 256
	tex.height = 256
	var glow := TextureRect.new()
	glow.texture = tex
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glow)
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 1, 1)
	_flash.modulate.a = 0.0
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Added last in _build_lockup so it lies over everything.

func _cell_pos(i: int) -> Vector2:
	return Vector2((i % 3) * (_cell_px + _gap), (i / 3) * (_cell_px + _gap))

func _build_stage(vp: Vector2, side: float) -> void:
	_stage = Control.new()
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage.size = Vector2(side, side)
	_stage.position = Vector2((vp.x - side) * 0.5, vp.y * 0.42 - side * 0.5)
	add_child(_stage)
	_stage_pivot = Control.new()
	_stage_pivot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stage_pivot.size = Vector2(side, side)
	_stage_pivot.pivot_offset = Vector2(side, side) * 0.5
	_stage.add_child(_stage_pivot)
	for i in 9:
		var w := Well.new()
		w.position = _cell_pos(i)
		w.size = Vector2(_cell_px, _cell_px)
		_stage_pivot.add_child(w)
		_cells.append(w)

func _build_lockup(vp: Vector2, side: float) -> void:
	_lockup = VBoxContainer.new()
	_lockup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lockup.alignment = BoxContainer.ALIGNMENT_CENTER
	_lockup.add_theme_constant_override("separation", int(DesignSystem.SPACE_LG))
	_lockup.set_anchors_preset(Control.PRESET_FULL_RECT)
	_lockup.modulate.a = 0.0
	add_child(_lockup)
	# The block FLOATS between two elastic spacers rather than hanging off a fixed
	# top pad: the stack is only as tall as its content, and a fixed 16 % head left
	# it pinned to the top third with half a screen of air under the dots. The
	# uneven ratios park it a little above centre, which is where the board it
	# replaces bursts (the stage sits at 0.42 of the height) — the lockup arrives
	# where the player is already looking.
	_lockup.add_child(_spacer(vp.y * 0.04, true, 0.85))


	# THE NAME. The sibling project's board spelled T-I-C T-A-C T-O-E, so its
	# nine tiles WERE the wordmark and no name had to be set beside them. Nine
	# numbered tiles spell nothing, so the name is set here, in the same extruded
	# brand face the sign-in page wears, and the board underneath it becomes what
	# it actually is: the product, playable, sitting under its own logo.
	# SIZED OFF THE LETTER COUNT AND THE EXTRUSION, not off the stage. Eight
	# glyphs is a long word for a phone, and this face is drawn EXTRUDED: fifteen
	# layers stepped down-right add most of a glyph's width to the right-hand end
	# on top of the letters themselves. Sizing it like a four-letter word ran the
	# final E off the screen edge.
	var name_px: float = clampf(vp.x * 0.86 / (float(NAME.length()) * 0.72), 34.0, 96.0)
	var name_mark := ExtrudedWord.make(NAME, int(name_px),
		Color("7B5CF0"), Color("E0529C"), Color("F2913D"))
	name_mark.extrude = Vector2(4, 6)
	name_mark.layers = 10
	name_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_mark.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var name_hold := CenterContainer.new()
	name_hold.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_hold.add_child(name_mark)
	_lockup.add_child(name_hold)

	# The same living wordmark Home and the sign-in page wear, so the sequence
	# hands the player the mark they are about to live with. Sized against THIS
	# screen's own dark ground, not the theme's page colour: the splash keeps its
	# Midnight palette whatever world the player has chosen.
	var board := HeroBoard.make(side * 0.78)
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var hold := CenterContainer.new()
	hold.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hold.add_child(board)
	_lockup.add_child(hold)

	var pill := UI.glass_pill(1)
	pill.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var pill_lbl := UI.label("L I M I T L E S S", 30, "text")
	# AUTOWRAP_OFF, and it is not cosmetic: UI.label ships WORD_SMART, and an
	# autowrapping Label reports a MINIMUM WIDTH OF 1. The pill around it is
	# SHRINK_CENTER, so it took that 1 px as its size and the capsule wrapped the
	# wordmark one letter per line — the title read vertically down the screen.
	# A pill never wraps; anything laid out at its minimum width says so here.
	pill_lbl.autowrap_mode = TextServer.AUTOWRAP_OFF
	pill_lbl.add_theme_color_override("font_color", Color(0.96, 0.95, 1.0))
	pill.add_child(pill_lbl)
	_lockup.add_child(pill)

	var tag := UI.label(TAGLINE, 38, "text_dim")
	tag.add_theme_color_override("font_color", TAG_COL)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# FILL (the VBox default), never SHRINK_CENTER — same 1-px minimum as above,
	# which stood the tagline on its end too. It keeps its autowrap and centres
	# itself with the alignment, so a narrow phone breaks it by WORDS instead.
	tag.size_flags_horizontal = Control.SIZE_FILL
	_lockup.add_child(tag)

	_dots = Dots.new()
	_dots.custom_minimum_size = Vector2(120, 40)
	_dots.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_lockup.add_child(_dots)
	_lockup.add_child(_spacer(0.0, true, 1.15))
	add_child(_flash)

func _spacer(h: float, expand: bool = false, ratio: float = 1.0) -> Control:
	var s := Control.new()
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.custom_minimum_size = Vector2(0, h)
	if expand:
		s.size_flags_vertical = Control.SIZE_EXPAND_FILL
		s.size_flags_stretch_ratio = ratio
	return s

# --- The timeline ----------------------------------------------------------------
## Deals the tray and finds the way home. Before the timeline: the timeline is
## as long as the solution is.
func _deal() -> void:
	var mode := GameModes.get_mode("classic")
	mode.board_size = 3
	_rules = SlideRules.make(mode)
	_sboard = _rules.new_board()
	var rng := RandomNumberGenerator.new()
	rng.seed = DEAL_SEED
	_rules.scramble(_sboard, rng, SCRAMBLE_STEPS)
	_path = SlideSolver.solve(_sboard, _rules)

func _schedule() -> void:
	var tw := create_tween()
	tw.tween_interval(T_DROP0)
	for cell in FILL_ORDER:
		var number := _sboard.at(int(cell))
		if number == SlideBoard.BLANK:
			continue
		tw.tween_callback(_drop.bind(int(cell), number))
		tw.tween_interval(DROP_EVERY)
	tw.tween_interval(T_BEFORE_SOLVE)
	for k in _path.size():
		tw.tween_callback(_slide_step.bind(k))
		tw.tween_interval(SOLVE_EVERY)
	tw.tween_callback(_solved_sweep)
	tw.tween_interval(T_AFTER_SOLVE)
	tw.tween_callback(_burst)
	tw.tween_interval(T_AFTER_BURST)
	tw.tween_callback(_reveal_lockup)
	tw.tween_interval(T_LOCKUP_HOLD)
	tw.tween_callback(_advance)

## One piece falls into its socket and pings.
func _drop(idx: int, number: int) -> void:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.position = _cell_pos(idx)
	holder.size = Vector2(_cell_px, _cell_px)
	holder.pivot_offset = holder.size * 0.5
	var piece := Piece.new()
	# Banded by the number's HOME row, so a tile out of place looks it.
	@warning_ignore("integer_division")
	piece.vivid = BAND[clampi((number - 1) / 3, 0, BAND.size() - 1)]
	piece.number = number
	piece.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(piece)
	_stage_pivot.add_child(holder)
	_pieces[idx] = holder
	holder.scale = Vector2(1.7, 1.7)
	holder.modulate.a = 0.0
	var tw := holder.create_tween().set_parallel(true)
	tw.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(holder, "scale", Vector2.ONE, DROP_DUR)
	tw.tween_property(holder, "modulate:a", 1.0, DROP_DUR * 0.6)
	tw.chain().tween_callback(_ping.bind(idx))
	tw.chain().tween_property(holder, "scale", Vector2(0.94, 0.94), 0.06)
	tw.chain().tween_property(holder, "scale", Vector2.ONE, 0.16).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	AudioManager.play_sfx("tile_move", 0.02)
	Haptics.light()
	# The board takes the impact: a tiny dip.
	var bump := _stage.create_tween()
	bump.tween_property(_stage, "position:y", _stage.position.y + 6.0, 0.06)
	bump.tween_property(_stage, "position:y", _stage.position.y, 0.14)

func _ping(idx: int) -> void:
	var ring := Ring.new()
	ring.position = _cell_pos(idx)
	ring.size = Vector2(_cell_px, _cell_px)
	ring.max_r = _cell_px * 0.9
	_stage_pivot.add_child(ring)
	var tw := ring.create_tween()
	tw.tween_property(ring, "t", 1.0, 0.55).from(0.01)
	tw.tween_callback(ring.queue_free)

## One move of the solution. The rules move the board; the tray follows the
## events they return, exactly as the gameplay screen does.
func _slide_step(k: int) -> void:
	if k < 0 or k >= _path.size():
		return
	for e_v in _rules.apply(_sboard, _path[k]):
		var e: Dictionary = e_v
		if String(e.get("type", "")) != "slid":
			continue
		# Read every holder out first, then write them back: one tile's
		# destination is the next one's origin.
		var moving: Array = []
		for pair_v in e.get("pairs", []):
			var pair: Vector2i = pair_v
			var holder: Control = _pieces.get(pair.x, null)
			if holder != null:
				moving.append([holder, pair.y])
				_pieces.erase(pair.x)
		for entry_v in moving:
			var entry: Array = entry_v
			var holder: Control = entry[0]
			var to: int = int(entry[1])
			_pieces[to] = holder
			var tw := holder.create_tween()
			tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
			tw.tween_property(holder, "position", _cell_pos(to), SLIDE_DUR)
			tw.parallel().tween_property(holder, "scale", Vector2(1.06, 0.94), SLIDE_DUR * 0.45)
			tw.chain().tween_property(holder, "scale", Vector2.ONE, SLIDE_DUR * 0.55) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	AudioManager.play_sfx("tile_move", 0.02)
	Haptics.light()

## The board is home: light sweeps it in reading order. Not "three of these are
## mine" but "all of them are where they belong".
func _solved_sweep() -> void:
	AudioManager.play_sfx("victory", 0.04)
	Haptics.success()
	for i in 9:
		var holder: Control = _pieces.get(i, null)
		if holder == null:
			continue
		var tw := holder.create_tween()
		tw.tween_interval(float(i) * 0.045)
		tw.tween_callback(_ping.bind(i))
		tw.tween_property(holder, "scale", Vector2(1.16, 1.16), 0.10) \
			.set_trans(Tween.TRANS_SINE)
		tw.tween_property(holder, "scale", Vector2(1.04, 1.04), 0.24) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _burst() -> void:
	var f := _flash.create_tween()
	f.tween_property(_flash, "modulate:a", 0.92, 0.09)
	f.tween_property(_flash, "modulate:a", 0.0, 0.55).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	var st := _stage_pivot.create_tween().set_parallel(true)
	st.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	st.tween_property(_stage_pivot, "scale", Vector2(1.35, 1.35), 0.22)
	st.tween_property(_stage, "modulate:a", 0.0, 0.22)
	Confetti.celebrate(self, 120)
	AudioManager.play_sfx("victory", 0.04)
	Haptics.success()

func _reveal_lockup() -> void:
	_stage.visible = false
	_lockup.pivot_offset = _lockup.size * 0.5
	_lockup.scale = Vector2(0.72, 0.72)
	var tw := _lockup.create_tween().set_parallel(true)
	tw.tween_property(_lockup, "modulate:a", 1.0, 0.28)
	tw.tween_property(_lockup, "scale", Vector2.ONE, 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_ELASTIC)
