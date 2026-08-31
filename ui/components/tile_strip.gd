class_name ThemeTileStrip
extends Control
## The tiles a theme actually gives you, drawn in that theme's OWN ramp.
##
## The Shop used to preview a theme with ThemePreview alone — drifting ambience
## motes, i.e. the WALLPAPER. But a player spends the whole run looking at tiles,
## and every shipped theme owns a bespoke colour story (ThemeManager's
## `_LUXE_RAMPS`: gold, crystal, molten, jade, phantom, toxic...) that the
## storefront never showed. This is the product; the backdrop is the packaging.
##
## Resolvable without owning the theme because the painters take a PALETTE rather
## than reading the active one, so a locked theme can show its real glass with a
## real X and O on it. The ramp still picks the tile colours; the marks keep their
## own fixed pair, exactly as they do on the board.
##
## Decorative only: never eats input, so the card it sits on stays one hit target.

## Which rungs of the theme's ramp the strip samples. Four fits a row at a
## readable size; the numbers are colour indices into the ramp, never drawn.
const VALUES: Array[int] = [2, 4, 8, 16]
## Gap between tiles as a fraction of tile size.
const GAP_FRAC := 0.18
## Seconds between catch-light sweeps when there is no tilt to drive them.
const SWEEP_PERIOD := 5.0
const SWEEP_DUR := 1.0
## Seconds between merge beats, and how long one takes.
const MERGE_PERIOD := 2.6
const MERGE_DUR := 0.5

var pal: Dictionary = {}
var values: Array[int] = VALUES
## Opt-in catch-light. On a device this tracks the accelerometer, so the glass
## lights as the player tilts the phone; on desktop (and any device with no
## accelerometer) it falls back to a slow timed sweep.
var live_shine := false
## Opt-in merge beat. A ramp IS a chain of merges — 2 makes 4 makes 8 makes 16 —
## so rather than sitting as four static swatches the strip plays that chain: each
## tile in turn leans into its successor, which pops on the board's own spawn
## curve. It is the game's motion, describing the exact thing the ramp means.
var animate := false

var _t := 0.0
var _sweep := -1.0
var _acc := 0.0
var _tilt := 0.0
## Seconds into the current merge beat, and which tile is feeding its successor.
var _beat := 0.0
var _feeder := 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	set_process(live_shine or animate)
	queue_redraw()

func setup(p: Dictionary, with_shine: bool = false, vals: Array[int] = VALUES,
		with_merge: bool = false) -> void:
	pal = p
	values = vals
	# Ambient motion, and reduce_motion switches every other ambient layer in the
	# app off (GlassDrift skips spawning outright). The tiles keep their full glass
	# material either way — only the movement stops.
	var still := bool(SettingsManager.get_value("reduce_motion"))
	live_shine = with_shine and not still
	animate = with_merge and not still
	set_process((live_shine or animate) and is_inside_tree())
	queue_redraw()

## 30 Hz like every other ambient animation here — the band moves under a pixel
## per frame at 60, so a half-rate step is free.
func _process(delta: float) -> void:
	_acc += delta
	if _acc < 1.0 / 30.0:
		return
	var dt := _acc
	_acc = 0.0

	if animate:
		_beat += dt
		if _beat >= MERGE_PERIOD:
			_beat = 0.0
			# Walk the chain: 2 into 4, then 4 into 8, then 8 into 16, then round.
			# The last tile has no successor, so it never takes a turn as feeder.
			_feeder = (_feeder + 1) % maxi(1, values.size() - 1)
		queue_redraw()

	# TILT FIRST. get_accelerometer() reports zero on hardware without one (and on
	# desktop), which is exactly the signal to fall back rather than a reading of
	# "perfectly level" — a real device is never exactly zero.
	var g := Input.get_accelerometer()
	if g.length() > 0.05:
		# Phone rolled left/right maps across the band's travel. Smoothed hard: raw
		# accelerometer is noisy enough that a direct map jitters the highlight.
		var target := clampf(0.5 - g.x / 12.0, 0.0, 1.0)
		_tilt = lerpf(_tilt, target, 0.18)
		_sweep = _tilt
		queue_redraw()
		return

	_t += dt
	if _sweep < 0.0:
		if _t >= SWEEP_PERIOD:
			_t = 0.0
			_sweep = 0.0
			queue_redraw()
		return
	_sweep += dt / SWEEP_DUR
	if _sweep > 1.0:
		_sweep = -1.0
	queue_redraw()

func _draw() -> void:
	var s := size
	var n := values.size()
	if s.x <= 0.0 or s.y <= 0.0 or n <= 0 or pal.is_empty():
		return
	# Sized off the HEIGHT first so the strip never outgrows its slot, then capped
	# by the width it actually has.
	var by_w := s.x / (float(n) + GAP_FRAC * float(n - 1))
	var tile := minf(s.y, by_w)
	if tile <= 2.0:
		return
	var gap := tile * GAP_FRAC
	var span := tile * float(n) + gap * float(n - 1)
	var x := (s.x - span) * 0.5 + tile * 0.5
	var cy := s.y * 0.5

	# The merge beat, as a 0..1 ramp with a hold at the end of each period.
	var beat := clampf(_beat / MERGE_DUR, 0.0, 1.0) if animate else 0.0
	# Out-and-back, so the feeder leans in and settles rather than teleporting home.
	var lean := sin(beat * PI)

	for i in n:
		var vivid := CandyFace.color_for(pal, int(values[i]))
		var centre := Vector2(x + float(i) * (tile + gap), cy)
		var half := tile * 0.5
		if animate:
			if i == _feeder:
				# Leans toward its successor and shrinks a little — the giving half.
				centre.x += lean * (tile + gap) * 0.22
				half *= 1.0 - lean * 0.12
			elif i == _feeder + 1:
				# Pops on the board's own merge curve, so a tile in the Shop and a
				# tile on the grid answer to the same overshoot.
				half *= 1.0 + lean * (DesignSystem.TILE_MERGE_OVERSHOOT - 1.0)
		CandyFace.draw_face_soft(self, centre, half, vivid, true)
		if live_shine and _sweep >= 0.0:
			CandyFace.draw_shine_band(self, centre, half, _sweep, 0.24)
		# The pieces this theme gives you: numbered tiles, one per rung of the
		# strip, in the ink the glass under them asks for. The glass is what the
		# theme actually changes, and the numbers are what the player reads.
		TileFace.draw_number(self, centre, half, i + 1,
			CandyFace.text_color(vivid), 1.0, 0.35)
