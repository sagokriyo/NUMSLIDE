class_name Confetti
extends Control
## Confetti — a celebratory burst at milestones / victory, themed to the active
## palette instead of one rainbow-for-everything shower.
##
## Every recipe is a SHAPE + COLOURS + a MATERIAL. The material is what makes it
## read as real: paper flutters and tumbles end-over-end, foil coins drop straight
## and heavy, petals and leaves rock down slowly, sparks cool and die, gems fall
## hard with a fast tumble, bubbles and glowing motes rise. Tumbling is a per-piece
## y-scale flip (split-scale curve) so pieces go thin edge-on and wide face-on,
## desynchronised via lifetime randomness.
##
##   gold / silver / desert → foil coins & bars;  clockwork → bronze GEARS + coins
##   crystal / frost+hoarfrost / emerald / ruby / sanctum / blood moon → tumbling gems
##   autumn (leaves) / jade → falling leaves; sakura / rose / bloom / ronin → petals
##   koi garden             → blossom onto the pond + a live SCHOOL of koi
##                            crossing under it, each opening a ripple
##   ocean / coral depths   → rising bubbles;  biolum / firefly (blinking) → glow motes
##   antigrav               → pulsing motes floating up (antigrav must NOT fall)
##   daybreak               → the dawn chorus ITSELF: a live flock of songbirds
##                            takes wing — no pieces at all, like the bat flock
##   space / nebula / starforged / star atlas / obsidian / event horizon
##                          → BRIGHT stars: kirakira + five-point glow-halo stars
##   anime                  → ink-doodle heads + neko & onigiri doodles +
##                            kirakira, opened by a manga IMPACT FRAME
##   thunderstorm (lightning flash + bolts) / ember serpent / nova forge → sparks
##   lanterns → a lantern release; hearts → rising hearts + pastel stars
##   aurora → shimmering ribbon curtains; carnival → spiral streamers
##   skywriter → the SKY answers: wind-waves ripple the background, no pieces
##   origami sky → a live flight of paper CRANES over falling darts & squares
##   candy pop → sprinkles + lollipop swirls
##   zen garden → calm sand motes + moss leaves; paper → cream & kraft squares
##   vaporwave → stage lasers; neon / circuit → electric vortex; phantom → live bats
##   shadow fog → the fog itself (plus faint glints); ink wash → ink-bloom wisps
##   playful / arcade       → classic tumbling rainbow paper
##   everything else        → paper tinted from the theme's own tile ramp
## Frees itself once every piece has left (or faded). Skipped under reduce-motion.

var _amount: int = 180
var _shape: String = "square"
var _colors: Array = []
var _mix: Array = []            # optional [{shape, colors?}] — splits every emitter
								# across several shapes (e.g. gold coins + bars)
var _top_shower: bool = false   # also rain pieces top→bottom over the whole screen
var _rise: bool = false         # float straight up and off the top (lanterns / bubbles …)
var _with_bubbles: bool = false # coral reef: bubbles stream up AROUND the falling pieces
var _laser_flag: bool = false   # vaporwave: replace the cannons with a stage laser show
var _bat_flock_flag: bool = false  # phantom: release live animated bats, not particles
var _fly_flock_flag: bool = false  # butterfly grove: a live flock, but one that WANDERS
## Peacock: feathers are never thrown. A tap is the train SHED (feathers drifting
## in from above the top edge) and a bomb is the DISPLAY (the train fanning up
## from the bottom of the screen). Routed above the bomb branch like the flocks.
var _feather_drift_flag: bool = false
var _bird_flock_flag: bool = false # daybreak: songbirds take wing ALONGSIDE the pieces
var _koi_school_flag: bool = false # koi garden: a live school swims under the blossom
var _crane_flight_flag: bool = false  # origami sky: live cranes glide over the paper
var _speed_lines_flag: bool = false  # anime: a manga impact frame opens the burst
var _wind_flag: bool = false       # thunderstorm: the storm sweeps the screen, no pieces
var _storm_flash: bool = false  # thunderstorm: a double lightning flash opens the burst
var _fog_glints: bool = false   # shadow fog: faint glints drift up inside the haze
## Shadow Fog only: the celebration is a fog BANK that fills the frame, and a
## bomb is a heavier one — so it routes above the detonation branch rather than
## through it. Kept separate from `_fog_glints` because Ink Wash rides the same
## mist shape and must keep its own centre bloom (see `_spawn`).
var _fog_bank_flag: bool = false
var _wave_flag: bool = false    # skywriter: the sky ripples — wind-waves, no pieces
var _bomb_strength: float = -1.0  # ≥ 0 → the long-press bomb: one 360° centre blast

# Material knobs (set by _set_material; branches may nudge them after).
var _spin: float = 420.0
var _grav: float = 540.0
var _damp_lo: float = 4.0       # air drag: high values give a fluttery terminal fall
var _damp_hi: float = 20.0
var _sway: float = 0.0          # ± orbit velocity — a light random air-wander per piece
var _orbit_lo: float = 0.0      # one-signed orbit band (spirals): overrides ±_sway when set
var _orbit_hi: float = 0.0
var _tumble: bool = false       # end-over-end flip via a split y-scale curve
var _shimmer: bool = false      # shiny pieces pulse bright↔dim over life — they CATCH
								# and lose the light as they tumble (foil, gems, stars)
var _align: bool = false        # align each piece to its motion (laser beams)
var _cool: Gradient = null      # lifetime ramp override (sparks cool, mist thins away)
var _life: float = 4.8          # particle lifetime (slow materials need longer to clear)
var _launch: float = 1.0        # cannon speed multiplier (near-weightless bits launch soft)
var _scale_lo: float = 1.8
var _scale_hi: float = 3.4
var _ttl: float = 6.4           # node lifetime — computed from the emitters in _spawn
## How long the LIVE cast (the koi school, the crane flight) needs the node to
## stay alive. Those two recipes fly their cast BESIDE their particles rather
## than instead of them, so `_ttl` — which the particle paths compute from the
## material — has to be raised to whichever is longer, or the node reaps itself
## with fish still mid-screen.
var _live_ttl: float = 0.0

# Baked shapes and curves are plain white masks with no per-theme state, so they
# are STATIC: baked once for the app's lifetime instead of pixel-looped again on
# every celebration.
static var _sq_tex: ImageTexture
static var _coin_tex: ImageTexture
static var _gem_tex: ImageTexture
static var _petal_tex: ImageTexture
static var _spark_tex: ImageTexture
static var _dot_tex: ImageTexture
static var _lantern_tex: ImageTexture
static var _ribbon_tex: ImageTexture
static var _heart_tex: ImageTexture
static var _sparkle_tex: ImageTexture
static var _leaf_tex: ImageTexture
static var _bubble_tex: ImageTexture
static var _streak_tex: ImageTexture
static var _bar_tex: ImageTexture
static var _emeraldcut_tex: ImageTexture
static var _ice_tex: ImageTexture
static var _starfish_tex: ImageTexture
static var _mist_tex: ImageTexture
static var _brilliant_tex: ImageTexture
static var _icicle_tex: ImageTexture
static var _bat_tex: ImageTexture
static var _snowflake_tex: ImageTexture
static var _maple_tex: ImageTexture
static var _shard_tex: ImageTexture
static var _cinder_tex: ImageTexture
static var _star5_tex: ImageTexture
static var _bolt_tex: ImageTexture
static var _gear_tex: ImageTexture
static var _crane_tex: ImageTexture
static var _dart_tex: ImageTexture
static var _koi_a_tex: ImageTexture
static var _koi_b_tex: ImageTexture
static var _koi_c_tex: ImageTexture
static var _swirl_tex: ImageTexture
static var _anime_a_tex: ImageTexture
static var _anime_b_tex: ImageTexture
static var _anime_c_tex: ImageTexture
## The dawn chorus is a FLIPBOOK, not one sprite: 2 birds x 3 wing positions
## (up / level / down), indexed variant * 3 + frame.
static var _bird_frames: Array[ImageTexture] = []
static var _doodle_cat_tex: ImageTexture
static var _onigiri_tex: ImageTexture
static var _blossom_a_tex: ImageTexture
static var _blossom_b_tex: ImageTexture
static var _blossom_c_tex: ImageTexture
static var _ruby_tex: ImageTexture
static var _ruby_marquise_tex: ImageTexture
static var _gold_coin_tex: ImageTexture
static var _gold_bar_tex: ImageTexture
static var _gold_nugget_tex: ImageTexture
static var _silver_coin_tex: ImageTexture
static var _silver_bar_tex: ImageTexture
static var _silver_nugget_tex: ImageTexture
static var _firefly_tex: ImageTexture
static var _bee_tex: ImageTexture
static var _honey_tex: ImageTexture
static var _waxcell_tex: ImageTexture
static var _butterfly_a_tex: ImageTexture
static var _butterfly_b_tex: ImageTexture
static var _butterfly_c_tex: ImageTexture
static var _feather_tex: ImageTexture
static var _diamond_tex: ImageTexture
static var _diamond_kite_tex: ImageTexture
static var _diamond_baguette_tex: ImageTexture
static var _rainstreak_tex: ImageTexture
static var _comb_chunk_tex: ImageTexture
static var _honey_ribbon_tex: ImageTexture
static var _flip: Curve
static var _flap: Curve
static var _flat: Curve

static func celebrate(parent: Node, amount: int = 180, top_shower: bool = false, cap: int = 2) -> void:
	if bool(SettingsManager.get_value("reduce_motion")):
		return
	# Safety cap: never let more than `cap` showers overlap — but a celebration
	# ALWAYS fires. When the cap is reached the OLDEST shower makes way for the
	# new one, instead of silently skipping the tap (long-lived showers like slow
	# petals used to block follow-up taps for seconds).
	var tree := parent.get_tree()
	var live_count := 0
	if tree != null:
		var live := tree.get_nodes_in_group("confetti_fx")
		# At the cap, rapid taps stop paying for teardown + rebuild entirely:
		# find the oldest still-flying shower under this SAME parent and relight
		# it in place (replay). Visually identical — same theme, same recipe —
		# and nearly free, where free-and-respawn allocated a dozen emitters and
		# hitched the tap frame.
		if live.size() >= cap:
			for node in live:
				var old := node as Confetti
				if old != null and is_instance_valid(old) \
						and old.get_parent() == parent \
						and old._bomb_strength < 0.0 and old._ttl_left > 0.0:
					old.replay()
					return
		while live.size() >= cap and not live.is_empty():
			var oldest: Node = live.pop_front()
			if is_instance_valid(oldest):
				oldest.queue_free()
		live_count = live.size()
	var c := Confetti.new()
	c.add_to_group("confetti_fx")
	# Rapid-tap thinning: overlapping showers blend into one field on screen, so
	# every ADDITIONAL shower already in flight lets the new one spawn thinner —
	# the screen still reads "confetti everywhere" while the live-particle bill
	# stays roughly flat instead of multiplying with the tap rate (this was the
	# wordmark-mash lag). A lone tap is always full strength.
	var thin := 1.0 / (1.0 + 0.55 * float(live_count))
	c._amount = maxi(int(float(amount) * _device_budget() * thin), 12)
	c._top_shower = top_shower
	c._apply_recipe()
	parent.add_child(c)

## Milestone-scaled celebration for reaching a new high tile IN PLAY: bigger
## tiles earn a denser burst, and every milestone also rains a full
## top-to-bottom shower. 128 ≈ 300 pieces; each doubling adds ~70, capped so
## phones stay smooth. Lifetime firsts hit ~35% harder.
static func tile_milestone(parent: Node, tile: int, first_ever: bool = false) -> void:
	var steps: float = maxf(log(float(maxi(tile, 128)) / 128.0) / log(2.0), 0.0)
	var amt: float = 300.0 + steps * 70.0
	if first_ever:
		amt *= 1.35
	celebrate(parent, mini(int(amt), 780), true)

## The long-press bomb detonation: a single 360° blast from mid-screen in the
## active theme's own confetti recipe. `strength` (0..1, from how long the
## button was held) scales both the piece count and the launch speed.
static func bomb(parent: Node, strength: float = 1.0) -> void:
	if bool(SettingsManager.get_value("reduce_motion")):
		return
	# Destructive: the detonation wipes EVERY other live shower off the screen —
	# whatever confetti was still falling, the blast is now the only event.
	var tree := parent.get_tree()
	if tree != null:
		for other in tree.get_nodes_in_group("confetti_fx"):
			if is_instance_valid(other):
				(other as Node).queue_free()
	var c := Confetti.new()
	c.add_to_group("confetti_fx")
	c._bomb_strength = clampf(strength, 0.0, 1.0)
	c._amount = maxi(int(lerpf(420.0, 1000.0, c._bomb_strength) * _device_budget()), 12)
	c._apply_recipe()
	# The recipe density multipliers (space's stardust doubles its field, crystal
	# runs 1.3x, ...) are tuned for ~156-piece tap showers. Compounding them onto
	# a full-strength bomb reached ~2000 live pieces hanging for 15+ seconds —
	# the detonation lag. One bounded ceiling keeps every recipe's bomb enormous
	# but finite; the piece count is the single lever frame cost scales with.
	c._amount = mini(c._amount, int(900.0 * _device_budget()))
	# ...except that piece COUNT is only a proxy for what a frame actually pays,
	# which is FILL. The mist recipes (Ink Wash, Shadow Fog) draw their wisps at
	# 6.5–11.5x scale — around thirteen times the area of every other recipe's
	# pieces — so at the shared ceiling they were buying thirteen bombs' worth of
	# overdraw. Measured across all 48 themes on both test devices (the four added
	# in 2026-08 are not mist recipes and do not change the finding), those two were
	# the ONLY detonations at ~24 fps (p50 ~40 ms) against a ~18 ms median, with
	# the same draw calls, the same primitive count and the same script time as
	# the rest: the gap is overdraw and nothing else. A fill-matched ceiling still
	# leaves the fog bomb denser than that theme's own tap celebration (~128
	# wisps), which is the density the recipe was authored at.
	if c._shape == "mist":
		c._amount = mini(c._amount, int(200.0 * _device_budget()))
	parent.add_child(c)

## A card-sized celebration for the Themes screen: the SAME recipe table the
## live showers use, built from the CARD's palette rather than the wearer's,
## and scoped to `parent`'s own rect (the caller clips it). Pieces shrink a
## touch — a full-screen piece is a boulder on a 340px stage. Skips while a
## previous burst is still flying in the same parent, so a card's timer never
## stacks showers. Deliberately NOT in the "confetti_fx" group: the cap and the
## bomb's wipe are gameplay bookkeeping, and neither may reach into the cards.
static func preview(parent: Control, pal: Dictionary, amount: int = 34) -> void:
	if bool(SettingsManager.get_value("reduce_motion")):
		return
	if pal.is_empty() or parent.size.x <= 0.0 or parent.size.y <= 0.0:
		return
	for child in parent.get_children():
		if child is Confetti:
			return
	var c := Confetti.new()
	c._pal_override = pal
	c._amount = maxi(int(float(amount) * _device_budget()), 8)
	c._apply_recipe()
	c._scale_lo *= 0.7
	c._scale_hi *= 0.7
	parent.add_child(c)
	# _ready's anchors preset preserves the 0×0 rect via compensating offsets,
	# which would drop _spawn to its full-canvas fallback — pin the card's rect.
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

## The cast the given palette's celebration throws — shapes, colours and the
## piece-size band, from the SAME recipe table the live showers use — so the
## Themes cards' ambient previews can drift the theme's own confetti instead of
## a stand-in. Returns {} for the recipes whose celebration is not made of
## pieces at all (the storm wind, the sky waves, the laser show, the fog bank):
## those keep the caller's generic motes.
static func recipe_preview(pal: Dictionary) -> Dictionary:
	var c := Confetti.new()
	c._pal_override = pal
	c._apply_recipe()
	if c._wind_flag or c._wave_flag or c._laser_flag or c._fog_bank_flag:
		c.free()
		return {}
	var parts: Array = []
	if c._bat_flock_flag:
		# Phantom's flock is live nodes, not particles — its arm sets no shape,
		# so hand the preview the bat silhouette directly.
		parts.append({"tex": c._texture_for("bat"), "colors": c._colors, "scale": 1.0})
	else:
		for part_v in c._parts():
			var part: Dictionary = part_v
			parts.append({
				"tex": c._texture_for(String(part.get("shape", c._shape))),
				"colors": part.get("colors", c._colors),
				"scale": float(part.get("scale", 1.0)),
			})
		# Koi Garden and Origami Sky fly their hero as LIVE nodes, so it is not
		# in the particle mix at all — hand it to the card directly, or the one
		# thing each theme is named after is missing from its own preview.
		if c._koi_school_flag:
			parts.append({"tex": c._texture_for("koi_a"), "colors": [Color(1, 1, 1)],
				"scale": 0.45})
		elif c._crane_flight_flag:
			# Bigger than the koi's share below: Origami's own mix is folded
			# SQUARES and darts, which draw tiny, so at matched scale the card
			# read as flecks with the crane lost among them.
			parts.append({"tex": c._texture_for("crane"), "colors": c._colors,
				"scale": 0.72})
	var out := {
		"parts": parts,
		"rise": c._rise,
		"shimmer": c._shimmer,
		"scale_lo": c._scale_lo,
		"scale_hi": c._scale_hi,
	}
	c.free()
	return out

## Phone-class particle budget (mirrors BoardFx): thinner showers on weaker
## hardware so celebrations never cost the frame rate they're celebrating.
static var _budget_cache: float = -1.0

static func _device_budget() -> float:
	if _budget_cache < 0.0:
		var cores := OS.get_processor_count()
		var s := 1.0
		if cores <= 4:
			s = 0.72
		elif cores <= 6:
			s = 0.92
		if OS.has_feature("mobile"):
			s = minf(s, 0.82)
		_budget_cache = s
	return _budget_cache

## Material presets — real confetti isn't one physics. Each preset tunes gravity,
## drag, spin, sway, tumble and lifetime so the pieces MOVE like what they depict.
func _set_material(mat: String) -> void:
	_cool = null
	_tumble = false
	_shimmer = false
	_sway = 0.0
	_orbit_lo = 0.0
	_orbit_hi = 0.0
	_launch = 1.0
	_align = false
	match mat:
		"paper":     # light, fluttery, tumbling — the classic
			_grav = 380.0; _damp_lo = 40.0; _damp_hi = 95.0; _spin = 520.0
			_sway = 0.020; _tumble = true; _life = 5.4
			_scale_lo = 1.6; _scale_hi = 3.4
		"foil":      # coins — heavy, fast, hard spin, a live metallic glint
			_grav = 860.0; _damp_lo = 4.0; _damp_hi = 14.0; _spin = 900.0
			_sway = 0.008; _tumble = true; _shimmer = true; _life = 4.2
			_scale_lo = 1.8; _scale_hi = 3.0
		"gem":       # hard and heavy, a quick glinting, glittering tumble
			_grav = 760.0; _damp_lo = 4.0; _damp_hi = 12.0; _spin = 640.0
			_sway = 0.010; _tumble = true; _shimmer = true; _life = 4.2
			_scale_lo = 1.6; _scale_hi = 3.0
		"candy":     # solid sprinkles — medium weight, a little wander + glaze glint
			_grav = 560.0; _damp_lo = 10.0; _damp_hi = 26.0; _spin = 380.0
			_sway = 0.012; _shimmer = true; _life = 4.6; _scale_lo = 1.4; _scale_hi = 2.8
		"petal":     # very light — rocks side to side, slowest fall
			_grav = 230.0; _damp_lo = 70.0; _damp_hi = 130.0; _spin = 120.0
			_sway = 0.038; _tumble = true; _life = 6.6
			_scale_lo = 1.8; _scale_hi = 3.2
		"leaf":      # like a petal with a touch more heft and twirl
			_grav = 260.0; _damp_lo = 60.0; _damp_hi = 120.0; _spin = 160.0
			_sway = 0.034; _tumble = true; _life = 6.4
			_scale_lo = 2.0; _scale_hi = 3.6
		"ribbon":    # long streamers — slow, lazy waggle, high drag
			_grav = 300.0; _damp_lo = 26.0; _damp_hi = 60.0; _spin = 260.0
			_sway = 0.028; _life = 5.6
			_scale_lo = 1.8; _scale_hi = 3.4
		"streak":    # neon laser bits — straight, fast-ish, a live neon flicker
			_grav = 230.0; _damp_lo = 10.0; _damp_hi = 30.0; _spin = 90.0
			_shimmer = true; _life = 4.6; _scale_lo = 1.6; _scale_hi = 3.0
		"spark":     # embers — fast launch, rapid decel, glow cools and dies
			_grav = 320.0; _damp_lo = 90.0; _damp_hi = 170.0; _spin = 0.0
			_life = 1.9; _cool = _cooling_ramp()
			_scale_lo = 1.2; _scale_hi = 2.6
		"sink":      # underwater pieces — starfish, coral bits drifting down through water
			_grav = 170.0; _damp_lo = 90.0; _damp_hi = 150.0; _spin = 60.0
			_sway = 0.03; _tumble = true; _life = 7.5; _launch = 0.8
			_scale_lo = 1.6; _scale_hi = 3.0
		"mist":      # moor fog — VAST slow wisps creeping and blending into a bank
			_grav = -10.0; _damp_lo = 30.0; _damp_hi = 60.0; _spin = 6.0
			_sway = 0.035; _life = 9.0; _launch = 0.18; _cool = _mist_ramp()
			_scale_lo = 6.5; _scale_hi = 11.5
		"laser":     # show lasers — fast beams aligned to their flight, cutting out
			_grav = 0.0; _damp_lo = 0.0; _damp_hi = 10.0; _spin = 0.0
			_life = 4.0; _launch = 1.6; _align = true; _cool = _beam_ramp()
			_scale_lo = 2.0; _scale_hi = 3.6
		"stardust":  # TINY star bits — pinpricks like a real night sky, drifting
					 # all the way down and twinkling; density, not size, sells it
			_grav = 120.0; _damp_lo = 18.0; _damp_hi = 40.0; _spin = 90.0
			_sway = 0.028; _shimmer = true; _life = 9.0; _launch = 0.4
			_scale_lo = 0.5; _scale_hi = 1.25

## The palette this shower celebrates in — the ACTIVE theme normally, but the
## Themes screen's card previews override it so every card throws ITS OWN
## theme's confetti rather than the wearer's (see preview / recipe_preview).
var _pal_override: Dictionary = {}

func _pal() -> Dictionary:
	return _pal_override if not _pal_override.is_empty() else ThemeManager.palette()

# Pick the shape, colours and material from the theme (see _pal).
func _apply_recipe() -> void:
	var pal := _pal()
	var style := String(pal.get("board_style", "plain"))
	var accent: Color = pal["accent"]
	var gold: Color = pal["gold"]
	var soft: Color = pal.get("accent2", accent)
	var white := Color(1, 1, 1)
	_set_material("paper")
	# Themes with a strong background motif get confetti that IS that motif.
	match String(pal.get("bg_motif", "motes")):
		"arcade_pop":
			# Arcade — the cabinet coughs up its PICKUPS: chunky neon pixel blocks
			# tumbling among gold TOKENS and 1-UP hearts. Rainbow squares had the
			# machine's colour and none of its iconography, and an arcade celebration
			# is made of the things you collect in one. Both extras are solid shapes
			# on purpose: the five-point star was tried first and its glow halo drew
			# at twice the blocks' size (the square bake is halved back down, see
			# _apply_material), so the pixels vanished under a field of sparkles.
			_shape = "square"; _spin = 640.0
			_scale_lo = 2.2; _scale_hi = 4.0
			_mix = [
				{"shape": "square"}, {"shape": "square"},
				{"shape": "coin", "scale": 0.55,
					"colors": [Color("FFE12E"), Color("FFB020"), Color("FFF0A0")]},
				{"shape": "heart", "scale": 0.55,
					"colors": [Color("FF2E63"), Color("FF5C8A")]},
			]
			_colors = _rainbow_cols()
			return
		"candy":
			# Candy Pop — candy sprinkles in EXACTLY the colours the WORDMARK
			# wears, plus glossy lollipop SWIRLS tumbling through the sprinkle
			# rain. The shower used to sample six raw ramp stops; the wordmark
			# wears four of them dressed through CandyFace (saturation and value
			# lifted), so the confetti a tap on the logo throws came out duller
			# than the logo throwing it. Same four tiles, same candy paint.
			#
			# LIGHT BALLS ride the sprinkle rain: soft glowing orbs in two sizes,
			# big ones catching the eye and small ones filling between them, so
			# the shower has luminous depth instead of a flat field of sprinkles.
			# They also carry the wordmark's colour at full brightness, which the
			# sprinkles cannot: the candy dot bakes a shaded body (~0.74 of its
			# tint, see _fn_dot), so a sprinkle in the word's bright yellow lands
			# olive however it is tinted. The glow balls are where the palette
			# reads at the value the word wears it.
			_shape = "dot"; _set_material("candy")
			# The glaze pulse instead of the deep shimmer (see _glaze_ramp): the
			# shared one drops a piece to two-thirds brightness and half the field
			# sits in that dip at any moment.
			_cool = _glaze_ramp()
			# Three parts in five are glowing BALLS, in three sizes, and they draw
			# at the full tint where the sprinkle bake shades its body to ~0.74 —
			# so the light in the shower comes from them and the sprinkles read as
			# the candy between.
			_mix = [
				{"shape": "dot"},
				{"shape": "mote", "scale": 1.7, "colors": _wordmark_cols(0.55)},
				{"shape": "mote", "scale": 1.1, "colors": _wordmark_cols(0.70)},
				{"shape": "mote", "scale": 0.7, "colors": _wordmark_cols(0.38)},
				{"shape": "swirl", "colors": _wordmark_cols(0.55)},
			]
			_colors = _wordmark_cols(0.70)
			return
		"lanterns":
			# Lantern Festival — a REAL release: few, big lanterns climbing slowly
			# from the bottom. (A dense crowd of small fast ones read as fireflies,
			# not lanterns — realism here is scarcity and calm.)
			_shape = "lantern"; _rise = true
			_amount = clampi(int(_amount * 0.16), 12, 26)
			_colors = [Color("FFC24D"), Color("FFDE8A"), Color("FF8A3D"), Color("FFF0C8")]
			return
		"fireworks":
			# Carnival — SPIRAL streamers: ribbons and paper corkscrewing down in
			# fast twirls, the whole shower swirling one way like a big-top vortex.
			_shape = "ribbon"; _set_material("ribbon")
			_spin = 540.0; _tumble = true; _sway = 0.05
			_orbit_lo = 0.12; _orbit_hi = 0.38   # one-signed orbit = a true spiral drift
			_mix = [{"shape": "ribbon"}, {"shape": "ribbon"}, {"shape": "square"}]
			_colors = _rainbow_cols()
			return
		"grid":
			# Vaporwave — a FULL stage laser show: projector fans sweep sequential
			# beams up from the bottom corners and centre stage (see _laser_show),
			# each beam aligned to its flight and cutting out like a real rig.
			_shape = "streak"; _set_material("laser")
			_laser_flag = true
			_scale_lo = 2.6; _scale_hi = 4.4   # long beams, not short bits
			_colors = [Color("FF59C7"), Color("59E0FF"), Color("B96BFF"), white]
			return
		"hearts":
			# Kawaii — a FULL RAINBOW of bright hearts floating up from the bottom
			# (pink, red, orange, yellow, green, blue, purple), sprinkled with
			# pastel five-point stars riding the same rise.
			_shape = "heart"; _rise = true
			_mix = [
				{"shape": "heart"}, {"shape": "heart"},
				{"shape": "star5", "colors": [white, Color("FFE08A"), Color("FFB8E8")]},
			]
			_colors = [
				Color("FF4D94"), Color("FF5C5C"), Color("FF9E4D"), Color("FFE066"),
				Color("7AE582"), Color("5CC8FF"), Color("B78AFF"), Color("FF8AD8")]
			return
		"anime":
			# Anime — sketchbook mascots and kirakira: the chibi neko blob and
			# the cute onigiri tumble among big four-point sparkles and star
			# pops, and the burst OPENS on a manga impact frame — a white pop
			# with radial concentration lines rushing in from the edges
			# (_speed_burst). The doodle character HEADS are deliberately not in
			# the shower any more: they are the WORLD's doodles now, drawn
			# drifting through the theme itself (BoardFx._anime_doodles shares
			# these very bakes), and throwing the same faces as confetti made
			# the two layers read as one soup. Doodles float flat — never the
			# sliver-thin paper flip, which would fold a face in half.
			_set_material("paper")
			_tumble = false
			_spin = 140.0
			_grav = 300.0
			_scale_lo = 1.3; _scale_hi = 2.4
			_speed_lines_flag = true
			_shape = "doodle_cat"
			_mix = [
				{"shape": "doodle_cat", "colors": [white]},
				{"shape": "doodle_onigiri", "scale": 0.9, "colors": [white]},
				{"shape": "sparkle", "scale": 1.2, "colors": [Color("C89CFF"), Color("FF9EE0"), Color("9CD8FF"), Color("FFE08A"), white]},
				{"shape": "star5", "colors": [Color("FFE08A"), white, Color("FF9EE0")]},
			]
			_colors = [white]
			return
		"leaves":
			# Autumn — a real leaf FALL: broad lobed MAPLES turning down among slimmer
			# blades, with dry seed husks spinning between them. The shower used to be
			# the slim pointed leaf repeated in five browns, and a maple is the
			# silhouette the season is made of — one shape at five colours is a
			# palette, not a fall.
			_shape = "maple"; _set_material("leaf")
			_scale_lo = 1.8; _scale_hi = 3.4
			_mix = [
				{"shape": "maple"}, {"shape": "maple"}, {"shape": "leaf"},
				{"shape": "petal", "colors": [Color("F0C75E"), Color("C99A4B"), Color("8C5A2B")]},
			]
			_colors = [Color("E8A33D"), Color("D96C2F"), Color("B8452B"), Color("F0C75E"), Color("8C5A2B")]
			return
		"petals":
			# Sakura — WHOLE CHERRY BLOSSOMS, not just loose petals. Five notched
			# petals around a gold stamen burst, baked in full colour in three
			# depths (pale, mid, deep rose) so the fall carries the real tree's
			# range; single petals still drift between the flowers, coloured off
			# the board's own blossom tiles (2 -> 128) so the shower still matches
			# the board. Flowers are drawn bigger and turn slower than a loose
			# petal — that weight difference is what stops them reading as more
			# confetti and starts them reading as flowers coming off the tree.
			var sakura: Array = _tile_cols(true, [2, 8, 16, 32, 64, 128])
			_shape = "blossom_a"; _set_material("petal")
			_spin = 190.0
			_scale_lo = 1.5; _scale_hi = 2.9
			_mix = [
				{"shape": "blossom_a", "colors": [white]},
				{"shape": "blossom_b", "colors": [white]},
				{"shape": "blossom_c", "colors": [white]},
				{"shape": "petal", "colors": sakura},
				{"shape": "petal", "colors": sakura},
			]
			_colors = [white]
			return
		"bubbles":
			# Ocean — the whole column comes up, not one size of bubble: big wobbling
			# domes with a fine seltzer of tiny ones between them and sunlight caught
			# on the water as they climb.
			_shape = "bubble"; _rise = true
			_mix = [
				{"shape": "bubble"}, {"shape": "bubble"},
				{"shape": "mote", "colors": [Color("CFF4FF"), Color("7FD8F0"), white]},
				{"shape": "sparkle", "scale": 0.7, "colors": [white, Color("9FE8FF")]},
			]
			_colors = [white, Color("CFF4FF"), Color("9FE8FF"), Color("E8FBFF")]
			return
		"deep_sea":
			# Coral Depths — reef treasures: starfish and coral fronds sinking
			# through the water while bubbles stream up around them.
			_set_material("sink")
			_mix = [
				{"shape": "starfish", "colors": [Color("FF8A5C"), Color("E8604A"), Color("FFB088"), Color("D9484F")]},
				{"shape": "petal", "colors": [Color("FF7FA8"), Color("C86BD9"), Color("5CE0C8"), Color("FFB088")]},
			]
			_shape = "bubble"   # the rising layer
			_with_bubbles = true
			_colors = [white, Color("CFF4FF"), Color("9FE8FF")]
			return
		"biolum":
			# Bioluminescence — a plankton bloom lighting up: motes drifting and
			# PULSING (shimmer rides the rise ramp), hard little flashes firing off
			# among them where the water is disturbed, and glowing gas bubbles
			# carrying the light up. One size of glowing dot was a field of pixels;
			# what makes a bloom read is the flash going off inside it.
			_shape = "mote"; _rise = true; _shimmer = true
			_mix = [
				{"shape": "mote"}, {"shape": "mote"},
				{"shape": "sparkle", "scale": 0.7,
					"colors": [white, Color("AFFFF0"), Color("66FFE0")]},
				{"shape": "bubble", "colors": [Color("66FFE0"), Color("3DD6FF"), Color("AFFFF0")]},
			]
			_colors = [Color("66FFE0"), Color("3DD6FF"), Color("AFFFF0"), white]
			return
		"firefly_night":
			# Firefly Night — actual FIREFLIES, not tinted glow dots: a dark
			# beetle body with the species' red pronotum and two translucent
			# wings, and a lantern abdomen burning amber through a wide halo.
			# They rise, wander and BLINK (the shimmer ramp), with bare motes
			# still riding among them so the field keeps its depth instead of
			# becoming a wall of identical insects.
			_shape = "firefly"; _rise = true; _shimmer = true
			_mix = [
				{"shape": "firefly", "colors": [white]},
				{"shape": "firefly", "colors": [white]},
				{"shape": "mote", "colors": [Color("FFE87A"), Color("D8FF7A"), Color("FFF4B8")]},
			]
			_colors = [white]
			return
		"space":
			# Space — a DENSE sky of tiny stars drifting slowly down, never
			# fading: pinprick kirakira four-rays and five-point glints, like a
			# clear night poured over the screen.
			_shape = "sparkle"; _set_material("stardust")
			_amount = int(_amount * 2.0)
			_mix = [{"shape": "sparkle"}, {"shape": "star5"}, {"shape": "sparkle"}]
			_colors = [white, Color("9CD8FF"), Color("FFE08A"), Color("C89CFF")]
			return
		"nebula":
			# Cosmic Nebula — the same dense tiny-star sky in nebula violets.
			_shape = "sparkle"; _set_material("stardust")
			_amount = int(_amount * 2.0)
			_mix = [{"shape": "sparkle"}, {"shape": "star5"}, {"shape": "sparkle"}]
			_colors = [Color("C89CFF"), Color("FF9EE0"), Color("9CD8FF"), white]
			return
		"rain":
			# Thunderstorm — the celebration is the STORM, and only the storm.
			# Bolts as confetti were tried and they read as litter: a discharge
			# happens in an instant across the whole sky, and chopping it into
			# scraps that tumble out of a party popper fights everything the eye
			# knows about lightning. So the screen is swept by WIND instead —
			# spray, rain and gust curls driving across it (see _storm_wind) —
			# under the double flash, which stays because a flash is weather,
			# not a falling object.
			_wind_flag = true
			_storm_flash = true
			_life = 2.6
			_colors = [white]
			return
		"neon":
			# Neon Blue — SPIRALLING neon: streaks and squares corkscrewing down in
			# one shared swirl (Carnival's one-signed orbit trick), so the shower
			# reads as an electric vortex instead of plain falling bits.
			_shape = "streak"; _set_material("streak")
			_spin = 340.0; _tumble = true
			_orbit_lo = 0.15; _orbit_hi = 0.45
			_mix = [{"shape": "streak"}, {"shape": "streak"}, {"shape": "square"}]
			_colors = [Color("59E0FF"), Color("4D8DF0"), Color("9BF1FF"), white]
			return
		"aurora":
			# Aurora — the sky's own curtains, not plain paper: long shimmering
			# ribbons in aurora greens and violets that catch and lose the light.
			_shape = "ribbon"; _set_material("ribbon")
			_shimmer = true
			_mix = [{"shape": "ribbon"}, {"shape": "ribbon"}, {"shape": "streak"}]
			_colors = [Color("66FFC2"), Color("7AE8A8"), Color("B96BFF"), Color("59E0FF"), white]
			return
		"blood_moon":
			# Blood Moon — dark red gems, with hot embers riding the same fall.
			_shape = "gem"; _set_material("gem")
			_mix = [
				{"shape": "gem"}, {"shape": "gem"},
				{"shape": "spark", "colors": [Color("FF8A3D"), Color("FF5C2E"), Color("FFC46B")]},
			]
			_colors = [Color("C22E3A"), Color("8C1F2B"), Color("FF5C4D"), Color("E86A5A")]
			return
		"metaballs":
			# Antigrav — confetti that FALLS would betray the theme: glowing plasma
			# floats up and off the top, pulsing like the live blobs behind it. The
			# cast is the backdrop's own now — fat metaball skins with charged motes
			# and discharge stars riding between them, instead of one glowing dot.
			_shape = "mote"; _rise = true; _shimmer = true
			_mix = [
				{"shape": "mote"}, {"shape": "mote"},
				{"shape": "bubble", "colors": [Color("FF5CB8"), Color("59E0FF"), Color("B96BFF")]},
				{"shape": "star5", "scale": 0.55,
					"colors": [white, Color("59E0FF"), Color("FF5CB8")]},
			]
			_colors = [Color("FF5CB8"), Color("59E0FF"), Color("B96BFF"), white]
			return
		"blackhole":
			# Event Horizon — accretion-disk starlight: a dense field of tiny
			# white-hot-through-orange stars.
			_shape = "sparkle"; _set_material("stardust")
			_amount = int(_amount * 1.5)
			_mix = [{"shape": "sparkle"}, {"shape": "star5"}, {"shape": "sparkle"}]
			_colors = [white, Color("FFC46B"), Color("FF8A3D"), Color("9CD8FF")]
			return
		"serpent":
			# Ember Serpent — the coil throws more than sparks: CINDERS break off it
			# and tumble away still glowing, trailing fine sparks and hot streaks.
			# Sparks alone are a field of identical pinpricks; the cinder is the piece
			# with mass, and it is what the sparks come off.
			_shape = "cinder"; _set_material("spark")
			_life = 2.7                # a cinder takes longer than a spark to cool
			_spin = 260.0
			_scale_lo = 1.3; _scale_hi = 2.9
			_mix = [
				{"shape": "cinder", "colors": [white, Color("FF8A3D"), Color("FF4D2E")]},
				{"shape": "spark"}, {"shape": "spark"},
				{"shape": "streak", "colors": [white, Color("FFC46B"), Color("FF7A2E")]},
			]
			_colors = [white, Color("FFC46B"), Color("FF7A2E"), Color("FF4D2E")]
			return
		"forge":
			# Nova Forge — the hammer lands: a spray of anvil sparks, glowing scale
			# knocked off the billet, and stubby chips of hot bar-stock thrown clear.
			# A strike is a shower of DEBRIS with sparks in it, not sparks alone.
			_shape = "spark"; _set_material("spark")
			_life = 2.7
			_spin = 300.0
			_mix = [
				{"shape": "spark"}, {"shape": "spark"},
				{"shape": "cinder", "colors": [white, Color("FFD98A"), Color("FF8A3D")]},
				{"shape": "bar", "colors": [Color("FFF0C8"), Color("FFA83D"), Color("FF6B2E")]},
			]
			_colors = [white, Color("FFD98A"), Color("FFA83D"), Color("FF6B2E")]
			return
		"circuit":
			# Circuit Pulse — Neon City's electric vortex re-wired to terminal greens.
			_shape = "streak"; _set_material("streak")
			_spin = 340.0; _tumble = true
			_orbit_lo = 0.15; _orbit_hi = 0.45
			_mix = [{"shape": "streak"}, {"shape": "streak"}, {"shape": "square"}]
			_colors = [Color("5CFF6B"), Color("2EDB55"), Color("B8FFC2"), white]
			return
		"starmap":
			# Starforged — a dense drift of tiny forged-star points in steel blues.
			_shape = "sparkle"; _set_material("stardust")
			_amount = int(_amount * 1.5)
			_mix = [{"shape": "sparkle"}, {"shape": "star5"}, {"shape": "sparkle"}]
			_colors = [white, Color("8AB8FF"), Color("5C8DE0"), Color("C9DFFF")]
			return
		"star_atlas":
			# Star Atlas — a calm chart-room starfall: still the quietest sky,
			# tiny parchment-gold points with the odd brighter mark.
			_shape = "sparkle"; _set_material("stardust")
			_mix = [{"shape": "sparkle"}, {"shape": "star5"}, {"shape": "sparkle"}]
			_colors = [white, Color("F0D8A8"), Color("D9B86B"), Color("9CB8D8")]
			return
		"skywriter":
			# Skywriter — the celebration is the SKY itself answering: soft
			# wind-waves rippling across the whole background, like currents
			# combed through high cloud. NO falling confetti at all, by design.
			_wave_flag = true
			_shape = "wave"
			_colors = [white, Color("EAF6FF"), Color("BFE3FF"), Color("8FCBFF")]
			return
		"stained_glass":
			# Sanctum — the window shatters, and shattered glass is SPLINTERS: long
			# irregular slivers cartwheeling down in the window's own jewel tones,
			# with the odd thick pane fragment among them and hard glints coming off
			# the broken edges. The old shower threw faceted gems, which is a
			# jeweller's tray rather than a broken window.
			_shape = "shard"; _set_material("gem")
			_spin = 600.0
			_scale_lo = 1.4; _scale_hi = 2.8
			_mix = [
				{"shape": "shard"}, {"shape": "shard"}, {"shape": "gem"},
				{"shape": "sparkle", "scale": 0.7,
					"colors": [white, Color("FFE8B8"), Color("CFE4FF")]},
			]
			_colors = [Color("D93646"), Color("2FBF71"), Color("4D8DF0"),
				Color("B96BFF"), Color("F4C13E")]
			return
		"bonsai":
			# First Bloom — the season's FIRST flowers, so whole blossoms come off the
			# little tree among the loose petals, with pollen lit gold by the dusk
			# drifting after them. Sakura's shower is the tree in full flower (all
			# three depths at once); this one is a single deep bloom in a fall of
			# petals — the same event a fortnight earlier.
			_shape = "petal"; _set_material("petal")
			_spin = 200.0
			_mix = [
				{"shape": "blossom_c", "colors": [white]},
				{"shape": "petal"}, {"shape": "petal"},
				{"shape": "mote", "colors": [Color("FFE0EA"), Color("FFC46B"), Color("FFF0D8")]},
			]
			_colors = [Color("FFB8CE"), Color("FF8FB0"), Color("E86A96"), Color("FFE0EA")]
			return
		"koi":
			# Koi Garden — the screen IS the pond, seen from above. Blossom drifts
			# down onto the water while the koi themselves come up through it
			# (_koi_school), each one opening a ripple as it passes.
			#
			# The koi used to fall as PARTICLES, tumbling down among the petals,
			# and a fish raining out of the sky reads as a dead one. A koi is the
			# one piece in the catalogue that has to swim, so it left the mix and
			# became live cast — the emitters below are the blossom only.
			_koi_school_flag = true
			_shape = "petal"; _set_material("petal")
			# The blossom is the SETTING, not the subject: at the shared amount it
			# came down as a wall of flowers with the fish lost somewhere inside it.
			_amount = int(_amount * 0.55)
			_mix = [
				{"shape": "petal", "colors": [white, Color("FFD9E0"), Color("FFB8CE")]},
				{"shape": "blossom_c", "colors": [white], "scale": 0.72},
				{"shape": "petal", "colors": [white, Color("FFD9E0"), Color("FFB8CE")]},
			]
			_colors = [white, Color("FFD9E0")]
			return
		"katana":
			# Ronin — crimson petals falling past the BLADE: pale steel glints flash
			# between them and a little gold menuki work spins loose. Putting the
			# steel in the colour list only made some petals white; a glint has to be
			# its own shape before it reads as metal rather than a pale flower.
			_shape = "petal"; _set_material("petal")
			_mix = [
				{"shape": "petal"}, {"shape": "petal"},
				{"shape": "streak", "scale": 0.65,
					"colors": [Color("F0EDE6"), white, Color("B8C4D8")]},
				{"shape": "dot", "scale": 0.40,
					"colors": [Color("D9A05C"), Color("F0C88A")]},
			]
			# The pale steel leaves the PETAL list now that it has a shape of its
			# own — kept in both, a quarter of the flowers came down grey.
			_colors = [Color("C22E3A"), Color("E85560"), Color("D94452"), Color("8C1F2B")]
			return
		"gears":
			# Clockwork — the movement comes apart: toothed GEARS spinning down
			# among bronze coins and bar-stock, all heavy glinting metal.
			_shape = "gear"; _set_material("foil")
			_mix = [{"shape": "gear"}, {"shape": "coin"}, {"shape": "bar"}]
			_colors = [Color("D9A05C"), Color("B87A3D"), Color("F0C88A"), Color("8C5A2B")]
			return
		"stardrift":
			# Obsidian — a dense drift of tiny gold-fleck stars, like its
			# stardrift backdrop poured down the screen.
			_shape = "sparkle"; _set_material("stardust")
			_amount = int(_amount * 1.5)
			_mix = [{"shape": "sparkle"}, {"shape": "star5"}, {"shape": "sparkle"}]
			_colors = [Color("E7C56B"), Color("B89A55"), Color("F0E0B0"), Color("8A8FA0")]
			return
		"lightdust":
			# Daybreak — the celebration IS the dawn chorus: a live flock of
			# songbirds takes wing across the sunrise (_dawn_flock), and nothing
			# else. Leaves and motes rode along in an earlier cut and were
			# removed — under a flock of real birds every extra piece read as
			# clutter, and the birds carry the whole morning on their own. The
			# _mix below is dead code BY DESIGN, exactly like Butterfly Grove's:
			# the flock returns before any particle path runs, but recipe_preview
			# reads it, so the Themes card drifts the birds themselves. _rise
			# rides along for the same reason — the card's cast floats up, the
			# way the flock actually flies.
			_bird_flock_flag = true
			_rise = true
			_shape = "bird_a"
			_mix = [
				{"shape": "bird_a", "colors": [white]},
				{"shape": "bird_b", "colors": [white]},
			]
			_colors = [white]
			return
		"origami":
			# Origami Sky — a thousand cranes take flight (_crane_flight) and the
			# folded paper they were cut from comes down after them: darts gliding
			# nose-first, plain squares fluttering, all in the theme's sky pastels.
			#
			# The cranes used to TUMBLE down as particles, flipping end over end.
			# Paper folded into a bird is the one piece in a paper shower that
			# should never fall, so they left the mix and became live cast; the
			# dart took their place in it, which is the fold that does flutter.
			_crane_flight_flag = true
			_shape = "paper_dart"
			# Same reason as Koi Garden's blossom: at the shared amount the loose
			# paper is dense enough to hide the cranes flying through it.
			_amount = int(_amount * 0.66)
			_spin = 220.0
			_sway = 0.03
			_mix = [{"shape": "paper_dart", "scale": 0.62}, {"shape": "square"},
				{"shape": "square"}]
			_colors = [white, Color("9CD8FF"), Color("FFB8CE"), Color("FFE08A"), Color("B8E8C8")]
			return
		"zen_sand":
			# Zen Garden — a CALM drift, not a party: pale sand motes and a few
			# moss leaves sinking slowly, raked-garden quiet.
			_set_material("sink")
			_amount = int(_amount * 0.7)
			_shape = "dot"
			_mix = [
				{"shape": "dot", "colors": [Color("EDE3CE"), Color("D9CDB0"), Color("C9BFA8")]},
				{"shape": "leaf", "colors": [Color("8FAF7E"), Color("6E9464")]},
				{"shape": "petal", "colors": [white, Color("F2EDE2")]},
			]
			_colors = [Color("EDE3CE")]
			return
		"flecks":
			# Paper — a pressed-paper party: kraft and ink squares, hole-punch dots
			# out of the puncher's tray, and long paper streamers. Paper is a LIGHT
			# theme and the shower used to lead on cream and white against a cream
			# page — four of its five colours were doing nothing. It leads on kraft,
			# ink-blue and rust now, with cream kept as the accent rather than the
			# body, so the same matte party actually lands on the paper.
			_mix = [
				{"shape": "square"}, {"shape": "square"},
				{"shape": "dot", "colors": [Color("38507F"), Color("C4553D"), Color("6E6A60")]},
				{"shape": "ribbon"},
			]
			_colors = [Color("B8A888"), Color("38507F"), Color("C4553D"), Color("8C8578"), Color("E8DFC8")]
			return
		"honeycomb":
			# Honeycomb — the hive spills: fat drops of raw honey falling heavy and
			# glossy, broken wax cells tumbling after them, and BEES flying out
			# among it. The bees are baked in full colour (fuzzy amber and black,
			# wings blurred) so they never come out as tinted paper — a yellow
			# square is not an insect, and at this size that is the whole gag.
			_shape = "bee"; _set_material("foil")
			_tumble = false            # a bee folded edge-on is not a bee
			_grav = 640.0
			_spin = 170.0
			_scale_lo = 1.6; _scale_hi = 3.0
			# BEES lead the mix at two parts in five. They are the thing the theme
			# is named for, and one bee in three pieces of falling wax is a hive
			# with nobody home. Comb falls as joined CHUNKS rather than single
			# cells (a lone hexagon reads as a UI icon), and the honey comes as
			# both fat drops and curling ribbons of drizzle.
			_mix = [
				{"shape": "bee", "colors": [white]},
				{"shape": "bee", "colors": [white]},
				{"shape": "honey_drop", "colors": [white]},
				{"shape": "honey_ribbon", "colors": [white]},
				{"shape": "comb_chunk", "colors": [Color("F0B72E"), Color("C4890F"), Color("E8C46A")]},
			]
			_colors = [white]
			return
		"butterflies":
			# Butterfly Grove — a LIVING flock, the same idea as Phantom Realm's
			# bats turned the other way round: a couple of dozen real butterflies
			# lift off and wander up and out, beating their wings, each one
			# CURVING between waypoints instead of flying the bats' straight
			# accelerating line — a butterfly that flies like a bat is a moth.
			_fly_flock_flag = true
			# Kept as a safety net rather than a live path: _spawn routes both the
			# tap and the bomb into the flock, but if that branch is ever reordered
			# below _blast again, this is what stops a detonation falling back to
			# plain white squares (which is exactly what it did once already).
			_shape = "butterfly_a"; _set_material("petal")
			_tumble = false
			_spin = 140.0
			_scale_lo = 1.6; _scale_hi = 3.0
			_mix = [
				{"shape": "butterfly_a", "colors": [white]},
				{"shape": "butterfly_b", "colors": [white]},
				{"shape": "butterfly_c", "colors": [white]},
			]
			_life = 6.5              # after _set_material, which sets its own
			_colors = [white]
			return
		"plumage":
			# Peacock — the train is shed: whole tail feathers turning slowly down,
			# each with its iridescent eye baked in, among loose barbs of teal and
			# gold. Feathers are the lightest thing in the catalogue, so they ride
			# the petal material and take their time.
			# The feather bakes at 44x96, 2.4x the old piece, so the feathers
			# carry their own scale band here; the barbs keep the petal band.
			_shape = "feather"; _set_material("petal")
			_feather_drift_flag = true
			_spin = 70.0
			_life = 7.4
			# A train sheds a few feathers, not a blizzard: the pieces are big and
			# every one carries an eye, so at full density the shower is a wall
			# of eyes and nothing reads as a feather.
			_amount = int(_amount * 0.16)
			_mix = [
				{"shape": "feather", "colors": [white], "scale": 0.48},
				{"shape": "feather", "colors": [white], "scale": 0.48},
				{"shape": "streak", "colors": [Color("178A6C"), Color("12633E"), Color("8A7A42"), Color("0B3D64")]},
			]
			_colors = [white]
			return
		"inkwash":
			# Ink Wash — ink blooming in water: dark wisps spreading like the wash.
			_shape = "mist"; _set_material("mist")
			_colors = [Color(0.18, 0.20, 0.25), Color(0.27, 0.31, 0.37), Color(0.42, 0.45, 0.51)]
			return
	match style:
		"gold":
			# Golden Rain — a real hoard: struck coins, cast bars and raw
			# nuggets, every piece baked in FULL colour through gold's own
			# response curve (_metal), so its shadows fall to brown-red while its
			# highlight blows out to warm white. Tinting one grey coin could only
			# ever scale a single hue, and that hue SHIFT across the value range
			# is most of what reads as metal — so these emit white and let the
			# bake carry the colour.
			_shape = "gold_coin"; _set_material("foil")
			_mix = [
				{"shape": "gold_coin", "colors": [white]},
				{"shape": "gold_coin", "colors": [white]},
				{"shape": "gold_bar", "colors": [white]},
				{"shape": "gold_nugget", "colors": [white]},
			]
			_colors = [white]
		"silver":
			# Silver Rain — the same hoard struck in silver: cold blue-grey
			# shadows against a pure white specular, which is exactly the
			# difference a tint cannot make and the bake can.
			_shape = "silver_coin"; _set_material("foil")
			_mix = [
				{"shape": "silver_coin", "colors": [white]},
				{"shape": "silver_coin", "colors": [white]},
				{"shape": "silver_bar", "colors": [white]},
				{"shape": "silver_nugget", "colors": [white]},
			]
			_colors = [white]
		"desert":
			# Desert Midnight — an Arabian-nights hoard: gold, silver AND jewels.
			_shape = "coin"; _set_material("foil")
			_mix = [
				{"shape": "coin", "colors": [gold, Color(1, 0.9, 0.5), Color(1, 0.78, 0.25)]},
				{"shape": "bar", "colors": [gold, Color(0.92, 0.94, 1.0), Color(1, 0.82, 0.35)]},
				{"shape": "gem", "colors": [Color("D93646"), Color("2FBF71"), Color("4D8DF0"), Color("F4C13E")]},
			]
			_colors = [gold, Color(1, 0.9, 0.5), white]
		"diamond":
			# Diamond Rain — KITE-cut stones, the flat-topped silhouette everyone
			# pictures when they hear the word, with baguettes falling among them
			# for a second outline and hard white star-glints between. The first
			# pass shaded round brilliants in near-white and they read as PEARLS:
			# the catalogue is already full of discs, so no amount of facet work
			# was going to say diamond while the shape said bead. Shape first,
			# then contrast, then dispersion.
			_shape = "diamond_kite"; _set_material("gem")
			_spin = 700.0
			_scale_lo = 1.2; _scale_hi = 2.4
			_mix = [
				{"shape": "diamond_kite", "colors": [white]},
				{"shape": "diamond_kite", "colors": [white]},
				{"shape": "diamond_baguette", "colors": [white]},
				{"shape": "star5", "colors": [white, Color("DCF2FF")]},
			]
			_colors = [white]
		"crystal":
			# Crystal Storm — a STORM of crystals, which means the storm is carrying
			# more than one thing: whole stones whirling among long rime splinters
			# with hard glints struck off both. Dense and fast was already right; a
			# single silhouette at that density is what read as hail.
			_shape = "gem"; _set_material("gem")
			_amount = int(_amount * 1.3)
			_spin = 820.0; _launch = 1.15; _sway = 0.02
			_mix = [
				{"shape": "gem"}, {"shape": "gem"}, {"shape": "icicle"},
				{"shape": "star5", "scale": 0.5, "colors": [white, Color("DCF2FF")]},
			]
			_colors = [soft, white, accent.lightened(0.2), accent]
		"hoarfrost":
			# Arctic — the frost comes off in PIECES: six-armed crystals fluttering
			# down among hard rime splinters, glinting as they turn. (Arctic spent a
			# long time silently on the generic-paper fallback because this arm used
			# to match only Glacier Dawn's "frost"; that theme is gone and so is that
			# value.) Arctic is also a LIGHT theme, and a shower led by white on a
			# near-white sky was invisible: the crystals now carry the board's own
			# deep blues and white is kept for the glint, where a bright pinprick
			# still reads against snow.
			_shape = "snowflake"; _set_material("petal")
			_spin = 200.0
			_mix = [
				{"shape": "snowflake"}, {"shape": "snowflake"},
				{"shape": "icicle", "colors": [Color("6FB4E8"), Color("2E6FA8"), Color("A8DCFF")]},
				{"shape": "star5", "scale": 0.6,
					"colors": [Color("A8DCFF"), Color("5CA8E0"), white]},
			]
			_colors = [Color("4E93D6"), Color("2E6FA8"), Color("8FC8F0"), Color("BFE4FF")]
		"emerald":
			# Emerald — SMALL precious stones, not slabs: emerald-cut faces with hard
			# stepped facets and a hot glint, tumbling fast so they catch the light
			# like real 3D gems. Two cuts fall together with loose fire coming off
			# them, the same two-silhouette treatment Ruby already had, because one
			# repeated outline is what makes a stone shower look printed. The second
			# cut is the pointed `gem`, NOT the round brilliant: a near-white disc
			# reads as a pearl however well it is faceted, which is the trap Diamond
			# Rain already climbed out of.
			_shape = "emeraldcut"; _set_material("gem")
			_spin = 780.0
			_scale_lo = 1.0; _scale_hi = 1.9
			_mix = [
				{"shape": "emeraldcut"}, {"shape": "emeraldcut"},
				{"shape": "gem", "colors": [Color("2FBF71"), Color("128A4C"), Color("57E695")]},
				{"shape": "sparkle", "scale": 0.7, "colors": [white, Color("BFF5D8")]},
			]
			# The pale mint stays in the GLINTS and out of the stones: tinting a
			# faceted disc near-white is the whole pearl problem, and a quarter of
			# the shower was drawing that way.
			_colors = [Color("2FBF71"), Color("57E695"), Color("128A4C"), Color("1FA85E")]
		"ruby":
			# Ruby — real cut stones, baked in FULL colour so the crown can do
			# what a tint multiply cannot: a pavilion falling almost to black
			# maroon, facets climbing THROUGH scarlet into pink-white fire, and
			# stray dispersion flashes (orange one way, violet the other) out
			# near the girdle. Two cuts fall together — round brilliants and a
			# marquise — so the shower has two silhouettes instead of one disc
			# repeated, with loose sparks of fire coming off them.
			_shape = "ruby_stone"; _set_material("gem")
			_spin = 760.0
			_scale_lo = 1.1; _scale_hi = 2.1
			_mix = [
				{"shape": "ruby_stone", "colors": [white]},
				{"shape": "ruby_stone", "colors": [white]},
				{"shape": "ruby_marquise", "colors": [white]},
				{"shape": "sparkle", "colors": [white, Color("FFD3D3"), Color("FF8A8A")]},
			]
			_colors = [white]
		"jade":
			# Moonlit Bamboo — slim bamboo leaves twirling down through the MOONLIGHT
			# that gives the theme its name: jade chips turn among them and the light
			# catches on both. The old shower drew half its leaves in the theme's
			# partner colour, a deep forest green, on a near-black grove — those
			# pieces never showed up at all, so the palette holds mid greens now.
			_shape = "leaf"; _set_material("leaf")
			_mix = [
				{"shape": "leaf"}, {"shape": "leaf"},
				{"shape": "gem", "colors": [Color("7ACF9E"), Color("B8F0D0"), Color("4E9E6E")]},
				{"shape": "sparkle", "scale": 0.55,
					"colors": [Color("D8FFE8"), Color("A8E8C4"), Color("7ACF9E")]},
			]
			_colors = [accent, Color("7ACF9E"), Color("4E9E6E"), Color(0.7, 0.98, 0.8)]
		"rose":
			# NOTE: currently only Sakura Pink carries board_style "rose", and its
			# "petals" motif is matched above — so this arm only fires for a FUTURE
			# rose-board theme without a petal motif. Kept as the correct fallback.
			_shape = "petal"; _set_material("petal")
			_colors = [accent, soft, white, accent.lightened(0.25)]
		"phantom":
			# Phantom Realm — not paper at all: a LIVING flock. A handful of real
			# animated bats erupt and fly off screen (see _bat_flock), each facing
			# its flight line and beating its wings.
			_bat_flock_flag = true
			_life = 5.0
			_colors = [accent, soft]   # unused by the flock; kept for safety
			return
		"shadow":
			# Shadow Fog — the celebration IS the fog: huge translucent wisps of
			# mist billowing up and thinning away, with a handful of faint glints
			# inside the haze so a WIN still reads as a win.
			_shape = "mist"; _set_material("mist")
			_fog_glints = true
			_fog_bank_flag = true
			_colors = [Color(0.82, 0.85, 0.95), Color(0.62, 0.66, 0.8), white]
		"marble":
			# Carrara: stone chips and gold leaf. Hard and heavy, and no colour in
			# it but the brass.
			_shape = "shard"; _set_material("gem")
			_scale_lo = 1.4; _scale_hi = 2.6
			_mix = [
				{"shape": "shard", "colors": [white, Color("F0ECE4"), Color("D6C9B0")]},
				{"shape": "square", "colors": [Color("EDE9E2"), Color("C9C2B8"), Color("B8B0A4")]},
				{"shape": "ribbon", "colors": [Color("B08D57"), Color("D4B98C")]},
			]
			_colors = [white]
			return
		"noir":
			# Noir: a flashbulb's worth of ivory sparks, ivory paper, streaks of
			# light. No colour.
			_shape = "spark"; _set_material("paper")
			_shimmer = true
			_mix = [
				{"shape": "spark", "colors": [Color("F2E8D5"), white]},
				{"shape": "square", "colors": [Color("DCC39A"), Color("F4EEE1")]},
				{"shape": "streak", "colors": [Color("F2E8D5")]},
			]
			_colors = [Color("F2E8D5")]
			return
		"bismuth":
			# Bismuth: hopper facets, every colour of the film at once, and hard.
			_shape = "square"; _set_material("gem")
			_scale_lo = 1.6; _scale_hi = 3.0
			_mix = [
				{"shape": "hopper", "colors": [white]}, {"shape": "hopper", "colors": [white]},
				{"shape": "square"},
				{"shape": "gem", "colors": [Color("F3E4A0"), Color("3FC9B4")]},
				{"shape": "sparkle", "colors": [white]},
			]
			_colors = [Color("F3E4A0"), Color("D65A9C"), Color("3FC9B4"), Color("5A3FB0"), Color("2E7CE6")]
			return
		"wash":
			# Aquarelle: paint. Fat drops, splatter and runs, in the pigments.
			_shape = "dot"; _set_material("candy")
			_mix = [
				{"shape": "splat"}, {"shape": "splat"},
				{"shape": "dot"},
				{"shape": "spark", "scale": 0.7},
				{"shape": "streak", "scale": 0.8},
			]
			_colors = [Color("F2C94C"), Color("E88BA8"), Color("9B7FD1"), Color("3D7AB8"), Color("E07A5F")]
			return
		"mono":
			# Mono: black, white, grey and the one red. Squares, mostly.
			_shape = "square"; _set_material("paper")
			_mix = [
				{"shape": "square"}, {"shape": "square"},
				{"shape": "dot", "colors": [Color("E63B2E")]},
			]
			_colors = [Color("111111"), white, Color("A6A6A6"), Color("E63B2E")]
			return
		_:
			# Non-premium: colour the paper from the theme's OWN tile ramp, so the
			# confetti matches the board — a soft rainbow on Playful themes, the
			# accent→gold story on the rest.
			_shape = "square"
			_colors = _tile_cols()

var _spawned := false          # _spawn runs on the first _process tick (post-layout)
var _ttl_left: float = -1.0    # lifetime countdown; extendable by replay()

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# No forced z_index: draw order follows the parent we're added to, so callers
	# can place a shower BEHIND the grid (add to the board's bg layer) or on top
	# (add to the screen). See gameplay's in-play vs. victory celebrations.

## Spawn happens on the first _process tick (after the layout pass, same timing
## the old awaited process_frame gave); the lifetime is a _process countdown,
## NOT an awaited timer, so a rapid tap can EXTEND it when it relights this
## shower in place (see replay) and a bomb wipe never strands a coroutine.
## The node still lives long enough for every piece to leave the screen (or
## fade, for sparks/stardust) — nothing gets cut off mid-air.
func _process(delta: float) -> void:
	if not _spawned:
		_spawned = true
		_spawn()
		_ttl_left = _ttl + 0.5
		return
	if _ttl_left < 0.0:
		return
	_ttl_left -= delta
	if _ttl_left <= 0.0:
		queue_free()

## The rapid-tap fast path (see celebrate): relight this shower IN PLACE.
## Restarting the emitters that already exist costs almost nothing, while the
## old free-and-rebuild path allocated ~a dozen emitters per tap — that churn
## was the wordmark-mash lag. Recipes whose cast is transient lightweight nodes
## (the bat flock, the sky waves, the lightning flash) run their routine again.
func replay() -> void:
	if _ttl_left <= 0.0:
		return   # not spawned yet, or already being reaped — leave it alone
	var s := _field()
	if _wave_flag:
		_sky_waves(s.x, s.y, 1.0)
	elif _bat_flock_flag:
		_bat_flock(s.x, s.y)
	elif _bird_flock_flag:
		_dawn_flock(s.x, s.y)
	else:
		if _storm_flash:
			_lightning()
		if _speed_lines_flag:
			_speed_burst(s.x, s.y)
		# Like the impact frame, the school and the flight are transient nodes
		# that have already freed themselves — restarting the emitters alone
		# would relight the blossom with no fish in it.
		if _koi_school_flag:
			_koi_school(s.x, s.y)
		if _crane_flight_flag:
			_crane_flight(s.x, s.y)
		for child in get_children():
			var ps := child as CPUParticles2D
			if ps != null:
				ps.restart()
	_ttl_left = maxf(_ttl, _live_ttl) + 0.5

func _field() -> Vector2:
	if size.x > 0.0:
		return size
	return UI.canvas_size(self)

func _spawn() -> void:
	var w := size.x
	var h := size.y
	if w <= 0.0:
		var vp := UI.canvas_size(self)
		w = vp.x
		h = vp.y
	# Skywriter: EVERY celebration — tap or bomb — is the sky rippling; a bomb
	# just combs more, stronger waves through it. Never falling pieces.
	if _wave_flag:
		_sky_waves(w, h, 1.0 + maxf(_bomb_strength, 0.0))
		return
	# Thunderstorm: every celebration is the storm sweeping the screen; a bomb
	# just drives it harder. Checked here, above the bomb branch, for the same
	# reason Skywriter is — there are no pieces for _blast to throw.
	if _wind_flag:
		if _storm_flash:
			_lightning()
		_storm_wind(w, h, 1.0 + maxf(_bomb_strength, 0.0))
		return
	# Butterfly Grove: a live flock, and a bomb spins it into a vortex. ALSO
	# above the bomb branch — below it, a detonation never reached the flock
	# and fell through to _blast's default squares.
	if _fly_flock_flag:
		if _bomb_strength >= 0.0:
			_butterfly_spiral(w, h)
		else:
			_butterfly_flock(w, h)
		return
	# Peacock: nothing FIRES a feather. A tap or milestone is the train shed,
	# feathers let go above the top edge and drifting down, and a bomb is the
	# display itself, the train fanning up out of the bottom of the screen.
	# ABOVE the bomb branch like the flocks, or a detonation falls through to
	# _blast and blows feathers out of a 26px sphere like so much paper.
	if _feather_drift_flag:
		if _bomb_strength >= 0.0:
			_train_fan(w, h)
		else:
			_feather_drift(w, h)
		return
	# Shadow Fog: every celebration is the fog rolling IN, and a bomb is a
	# heavier roll — never a detonation. ABOVE the bomb branch for the same
	# reason Skywriter and Thunderstorm are, and it was below it: a long press
	# fell through to `_blast`, which throws its cloud out of a 26px sphere at
	# the centre of the screen, so the one theme whose whole subject is weather
	# answered a bomb with a grey ball hanging in the middle of a black frame.
	# Ink Wash shares the mist shape and keeps the centre bloom — a drop of ink
	# hitting water genuinely does spread from a point.
	if _fog_bank_flag:
		_fog_field(w, h, 1.0 + maxf(_bomb_strength, 0.0))
		return
	# Daybreak: the celebration IS the dawn chorus — a live flock of songbirds
	# takes wing, and nothing else (pieces were tried under the birds and cut as
	# clutter). ABOVE the bomb branch like the other flocks; a bomb startles the
	# flock outward from the blast instead (see _dawn_flock's bomb arm).
	if _bird_flock_flag:
		_dawn_flock(w, h)
		return
	# Anime: the manga IMPACT FRAME opens everything — tap bursts and bombs both
	# get the white pop + concentration lines; the pieces still spawn below.
	if _speed_lines_flag:
		_speed_burst(w, h, 1.0 + maxf(_bomb_strength, 0.0))
	# Koi Garden and Origami Sky fly a live cast ALONGSIDE their pieces rather
	# than instead of one (the flocks above all return). Both sit above the bomb
	# branch for the same reason those do: a detonation must still be the theme's
	# own event, not a bare paper blast — the school scatters, the flight is
	# blown apart, and the pieces then explode underneath it.
	if _koi_school_flag:
		_koi_school(w, h)
	if _crane_flight_flag:
		_crane_flight(w, h)
	# Phantom Realm: a living bat flock erupts and flies off — no paper at all.
	# ABOVE the bomb branch for the same reason Butterfly Grove is, and it was
	# below it: the phantom arm never sets a shape (the flock does not use one),
	# so a detonation walked straight past the colony into _blast and threw plain
	# accent-tinted PAPER SQUARES — the one theme in the catalogue whose bomb had
	# nothing to do with its celebration.
	if _bat_flock_flag:
		_bat_flock(w, h)
		return
	# The long-press bomb detonation takes over everything: one 360° centre blast.
	if _bomb_strength >= 0.0:
		_blast(w, h)
		_ttl = maxf(_ttl, _live_ttl)
		return
	# Lanterns / hearts / bubbles / motes float straight up and off the top.
	if _rise:
		_rise_up(w, h)   # sets _ttl from its per-shape lifetime
		return
	# Vaporwave: the celebration IS a laser show — projector fans, not poppers.
	if _laser_flag:
		_laser_show(w, h)
		return
	# Shadow Fog: the fog surfaces EVERYWHERE at once — an even full-screen
	# field of thin wisps, never two thick banks clumping out of the corners.
	if _shape == "mist":
		_fog_field(w, h)
		return
	# Thunderstorm: the double lightning flash opens the strike.
	if _storm_flash:
		_lightning()
	# The classic celebration: party-popper BURSTS up-and-inward from the two lower
	# corners, plus a SHOWER raining down from the top. Paper-like pieces stay fully
	# opaque and leave the screen edges; only sparks/stardust fade, by design.
	_ttl = 0.06 + _life * 1.1
	_cannon(Vector2(w * 0.05, h * 0.96), Vector2(0.7, -1.0), int(_amount * 1.1), 0.0)
	_cannon(Vector2(w * 0.95, h * 0.96), Vector2(-0.7, -1.0), int(_amount * 1.1), 0.06)
	if _top_shower:
		_ttl = maxf(_ttl, _life * 1.7)
		_top_rain(w)
	# Coral reef: bubbles stream UP around the sinking starfish and coral pieces.
	if _with_bubbles:
		_rise_up(w, h)
	_ttl = maxf(_ttl, _live_ttl)

# --- Lifetime colour ramps ------------------------------------------------------
# Every ramp is identical on every call, so they are baked ONCE and shared by
# all emitters (rapid wordmark taps used to rebuild them per emitter, per tap).
static var _opaque_g: Gradient
static var _shimmer_g: Gradient
static var _cooling_g: Gradient
static var _mist_g: Gradient
static var _beam_g: Gradient
static var _glint_g: Gradient

## A no-fade colour ramp — pieces stay fully opaque and leave the screen edges rather
## than fading out on-screen.
func _opaque() -> Gradient:
	if _opaque_g == null:
		_opaque_g = Gradient.new()
		_opaque_g.offsets = PackedFloat32Array([0.0, 1.0])
		_opaque_g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 1)])
	return _opaque_g

## Shiny pieces (foil, gems, stars, candy, neon) pulse bright↔dim over their life
## — the RGB multiplier swings between full and ~0.66 several times while alpha
## stays 1.0, so a coin/gem/star flashes as it catches the light and dims as it
## turns away, never fading off-screen. Per-piece lifetime randomness (see
## `_liferand`) staggers the pulses so the whole shower glitters out of phase.
func _shimmer_ramp() -> Gradient:
	if _shimmer_g == null:
		_shimmer_g = Gradient.new()
		_shimmer_g.offsets = PackedFloat32Array([0.0, 0.14, 0.3, 0.46, 0.62, 0.78, 0.9, 1.0])
		var hi := Color(1, 1, 1, 1)
		var lo := Color(0.66, 0.66, 0.66, 1)
		_shimmer_g.colors = PackedColorArray([hi, lo, hi, lo, hi, lo, hi, hi])
	return _shimmer_g

## A GLAZE, not a glint: the same catch-the-light pulse as _shimmer_ramp but
## swinging 1.0 <-> 0.9 instead of 1.0 <-> 0.66.
##
## The deep swing is right on a dark theme, where a piece dropping to two-thirds
## reads as a face turning away from the light. On a pale theme it reads as the
## piece going muddy, and since the pulses are staggered by lifetime randomness,
## roughly half the field sits dimmed at any instant — which is most of why Candy
## Pop's shower looked darker than the board it falls on.
static var _glaze_g: Gradient

func _glaze_ramp() -> Gradient:
	if _glaze_g == null:
		_glaze_g = Gradient.new()
		_glaze_g.offsets = PackedFloat32Array([0.0, 0.16, 0.34, 0.52, 0.7, 0.86, 1.0])
		var hi := Color(1, 1, 1, 1)
		var lo := Color(0.90, 0.90, 0.90, 1)
		_glaze_g.colors = PackedColorArray([hi, lo, hi, lo, hi, lo, hi])
	return _glaze_g

## Sparks flare white-hot, cool through orange and die dark — an ember's life.
func _cooling_ramp() -> Gradient:
	if _cooling_g == null:
		_cooling_g = Gradient.new()
		_cooling_g.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
		_cooling_g.colors = PackedColorArray([Color(1, 1, 1, 1),
			Color(1, 0.78, 0.5, 0.85), Color(0.45, 0.16, 0.08, 0.0)])
	return _cooling_g

## Mist wisps stay translucent their whole life and thin away like real fog —
## kept THIN (low peak alpha) so overlapping wisps read as haze, never a wall.
func _mist_ramp() -> Gradient:
	if _mist_g == null:
		_mist_g = Gradient.new()
		_mist_g.offsets = PackedFloat32Array([0.0, 0.2, 0.7, 1.0])
		_mist_g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.22),
			Color(1, 1, 1, 0.18), Color(1, 1, 1, 0.0)])
	return _mist_g

## Fog glints (Shadow Fog): fade in, pulse a few times, fade away — a soft
## sparkle surfacing inside the haze, never a hard pop.
func _glint_ramp() -> Gradient:
	if _glint_g == null:
		_glint_g = Gradient.new()
		_glint_g.offsets = PackedFloat32Array([0.0, 0.15, 0.35, 0.55, 0.75, 1.0])
		_glint_g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 0.9),
			Color(0.6, 0.6, 0.6, 0.5), Color(1, 1, 1, 0.9), Color(0.6, 0.6, 0.6, 0.5),
			Color(1, 1, 1, 0)])
	return _glint_g

## Show lasers snap on, burn at full brightness, then cut out — never a slow fade.
func _beam_ramp() -> Gradient:
	if _beam_g == null:
		_beam_g = Gradient.new()
		_beam_g.offsets = PackedFloat32Array([0.0, 0.06, 0.88, 1.0])
		_beam_g.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1),
			Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	return _beam_g

# --- Tumble ----------------------------------------------------------------------
## End-over-end paper flip: the y-scale oscillates wide→sliver→wide while x stays
## put, so a piece reads as flipping in 3D. Lifetime randomness (set per-emitter)
## staggers the phases so the pieces never flip in unison.
func _flip_curve() -> Curve:
	if _flip == null:
		# Four full end-over-end flips across the lifetime (was three) — a faster,
		# livelier tumble that catches the eye and, with the shimmer pulse, glints
		# on every turn.
		_flip = Curve.new()
		_flip.add_point(Vector2(0.0, 1.0))
		_flip.add_point(Vector2(0.125, 0.1))
		_flip.add_point(Vector2(0.25, 1.0))
		_flip.add_point(Vector2(0.375, 0.12))
		_flip.add_point(Vector2(0.5, 1.0))
		_flip.add_point(Vector2(0.625, 0.1))
		_flip.add_point(Vector2(0.75, 1.0))
		_flip.add_point(Vector2(0.875, 0.12))
		_flip.add_point(Vector2(1.0, 1.0))
	return _flip

func _flat_curve() -> Curve:
	if _flat == null:
		_flat = Curve.new()
		_flat.add_point(Vector2(0.0, 1.0))
		_flat.add_point(Vector2(1.0, 1.0))
	return _flat

## The bats' wing-beat: the y-scale pumps between full spread and half-folded —
## unlike the paper flip it NEVER goes sliver-thin, so a bat always reads as a
## bat, its wings visibly beating.
func _flap_curve() -> Curve:
	if _flap == null:
		_flap = Curve.new()
		_flap.add_point(Vector2(0.0, 1.0))
		_flap.add_point(Vector2(0.125, 0.5))
		_flap.add_point(Vector2(0.25, 1.0))
		_flap.add_point(Vector2(0.375, 0.5))
		_flap.add_point(Vector2(0.5, 1.0))
		_flap.add_point(Vector2(0.625, 0.5))
		_flap.add_point(Vector2(0.75, 1.0))
		_flap.add_point(Vector2(0.875, 0.5))
		_flap.add_point(Vector2(1.0, 1.0))
	return _flap

## The shapes this shower is made of: one entry per shape, each with its own
## colour set (defaulting to the recipe's). Single-shape recipes yield one part.
func _parts() -> Array:
	if _mix.is_empty():
		return [{"shape": _shape, "colors": _colors}]
	return _mix

func _apply_material(ps: CPUParticles2D, part: Dictionary) -> void:
	ps.gravity = Vector2(0, _grav)
	ps.damping_min = _damp_lo
	ps.damping_max = _damp_hi
	# A one-signed orbit band (spirals) beats the symmetric ±sway wander when set:
	# every piece swirls the same way, so the shower reads as one turning vortex.
	if _orbit_hi != 0.0:
		ps.orbit_velocity_min = _orbit_lo
		ps.orbit_velocity_max = _orbit_hi
	else:
		ps.orbit_velocity_min = -_sway
		ps.orbit_velocity_max = _sway
	ps.angular_velocity_min = -_spin
	ps.angular_velocity_max = _spin
	ps.scale_amount_min = _scale_lo
	ps.scale_amount_max = _scale_hi
	ps.lifetime_randomness = _liferand()
	if _tumble:
		ps.split_scale = true
		ps.scale_curve_x = _flat_curve()
		# Bats beat their wings (never collapsing to a line); paper flips fully.
		ps.scale_curve_y = _flap_curve() if _shape == "bat" else _flip_curve()
		# A feather ROCKS about its spine as it falls, never quite going edge-on.
		# The default flip collapses the long axis instead, which folds the
		# feather in half every quarter-turn, and a full flip about the spine
		# left half the shower as slivers at any moment.
		if String(part.get("shape", _shape)) == "feather":
			ps.scale_curve_x = _flap_curve()
			ps.scale_curve_y = _flat_curve()
	if _align:
		# Laser beams fly point-first: aligned to their velocity, never spinning.
		ps.particle_flag_align_y = true
		ps.angle_min = 0.0
		ps.angle_max = 0.0
		ps.angular_velocity_min = 0.0
		ps.angular_velocity_max = 0.0
	ps.texture = _texture_for(String(part.get("shape", _shape)))
	# The paper square is baked at 2× its old resolution for smooth edges —
	# halve this emitter's scale so pieces stay their designed on-screen size.
	if String(part.get("shape", _shape)) == "square":
		ps.scale_amount_min *= 0.5
		ps.scale_amount_max *= 0.5
	# Optional per-part size. A mix is a cast, and a cast is not all one size: an
	# arcade token is bigger than the pixel block beside it and a glint struck off
	# a glass edge is smaller than the splinter it came from. Without this the only
	# lever was the shared _scale band, so balancing one part mis-sized the rest —
	# and the half-scale square above quietly made every square-led mix lopsided.
	var part_scale := float(part.get("scale", 1.0))
	if part_scale != 1.0:
		ps.scale_amount_min *= part_scale
		ps.scale_amount_max *= part_scale
	ps.color_initial_ramp = _ramp(part.get("colors", _colors))
	if _cool != null:
		ps.color_ramp = _cool
	elif _shimmer:
		ps.color_ramp = _shimmer_ramp()
	else:
		ps.color_ramp = _opaque()

## How much each piece's lifetime may vary. Fading materials can vary a lot; tumbling
## ones need some jitter to desync the flips; plain opaque pieces keep it small so
## none die visibly early on-screen.
func _liferand() -> float:
	if _cool != null:
		return 0.3
	if _shimmer:
		return 0.35   # desync the glint pulses so the field sparkles out of phase
	return 0.25 if _tumble else 0.1

# --- Emitters ---------------------------------------------------------------------
## A party-popper burst from a lower corner: a fast cone fired up-and-inward, then
## air drag takes over and the pieces flutter down at their material's pace.
func _cannon(pos: Vector2, dir: Vector2, amount: int, delay: float) -> void:
	var parts := _parts()
	var per := maxi(int(round(float(amount) / float(parts.size()))), 1)
	for part in parts:
		var ps := CPUParticles2D.new()
		ps.position = pos
		ps.one_shot = true
		ps.explosiveness = 0.9
		ps.amount = per
		ps.lifetime = _life
		ps.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINT
		ps.direction = dir.normalized()
		ps.spread = 38.0
		ps.initial_velocity_min = 540.0 * _launch
		ps.initial_velocity_max = 1010.0 * _launch
		ps.angle_min = -180.0
		ps.angle_max = 180.0
		_apply_material(ps, part)
		add_child(ps)
		if delay > 0.0:
			ps.emitting = false
			_delayed_start(ps, delay)
		else:
			ps.emitting = true

func _delayed_start(ps: CPUParticles2D, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	if is_instance_valid(ps):
		ps.emitting = true

## Phantom Realm's celebration: a LIVING flock, not particles. A dozen-odd
## real bats erupt from the lower screen and fly off the top and sides — each
## one FACES its flight line, beats its wings with a fast flap, staggers its
## takeoff, and wobbles slightly in flight. Few and realistic beats many and
## papery.
##
## On the BOMB it is the same colony blown off its roost: the detonation beat
## opens it, every bat starts at the blast point instead of the lower screen,
## and they scatter radially in every direction at speed rather than lifting off
## toward the top. (Before this the bomb never reached here at all — see _spawn.)
func _bat_flock(w: float, h: float) -> void:
	_ttl = 6.0
	var blown := _bomb_strength >= 0.0
	var centre := Vector2(w * 0.5, h * 0.46)
	if blown:
		_detonation(centre, w, h)
	# A big flock — more bats, sized to the bat texture's 48×30 (~1.6:1) aspect so
	# the wings render full, not stretched thin.
	var n := clampi(int(float(_amount) / 15.0), 16, 30)
	if blown:
		n = clampi(int(lerpf(34.0, 56.0, _bomb_strength)), 34, 56)
	for i in n:
		var bat := TextureRect.new()
		bat.texture = _bat()
		bat.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bat.stretch_mode = TextureRect.STRETCH_SCALE
		bat.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bw := randf_range(52.0, 100.0)
		bat.size = Vector2(bw, bw * 0.62)
		bat.pivot_offset = bat.size * 0.5
		var shade := randf()
		bat.modulate = Color(0.16 + 0.14 * shade, 0.11 + 0.10 * shade,
			0.26 + 0.20 * shade, 0.0)
		# Erupt from the lower-middle of the screen; scatter to the top + sides.
		var start := Vector2(w * randf_range(0.30, 0.70), h * randf_range(0.70, 0.95))
		var target := Vector2(w * randf_range(-0.25, 1.25), -h * randf_range(0.10, 0.30))
		if blown:
			var ang := randf() * TAU
			start = centre + Vector2(cos(ang), sin(ang)) * randf_range(6.0, 70.0)
			target = centre + Vector2(cos(ang), sin(ang)) \
				* (maxf(w, h) * randf_range(0.95, 1.55))
		bat.position = start - bat.size * 0.5
		# Face the flight line: the baked bat's head points up.
		bat.rotation = (target - start).angle() + PI * 0.5
		add_child(bat)
		# Takeoff is staggered; the flight itself accelerates away. A blast has no
		# stagger worth the name and no patience — they are all gone at once.
		var dur: float = randf_range(1.3, 2.1) if blown else randf_range(2.0, 3.4)
		var fly := bat.create_tween()
		fly.tween_interval(float(i) * (0.012 if blown else 0.07))
		fly.tween_property(bat, "modulate:a", 0.95, 0.12)
		fly.parallel().tween_property(bat, "position", target - bat.size * 0.5, dur) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		fly.tween_callback(bat.queue_free)
		# The wing-beat: a fast pump along the body axis.
		var flap := bat.create_tween().set_loops()
		flap.tween_property(bat, "scale:y", 0.64, randf_range(0.10, 0.15))
		flap.tween_property(bat, "scale:y", 1.0, randf_range(0.10, 0.15))
		# A slight in-flight waver so the line never reads dead straight.
		var waver := bat.create_tween().set_loops()
		waver.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		waver.tween_property(bat, "rotation", bat.rotation + deg_to_rad(7.0), randf_range(0.3, 0.5))
		waver.tween_property(bat, "rotation", bat.rotation - deg_to_rad(7.0), randf_range(0.3, 0.5))

## Shadow Fog / Ink Wash: the celebration IS the fog surfacing — an even
## full-screen field of thin wisps, never two thick banks clumping out of the
## corners.
##
## `power` is 1.0 for a tap and up to 2.0 for a full-strength bomb, and it does
## NOT multiply the wisp count. That is the whole design of this function. The
## mist recipes draw their wisps at 6.5-11.5x scale — around thirteen times the
## area of every other recipe's pieces — and they were measured as the only two
## detonations in the catalogue running at ~24 fps, with the same draw calls and
## the same script time as the rest: the cost is OVERDRAW and nothing else (see
## the ceiling in `bomb`). So a bigger fog is a WIDER and DEEPER one, never a
## denser one. The wisps spread across the whole frame plus a margin, so fog is
## already crossing the edges when it arrives; and the screen actually FILLS
## from one base veil and three huge banks rolling over it — four quads however
## hard the player presses, which does more for the read than another hundred
## wisps and costs a fraction as much.
##
## Routing a fog bomb here instead of into `_blast` also makes it cheaper than
## it was: the shared blast spent the full mist ceiling of ~200 wisps throwing
## them out of a 26px sphere at the centre, which is why a detonation used to
## read as one grey ball in the middle of a black screen rather than as weather.
func _fog_field(w: float, h: float, power: float = 1.0) -> void:
	var over: float = clampf(power - 1.0, 0.0, 1.0)      # 0 tap .. 1 full bomb
	_ttl = 0.06 + _life * (1.2 + 0.55 * over)
	var pale: Color = _colors[0]
	var deep: Color = _colors[1] if _colors.size() > 1 else pale
	# --- The wisps, over the WHOLE frame and a margin beyond it.
	var ps := CPUParticles2D.new()
	ps.position = Vector2(w * 0.5, h * 0.52)
	ps.one_shot = true
	ps.explosiveness = 0.18   # wisps keep surfacing over time, all over
	ps.amount = clampi(_amount, 1, int(lerpf(92.0, 124.0, over)))
	ps.lifetime = _life * (1.0 + 0.25 * over)
	ps.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	ps.emission_rect_extents = Vector2(w * (0.62 + 0.06 * over), h * (0.60 + 0.06 * over))
	ps.direction = Vector2(1, -0.05)
	ps.spread = 18.0
	ps.initial_velocity_min = 18.0 + 14.0 * over
	ps.initial_velocity_max = 55.0 + 35.0 * over
	_apply_material(ps, {"shape": _shape, "colors": _colors})
	ps.gravity = Vector2(0, -14.0)
	add_child(ps)
	ps.emitting = true
	if _fog_bank_flag:
		_fog_veil(w, h, over, pale, deep)
	# Shadow Fog only: a handful of faint glints drifting up INSIDE the fog —
	# the "you won" signal a pure haze was missing. (Ink Wash shares the fog
	# path but stays pure ink: no glints there.)
	if _fog_glints:
		var gl := CPUParticles2D.new()
		gl.position = Vector2(w * 0.5, h * 0.5)
		gl.one_shot = true
		gl.explosiveness = 0.2
		gl.amount = clampi(int(float(_amount) / 10.0), 8, 16) + int(10.0 * over)
		gl.lifetime = _life * 0.9
		gl.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		gl.emission_rect_extents = Vector2(w * 0.5, h * 0.5)
		gl.direction = Vector2(0, -1)
		gl.spread = 30.0
		gl.gravity = Vector2(0, -20.0)
		gl.initial_velocity_min = 12.0
		gl.initial_velocity_max = 40.0
		gl.scale_amount_min = 0.9
		gl.scale_amount_max = 1.8
		gl.lifetime_randomness = 0.4
		gl.texture = _texture_for("sparkle")
		gl.color_initial_ramp = _ramp([Color(0.86, 0.92, 1.0), Color(0.66, 0.74, 0.92), Color(1, 1, 1)])
		gl.color_ramp = _glint_ramp()
		add_child(gl)
		gl.emitting = true

## The part that makes the screen FOG rather than "some wisps drifting past":
## a base veil over the whole frame, three vast banks rolling across it, and a
## thicker layer along the ground, because fog lies heaviest low down. Every
## one of these is a single quad on its own clock — the entire effect is seven
## draws, and none of it scales with `_amount`.
func _fog_veil(w: float, h: float, over: float, pale: Color, deep: Color) -> void:
	var mist := _texture_for("mist")
	# The base: the air itself going grey. Comes up fast, sits, drains slowly.
	var veil := ColorRect.new()
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil.size = Vector2(w, h)
	veil.color = Color(deep.r, deep.g, deep.b, 0.0)
	add_child(veil)
	var peak: float = 0.09 + 0.13 * over
	var vt := veil.create_tween()
	vt.set_trans(Tween.TRANS_SINE)
	vt.tween_property(veil, "color:a", peak, 0.45 + 0.35 * over)
	vt.tween_interval(_life * (0.25 + 0.18 * over))
	vt.tween_property(veil, "color:a", 0.0, _life * 0.70)
	# Nine banks crossing it, each entering from a different edge so the fog
	# ARRIVES rather than appears. Most of the density lives here rather than in
	# the base veil, for two reasons. A base strong enough to fill the screen on
	# its own just greys it out uniformly, which reads as a filter over the game
	# and not as weather in front of it. And a bank has to be SMALLER than the
	# frame to be seen as a bank at all: stretched past a screen width the mist
	# texture is a smooth gradient with no edge anywhere in it, so five huge ones
	# produced exactly the flat grey the base was already giving.
	# [x0 (in screen widths), y centre, travel direction, width]
	for e_v in [[-0.42, 0.10, 1.0, 0.80], [1.34, 0.24, -1.0, 0.95],
			[-0.50, 0.36, 1.0, 0.70], [1.28, 0.50, -1.0, 0.88],
			[-0.38, 0.62, 1.0, 0.76], [1.36, 0.72, -1.0, 0.66],
			[-0.46, 0.84, 1.0, 0.92], [1.30, 0.92, -1.0, 0.78],
			[-0.34, 0.98, 1.0, 0.86]]:
		var e: Array = e_v
		var bank := TextureRect.new()
		bank.texture = mist
		bank.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bank.stretch_mode = TextureRect.STRETCH_SCALE
		bank.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bw: float = w * float(e[3]) * (1.0 + 0.30 * over) * randf_range(0.88, 1.14)
		bank.size = Vector2(bw, bw * 0.72)
		var y0: float = h * float(e[1]) - bank.size.y * 0.5
		var x0: float = w * float(e[0])
		bank.position = Vector2(x0, y0)
		var bp: float = (0.17 + 0.21 * over) * randf_range(0.78, 1.22)
		bank.modulate = Color(pale.r, pale.g, pale.b, 0.0)
		add_child(bank)
		var run: float = float(e[2]) * w * (1.7 + 0.5 * over) * randf_range(0.85, 1.15)
		var bt := bank.create_tween()
		bt.set_parallel(true)
		bt.tween_property(bank, "position:x", x0 + run, _life * 1.15) \
			.set_trans(Tween.TRANS_LINEAR)
		bt.tween_property(bank, "modulate:a", bp, 0.7 + 0.5 * over) \
			.set_trans(Tween.TRANS_SINE)
		bt.chain().tween_interval(_life * 0.30)
		bt.chain().tween_property(bank, "modulate:a", 0.0, _life * 0.60) \
			.set_trans(Tween.TRANS_SINE)
	# ...and it lies THICKEST along the ground. Fog has a floor; without this
	# the effect reads as smoke hanging in mid-air.
	for i in 4:
		var low := TextureRect.new()
		low.texture = mist
		low.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		low.stretch_mode = TextureRect.STRETCH_SCALE
		low.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var lw: float = w * randf_range(0.75, 1.25)
		low.size = Vector2(lw, h * randf_range(0.16, 0.30))
		var lx: float = w * (-0.25 + 0.42 * float(i)) + randf_range(-0.08, 0.08) * w
		var ly: float = h * randf_range(0.80, 1.02) - low.size.y * 0.5
		low.position = Vector2(lx, ly + h * 0.10)
		low.modulate = Color(pale.r, pale.g, pale.b, 0.0)
		add_child(low)
		var lp: float = (0.20 + 0.24 * over) * randf_range(0.85, 1.15)
		var lt := low.create_tween()
		lt.set_parallel(true)
		# It ROLLS in: up out of the ground and sideways at the same time.
		lt.tween_property(low, "position:y", ly, 1.2 + 0.8 * over).set_trans(Tween.TRANS_SINE)
		lt.tween_property(low, "position:x", lx + (1.0 if i % 2 == 0 else -1.0) * w * 0.35,
			_life * 1.2).set_trans(Tween.TRANS_LINEAR)
		lt.tween_property(low, "modulate:a", lp, 0.6 + 0.4 * over).set_trans(Tween.TRANS_SINE)
		lt.chain().tween_interval(_life * (0.30 + 0.15 * over))
		lt.chain().tween_property(low, "modulate:a", 0.0, _life * 0.65) \
			.set_trans(Tween.TRANS_SINE)

## Skywriter's celebration: the sky ANSWERS. Soft wind-waves — translucent
## sine-bands in the theme's sky whites and blues — fade in across the whole
## background, roll sideways like currents combed through high cloud, and melt
## away. No confetti pieces at all, by design; `intensity` (the bomb passes
## >1.0) adds more, taller waves instead of more debris.
func _sky_waves(w: float, h: float, intensity: float = 1.0) -> void:
	_ttl = 3.8
	var n := clampi(int(round(5.0 * intensity)), 4, 10)
	for i in n:
		var wave := _SkyWave.new()
		wave.mouse_filter = Control.MOUSE_FILTER_IGNORE
		wave.size = Vector2(w, h)
		wave.y0 = h * (0.10 + 0.80 * (float(i) + randf() * 0.6) / float(n))
		wave.amp = randf_range(10.0, 26.0) * minf(intensity, 1.6)
		wave.wavelen = w / randf_range(1.6, 3.0)
		wave.speed = randf_range(1.2, 2.4)
		wave.thickness = randf_range(2.5, 5.0)
		wave.col = _colors[i % _colors.size()]
		wave.delay = float(i) * 0.10
		wave.dur = randf_range(2.2, 3.0)
		add_child(wave)

## Thunderstorm's opening beat: a double lightning flash — a hard white blink,
## a breath of dark, then a dimmer echo — before the sparks rain. Pure overlay:
## it never blocks input and frees itself when the echo dies.
func _lightning() -> void:
	var flash := ColorRect.new()
	flash.color = Color(1, 1, 1, 0.0)
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash)
	var t := flash.create_tween()
	t.tween_property(flash, "color:a", 0.34, 0.05)
	t.tween_property(flash, "color:a", 0.0, 0.09)
	t.tween_interval(0.07)
	t.tween_property(flash, "color:a", 0.20, 0.04)
	t.tween_property(flash, "color:a", 0.0, 0.30)
	t.tween_callback(flash.queue_free)

## Anime's opening beat: the manga IMPACT FRAME — one hard white pop and a ring
## of radial concentration lines rushing in from the frame edges, gone in half a
## second, with the centre left CLEAR so the pieces own it. Pure overlay, like
## the lightning: it never blocks input and frees itself when it fades. The
## lines are INK, not light — on Anime's pale sky a white ray would vanish (the
## Daybreak lesson) — pulled a little toward the theme accent.
func _speed_burst(w: float, h: float, strength: float = 1.0) -> void:
	var flash := ColorRect.new()
	flash.color = Color(1, 1, 1, 0.0)
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash)
	var t := flash.create_tween()
	t.tween_property(flash, "color:a", 0.30, 0.04)
	t.tween_property(flash, "color:a", 0.0, 0.20)
	t.tween_callback(flash.queue_free)
	var pal := _pal()
	var accent: Color = pal["accent"]
	var lines := _SpeedLines.new()
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines.size = Vector2(w, h)
	lines.strength = clampf(strength, 1.0, 2.0)
	lines.tint = Color(0.16, 0.13, 0.2).lerp(accent, 0.35)
	lines.add_to_group("anime_impact_frame")
	add_child(lines)

## Vaporwave's stage laser show: three projectors (bottom corners + centre
## stage) each fire five sequential tight-fan bursts at stepped angles, so the
## beams SWEEP across the dark like a rig running a programme. Each burst is a
## single colour; the whole show cycles the theme's neon set.
func _laser_show(w: float, h: float) -> void:
	_ttl = 0.06 + _life * 1.4
	var beams_per := maxi(int(float(_amount) / 16.0), 4)
	# [origin, base angle from straight-up (deg; + leans right)]
	var projectors := [
		[Vector2(w * 0.04, h * 0.98), 42.0],
		[Vector2(w * 0.96, h * 0.98), -42.0],
		[Vector2(w * 0.5, h * 1.02), 0.0],
	]
	var ci := 0
	for p in projectors:
		var origin: Vector2 = p[0]
		var base_deg: float = p[1]
		for k in 5:
			var ang := deg_to_rad(base_deg + (float(k) - 2.0) * 14.0)
			var ps := CPUParticles2D.new()
			ps.position = origin
			ps.one_shot = true
			ps.explosiveness = 1.0
			ps.amount = beams_per
			ps.lifetime = _life
			ps.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINT
			ps.direction = Vector2(sin(ang), -cos(ang))
			ps.spread = 3.0
			ps.initial_velocity_min = 840.0 * _launch
			ps.initial_velocity_max = 1300.0 * _launch
			_apply_material(ps, {"shape": "streak", "colors": [_colors[ci % _colors.size()]]})
			ci += 1
			add_child(ps)
			ps.emitting = false
			_delayed_start(ps, 0.05 + float(k) * 0.11)
	if _top_shower:
		_ttl = maxf(_ttl, _life * 1.7)
		_top_rain(w)

## The detonation's own colour: the recipe's dominant piece colour, falling back
## to the theme accent for the recipes whose pieces carry their own bake and emit
## WHITE (gold, ruby, sakura, the bee …). A white flash under a white ring fired
## on all fifty-odd themes was the bomb's plainest tell that nothing about it was
## themed — the pieces were the theme and the explosion was stock.
func _bomb_tint() -> Color:
	for part in _parts():
		var cols: Array = part.get("colors", _colors)
		for entry in cols:
			var col: Color = entry
			if col.s > 0.18 and col.v > 0.25:
				return col
	var pal := _pal()
	var accent: Color = pal.get("accent", Color(1, 1, 1))
	return accent

## The opening beat every detonation shares: a screen flash and one expanding
## shockwave ring, both in the recipe's own colour.
##
## On a LIGHT theme (Arctic, Daybreak, Paper) a white-on-white flash and a white
## ring are simply not there, which is how those three came to have the quietest
## bombs in the game while spending exactly as much frame time as the loudest —
## so the light themes take a saturated tint at a touch more alpha instead of a
## white wash.
func _detonation(centre: Vector2, w: float, h: float, with_ring: bool = true) -> void:
	var tint := _bomb_tint()
	var pal := _pal()
	var light := bool(pal.get("is_light", false))
	var flash := ColorRect.new()
	var fc := Color(1, 1, 1).lerp(tint, 0.85 if light else 0.42)
	fc.a = 0.55 if light else 0.5
	flash.color = fc
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash)
	var fl := flash.create_tween()
	fl.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	fl.tween_property(flash, "color:a", 0.0, 0.4)
	fl.tween_callback(flash.queue_free)
	if not with_ring:
		return
	var ring := TextureRect.new()
	ring.texture = _shock_ring()
	ring.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ring.stretch_mode = TextureRect.STRETCH_SCALE
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var start := 120.0
	ring.size = Vector2(start, start)
	ring.position = centre - ring.size * 0.5
	var rc := Color(1, 1, 1).lerp(tint, 0.9 if light else 0.55)
	rc.a = 0.92 if light else 0.85
	ring.modulate = rc
	add_child(ring)
	var grow := maxf(w, h) * 1.7
	var rt := ring.create_tween().set_parallel(true)
	rt.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	rt.tween_property(ring, "size", Vector2(grow, grow), 0.8)
	rt.tween_property(ring, "position", centre - Vector2(grow, grow) * 0.5, 0.8)
	rt.tween_property(ring, "modulate:a", 0.0, 0.8)
	rt.set_parallel(false)
	rt.tween_callback(ring.queue_free)

## The long-press bomb: DESTRUCTIVE, slow, dramatic. A themed flash and an
## expanding shockwave ring sell the detonation; the confetti itself explodes
## violently outward, then heavy air-braking stalls the pieces mid-flight so
## they HANG in a suspended cloud before raining down at less than half their
## material's usual gravity — a slow-motion explosion filling the whole screen.
func _blast(w: float, h: float) -> void:
	var centre := Vector2(w * 0.5, h * 0.44)
	_ttl = 0.06 + _life * 2.1
	_detonation(centre, w, h)
	# The cloud: violent launch, hard stall, floaty fall.
	var boost := 1.0 + 0.6 * _bomb_strength
	# Buoyant recipes are thrown SOFTER: the point of their blast is the climb
	# that follows it, and a full-speed scatter puts half the cloud off the edges
	# before the lift can take hold.
	var throw: float = 0.55 if _rise else 1.0
	var parts := _parts()
	var per := maxi(int(round(float(_amount) / float(parts.size()))), 1)
	for part in parts:
		var ps := CPUParticles2D.new()
		ps.position = centre
		ps.one_shot = true
		ps.explosiveness = 1.0
		ps.amount = per
		ps.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
		ps.emission_sphere_radius = 26.0
		ps.direction = Vector2(0, -1)
		# A full sphere for anything that falls. Buoyant recipes get a FOUNTAIN
		# instead: thrown straight down, a rising piece spends its whole life
		# crossing the bottom of the screen and leaves before the lift can turn it
		# round, so the blast opens as a wide upward bloom and the climb carries it
		# from there.
		ps.spread = 118.0 if _rise else 180.0
		ps.initial_velocity_min = 880.0 * _launch * boost * throw
		ps.initial_velocity_max = 1560.0 * _launch * boost * throw
		ps.angle_min = -180.0
		ps.angle_max = 180.0
		_apply_material(ps, part)
		# Post-material overrides — the slow-motion drama: pieces brake HARD
		# after the initial violence (they stall and hang mid-air), then drift
		# down at a fraction of their usual weight, living long enough to coat
		# the whole screen on the way.
		if _rise:
			# ...except for the recipes that DO NOT FALL. Plasma, plankton, bubbles,
			# lanterns and hearts all rise on a tap, and the shared blast rained
			# every one of them back down the screen — on Antigrav, whose whole
			# premise is that nothing falls, the detonation was the single moment
			# that broke the theme. Same violence, same stall; then buoyancy takes
			# the cloud and sweeps it up and off the top. Drag stays well UNDER the
			# lift, or the pieces stop dead mid-screen instead of climbing.
			ps.lifetime = _life * 1.9
			ps.damping_min = 120.0
			ps.damping_max = 200.0
			ps.gravity = Vector2(0, -260.0 - 180.0 * _bomb_strength)
			# Risers stay upright: no paper flip, barely any spin.
			ps.split_scale = false
			ps.angular_velocity_min = -30.0
			ps.angular_velocity_max = 30.0
		else:
			ps.lifetime = _life * 1.7
			ps.damping_min = 130.0
			ps.damping_max = 240.0
			ps.gravity = Vector2(0, _grav * 0.42)
		add_child(ps)
		ps.emitting = true

## A crisp-edged shockwave ring (transparent → bright rim → transparent).
static var _shock_tex: GradientTexture2D

func _shock_ring() -> GradientTexture2D:
	if _shock_tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.62, 0.8, 1.0])
		g.colors = PackedColorArray([
			Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.0),
			Color(1, 1, 1, 0.9), Color(1, 1, 1, 0.0)])
		_shock_tex = GradientTexture2D.new()
		_shock_tex.gradient = g
		_shock_tex.fill = GradientTexture2D.FILL_RADIAL
		_shock_tex.fill_from = Vector2(0.5, 0.5)
		_shock_tex.fill_to = Vector2(0.5, 1.0)
		_shock_tex.width = 160
		_shock_tex.height = 160
	return _shock_tex

## A full-width SHOWER raining down from just above the top edge all the way off the
## bottom, emitted over time so it reads as rain.
func _top_rain(w: float) -> void:
	var parts := _parts()
	var per := maxi(int(round(_amount * 1.3 / float(parts.size()))), 1)
	for part in parts:
		var ps := CPUParticles2D.new()
		ps.position = Vector2(w * 0.5, -40.0)
		ps.one_shot = true
		ps.explosiveness = 0.3
		ps.amount = per
		ps.lifetime = _life
		ps.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		ps.emission_rect_extents = Vector2(w * 0.5, 6.0)
		ps.direction = Vector2(0, 1)
		ps.spread = 12.0
		# Soft materials keep the gentle rain; fast ones (lasers) rain harder too.
		ps.initial_velocity_min = 150.0 * maxf(_launch, 1.0)
		ps.initial_velocity_max = 320.0 * maxf(_launch, 1.0)
		ps.angle_min = -180.0
		ps.angle_max = 180.0
		_apply_material(ps, part)
		# No finished→free: a finished one-shot emitter costs nothing, the node's
		# ttl reaps it, and replay() needs the full cast still present to relight.
		add_child(ps)
		ps.emitting = true

## Peacock's shower: feathers let go above the top edge over several seconds,
## in ones and twos, each falling quill-down with its plume held up like a
## parachute and rocking about its spine on the way. The corner cannons every
## paper recipe uses were the wrong gesture for a feather: they THREW it, and a
## feather fired across a screen is fletching on an arrow. The loose barbs in
## the mix fall with them as fine filaments.
func _feather_drift(w: float, h: float) -> void:
	var parts := _parts()
	# Long enough to clear the canvas at drift speed, or a piece pops mid-frame
	# (the ramp is opaque to the end, on purpose, like every falling recipe).
	var life: float = clampf(h / 260.0, 8.0, 11.0)
	_ttl = maxf(_ttl, life * 1.6)
	for part in parts:
		var is_feather: bool = String(part.get("shape", _shape)) == "feather"
		var ps := CPUParticles2D.new()
		ps.position = Vector2(w * 0.5, -140.0)
		ps.one_shot = true
		ps.explosiveness = 0.3          # arrive over ~6 s, never all at once
		ps.amount = maxi(int(round(float(_amount) / float(parts.size()))), 1)
		ps.lifetime = life
		ps.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		ps.emission_rect_extents = Vector2(w * 0.5, 20.0)
		ps.direction = Vector2(0.12, 1.0)
		ps.spread = 16.0
		ps.initial_velocity_min = 90.0
		ps.initial_velocity_max = 170.0
		ps.angle_min = -180.0
		ps.angle_max = 180.0
		_apply_material(ps, part)
		# Post-material: a net ~70 px/s^2 carries a piece the height of the
		# canvas in about seven seconds, so nothing plummets and nothing hangs.
		ps.gravity = Vector2(0, 150.0)
		ps.damping_min = 60.0
		ps.damping_max = 90.0
		if is_feather:
			# Quill down, eye up, a lazy turn either way: the plume is the light
			# end and it rides on top, the way a dropped feather really falls.
			ps.angle_min = -40.0
			ps.angle_max = 40.0
			ps.angular_velocity_min = -8.0
			ps.angular_velocity_max = 8.0
		add_child(ps)
		ps.emitting = true

## Peacock's bomb: the DISPLAY. The train fans up out of the bottom of the
## screen in rays, every feather pointing outward along its own ray, climbs,
## stalls at full spread and hangs there, then sinks slowly, rocking. No
## shockwave and no pieces: a peacock opening its train is not an explosion.
func _train_fan(w: float, h: float) -> void:
	var life: float = 11.0
	_ttl = maxf(_ttl, life * 1.2)
	var rays: int = 19
	var root := Vector2(w * 0.5, h * 1.04)
	# The fan's outline is an ELLIPSE that fits the bottom of the screen: 62% of
	# the height up the middle, 47% of the width out to the sides, so a portrait
	# phone gets a full display with nothing leaving by the edges (at a plain
	# 70%-of-height reach the outer rays walked straight off both sides). A ray
	# stalls where gravity plus drag have eaten its launch speed, at
	# v^2 / (2 * (g + d)), so the speed is solved from the reach.
	var decel: float = 230.0 + 190.0
	var ry: float = h * 0.62 * (1.0 + 0.12 * _bomb_strength)
	var rx: float = w * 0.47
	# Three TIERS per ray: an outer row whose eyes trace the rim of the ellipse
	# and two inner rows, each a little smaller, so the display has depth. A
	# single band of feathers scattered at random radii read as loose feathers
	# in the air; the rows are what make it a train, the way the eyes on a real
	# display sit in staggered arcs. [radius lo, radius hi, scale, extra count]
	var tiers: Array = [[0.94, 1.02, 0.66, 1], [0.72, 0.80, 0.56, 0], [0.50, 0.58, 0.48, 0]]
	for i in rays:
		var f: float = float(i) / float(rays - 1)            # 0 .. 1 across the fan
		var deg: float = lerpf(-68.0, 68.0, f)
		var rad: float = deg_to_rad(deg)
		var reach: float = 1.0 / sqrt(pow(cos(rad) / ry, 2.0) + pow(sin(rad) / rx, 2.0))
		var v: float = sqrt(2.0 * decel * reach)
		for tier in tiers:
			var ps := CPUParticles2D.new()
			ps.position = root
			ps.one_shot = true
			ps.explosiveness = 1.0
			ps.amount = 1 + int(tier[3]) * int(_bomb_strength)
			ps.lifetime = life
			ps.emission_shape = CPUParticles2D.EMISSION_SHAPE_POINT
			ps.direction = Vector2(sin(rad), -cos(rad))
			ps.spread = 3.0
			# Speed sets the radius a feather stalls at (v^2 / 2*decel), so a
			# tier's band is a band of RADII, not of speeds.
			ps.initial_velocity_min = v * sqrt(float(tier[0]))
			ps.initial_velocity_max = v * sqrt(float(tier[1]))
			_fan_emitter(ps, deg, float(tier[2]))

## One ray of the train (see _train_fan): the feather points OUT along its ray
## and stays that way, eye leading, hangs, then sinks and fades.
func _fan_emitter(ps: CPUParticles2D, deg: float, scale: float) -> void:
	_apply_material(ps, {"shape": "feather", "colors": [Color(1, 1, 1)], "scale": scale})
	# Every feather points OUT along its ray and stays that way, eye
	# leading; spin would turn the display into a bin of feathers.
	ps.angle_min = deg
	ps.angle_max = deg
	ps.angular_velocity_min = -6.0
	ps.angular_velocity_max = 6.0
	# Drag just under gravity: the display HANGS at full spread for a few
	# seconds, sinking barely, before the ramp lets it go.
	ps.gravity = Vector2(0, 230.0)
	ps.damping_min = 190.0
	ps.damping_max = 190.0
	# No orbit. The petal material's sway is an orbit about the emitter's
	# origin, harmless under a shower, but this emitter's origin is the
	# root of the fan and its feathers are a screen-height away from it, so
	# the same 0.038 rev/s swept the whole display down the arc in seconds.
	ps.orbit_velocity_min = 0.0
	ps.orbit_velocity_max = 0.0
	ps.color_ramp = _fan_ramp()
	add_child(ps)
	ps.emitting = true

## The fan's feathers do not leave the screen in their lifetime (they hang, then
## sink), so unlike the falling recipes they fade at the very end rather than
## popping out of the frame at full opacity.
static var _fan_g: Gradient

func _fan_ramp() -> Gradient:
	if _fan_g == null:
		_fan_g = Gradient.new()
		_fan_g.offsets = PackedFloat32Array([0.0, 0.80, 1.0])
		_fan_g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	return _fan_g

## Rising pieces: a curtain climbing from the bottom straight up and off the top with
## a whisper of fade-IN as they emerge. Lanterns/hearts stay upright and calm; bubbles
## climb quicker with a wobble; motes (fireflies/plankton) drift slow and wander.
func _rise_up(w: float, h: float) -> void:
	var ps := CPUParticles2D.new()
	ps.position = Vector2(w * 0.5, h + 40.0)
	ps.one_shot = true
	ps.explosiveness = 0.6              # emit a touch sooner so the slower rise still clears
	ps.amount = maxi(int(_amount * 1.2), 1)
	ps.lifetime = 5.6
	ps.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	ps.emission_rect_extents = Vector2(w * 0.5, 8.0)
	ps.direction = Vector2(0, -1)
	ps.spread = 10.0
	ps.gravity = Vector2(0, -10.0)      # gentle upward buoyancy — keeps them climbing
	# Speed scales with the screen height so they always rise the WHOLE way to the top
	# and leave — a calm, unhurried float (larger divisor = slower).
	var base := (h + 80.0) / 4.0
	ps.damping_min = 0.0                # no drag, so they never slow to a stop mid-screen
	ps.damping_max = 2.0
	ps.angle_min = -8.0                 # stay upright
	ps.angle_max = 8.0
	ps.angular_velocity_min = -14.0
	ps.angular_velocity_max = 14.0
	ps.scale_amount_min = 1.8
	ps.scale_amount_max = 3.6
	match _shape:
		"lantern":
			# Big lanterns take their time: a slow climb over a long life, a gentle
			# air-sway, and barely any tilt — like a real release.
			ps.lifetime = 9.5
			base = (h + 80.0) / 7.5
			ps.scale_amount_min = 3.0
			ps.scale_amount_max = 5.4
			ps.orbit_velocity_min = -0.02
			ps.orbit_velocity_max = 0.02
			ps.angular_velocity_min = -6.0
			ps.angular_velocity_max = 6.0
		"bubble":
			# Bubbles: quicker, wobbling side to side as they climb — mostly
			# small, with the occasional big "hero" bubble for scale contrast.
			base = (h + 80.0) / 3.2
			ps.orbit_velocity_min = -0.05
			ps.orbit_velocity_max = 0.05
			ps.scale_amount_min = 0.9
			ps.scale_amount_max = 3.0
		"mote":
			# Glow motes (plankton / plasma / sun dust): slow, small, wandering.
			base = (h + 80.0) / 4.6
			ps.orbit_velocity_min = -0.07
			ps.orbit_velocity_max = 0.07
			ps.scale_amount_min = 0.9
			ps.scale_amount_max = 2.2
		"firefly":
			# Fireflies: the same unhurried climb, wandering a little harder and
			# drawn LARGER — the bake carries a whole insect, and at mote scale
			# its body and wings would disappear inside the halo.
			base = (h + 80.0) / 4.8
			ps.orbit_velocity_min = -0.09
			ps.orbit_velocity_max = 0.09
			ps.scale_amount_min = 1.2
			ps.scale_amount_max = 2.8
	ps.initial_velocity_min = base
	ps.initial_velocity_max = base * 1.5
	_ttl = maxf(_ttl, ps.lifetime * 1.4)
	var fade := Gradient.new()
	if _shimmer:
		# Blinking risers (fireflies / plankton / plasma / sun dust): fade in,
		# then pulse bright↔dim for the whole climb. Lifetime randomness staggers
		# the phases so the field blinks out of sync — some motes fading early
		# mid-air reads as a firefly going dark, which is exactly right.
		fade.offsets = PackedFloat32Array([0.0, 0.1, 0.28, 0.46, 0.64, 0.82, 1.0])
		var hi := Color(1, 1, 1, 1)
		var lo := Color(0.45, 0.45, 0.45, 0.8)
		fade.colors = PackedColorArray([Color(1, 1, 1, 0), hi, lo, hi, lo, hi, hi])
		ps.lifetime_randomness = 0.35
	else:
		fade.offsets = PackedFloat32Array([0.0, 0.12, 1.0])
		fade.colors = PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1)])
	ps.color_ramp = fade
	# Mixed rises (Kawaii's hearts + pastel stars …) clone the fully-tuned
	# emitter and swap only texture + colours, splitting the piece budget
	# across the parts. ONLY when the rise is the recipe itself (_rise): Coral
	# Depths reuses this path for its bubble layer while _mix holds the
	# SINKING starfish parts, and those must not leak into the rise.
	var parts: Array = [{"shape": _shape, "colors": _colors}]
	if _rise:
		parts = _parts()
	ps.amount = maxi(int(_amount * 1.2 / float(parts.size())), 1)
	# The per-part size multiplier (see _apply_material) has to be honoured here
	# too, off the SHARED band this emitter was tuned with — the rise path builds
	# one emitter and clones it, so anything read only inside _apply_material is
	# silently ignored by every rising recipe.
	var rise_lo := ps.scale_amount_min
	var rise_hi := ps.scale_amount_max
	ps.texture = _texture_for(String(parts[0].get("shape", _shape)))
	ps.color_initial_ramp = _ramp(parts[0].get("colors", _colors))
	for i in range(1, parts.size()):
		var extra := ps.duplicate() as CPUParticles2D
		extra.texture = _texture_for(String(parts[i].get("shape", _shape)))
		extra.color_initial_ramp = _ramp(parts[i].get("colors", _colors))
		var extra_scale := float(parts[i].get("scale", 1.0))
		extra.scale_amount_min = rise_lo * extra_scale
		extra.scale_amount_max = rise_hi * extra_scale
		add_child(extra)
		extra.emitting = true
	var first_scale := float(parts[0].get("scale", 1.0))
	ps.scale_amount_min = rise_lo * first_scale
	ps.scale_amount_max = rise_hi * first_scale
	# No finished→free on risers either — the node's ttl reaps them, and replay()
	# relights the same emitters instead of rebuilding (the rapid-tap fast path).
	add_child(ps)
	ps.emitting = true

# --- Colour ramp --------------------------------------------------------------
func _ramp(cols_in: Array) -> Gradient:
	var cols := cols_in
	if cols.is_empty():
		cols = _rainbow_cols()
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var pc := PackedColorArray()
	var n := cols.size()
	for i in n:
		offs.append(float(i) / float(maxi(n - 1, 1)))
		pc.append(cols[i])
	g.offsets = offs
	g.colors = pc
	return g

## The four colours the "2048" wordmark is painted in, in its own order — the
## board's tile ramp dressed through CandyFace exactly as Home and the sign-in
## screen dress it. Read from ExtrudedWord's list rather than a fourth copy of
## it, so a change to which tiles the word wears reaches the confetti too.
## `light` (0..1) raises each colour toward a BRIGHT version of itself, which is
## what makes the light balls light. It spends VALUE first and white last: the
## deep magenta the "8" wears sits at v=0.52 and lands near v=0.39 once the candy
## dot has shaded it, which is a dark blot in a sprinkle rain however pink it is
## in name. Lerping straight to white instead was the first cut and it turned the
## whole shower into dusty pastel - the hue survives, the candy does not.
func _wordmark_cols(light: float = 0.0) -> Array:
	# color_for, not color(): the wordmark's candy paint must come from THIS
	# shower's palette — under a Themes-card override, color() would dress the
	# sprinkles in the WEARER's ramp (the smoke's override pass caught exactly
	# that on Candy Pop).
	var pal := _pal()
	var cols: Array = []
	for tile in ExtrudedWord.WORDMARK_TILES:
		var c := CandyFace.color_for(pal, int(tile))
		if light > 0.0:
			c = Color.from_hsv(c.h,
				clampf(c.s * (1.0 - 0.30 * light), 0.0, 1.0),
				clampf(lerpf(c.v, 1.0, light), 0.0, 1.0))
			c = c.lerp(Color(1, 1, 1), 0.16 * light)
		cols.append(c)
	return cols

func _rainbow_cols() -> Array:
	# Punchier, higher-saturation party colours — jewel-bright, not pastel.
	return [
		Color("FF2E63"), Color("FF9A1F"), Color("FFE12E"),
		Color("22D879"), Color("2B8CFF"), Color("A63BFF")]

## Colours sampled from the theme's OWN tile ramp (low → high; see _pal), so the
## confetti falls in the same hues as the board's tiles. By default saturation/
## brightness are nudged up a touch so pieces stay punchy against any backdrop;
## `exact` skips the nudge and samples a wider slice of the ramp — the pieces
## are then literally the board's tile colours (Candy Pop's sprinkles).
func _tile_cols(exact: bool = false, vals: Array = []) -> Array:
	var pal := _pal()
	var cols: Array = []
	if vals.is_empty():
		vals = [2, 8, 32, 128, 512, 2048] if exact else [8, 32, 128, 512, 2048]
	for v in vals:
		var c: Color = ThemeManager.tile_style_for(pal, int(v))["bg"]
		if exact:
			cols.append(c)
		else:
			# A firmer vibrance lift so themed paper reads punchy against any backdrop.
			cols.append(Color.from_hsv(c.h, clampf(c.s + 0.18, 0.0, 1.0), clampf(maxf(c.v, 0.80), 0.0, 1.0)))
	return cols

# --- Shaped textures (baked shading in RGB; tinted by the particle) ------------
func _texture_for(shape: String) -> Texture2D:
	match shape:
		"coin":  return _coin()
		"gem":   return _gem()
		"petal": return _petal()
		"spark":   return _spark()
		"dot":     return _dot()
		"lantern": return _lantern()
		"ribbon":  return _ribbon()
		"heart":   return _heart()
		"sparkle": return _sparkle()
		"leaf":    return _leaf()
		"bubble":  return _bubble()
		"streak":  return _streak()
		"bar":     return _bar()
		"emeraldcut": return _emeraldcut()
		"brilliant": return _brilliant()
		"icicle":  return _icicle()
		"bat":     return _bat()
		"snowflake": return _snowflake()
		"maple":   return _maple()     # broad lobed maple — the leaf everyone pictures
		"shard":   return _shard()     # a splinter of broken glass
		"cinder":  return _cinder()    # a coal off the fire, cracked and glowing
		"ice":     return _ice()
		"starfish": return _starfish()
		"star5":   return _star5()   # bright five-point star with a glow halo
		"bolt":    return _bolt()
		"gear":    return _gear()
		"crane":   return _crane()      # a folded paper crane, wings spread
		"paper_dart": return _dart()    # the fold everyone can actually make
		"koi_a":   return _koi(0)       # full-colour koi - kohaku, ogon, showa
		"koi_b":   return _koi(1)
		"koi_c":   return _koi(2)
		"swirl":   return _swirl()
		"blossom_a": return _blossom(0)   # whole sakura flowers, full colour
		"blossom_b": return _blossom(1)
		"blossom_c": return _blossom(2)
		"ruby_stone":    return _ruby_stone()
		"ruby_marquise": return _ruby_marquise()
		"gold_coin":     return _metal_coin(true)
		"gold_bar":      return _metal_bar(true)
		"gold_nugget":   return _metal_nugget(true)
		"silver_coin":   return _metal_coin(false)
		"silver_bar":    return _metal_bar(false)
		"silver_nugget": return _metal_nugget(false)
		"firefly":      return _firefly()
		"bee":          return _bee()
		"honey_drop":   return _honey_drop()
		"wax_cell":     return _wax_cell()
		"butterfly_a":  return _butterfly(0)
		"butterfly_b":  return _butterfly(1)
		"butterfly_c":  return _butterfly(2)
		"feather":      return _feather()
		"diamond_stone": return _diamond_stone()
		"diamond_kite":     return _diamond_kite()
		"diamond_baguette": return _diamond_baguette()
		"rainstreak":       return _rainstreak()
		"comb_chunk":       return _comb_chunk()
		"honey_ribbon":     return _honey_ribbon()
		"anime_a": return _anime(0)  # empty pen-sketch heads — self-inked, tint stays white
		"anime_b": return _anime(1)
		"anime_c": return _anime(2)
		"bird_a":  return _bird(0, 1)   # dawn songbirds, full colour, wings level
		"bird_b":  return _bird(1, 1)
		"bird_a_up":   return _bird(0, 0)   # probe-only: the rest of the wingbeat
		"bird_a_down": return _bird(0, 2)
		"bird_perch_a": return _bird_perched(0)   # the same birds SITTING
		"bird_perch_b": return _bird_perched(1)
		"doodle_cat":     return _doodle_cat()   # ink doodles — tint stays white
		"doodle_onigiri": return _onigiri()
		"hopper":  return _hopper()  # a bismuth hopper, full colour - tint stays white
		"splat":   return _splat()   # a paint splat with its satellite drops (mask)
		"mote":    return _spark()   # motes reuse the soft glow dot
		"mist":    return _mist()    # fog wisps: huge, ultra-soft, irregular-edged
		_:         return _square()

func _shape_tex(w: int, h: int, fn: Callable) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var uv := Vector2(
				float(x) / float(w - 1) * 2.0 - 1.0,
				float(y) / float(h - 1) * 2.0 - 1.0)
			var rgba: Color = fn.call(uv)
			img.set_pixelv(Vector2i(x, y), rgba)
	return ImageTexture.create_from_image(img)

func _square() -> ImageTexture:
	# Paper, upgraded: a rounded-corner square baked at 2× the old hard 6×6,
	# with an anti-aliased edge and a faint top-lit face so a tumbling piece
	# shows a shaded surface instead of a flat stair-stepped quad. Emitters
	# halve the scale back down (see _apply_material) so pieces keep their size.
	if _sq_tex == null:
		_sq_tex = _shape_tex(12, 12, _fn_paper)
	return _sq_tex

func _fn_paper(uv: Vector2) -> Color:
	var q := uv.abs() - Vector2(0.6, 0.6)
	var d := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() \
		+ minf(maxf(q.x, q.y), 0.0) - 0.3
	var a := clampf(0.5 - d / 0.18, 0.0, 1.0)
	# A firmer top-lit gradient plus a tight glossy catch up-left, so a tumbling
	# piece flashes a highlight as it turns — coated paper, not matte card.
	var shade := lerpf(1.0, 0.78, clampf((uv.x + uv.y) * 0.25 + 0.5, 0.0, 1.0))
	var sheen: float = pow(clampf(1.0 - (uv - Vector2(-0.35, -0.35)).length() * 1.6, 0.0, 1.0), 3.0)
	shade = clampf(shade + sheen * 0.18, 0.0, 1.0)
	return Color(shade, shade, shade, a)

func _coin() -> ImageTexture:
	if _coin_tex == null:
		_coin_tex = _shape_tex(16, 16, _fn_coin)
	return _coin_tex

func _gem() -> ImageTexture:
	if _gem_tex == null:
		_gem_tex = _shape_tex(14, 16, _fn_gem)
	return _gem_tex

func _petal() -> ImageTexture:
	if _petal_tex == null:
		_petal_tex = _shape_tex(12, 18, _fn_petal)
	return _petal_tex

func _spark() -> ImageTexture:
	if _spark_tex == null:
		_spark_tex = _shape_tex(12, 12, _fn_spark)
	return _spark_tex

func _dot() -> ImageTexture:
	if _dot_tex == null:
		_dot_tex = _shape_tex(12, 12, _fn_dot)
	return _dot_tex

func _lantern() -> ImageTexture:
	if _lantern_tex == null:
		_lantern_tex = _shape_tex(20, 28, _fn_lantern)
	return _lantern_tex

func _ribbon() -> ImageTexture:
	if _ribbon_tex == null:
		_ribbon_tex = _shape_tex(6, 30, _fn_ribbon)
	return _ribbon_tex

func _heart() -> ImageTexture:
	if _heart_tex == null:
		_heart_tex = _shape_tex(18, 16, _fn_heart)
	return _heart_tex

func _sparkle() -> ImageTexture:
	if _sparkle_tex == null:
		_sparkle_tex = _shape_tex(18, 18, _fn_sparkle)
	return _sparkle_tex

func _leaf() -> ImageTexture:
	if _leaf_tex == null:
		_leaf_tex = _shape_tex(12, 20, _fn_leaf)
	return _leaf_tex

func _bubble() -> ImageTexture:
	if _bubble_tex == null:
		_bubble_tex = _shape_tex(16, 16, _fn_bubble)
	return _bubble_tex

func _streak() -> ImageTexture:
	if _streak_tex == null:
		_streak_tex = _shape_tex(8, 26, _fn_streak)
	return _streak_tex

func _bar() -> ImageTexture:
	if _bar_tex == null:
		_bar_tex = _shape_tex(28, 16, _fn_bar)
	return _bar_tex

func _emeraldcut() -> ImageTexture:
	if _emeraldcut_tex == null:
		_emeraldcut_tex = _shape_tex(18, 22, _fn_emeraldcut)
	return _emeraldcut_tex

func _ice() -> ImageTexture:
	if _ice_tex == null:
		_ice_tex = _shape_tex(44, 44, _fn_ice)
	return _ice_tex

func _starfish() -> ImageTexture:
	if _starfish_tex == null:
		_starfish_tex = _shape_tex(40, 40, _fn_starfish)
	return _starfish_tex

func _mist() -> ImageTexture:
	if _mist_tex == null:
		_mist_tex = _shape_tex(40, 40, _fn_mist)
	return _mist_tex

func _brilliant() -> ImageTexture:
	if _brilliant_tex == null:
		_brilliant_tex = _shape_tex(22, 22, _fn_brilliant)
	return _brilliant_tex

func _icicle() -> ImageTexture:
	if _icicle_tex == null:
		_icicle_tex = _shape_tex(10, 30, _fn_icicle)
	return _icicle_tex

func _bat() -> ImageTexture:
	if _bat_tex == null:
		_bat_tex = _shape_tex(48, 30, _fn_bat)
	return _bat_tex

func _snowflake() -> ImageTexture:
	if _snowflake_tex == null:
		_snowflake_tex = _shape_tex(36, 36, _fn_snowflake)
	return _snowflake_tex

func _maple() -> ImageTexture:
	if _maple_tex == null:
		_maple_tex = _shape_tex(36, 30, _fn_maple)
	return _maple_tex

func _shard() -> ImageTexture:
	if _shard_tex == null:
		_shard_tex = _shape_tex(22, 38, _fn_shard)
	return _shard_tex

func _cinder() -> ImageTexture:
	if _cinder_tex == null:
		_cinder_tex = _shape_tex(24, 22, _fn_cinder)
	return _cinder_tex

## The SAME six-armed snow crystal (arms + branchlets + bright core) that falls
## through the Glacier Dawn / Arctic backdrops — the confetti matches the sky.
func _fn_snowflake(uv: Vector2) -> Color:
	var r := uv.length()
	if r > 1.0:
		return Color(0, 0, 0, 0)
	var ang := atan2(uv.y, uv.x)
	var sector := absf(fposmod(ang, PI / 3.0) - PI / 6.0)
	var w := 0.16 * (1.05 - r)
	var arm := (1.0 - smoothstep(w * 0.5, maxf(w, 0.001), sector)) \
		* (1.0 - smoothstep(0.85, 1.0, r))
	var br := absf(sector - 0.30 * (1.0 - r))
	var branch := (1.0 - smoothstep(0.02, 0.05, br)) \
		* smoothstep(0.30, 0.55, r) * (1.0 - smoothstep(0.75, 0.95, r))
	var core := pow(clampf(1.0 - r * 2.2, 0.0, 1.0), 1.6)
	var a := clampf(maxf(maxf(arm, branch * 0.8), core), 0.0, 1.0)
	if a <= 0.03:
		return Color(0, 0, 0, 0)
	return Color(1, 1, 1, a)

## A broad five-lobed MAPLE leaf on a short stem, with deep sinuses between the
## lobes, a serrated margin and veins fanning out from the base. Autumn's shower
## was the slim pointed `leaf` (a bamboo blade) repeated at five colours, and the
## silhouette is most of what says "autumn" before any colour arrives.
func _fn_maple(uv: Vector2) -> Color:
	# The blade sits a little above centre; the stem hangs off the bottom.
	var p := uv - Vector2(0.0, 0.14)
	var r := p.length()
	# Angle measured from straight UP, so the lobe pattern is symmetric about the
	# midrib and the base (t = +-PI) lands in a sinus rather than on a lobe.
	var t := atan2(p.x, -p.y)
	# Five lobes: |cos(2.5t)| peaks at t = 0, +-1.26, +-2.51 across the full turn,
	# leaving a sinus at t = +-PI where the stem joins. The exponent is what makes
	# a maple rather than a five-point star (sharp) or a circle (flat): lobes that
	# stay broad most of their length and then come to a point.
	var lobe: float = pow(absf(cos(t * 2.5)), 1.15)
	# The lower pair of lobes is smaller than the crown, and the base narrows to
	# almost nothing where the stalk joins — without the taper the five lobes come
	# out equal and the leaf reads as a starfish.
	var taper := 0.70 + 0.30 * cos(t * 0.5)
	var edge := (0.44 + 0.50 * lobe) * taper
	edge -= 0.040 * pow(absf(sin(t * 12.5)), 3.0)     # a serrated margin
	var a := 1.0 - smoothstep(edge - 0.07, edge, r)
	# The stem: a short stalk below the blade, joined at the base sinus.
	var stem := (1.0 - smoothstep(0.045, 0.075, absf(uv.x))) \
		* smoothstep(0.30, 0.42, uv.y) * (1.0 - smoothstep(0.86, 1.0, uv.y))
	a = clampf(maxf(a, stem), 0.0, 1.0)
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	# Veins run out along each lobe axis and read a shade darker than the blade,
	# which curls toward the light from the upper left.
	var vein: float = pow(absf(cos(t * 2.5)), 40.0) * smoothstep(0.10, 0.50, r)
	var b := clampf(0.66 + (-p.x) * 0.13 + (-p.y) * 0.10 - vein * 0.20, 0.0, 1.0)
	return Color(b, b, b, a)

## A SPLINTER of broken glass: an irregular four-sided sliver with one long
## fracture running its length, a bright cleaved edge and a dark face — Sanctum's
## window coming apart. A cut `gem` says jewellery; this says shattered.
func _fn_shard(uv: Vector2) -> Color:
	# Two triangles sharing the long fracture line make one asymmetric sliver.
	var top := Vector2(-0.06, -1.0)
	var mid_r := Vector2(0.68, 0.10)
	var bot := Vector2(0.18, 1.0)
	var mid_l := Vector2(-0.62, -0.06)
	var a := clampf(maxf(_tri(uv, top, mid_r, bot), _tri(uv, top, bot, mid_l)), 0.0, 1.0)
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	# The fracture: a hot line down the break, with the two faces catching the
	# light differently either side of it.
	var seam := clampf(1.0 - absf(uv.x - uv.y * 0.12) * 5.0, 0.0, 1.0)
	var face := 0.42 if uv.x > uv.y * 0.12 else 0.66
	var glint: float = pow(clampf(1.0 - (uv - Vector2(-0.22, -0.44)).length() * 1.7, 0.0, 1.0), 4.0)
	var b := clampf(face + seam * 0.30 + glint * 0.55 + (-uv.y) * 0.08, 0.0, 1.0)
	return Color(b, b, b, a)

## A CINDER: a lump of coal knocked off the fire, its edge irregular, its core
## still white-hot and cracked. Sparks alone gave Ember Serpent and Nova Forge a
## shower of identical pinpricks; a cinder is the piece with mass in the middle
## of them, and it is what makes the sparks read as coming OFF something.
func _fn_cinder(uv: Vector2) -> Color:
	var r := uv.length()
	var ang := atan2(uv.y, uv.x)
	var edge := 0.76 + 0.12 * sin(ang * 3.0 + 0.7) + 0.07 * sin(ang * 5.0 + 2.1)
	var a := 1.0 - smoothstep(edge - 0.09, edge, r)
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	# A dark crust over a molten interior. The heat sits OFF-CENTRE, with a faint
	# mottle over it — a symmetric pattern of cracks turned the lump into a
	# starburst printed on a rock, which is the one thing an ember never looks
	# like at twenty pixels across.
	var core: float = pow(clampf(1.0 - (uv - Vector2(-0.14, -0.10)).length() * 1.05, 0.0, 1.0), 1.7)
	var mottle := 0.05 * sin(ang * 7.0 + r * 9.0)
	var b := clampf(0.26 + core * 0.74 + mottle, 0.0, 1.0)
	return Color(b, b, b, a)

func _fn_coin(uv: Vector2) -> Color:
	# A minted coin: raised outer rim, an embossed inner ring, a brushed face
	# gradient and a HARD top-left glint — dimensional enough to read as real
	# metal while it flip-tumbles.
	var r := uv.length()
	var a := 1.0 - smoothstep(0.86, 1.0, r)
	if a <= 0.0:
		return Color(0, 0, 0, 0)
	var rim := smoothstep(0.62, 0.88, r) * (1.0 - smoothstep(0.90, 1.0, r))
	var ring := (1.0 - smoothstep(0.03, 0.09, absf(r - 0.52))) * 0.30
	# Brushed-metal face: a stronger diagonal light sweep (deep lower-right → bright
	# upper-left) reads as polished metal; a broad specular plus a hot pinpoint glint
	# on top of it sell a real mirror reflection while the coin flip-tumbles.
	var face := 0.40 + (-uv.x - uv.y) * 0.20
	var spec: float = pow(clampf(1.0 - (uv - Vector2(-0.32, -0.32)).length(), 0.0, 1.0), 2.2)
	var glint: float = pow(clampf(1.0 - (uv - Vector2(-0.30, -0.30)).length() * 2.2, 0.0, 1.0), 6.0)
	var b := clampf(face + rim * 0.55 + ring + spec * 0.85 + glint * 0.60, 0.0, 1.0)
	return Color(b, b, b, a)

func _fn_gem(uv: Vector2) -> Color:
	var m := absf(uv.x) + absf(uv.y)
	var a := 1.0 - smoothstep(0.92, 1.05, m)
	if a <= 0.0:
		return Color(0, 0, 0, 0)
	# Deeper facet contrast (near-white top-left face, dark lower-right) plus a hot
	# specular glint reads as a glossy cut stone rather than a flat tinted diamond.
	var b := 0.5
	if uv.y < 0.0:
		b = 1.0 if uv.x < 0.0 else 0.80
	else:
		b = 0.60 if uv.x < 0.0 else 0.34
	b += pow(clampf(1.0 - m, 0.0, 1.0), 3.0) * 0.32
	var glint: float = pow(clampf(1.0 - (uv - Vector2(-0.28, -0.34)).length() * 2.0, 0.0, 1.0), 4.0)
	b += glint * 0.50
	b = clampf(b, 0.0, 1.0)
	return Color(b, b, b, a)

func _fn_petal(uv: Vector2) -> Color:
	var e := (uv.x * uv.x) / 0.30 + (uv.y * uv.y) / 0.95
	var a := 1.0 - smoothstep(0.9, 1.06, e)
	if a <= 0.0:
		return Color(0, 0, 0, 0)
	var b := clampf(0.6 + (-uv.x) * 0.18, 0.0, 1.0)
	return Color(b, b, b, a)

func _fn_spark(uv: Vector2) -> Color:
	var r := uv.length()
	var a := 1.0 - smoothstep(0.2, 1.0, r)
	if a <= 0.0:
		return Color(0, 0, 0, 0)
	return Color(1, 1, 1, a)

func _fn_dot(uv: Vector2) -> Color:
	# A solid round candy sprinkle with a soft edge + a gentle top-left highlight.
	var r := uv.length()
	var a := 1.0 - smoothstep(0.86, 1.0, r)
	if a <= 0.0:
		return Color(0, 0, 0, 0)
	# A glazed sprinkle: a lightly shaded body plus a broad sheen and a tight glossy
	# glint up-left — candy-coated, catching the light rather than flat.
	var shade := 0.74 + (-uv.x - uv.y) * 0.06
	var spec: float = pow(clampf(1.0 - (uv - Vector2(-0.32, -0.32)).length(), 0.0, 1.0), 2.0)
	var glint: float = pow(clampf(1.0 - (uv - Vector2(-0.30, -0.30)).length() * 2.4, 0.0, 1.0), 6.0)
	var b := clampf(shade + spec * 0.34 + glint * 0.50, 0.0, 1.0)
	return Color(b, b, b, a)

func _fn_lantern(uv: Vector2) -> Color:
	# A little paper lantern — rounded glowing body, a cap on top, a short tassel below.
	var a := 0.0
	var bx := absf(uv.x) / 0.68
	var by := absf(uv.y + 0.04) / 0.80
	var body := pow(bx, 4.0) + pow(by, 4.0)
	if body < 1.05:
		a = 1.0 - smoothstep(0.82, 1.02, body)
	if absf(uv.x) < 0.28 and uv.y < -0.78 and uv.y > -0.99:
		a = maxf(a, 1.0)                              # top cap
	if absf(uv.x) < 0.06 and uv.y > 0.80 and uv.y < 0.99:
		a = maxf(a, 0.9)                             # tassel
	if a <= 0.0:
		return Color(0, 0, 0, 0)
	var glow := clampf(1.0 - (uv * Vector2(1.35, 0.95)).length(), 0.0, 1.0)
	var b := clampf(0.55 + glow * 0.5, 0.0, 1.0)
	return Color(b, b, b, a)

func _fn_ribbon(uv: Vector2) -> Color:
	# A long thin streamer — narrow, full height, soft ends, a bright lengthwise sheen.
	var ax := absf(uv.x)
	var a := (1.0 - smoothstep(0.55, 1.0, ax)) * (1.0 - smoothstep(0.9, 1.0, absf(uv.y)))
	if a <= 0.0:
		return Color(0, 0, 0, 0)
	var b := clampf(0.7 + (1.0 - ax) * 0.3, 0.0, 1.0)
	return Color(b, b, b, a)

func _fn_heart(uv: Vector2) -> Color:
	# A rounded heart: two lobes up top, a point at the bottom (implicit curve).
	var x := uv.x
	var y := -uv.y * 1.05 + 0.35
	var h := x * x + y * y - 0.32
	var d := h * h * h - x * x * y * y * y
	var a := 1.0 - smoothstep(-0.02, 0.05, d)
	if a <= 0.0:
		return Color(0, 0, 0, 0)
	var b := clampf(0.72 + (-uv.y) * 0.2, 0.0, 1.0)
	return Color(b, b, b, a)

func _fn_sparkle(uv: Vector2) -> Color:
	# A 4-point kirakira star, BRIGHT: a hot core, wider main rays, faint
	# diagonal cross-rays and a soft glow halo — a star that reads lit from
	# within, not printed on paper.
	var ax := absf(uv.x)
	var ay := absf(uv.y)
	var r := uv.length()
	var core := pow(clampf(1.0 - r * 1.35, 0.0, 1.0), 1.6)
	var hray := clampf(1.0 - ay / (0.17 * (1.0 - ax) + 0.02), 0.0, 1.0)
	var vray := clampf(1.0 - ax / (0.17 * (1.0 - ay) + 0.02), 0.0, 1.0)
	var du := absf(uv.x + uv.y) * 0.7071   # along / across the 45° diagonals
	var dv := absf(uv.x - uv.y) * 0.7071
	var d1 := clampf(1.0 - dv / (0.08 * (1.0 - minf(du, 1.0)) + 0.02), 0.0, 1.0)
	var d2 := clampf(1.0 - du / (0.08 * (1.0 - minf(dv, 1.0)) + 0.02), 0.0, 1.0)
	var halo := pow(clampf(1.0 - r, 0.0, 1.0), 3.0) * 0.35
	var a := clampf(core + hray * 0.9 + vray * 0.9 + (d1 + d2) * 0.45 + halo, 0.0, 1.0)
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	return Color(1, 1, 1, a)

func _fn_leaf(uv: Vector2) -> Color:
	# A pointed leaf: widest at the middle, tapering to both tips, with a darker
	# mid vein and an asymmetric top-light so it reads as a curved surface.
	var w := 0.62 * (1.0 - uv.y * uv.y)
	if w <= 0.02:
		return Color(0, 0, 0, 0)
	var a := 1.0 - smoothstep(w * 0.8, w, absf(uv.x))
	if a <= 0.0:
		return Color(0, 0, 0, 0)
	var b := clampf(0.62 + (-uv.x) * 0.14 + (-uv.y) * 0.08, 0.0, 1.0)
	if absf(uv.x) < 0.05:
		b *= 0.8   # mid vein
	return Color(b, b, b, a)

func _fn_bubble(uv: Vector2) -> Color:
	# A bubble: a bright thin rim, a faint fill, and a crisp up-left highlight —
	# mostly transparent inside, like the real thing.
	var r := uv.length()
	if r > 1.0:
		return Color(0, 0, 0, 0)
	var rim := smoothstep(0.62, 0.82, r) * (1.0 - smoothstep(0.88, 1.0, r))
	var spec: float = pow(clampf(1.0 - (uv - Vector2(-0.34, -0.34)).length(), 0.0, 1.0), 3.0)
	var fill := 0.10 * (1.0 - smoothstep(0.0, 0.85, r))
	var a := clampf(rim * 0.9 + spec + fill, 0.0, 1.0)
	if a <= 0.01:
		return Color(0, 0, 0, 0)
	return Color(1, 1, 1, a)

func _fn_bar(uv: Vector2) -> Color:
	# A cast ingot seen slightly from above: a trapezoid (narrow bright top face,
	# wider base), shaded sloping ends and a small glint.
	var half_w := 0.60 + 0.26 * clampf((uv.y + 0.7) / 1.4, 0.0, 1.0)
	var a := (1.0 - smoothstep(half_w - 0.07, half_w, absf(uv.x))) \
		* (1.0 - smoothstep(0.62, 0.72, absf(uv.y)))
	if a <= 0.0:
		return Color(0, 0, 0, 0)
	var b := 0.66
	if uv.y < -0.25:
		b = 1.0                                      # blazing polished top face
	elif absf(uv.x) > half_w - 0.24:
		b = 0.40                                     # deeper shaded sloped ends
	b += pow(clampf(1.0 - (uv - Vector2(-0.3, -0.4)).length(), 0.0, 1.0), 2.2) * 0.34
	var glint: float = pow(clampf(1.0 - (uv - Vector2(-0.35, -0.55)).length() * 2.4, 0.0, 1.0), 7.0)
	b += glint * 0.50                                # hot mirror glint on the top face
	b = clampf(b, 0.0, 1.0)
	return Color(b, b, b, a)

func _fn_emeraldcut(uv: Vector2) -> Color:
	# An emerald-cut stone with HARD stepped facets: a bright table, sharply
	# darker step rings, a lit rim, a shaded lower-right pavilion and a hot
	# specular glint — baked depth that reads as a 3D cut stone mid-tumble.
	var ax := absf(uv.x) / 0.80
	var ay := absf(uv.y) / 0.95
	var oct := maxf(maxf(ax, ay), (ax + ay) / 1.45)
	var a := 1.0 - smoothstep(0.94, 1.03, oct)
	if a <= 0.0:
		return Color(0, 0, 0, 0)
	var b := 0.5
	if oct < 0.42:
		b = 1.0                                      # blazing table
	elif oct < 0.66:
		b = 0.56
	elif oct < 0.86:
		b = 0.32                                     # deeper step ring for more snap
	else:
		b = 0.84                                     # lit rim
	if uv.x + uv.y < -0.6:
		b = clampf(b + 0.16, 0.0, 1.0)               # light catches the upper-left
	elif uv.x + uv.y > 0.7:
		b = clampf(b - 0.14, 0.0, 1.0)               # pavilion falls into shadow
	var spec: float = pow(clampf(1.0 - (uv - Vector2(-0.34, -0.40)).length() * 1.4, 0.0, 1.0), 2.2)
	var glint: float = pow(clampf(1.0 - (uv - Vector2(-0.32, -0.38)).length() * 2.6, 0.0, 1.0), 6.0)
	b = clampf(b + spec * 0.72 + glint * 0.45, 0.0, 1.0)
	return Color(b, b, b, a)

func _fn_ice(uv: Vector2) -> Color:
	# A six-armed ice crystal: slender arms every 60° tapering to points around a
	# bright core — a real snowflake silhouette, not a faceted gem.
	var r := uv.length()
	if r > 1.0:
		return Color(0, 0, 0, 0)
	var ang := atan2(uv.y, uv.x)
	var sector := absf(fposmod(ang, PI / 3.0) - PI / 6.0)
	var w := 0.22 * (1.1 - r)
	var arm := (1.0 - smoothstep(w * 0.45, maxf(w, 0.001), sector)) \
		* (1.0 - smoothstep(0.82, 1.0, r))
	var core := pow(clampf(1.0 - r * 1.7, 0.0, 1.0), 1.4)
	var a := clampf(maxf(arm, core), 0.0, 1.0)
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	var b := clampf(0.78 + core * 0.22, 0.0, 1.0)
	return Color(b, b, b, a)

func _fn_starfish(uv: Vector2) -> Color:
	# A five-armed starfish: rounded lobes, gently domed shading, a dimple at the
	# centre — reads as the real reef animal once tinted coral-orange.
	var r := uv.length()
	if r > 1.0:
		return Color(0, 0, 0, 0)
	var ang := atan2(uv.y, uv.x)
	var lobe := 0.50 + 0.48 * pow(absf(cos(ang * 2.5)), 0.55)
	var a := 1.0 - smoothstep(lobe - 0.10, lobe, r)
	if a <= 0.0:
		return Color(0, 0, 0, 0)
	var b := clampf(0.58 + (1.0 - r / maxf(lobe, 0.01)) * 0.3, 0.0, 1.0)
	b -= pow(clampf(1.0 - r * 2.6, 0.0, 1.0), 2.0) * 0.15   # centre dimple
	b = clampf(b, 0.0, 1.0)
	return Color(b, b, b, a)

func _fn_mist(uv: Vector2) -> Color:
	# An ultra-soft fog puff: a wide plateau melting away on a slow falloff, with a
	# gently irregular edge so overlapping wisps blend into one rolling bank.
	var r := uv.length()
	var ang := atan2(uv.y, uv.x)
	var edge := 1.0 + 0.10 * sin(ang * 3.0) + 0.06 * sin(ang * 5.0 + 1.7)
	var d := r / edge
	var a := pow(clampf(1.0 - d, 0.0, 1.0), 2.4)
	if a <= 0.01:
		return Color(0, 0, 0, 0)
	return Color(1, 1, 1, a)

func _fn_streak(uv: Vector2) -> Color:
	# A short neon streak: a bright core line inside a soft glow halo, fading at
	# both ends.
	var ax := absf(uv.x)
	var ay := absf(uv.y)
	var core := 1.0 - smoothstep(0.0, 0.28, ax)
	var halo := (1.0 - smoothstep(0.2, 1.0, ax)) * 0.4
	var endf := 1.0 - smoothstep(0.72, 1.0, ay)
	var a := clampf((core + halo) * endf, 0.0, 1.0)
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	return Color(1, 1, 1, a)

func _fn_brilliant(uv: Vector2) -> Color:
	# A round BRILLIANT cut: eight radial crown facets alternating bright/dark
	# around a lighter octagonal table, a thin bright girdle ring, and a hard
	# specular glint up-left. Baked dimensional shading + the flip-tumble in
	# flight is what makes the tinted stone read as a 3D cut gem.
	var r := uv.length()
	var a := 1.0 - smoothstep(0.88, 1.0, r)
	if a <= 0.0:
		return Color(0, 0, 0, 0)
	var ang := atan2(uv.y, uv.x)
	var wedge := floorf(fposmod(ang + PI, TAU) / (TAU / 8.0))
	var facet := 0.40 + 0.20 * fposmod(wedge, 2.0) + 0.07 * fposmod(wedge, 3.0)
	facet += clampf((-uv.x - uv.y) * 0.20, -0.12, 0.20)   # lit from upper-left
	var table := 1.0 - smoothstep(0.28, 0.40, r)
	var girdle := smoothstep(0.70, 0.80, r) * (1.0 - smoothstep(0.84, 0.94, r))
	var spec: float = pow(clampf(1.0 - (uv - Vector2(-0.30, -0.34)).length() * 1.5, 0.0, 1.0), 2.0)
	var glint: float = pow(clampf(1.0 - (uv - Vector2(-0.28, -0.32)).length() * 2.6, 0.0, 1.0), 6.0)
	var b := clampf(facet + table * 0.38 + girdle * 0.30 + spec * 0.95 + glint * 0.45, 0.0, 1.0)
	return Color(b, b, b, a)

func _fn_icicle(uv: Vector2) -> Color:
	# A SPIKY ice sliver: a tall thin double-pointed splinter with a bright
	# crystalline spine and one shaded face — the same spiky shards that drive
	# through the Glacier Dawn backdrop, not a snow crystal.
	var m := absf(uv.x) * 2.8 + absf(uv.y)
	var a := 1.0 - smoothstep(0.88, 1.04, m)
	if a <= 0.0:
		return Color(0, 0, 0, 0)
	var spine := clampf(1.0 - absf(uv.x) * 3.4, 0.0, 1.0)
	var side := 0.16 if uv.x > 0.0 else 0.0   # cold facet split: right face darker
	var b := clampf(0.50 + spine * 0.45 - side + (-uv.y) * 0.08, 0.0, 1.0)
	return Color(b, b, b, a)

func _fn_bat(uv: Vector2) -> Color:
	return _bat_silhouette(uv)

## A bold BATMAN-style bat, wings spread: a chunky eared body flanked by two
## LARGE membrane wings whose leading edge sweeps up to a pointed tip and whose
## trailing edge is deeply scalloped (finger points). Wings stay fat across most
## of their span so the bat never reads thin. Shared by the confetti flock and
## the BoardFx ambient bats (same bake, so both look identical).
static func _bat_silhouette(uv: Vector2) -> Color:
	var x := absf(uv.x)
	var y := uv.y
	var a := 0.0
	# Body: a rounded central mass (also covers the head).
	var body := (1.0 - smoothstep(0.12, 0.20, x)) \
		* (1.0 - smoothstep(0.34, 0.55, absf(y - 0.06)))
	a = maxf(a, body)
	# Two pointed ears above the head.
	if y < -0.30 and y > -0.74:
		var ear := (1.0 - smoothstep(0.03, 0.085, absf(x - 0.095))) \
			* smoothstep(-0.74, -0.34, y)
		a = maxf(a, ear)
	# Wings: fat membranes sweeping up to pointed tips, scalloped underneath.
	if x > 0.11:
		var wx := clampf((x - 0.11) / 0.89, 0.0, 1.0)
		var tip := 1.0 - wx
		var center := -0.16 - 0.30 * wx                  # sweeps UP toward the tip
		var half := 0.46 * pow(clampf(tip, 0.0, 1.0), 0.55)   # stays fat, points at tip
		var scallop := 0.13 * tip * sin(wx * PI * 3.0)   # trailing finger points
		var top_edge := center - half
		var bot_edge := center + half + scallop
		if y > top_edge and y < bot_edge:
			var soft := smoothstep(top_edge - 0.05, top_edge + 0.03, y) \
				* (1.0 - smoothstep(bot_edge - 0.04, bot_edge + 0.04, y))
			a = maxf(a, soft * (1.0 - smoothstep(0.95, 1.0, wx)))
	a = clampf(a, 0.0, 1.0)
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	var b := clampf(0.55 + (-y) * 0.22, 0.30, 0.85)
	return Color(b, b, b, a)

# --- The 10/10 pass: bespoke shape bakes -------------------------------------

func _star5() -> ImageTexture:
	if _star5_tex == null:
		_star5_tex = _shape_tex(24, 24, _fn_star5)
	return _star5_tex

func _bolt() -> ImageTexture:
	if _bolt_tex == null:
		_bolt_tex = _shape_tex(12, 26, _fn_bolt)
	return _bolt_tex

func _gear() -> ImageTexture:
	if _gear_tex == null:
		_gear_tex = _shape_tex(26, 26, _fn_gear)
	return _gear_tex

func _crane() -> ImageTexture:
	# 76x48, up from 30x26. The old bake spent six thin triangles on a crane and
	# resolved it as a grey smudge - at that pixel count a neck is one pixel wide
	# and a fold has nowhere to land.
	if _crane_tex == null:
		_crane_tex = _shape_tex(76, 48, _fn_crane)
	return _crane_tex

func _dart() -> ImageTexture:
	if _dart_tex == null:
		_dart_tex = _shape_tex(40, 46, _fn_dart)
	return _dart_tex

## The koi, in three colourings so a school is not one fish printed fifteen
## times: 0 kohaku (white with crimson), 1 ogon (metallic gold), 2 showa (white,
## crimson AND sumi black).
func _koi(variant: int) -> ImageTexture:
	if variant == 0:
		if _koi_a_tex == null:
			_koi_a_tex = _shape_tex(44, 76, _fn_koi_a)
		return _koi_a_tex
	if variant == 1:
		if _koi_b_tex == null:
			_koi_b_tex = _shape_tex(44, 76, _fn_koi_b)
		return _koi_b_tex
	if _koi_c_tex == null:
		_koi_c_tex = _shape_tex(44, 76, _fn_koi_c)
	return _koi_c_tex

func _swirl() -> ImageTexture:
	if _swirl_tex == null:
		_swirl_tex = _shape_tex(20, 20, _fn_swirl)
	return _swirl_tex

func _anime(variant: int) -> ImageTexture:
	# 36x40 (up from 30x32): the redrawn faces carry an iris, catch-lights and a
	# lash line, and at the old resolution those were single scattered pixels.
	if variant == 0:
		if _anime_a_tex == null:
			_anime_a_tex = _shape_tex(36, 40, _fn_anime_a)
		return _anime_a_tex
	if variant == 1:
		if _anime_b_tex == null:
			_anime_b_tex = _shape_tex(36, 40, _fn_anime_b)
		return _anime_b_tex
	if _anime_c_tex == null:
		_anime_c_tex = _shape_tex(36, 40, _fn_anime_c)
	return _anime_c_tex

## Soft point-in-triangle mask (1 inside → 0 at the edge), winding-agnostic —
## the building block for the folded-facet shapes (crane wings, koi tail). Its
## coverage falls off with the triangle's AREA, so a long thin sliver never
## reaches full alpha: for necks, spikes and beaks use _taper instead. STATIC so
## the doodle painters below can be shared with BoardFx (see _anime_head).
static func _tri(p: Vector2, a: Vector2, b: Vector2, c: Vector2) -> float:
	var d1 := (p - a).cross(b - a)
	var d2 := (p - b).cross(c - b)
	var d3 := (p - c).cross(a - c)
	var m := minf(minf(d1, d2), d3)
	var m2 := minf(minf(-d1, -d2), -d3)
	return smoothstep(0.0, 0.05, maxf(m, m2))

## Perpendicular distance from `p` to segment a→b — the field the folded facets
## shade their creases off.
static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 <= 0.0:
		return (p - a).length()
	return (p - (a + ab * clampf((p - a).dot(ab) / l2, 0.0, 1.0))).length()

## _taper, plus the raw distance and the local half-width in z/w — what a rim
## light needs, since "how near the edge am I" is distance OVER width, and both
## are thrown away by the time coverage has been smoothstepped.
static func _taper4(p: Vector2, a: Vector2, b: Vector2, w0: float, w1: float) -> Vector4:
	var ab := b - a
	var l2 := ab.length_squared()
	var t := 0.0 if l2 <= 0.0 else clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	var d := (p - (a + ab * t)).length()
	var w := lerpf(w0, w1, t)
	return Vector4(1.0 - smoothstep(maxf(w - 0.018, 0.0), w + 0.010, d), t, d, w)

## A tapered spike: the segment a→b swept from half-width `w0` at a to `w1` at
## b. Returns (coverage, t along the segment) so callers can shade down its
## length. This is what thin folds are made of — see _tri's note above.
static func _taper(p: Vector2, a: Vector2, b: Vector2, w0: float, w1: float) -> Vector2:
	var ab := b - a
	var l2 := ab.length_squared()
	var t := 0.0 if l2 <= 0.0 else clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	var d := (p - (a + ab * t)).length()
	var w := lerpf(w0, w1, t)
	return Vector2(1.0 - smoothstep(maxf(w - 0.018, 0.0), w + 0.010, d), t)

func _fn_star5(uv: Vector2) -> Color:
	# A BRIGHT five-point star: sharp spikes around a white-hot core inside a
	# soft glow halo — a real twinkling star, not a paper cutout.
	var r := uv.length()
	if r > 1.0:
		return Color(0, 0, 0, 0)
	var ang := atan2(uv.y, uv.x) + PI * 0.5
	var rad := 0.32 + 0.68 * pow(absf(cos(ang * 2.5)), 2.6)
	var body := 1.0 - smoothstep(rad - 0.12, rad, r)
	var core := pow(clampf(1.0 - r * 1.9, 0.0, 1.0), 1.6)
	var halo := pow(clampf(1.0 - r, 0.0, 1.0), 3.2) * 0.5
	var a := clampf(body + halo, 0.0, 1.0)
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	var b := clampf(0.85 + core * 0.15 + halo * 0.3, 0.0, 1.0)
	return Color(b, b, b, a)

func _fn_bolt(uv: Vector2) -> Color:
	# A jagged lightning bolt: two slanted strokes offset at a mid jag,
	# tapering toward the tip, with a white-hot spine.
	var t := (uv.y + 1.0) * 0.5
	var xc := 0.30 - 0.85 * t
	if t >= 0.5:
		xc += 0.42
	var w := 0.34 * (1.0 - t) + 0.10
	var d := absf(uv.x - xc)
	var a := (1.0 - smoothstep(w * 0.75, w, d)) * (1.0 - smoothstep(0.94, 1.0, absf(uv.y)))
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	var b := clampf(0.8 + (1.0 - d / maxf(w, 0.001)) * 0.2, 0.0, 1.0)
	return Color(b, b, b, a)

func _fn_gear(uv: Vector2) -> Color:
	# A toothed gear: eight square-ish teeth around a ring, a hub hole in the
	# middle, lit from the upper-left like the other metal bakes.
	var r := uv.length()
	if r > 1.0:
		return Color(0, 0, 0, 0)
	var ang := atan2(uv.y, uv.x)
	var teeth := smoothstep(-0.35, 0.35, sin(ang * 8.0))
	var outer := 0.70 + 0.22 * teeth
	var a := (1.0 - smoothstep(outer - 0.07, outer, r)) * smoothstep(0.26, 0.36, r)
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	var face := 0.55 + (-uv.x - uv.y) * 0.16
	var rim := smoothstep(outer - 0.20, outer - 0.06, r) * 0.25
	var hub := (1.0 - smoothstep(0.36, 0.5, r)) * 0.18
	var glint: float = pow(clampf(1.0 - (uv - Vector2(-0.32, -0.32)).length() * 2.0, 0.0, 1.0), 5.0)
	var b := clampf(face + rim + hub + glint * 0.4, 0.0, 1.0)
	return Color(b, b, b, a)

## A folded paper crane, seen from the side with its wings spread in a V: the
## long neck thrown forward to a beaked head, the tail raked back the other way,
## the two wings rising between them and the body kite hanging below. That
## silhouette - three points up, one down - IS the crane; the bake this replaces
## tried to build it out of six thin triangles at 30x26 and resolved into a
## grey smudge.
##
## Two lessons are baked in. Paper is FLAT FACETS with a crease between them,
## never an airbrushed gradient, so each fold carries one tone and a hairline
## darkens the seam - that is the whole difference between folded paper and a
## bird. And the thin parts (neck, tail, beak) are swept SEGMENTS, not
## triangles: `_tri`'s coverage falls off with the triangle's AREA, so a sliver
## never reaches full alpha and comes out as a wisp.
func _fn_crane(uv: Vector2) -> Color:
	var q := Vector2(uv.x, uv.y * (48.0 / 76.0))   # a square in q is square in px
	var a := 0.0
	var b := 0.0
	# Each fold is BOUNDING-BOXED before its mask is evaluated. Every part
	# covers a small slice of the bake, and without these guards all seven were
	# solved for all 3648 pixels - which made this the most expensive bake in
	# the file by five times over (see _fx_bake budget note in the koi below).
	# The 0.06 margins clear _tri's anti-aliased edge.
	if q.x > -0.10 and q.x < 0.78 and q.y > -0.62 and q.y < 0.26:
		# The far wing, folded away from the light.
		var far := _tri(q, Vector2(-0.04, 0.12), Vector2(0.72, -0.56), Vector2(0.32, 0.20))
		if far > 0.01:
			var dfar := _seg_dist(q, Vector2(-0.04, 0.12), Vector2(0.72, -0.56))
			b = lerpf(0.50, 0.36, smoothstep(0.08, 0.11, dfar))
			a = far
	if q.x > -0.12 and q.y > -0.12 and q.y < 0.30:
		# The tail: a flat spike raked back.
		var tl := _taper(q, Vector2(0.02, 0.15), Vector2(0.90, 0.02), 0.105, 0.030)
		if tl.x > 0.01:
			var tone_t := 0.66 - 0.10 * tl.y
			b = tone_t if a <= 0.02 else lerpf(b, tone_t, tl.x)
			a = maxf(a, tl.x)
	if q.x < 0.12 and q.y > 0.00 and q.y < 0.40:
		# The neck thrown forward.
		var nk := _taper(q, Vector2(-0.02, 0.14), Vector2(-0.84, 0.25), 0.105, 0.034)
		if nk.x > 0.01:
			var tone_n := 0.88 - 0.06 * nk.y
			b = tone_n if a <= 0.02 else lerpf(b, tone_n, nk.x)
			a = maxf(a, nk.x)
	if q.x < -0.70 and q.y > 0.16 and q.y < 0.45:
		# The beak, folded off the neck's tip.
		var hd := _taper(q, Vector2(-0.80, 0.25), Vector2(-0.99, 0.36), 0.055, 0.016)
		if hd.x > 0.01:
			b = 1.0 if a <= 0.02 else lerpf(b, 1.0, hd.x)
			a = maxf(a, hd.x)
	if q.x > -0.32 and q.x < 0.30 and q.y > 0.03:
		# The body kite hanging under the wing join, in two facets.
		var bd := _tri(q, Vector2(-0.26, 0.09), Vector2(0.24, 0.09), Vector2(0.01, 0.62))
		if bd > 0.01:
			b = 0.72 if a <= 0.02 else lerpf(b, 0.72, bd)
			a = maxf(a, bd)
		var bd2 := _tri(q, Vector2(0.01, 0.62), Vector2(0.24, 0.09), Vector2(0.06, 0.20))
		if bd2 > 0.01:
			b = 0.56 if a <= 0.02 else lerpf(b, 0.56, bd2)
			a = maxf(a, bd2)
	if q.x > -0.78 and q.x < 0.08 and q.y > -0.64 and q.y < 0.26:
		# The near wing, bright, folded over everything.
		var wa := Vector2(0.02, 0.10)
		var wb := Vector2(-0.72, -0.58)
		var wing := _tri(q, wa, wb, Vector2(-0.34, 0.20))
		if wing > 0.01:
			var dl := _seg_dist(q, wa, wb)
			var tone := lerpf(1.00, 0.74, smoothstep(0.10, 0.13, dl))
			tone -= 0.24 * (1.0 - smoothstep(0.0, 0.026, absf(dl - 0.115)))
			b = tone if a <= 0.02 else lerpf(b, tone, wing)
			a = maxf(a, wing)
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	return Color(b, b, b, clampf(a, 0.0, 1.0))

## A paper dart, nose-up: one straight leading edge each side, the centre keel
## standing proud, the underside fold turned away from the light. The wing
## splits RADIALLY from the nose - a constant-width band along the leading edge
## reads as an outline stroke rather than a fold, which is what the first cut of
## this looked like.
func _fn_dart(uv: Vector2) -> Color:
	var ax := absf(uv.x)
	var q := Vector2(ax, uv.y * (46.0 / 40.0))
	var body := _tri(q, Vector2(0.0, -1.05), Vector2(0.96, 0.86), Vector2(0.0, 0.34))
	if body <= 0.01:
		return Color(0, 0, 0, 0)
	var u := clampf((q.y + 1.05) / 1.91, 0.0, 1.0)
	var f := clampf(ax / maxf(0.96 * u, 0.001), 0.0, 1.0)
	var b := lerpf(0.62, 0.98, smoothstep(0.50, 0.56, f))
	b -= 0.22 * (1.0 - smoothstep(0.0, 0.035, absf(f - 0.53)))
	b = lerpf(b, 1.0, 1.0 - smoothstep(0.026, 0.050, ax))   # the keel fold
	b *= 1.0 - 0.16 * smoothstep(-0.9, 0.9, uv.x)
	return Color(b, b, b, clampf(body, 0.0, 1.0))

func _fn_koi_a(uv: Vector2) -> Color:
	return _koi_body(uv, 0)

func _fn_koi_b(uv: Vector2) -> Color:
	return _koi_body(uv, 1)

func _fn_koi_c(uv: Vector2) -> Color:
	return _koi_body(uv, 2)

## A REAL koi from above, baked in FULL colour (the emitters tint white), nose
## UP so the school can rotate it onto a heading: a blunt head swelling to the
## shoulders and tapering to the peduncle, pectoral and pelvic fin pairs, a
## broad forked caudal fan, kohaku blotches and two black beads for eyes.
##
## Everything is measured about a BENT spine, which is the whole difference
## between a fish and a torpedo - the bake this replaces was a straight ellipse
## with two orange blobs and a triangle stuck on the back, and it read as a
## cigar. Two more traps are answered here. The fins carry the BODY's colour at
## their root and thin to clear at the trailing edge; painted a flat pale grey,
## the tail reads as a separate object stuck on behind. And the eyes are
## COMPOSITED into the paint rather than punched through it - a hard cut at this
## pixel count gives two black squares, not two beads.
func _koi_body(uv: Vector2, variant: int) -> Color:
	const NOSE := -0.92
	const PEDUNCLE := 0.42
	# Nothing lives outside this box, and it is over a third of the bake. A
	# per-pixel bake pays for its empty margin at full price - the guard is
	# worth more here than any of the maths below it.
	if absf(uv.x) > 0.62 or uv.y < -0.96 or uv.y > 0.90:
		return Color(0, 0, 0, 0)
	var white := Color(0.98, 0.96, 0.91)
	var orange := Color(0.95, 0.40, 0.09)
	var sumi := Color(0.09, 0.08, 0.11)
	var lx := uv.x - 0.085 * sin((uv.y - NOSE) * 1.9)

	var body := 0.0
	var hw := 0.0
	if uv.y >= NOSE and uv.y <= PEDUNCLE:
		var t := (uv.y - NOSE) / (PEDUNCLE - NOSE)
		hw = 0.35 * pow(clampf(t * 8.0, 0.0, 1.0), 0.42) \
			* (1.0 - smoothstep(0.30, 1.0, t) * 0.68)
		body = 1.0 - smoothstep(maxf(hw - 0.055, 0.0), hw + 0.022, absf(lx))
	# The caudal fan, rooted ON the peduncle. A deep centre split reads as
	# trousers, so the notch only bites the inner third.
	var tail := 0.0
	var ty := 0.0
	if uv.y > PEDUNCLE - 0.14:
		ty = clampf((uv.y - (PEDUNCLE - 0.14)) / 0.58, 0.0, 1.0)
		var xa := lx - 0.09 * sin(ty * 1.8)
		var spread := 0.105 + 0.30 * pow(ty, 0.85)
		var lobe := 1.0 - smoothstep(spread * 0.72, spread + 0.055, absf(xa))
		var f := clampf(absf(xa) / 0.36, 0.0, 1.0)
		tail = lobe * (1.0 - smoothstep(0.68 + 0.14 * f, 0.86 + 0.14 * f, ty))
	# Pectoral fins behind the gills; pelvics further aft.
	var pf := Vector2(absf(lx) - 0.26, uv.y + 0.30)
	var pr := Vector2(pf.x * 0.64 - pf.y * 0.77, pf.x * 0.77 + pf.y * 0.64)
	var pex := pr.x / 0.30
	var pey := pr.y / 0.095
	var pect := 1.0 - smoothstep(0.60, 1.05, pex * pex + pey * pey)
	var vf := Vector2(absf(lx) - 0.17, uv.y + 0.12)
	var vr := Vector2(vf.x * 0.77 - vf.y * 0.64, vf.x * 0.64 + vf.y * 0.77)
	var vex := vr.x / 0.19
	var vey := vr.y / 0.062
	var pelv := 1.0 - smoothstep(0.60, 1.05, vex * vex + vey * vey)
	var fins: float = maxf(pect * 0.88, pelv * 0.72)

	var a: float = clampf(maxf(body, maxf(tail, fins)), 0.0, 1.0)
	if a <= 0.03:
		return Color(0, 0, 0, 0)

	# Kohaku blotches down the back.
	var m := 0.0
	m = maxf(m, 1.0 - smoothstep(0.10, 0.32, Vector2(lx - 0.02, uv.y + 0.58).length()))
	m = maxf(m, 1.0 - smoothstep(0.12, 0.36, Vector2(lx + 0.14, uv.y - 0.02).length()))
	m = maxf(m, 1.0 - smoothstep(0.08, 0.28, Vector2(lx - 0.11, uv.y - 0.24).length()))
	m = clampf(m * 1.45, 0.0, 1.0)
	var col := white.lerp(orange, m)
	if variant == 1:
		col = Color(0.99, 0.74, 0.22).lerp(Color(1.0, 0.93, 0.62), m * 0.7)   # ogon
	elif variant == 2:
		var k := 0.0                                                          # showa
		k = maxf(k, 1.0 - smoothstep(0.09, 0.26, Vector2(lx - 0.16, uv.y + 0.24).length()))
		k = maxf(k, 1.0 - smoothstep(0.10, 0.28, Vector2(lx + 0.11, uv.y - 0.14).length()))
		col = col.lerp(sumi, clampf(k * 1.4, 0.0, 1.0) * 0.9)

	if body < 0.5:
		var root: float = (1.0 - smoothstep(0.0, 0.62, ty)) if tail > fins else 0.55
		var fc := Color(0.99, 0.97, 0.94).lerp(col, root * 0.80)
		return Color(fc.r, fc.g, fc.b, a * (0.52 + 0.44 * root))

	var eye: float = minf(Vector2(lx + 0.135, uv.y + 0.70).length(),
		Vector2(lx - 0.135, uv.y + 0.70).length())
	col = col.lerp(sumi, (1.0 - smoothstep(0.028, 0.055, eye)) * body)
	# A wet back: bright along the spine, rolling off to darker flanks.
	var shade := 0.78 + 0.22 * clampf(1.0 - absf(lx) / maxf(hw, 0.001) * 0.85, 0.0, 1.0)
	shade += (1.0 - smoothstep(0.0, 0.07, absf(lx))) * 0.08
	return Color(col.r * shade, col.g * shade, col.b * shade, a)

func _fn_swirl(uv: Vector2) -> Color:
	# A lollipop swirl: a glossy disc with a spiral groove winding to the rim,
	# plus the same up-left glint the candy sprinkles wear.
	var r := uv.length()
	var a := 1.0 - smoothstep(0.86, 1.0, r)
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	var ang := atan2(uv.y, uv.x)
	var s := sin(ang * 2.0 + r * 10.0)
	var b := 0.86 + 0.14 * s
	b += pow(clampf(1.0 - (uv - Vector2(-0.3, -0.3)).length(), 0.0, 1.0), 2.2) * 0.2
	b = clampf(b, 0.0, 1.0)
	return Color(b, b, b, a)

# --- Anime pen-sketch heads (self-coloured ink; emitters tint white) ----------
## EMPTY pen-sketch heads for the Anime theme, straight off the reference sheet:
## a solid ink HAIR mass whose spiked silhouette is the whole identity, an
## outlined face with NOTHING inside it, and thin strand gaps scratched through
## the ink like real pen strokes. No colour, no eyes, no mouth — two earlier
## passes (painted chibi portraits, then flat-colour doodles with dot faces)
## both read as stickers; the sheet these copy leaves every face blank, and
## blank is what reads as a sketch. Three heads: 0 wild spikes, 1 a shaggy mop
## dropped over where the eyes would be, 2 a spiked crop with side curtains.
## The painters are STATIC and shared with BoardFx._anime_doodles (the bat
## precedent), which draws these same sketches through the theme's own world.
func _fn_anime_a(uv: Vector2) -> Color:
	return _anime_head(uv, 0)

func _fn_anime_b(uv: Vector2) -> Color:
	return _anime_head(uv, 1)

func _fn_anime_c(uv: Vector2) -> Color:
	return _anime_head(uv, 2)

static func _anime_head(uv: Vector2, variant: int) -> Color:
	var ink := Color(0.16, 0.13, 0.2)
	# The empty face: an outline ring around a soft ellipse, and nothing inside.
	var fx := uv.x
	var fy := uv.y - 0.12
	var f := (fx * fx) / 0.42 + (fy * fy) / 0.4
	var ring := smoothstep(0.78, 0.92, f) * (1.0 - smoothstep(1.02, 1.16, f))
	# The hair: an ink mass on a bigger dome, its SILHOUETTE spiked differently
	# per head and its hairline carving the brow.
	var hy := uv.y + 0.08
	var hang := atan2(fx, -hy)
	var hf := (fx * fx) / 0.52 + (hy * hy) / 0.52
	var hairline := -0.12
	if variant == 0:
		# Wild spikes all around, bangs jagged across the brow.
		hf -= 0.55 * pow(absf(sin(hang * 5.0 + 0.3)), 4.0) * smoothstep(0.35, -0.10, hy)
		hairline = -0.02 - 0.30 * absf(sin(fx * 9.0))
	elif variant == 1:
		# A shaggy mop dropping over where the eyes would be.
		hf -= 0.25 * pow(absf(sin(hang * 7.0 + 1.1)), 2.0) * smoothstep(0.45, -0.05, hy)
		hairline = 0.12 - 0.30 * absf(sin(fx * 6.0 + 0.8))
	else:
		# A spiked crop, curtains falling past the cheeks below.
		hf -= 0.40 * pow(absf(sin(hang * 4.0 + 0.9)), 5.0) * smoothstep(0.30, -0.15, hy)
		hairline = -0.10 - 0.16 * absf(sin(fx * 5.0 + 1.2))
	var dome := 1.0 - smoothstep(0.9, 1.04, hf)
	var hair := dome * (1.0 - smoothstep(hairline - 0.04, hairline + 0.06, uv.y))
	if variant == 2:
		var curtain := (1.0 - smoothstep(0.95, 1.06, hf)) \
			* smoothstep(0.42, 0.56, absf(fx)) * (1.0 - smoothstep(0.35, 0.60, uv.y))
		hair = maxf(hair, curtain)
	# Pen texture: a few thin strand GAPS scratched through the ink mass, so the
	# hair reads as strokes rather than a stamp — sparse and shallow, because a
	# gap that cuts through turns the mass into a lattice.
	var gap := smoothstep(0.955, 0.995, absf(sin(hang * 13.0 + float(variant) * 1.7)))
	var a := maxf(hair * (1.0 - gap * 0.35), ring * 0.9)
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	return Color(ink.r, ink.g, ink.b, clampf(a, 0.0, 1.0))

## The chibi NEKO blob — the doodle every anime margin grows sooner or later: a
## round white cat face with triangle ears, dot eyes, a pink nose, whiskers and
## blush, all ink on paper.
func _doodle_cat() -> ImageTexture:
	if _doodle_cat_tex == null:
		_doodle_cat_tex = _shape_tex(30, 28, _fn_doodle_cat)
	return _doodle_cat_tex

static func _fn_doodle_cat(uv: Vector2) -> Color:
	var line := Color(0.16, 0.13, 0.2)
	var paper := Color(0.99, 0.97, 0.93)
	var ap := Vector2(absf(uv.x), uv.y)
	# The blob head, and one triangle ear per side riding its top edge.
	var blob := 1.0 - smoothstep(0.85, 1.05, (uv.x * uv.x) / 0.55 + (uv.y - 0.08) * (uv.y - 0.08) / 0.42)
	var ear := _tri(ap, Vector2(0.18, -0.42), Vector2(0.62, -0.18), Vector2(0.52, -0.88))
	var a := maxf(blob, ear)
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	var col := paper
	# Inner-ear pink, then the face marks: dot eyes, pink nose, whiskers, blush.
	var inner := _tri(ap, Vector2(0.30, -0.44), Vector2(0.52, -0.32), Vector2(0.46, -0.68))
	col = col.lerp(Color(1.0, 0.68, 0.74), inner * 0.85)
	var eye := 1.0 - smoothstep(0.050, 0.090, (ap - Vector2(0.26, 0.02)).length())
	col = col.lerp(line, eye)
	var nose := _tri(uv, Vector2(-0.10, 0.16), Vector2(0.10, 0.16), Vector2(0.0, 0.32))
	col = col.lerp(Color(0.95, 0.45, 0.55), nose)
	var wy := 0.12 + (ap.x - 0.60) * -0.14
	var whisker := 0.0
	if ap.x > 0.58 and ap.x < 0.96:
		whisker = maxf(
			1.0 - smoothstep(0.020, 0.050, absf(uv.y - wy)),
			1.0 - smoothstep(0.020, 0.050, absf(uv.y - (wy + 0.20))))
	col = col.lerp(line, whisker * 0.8)
	var blush := 1.0 - smoothstep(0.04, 0.10, (ap - Vector2(0.46, 0.22)).length())
	col = col.lerp(Color(1.0, 0.62, 0.66), blush * 0.7)
	# The ink outline that makes it a doodle.
	col = col.lerp(line, (1.0 - smoothstep(0.02, 0.55, a)) * 0.95)
	return Color(col.r, col.g, col.b, clampf(a, 0.0, 1.0))

## The cute ONIGIRI — white rice triangle, nori band, a tiny happy face. As
## iconic to the doodle page as the neko.
func _onigiri() -> ImageTexture:
	if _onigiri_tex == null:
		_onigiri_tex = _shape_tex(28, 30, _fn_onigiri)
	return _onigiri_tex

static func _fn_onigiri(uv: Vector2) -> Color:
	var line := Color(0.16, 0.13, 0.2)
	var rice := Color(0.99, 0.97, 0.93)
	# A plump rounded triangle: the tri mask softened by a circle at the rim.
	var a := _tri(uv, Vector2(0.0, -0.78), Vector2(-0.82, 0.58), Vector2(0.82, 0.58)) \
		* (1.0 - smoothstep(0.90, 1.02, uv.length()))
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	var col := rice
	# The nori wrap: a dark band across the base.
	var nori := (1.0 - smoothstep(0.28, 0.36, absf(uv.x))) \
		* smoothstep(0.06, 0.16, uv.y)
	col = col.lerp(Color(0.15, 0.18, 0.16), nori)
	# The face: dot eyes and a smile arc, drawn ABOVE the nori and kept in from
	# the sloped rim so the outline never swallows them.
	var eye := 1.0 - smoothstep(0.050, 0.090, Vector2(absf(uv.x) - 0.20, uv.y + 0.10).length())
	col = col.lerp(line, eye * (1.0 - nori))
	var mcl := Vector2(uv.x, uv.y + 0.06)
	var smile := (1.0 - smoothstep(0.030, 0.060, absf(mcl.length() - 0.12))) \
		* smoothstep(-0.02, 0.04, mcl.y)
	col = col.lerp(line, smile * (1.0 - nori))
	var blush := 1.0 - smoothstep(0.04, 0.09, Vector2(absf(uv.x) - 0.47, uv.y + 0.02).length())
	col = col.lerp(Color(1.0, 0.62, 0.66), blush * 0.65)
	col = col.lerp(line, (1.0 - smoothstep(0.02, 0.30, a)) * 0.95)
	return Color(col.r, col.g, col.b, clampf(a, 0.0, 1.0))

# --- Sakura blossoms (baked in FULL colour; emitters tint white) --------------
## A whole CHERRY BLOSSOM seen face-on. Loose petals alone never read as sakura —
## every light pink five-petal fall does — so the flower itself is baked: five
## broad petals each NOTCHED at the tip (the one feature that separates a cherry
## blossom from a plum or an apple blossom), a deep rose throat, and a burst of
## gold stamens. Three variants carry the real tree's range from pale to deep.
func _blossom(variant: int) -> ImageTexture:
	if variant == 0:
		if _blossom_a_tex == null:
			_blossom_a_tex = _shape_tex(30, 30, _fn_blossom_a)
		return _blossom_a_tex
	if variant == 1:
		if _blossom_b_tex == null:
			_blossom_b_tex = _shape_tex(30, 30, _fn_blossom_b)
		return _blossom_b_tex
	if _blossom_c_tex == null:
		_blossom_c_tex = _shape_tex(30, 30, _fn_blossom_c)
	return _blossom_c_tex

func _fn_blossom_a(uv: Vector2) -> Color:
	return _blossom_face(uv, 0)

func _fn_blossom_b(uv: Vector2) -> Color:
	return _blossom_face(uv, 1)

func _fn_blossom_c(uv: Vector2) -> Color:
	return _blossom_face(uv, 2)

func _blossom_face(uv: Vector2, variant: int) -> Color:
	var body := Color(1.00, 0.89, 0.93)      # 0 — the pale outer blossom
	var deep := Color(1.00, 0.72, 0.83)
	if variant == 1:
		body = Color(1.00, 0.78, 0.87)       # 1 — mid pink
		deep = Color(0.96, 0.55, 0.71)
	elif variant == 2:
		body = Color(0.99, 0.64, 0.78)       # 2 — the deep rose of an older flower
		deep = Color(0.88, 0.40, 0.60)
	var r := uv.length()
	var ang := atan2(uv.y, uv.x)
	# Petal phase: 0 at the seam between two petals, 1 at the next seam.
	var p := fposmod(ang + PI, TAU / 5.0) / (TAU / 5.0)
	var lobe := sin(PI * p)                              # 0 at the seams, 1 mid-petal
	var edge := 0.34 + 0.66 * pow(lobe, 0.42)            # broad, near-round petals
	# THE NOTCH: a narrow V bitten out of each petal's outer tip.
	edge -= 0.21 * exp(-pow((p - 0.5) / 0.115, 2.0))
	var a := 1.0 - smoothstep(edge - 0.075, edge, r)
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	# Petals pale toward the rim and deepen into the throat, with a soft seam
	# shadow where one petal laps under the next.
	var col := deep.lerp(body, clampf(smoothstep(0.18, 0.78, r), 0.0, 1.0))
	col = col.lerp(deep, (1.0 - smoothstep(0.0, 0.45, lobe)) * 0.55)
	# Faint veins fanning out from the throat, and the up-left light.
	var vein: float = pow(absf(sin(p * PI * 3.0)), 6.0) * smoothstep(0.25, 0.9, r)
	col = col.lerp(deep, vein * 0.22)
	col = col.lerp(Color(1, 1, 1), clampf((-uv.x - uv.y) * 0.13, 0.0, 0.22))
	# The throat: a deep rose disc under a burst of gold stamens, each filament
	# tipped with a brighter anther.
	if r < 0.36:
		var st := absf(fposmod(ang + PI, TAU / 13.0) / (TAU / 13.0) - 0.5)
		col = col.lerp(Color(0.86, 0.28, 0.47), 1.0 - smoothstep(0.10, 0.30, r))
		if r > 0.09 and st < 0.11:
			col = Color(1.00, 0.82, 0.34)                # filament
		if absf(r - 0.30) < 0.055 and st < 0.24:
			col = Color(1.00, 0.96, 0.72)                # anther head
		if r < 0.07:
			col = Color(1.00, 0.93, 0.66)                # lit centre
	return Color(col.r, col.g, col.b, a)

# --- Real metal (baked in FULL colour; emitters tint white) -------------------
## Gold's and silver's own response curves. A tint multiply can only ever SCALE
## one hue, and metal does not behave that way: gold's shadows fall toward
## brown-red while its highlight blows out to warm white, and silver's fall
## toward cold blue-grey against a pure white specular. That hue SHIFT across
## the value range is most of what makes metal read as metal on screen — which
## is why the two rains bake in full colour instead of tinting a grey coin.
const _GOLD_RAMP: Array[Color] = [
	Color(0.20, 0.10, 0.02), Color(0.55, 0.32, 0.05), Color(0.87, 0.63, 0.16),
	Color(1.00, 0.85, 0.45), Color(1.00, 0.98, 0.87)]
const _SILVER_RAMP: Array[Color] = [
	Color(0.12, 0.14, 0.19), Color(0.36, 0.41, 0.50), Color(0.69, 0.74, 0.83),
	Color(0.91, 0.94, 1.00), Color(1.00, 1.00, 1.00)]

## Re-map a greyscale metal bake through one of those curves, alpha untouched.
func _metal(g: Color, gold: bool) -> Color:
	if g.a <= 0.0:
		return g
	var stops: Array = _GOLD_RAMP if gold else _SILVER_RAMP
	var t: float = clampf(g.r, 0.0, 1.0) * float(stops.size() - 1)
	var i: int = clampi(int(t), 0, stops.size() - 2)
	var lo: Color = stops[i]
	var hi: Color = stops[i + 1]
	var c := lo.lerp(hi, t - float(i))
	return Color(c.r, c.g, c.b, g.a)

func _metal_coin(gold: bool) -> ImageTexture:
	if gold:
		if _gold_coin_tex == null:
			_gold_coin_tex = _shape_tex(18, 18, _fn_gold_coin)
		return _gold_coin_tex
	if _silver_coin_tex == null:
		_silver_coin_tex = _shape_tex(18, 18, _fn_silver_coin)
	return _silver_coin_tex

func _metal_bar(gold: bool) -> ImageTexture:
	if gold:
		if _gold_bar_tex == null:
			_gold_bar_tex = _shape_tex(22, 16, _fn_gold_bar)
		return _gold_bar_tex
	if _silver_bar_tex == null:
		_silver_bar_tex = _shape_tex(22, 16, _fn_silver_bar)
	return _silver_bar_tex

func _metal_nugget(gold: bool) -> ImageTexture:
	if gold:
		if _gold_nugget_tex == null:
			_gold_nugget_tex = _shape_tex(18, 18, _fn_gold_nugget)
		return _gold_nugget_tex
	if _silver_nugget_tex == null:
		_silver_nugget_tex = _shape_tex(18, 18, _fn_silver_nugget)
	return _silver_nugget_tex

func _fn_gold_coin(uv: Vector2) -> Color:
	return _metal(_fn_coin(uv), true)

func _fn_silver_coin(uv: Vector2) -> Color:
	return _metal(_fn_coin(uv), false)

func _fn_gold_bar(uv: Vector2) -> Color:
	return _metal(_fn_bar(uv), true)

func _fn_silver_bar(uv: Vector2) -> Color:
	return _metal(_fn_bar(uv), false)

func _fn_gold_nugget(uv: Vector2) -> Color:
	return _metal(_fn_nugget(uv), true)

func _fn_silver_nugget(uv: Vector2) -> Color:
	return _metal(_fn_nugget(uv), false)

func _fn_nugget(uv: Vector2) -> Color:
	# Raw metal straight out of the ground: a lumpy blob (a low-frequency wobble
	# beaten into the radius) with two facets catching the up-left light, a
	# shaded underside and a hot glint on the high lump. A hoard that is ALL
	# struck coin reads as a token pile; one nugget in four makes it treasure.
	var ang := atan2(uv.y, uv.x)
	var wob := 0.80 + 0.13 * sin(ang * 3.0 + 0.7) + 0.07 * sin(ang * 5.0 - 1.9)
	var r := uv.length()
	var a := 1.0 - smoothstep(wob - 0.10, wob, r)
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	var b := 0.40 + (-uv.x - uv.y) * 0.20
	b += pow(clampf(1.0 - (uv - Vector2(-0.30, -0.34)).length() * 1.3, 0.0, 1.0), 2.0) * 0.55
	b += pow(clampf(1.0 - (uv - Vector2(0.26, -0.10)).length() * 1.8, 0.0, 1.0), 2.4) * 0.30
	b -= pow(clampf(1.0 - (uv - Vector2(0.20, 0.46)).length() * 1.5, 0.0, 1.0), 2.0) * 0.20
	var glint: float = pow(clampf(1.0 - (uv - Vector2(-0.32, -0.36)).length() * 2.8, 0.0, 1.0), 6.0)
	b = clampf(b + glint * 0.55, 0.0, 1.0)
	return Color(b, b, b, a)

# --- Cut rubies (baked in FULL colour; emitters tint white) -------------------
## A tinted grey gem can only be one red. A real ruby is not: its pavilion falls
## almost to black maroon, its crown facets climb THROUGH scarlet into pink-white
## fire, and the odd facet throws a stray orange or violet dispersion flash. That
## whole range is baked here, which is why the Ruby recipe emits with a white tint.
func _ruby_stone() -> ImageTexture:
	if _ruby_tex == null:
		_ruby_tex = _shape_tex(20, 20, _fn_ruby_stone)
	return _ruby_tex

func _ruby_marquise() -> ImageTexture:
	if _ruby_marquise_tex == null:
		_ruby_marquise_tex = _shape_tex(18, 30, _fn_ruby_marquise)
	return _ruby_marquise_tex

## Map a facet's brightness (0 shadowed pavilion .. 1 blown specular) onto ruby's
## own colour response. Shared by both cuts so the two read as one gemstone.
func _ruby_tone(b: float, fire: float) -> Color:
	var c := Color(0.16, 0.01, 0.04)
	if b < 0.34:
		c = Color(0.16, 0.01, 0.04).lerp(Color(0.52, 0.03, 0.10), b / 0.34)
	elif b < 0.70:
		c = Color(0.52, 0.03, 0.10).lerp(Color(0.93, 0.13, 0.22), (b - 0.34) / 0.36)
	else:
		c = Color(0.93, 0.13, 0.22).lerp(Color(1.00, 0.84, 0.86), (b - 0.70) / 0.30)
	# Dispersion: a stray facet throws orange one way and violet the other, the
	# split white light a cut stone actually makes.
	if fire > 0.0:
		c = c.lerp(Color(1.00, 0.62, 0.24), fire * 0.55)
	elif fire < 0.0:
		c = c.lerp(Color(0.72, 0.42, 1.00), -fire * 0.45)
	return c

func _fn_ruby_stone(uv: Vector2) -> Color:
	# A round brilliant: eight crown facets alternating bright/dark around a
	# blazing octagonal table, a thin lit girdle, and a hard specular star.
	var r := uv.length()
	var a := 1.0 - smoothstep(0.88, 1.0, r)
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	var ang := atan2(uv.y, uv.x)
	var wedge := floorf(fposmod(ang + PI, TAU) / (TAU / 8.0))
	var b := 0.30 + 0.26 * fposmod(wedge, 2.0) + 0.08 * fposmod(wedge, 3.0)
	b += clampf((-uv.x - uv.y) * 0.26, -0.16, 0.26)          # lit from the upper left
	b += (1.0 - smoothstep(0.28, 0.40, r)) * 0.34            # the table
	b += smoothstep(0.70, 0.80, r) * (1.0 - smoothstep(0.84, 0.94, r)) * 0.26
	var spec: float = pow(clampf(1.0 - (uv - Vector2(-0.30, -0.34)).length() * 1.5, 0.0, 1.0), 2.0)
	var glint: float = pow(clampf(1.0 - (uv - Vector2(-0.28, -0.32)).length() * 2.7, 0.0, 1.0), 6.0)
	b = clampf(b + spec * 0.55 + glint * 0.60, 0.0, 1.0)
	var fire := 0.0
	if wedge == 2.0:
		fire = 0.8
	elif wedge == 6.0:
		fire = -0.8
	var col := _ruby_tone(b, fire * (0.25 + 0.75 * smoothstep(0.35, 0.85, r)))
	return Color(col.r, col.g, col.b, a)

func _fn_ruby_marquise(uv: Vector2) -> Color:
	# A marquise cut: a boat-shaped stone whose two ends come to a POINT.
	# An ellipse will not do it — an ellipse is blunt at the ends, and blunt
	# ends read as a capsule, which is why the first pass looked like a pill.
	# The silhouette is a vesica (half-width falling to zero at both tips),
	# carrying a long central table with chevron steps running out to each
	# point. Beside the round brilliants it gives the shower two silhouettes
	# instead of one disc repeated.
	var yy := clampf(uv.y, -1.0, 1.0)
	var half := 0.58 * (1.0 - yy * yy)
	# Proportional feather: a fixed one swallows the tips, where half -> 0.
	var aa := maxf(half * 0.30, 0.05)
	var a := 1.0 - smoothstep(half - aa, half, absf(uv.x))
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	var u: float = absf(uv.x) / maxf(half, 0.001)          # 0 spine .. 1 girdle
	var b := 0.30 + 0.32 * (1.0 - smoothstep(0.0, 0.60, u))   # the long table
	b += 0.17 * fposmod(floorf(absf(yy) * 3.2 + u * 1.7), 2.0)  # chevron steps
	b += smoothstep(0.80, 0.99, u) * 0.16                      # lit girdle
	b += clampf((-uv.x - uv.y) * 0.24, -0.16, 0.26)
	var glint: float = pow(clampf(1.0 - (uv - Vector2(-0.14, -0.38)).length() * 2.6, 0.0, 1.0), 5.0)
	b = clampf(b + glint * 0.60, 0.0, 1.0)
	# Fire gathers in the two points, where a marquise actually throws it.
	var fire := 0.55 * smoothstep(0.58, 0.92, absf(yy)) * (1.0 if yy < 0.0 else -1.0)
	var col := _ruby_tone(b, fire)
	return Color(col.r, col.g, col.b, a)

# --- Fireflies (baked in FULL colour; emitters tint white) --------------------
## A tinted glow dot is a mote, not a firefly. This is the insect: a dark beetle
## body with the species' red pronotum and two translucent wings fanned back,
## and — the whole point — a lantern abdomen burning amber through a wide soft
## halo. The BLINK is still the emitter's shimmer ramp; the bake is the animal.
func _firefly() -> ImageTexture:
	if _firefly_tex == null:
		_firefly_tex = _shape_tex(26, 26, _fn_firefly)
	return _firefly_tex

func _fn_firefly(uv: Vector2) -> Color:
	# The lantern sits low in the frame; the insect hangs above it.
	var gr := (uv - Vector2(0.0, 0.30)).length()
	var halo: float = pow(clampf(1.0 - gr / 1.05, 0.0, 1.0), 1.7)
	var lamp: float = pow(clampf(1.0 - gr / 0.40, 0.0, 1.0), 1.0)
	# Two small wings swept back off the thorax, kept faint — at this size a
	# solid pair reads as a grey bar straight through the glow.
	var wl := Vector2(uv.x + 0.26, (uv.y + 0.06) * 2.2).length()
	var wr := Vector2(uv.x - 0.26, (uv.y + 0.06) * 2.2).length()
	var wing := 1.0 - smoothstep(0.20, 0.40, minf(wl, wr))
	# Body: a slim capsule from the head down into the lantern.
	var bd := Vector2(uv.x * 3.6, (uv.y + 0.18) * 1.15).length()
	var body := 1.0 - smoothstep(0.30, 0.46, bd)
	var a := clampf(maxf(maxf(halo, lamp), maxf(wing * 0.45, body * 0.95)), 0.0, 1.0)
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	# Paint the LIGHT first...
	var col := Color(1.00, 0.80, 0.26)
	col = col.lerp(Color(1.00, 1.00, 0.86), lamp)               # white-hot core
	# ...then let the animal darken it, but only where the light is thin.
	var solid := clampf(1.0 - lamp * 1.3, 0.0, 1.0)
	col = col.lerp(Color(0.78, 0.85, 0.92), wing * solid * 0.40)
	col = col.lerp(Color(0.13, 0.12, 0.09), body * solid * 0.90)
	if uv.y < -0.34:
		col = col.lerp(Color(0.62, 0.16, 0.12), body * 0.85)     # red pronotum
	return Color(col.r, col.g, col.b, a)

# --- The hive (baked in FULL colour; emitters tint white) ---------------------
## A honey bee seen from above: fuzzy amber-and-black abdomen, dark thorax, a
## small head, and two wings drawn as pale BLUR arcs rather than solid panels,
## because a bee in flight has no visible wing shape and a solid pair reads as a
## moth. Tinting a square yellow does not make an insect; this does.
func _bee() -> ImageTexture:
	if _bee_tex == null:
		_bee_tex = _shape_tex(26, 22, _fn_bee)
	return _bee_tex

func _fn_bee(uv: Vector2) -> Color:
	# Body runs along x: head at the left, abdomen tapering right.
	var half := 0.34 * sqrt(clampf(1.0 - pow((uv.x - 0.05) / 0.94, 2.0), 0.0, 1.0))
	var body := 1.0 - smoothstep(half - 0.09, half, absf(uv.y))
	# Wing blur: two translucent panes swept back and CLEAR of the body axis.
	# Centred ON the body they are simply overpainted by it, which is all the
	# first pass achieved — a faint halo ring and no visible wings.
	var wy := absf(uv.y)
	# A hard-edged pane at half alpha reads as a grey PLATE, not a wing. Real
	# wings at wingbeat speed are a faint blur, so this fades gradually from the
	# root outward and stays well under a third alpha.
	var wing := (1.0 - smoothstep(0.30, 1.06,
		Vector2((uv.x - 0.12) / 0.66, (wy - 0.46) / 0.26).length())) * 0.32
	var a := clampf(maxf(body, wing), 0.0, 1.0)
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	var col := Color(0.86, 0.90, 0.96)                     # the wing blur
	if body > wing:
		# Stripes: black bands across the amber abdomen, a dark thorax, dark head.
		var stripe: float = fposmod(floorf((uv.x + 0.05) * 6.4), 2.0)
		col = Color(0.98, 0.72, 0.12) if stripe > 0.5 else Color(0.16, 0.12, 0.06)
		if uv.x < -0.44:
			col = Color(0.12, 0.10, 0.06)                  # head
		elif uv.x < -0.10:
			col = Color(0.34, 0.24, 0.10)                  # fuzzy thorax
		# Round the body with a top-lit shade so it is not a flat sticker.
		col = col.lerp(Color(1, 1, 1), clampf(-uv.y * 0.30, 0.0, 0.26))
		col = col.lerp(Color(0, 0, 0), clampf(uv.y * 0.26, 0.0, 0.22))
	return Color(col.r, col.g, col.b, a)

## A fat drop of raw honey: a teardrop with a glossy rim-lit body and a bright
## specular, dark amber at the edges where the depth is greatest.
var _hopper_tex: ImageTexture = null
var _splat_tex: ImageTexture = null

## A bismuth hopper crystal: a stair of squares in the oxide film's colours,
## each step with a lit edge toward the light and a dark riser. Full colour,
## so the recipe tints it white.
func _hopper() -> ImageTexture:
	if _hopper_tex == null:
		_hopper_tex = _shape_tex(24, 24, _fn_hopper)
	return _hopper_tex

func _fn_hopper(uv: Vector2) -> Color:
	var m: float = maxf(absf(uv.x), absf(uv.y))
	var a: float = 1.0 - smoothstep(0.92, 1.0, m)
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	var film := [Color("E8C95A"), Color("D2408A"), Color("5A3FB0"), Color("2BB8A0")]
	var step: int = clampi(int((1.0 - m) / 0.25), 0, 3)
	var col: Color = film[step]
	var inner: float = 1.0 - 0.25 * float(step)
	# The riser just inside each step's edge.
	if m > inner - 0.07:
		col = col.darkened(0.55)
	elif uv.x + uv.y < -0.15 * inner:
		col = col.lightened(0.28)
	elif uv.x + uv.y > 0.5 * inner:
		col = col.darkened(0.22)
	return Color(col.r, col.g, col.b, a)

## A splat of paint: a wobbling body with a few satellite drops flung off it,
## pigment pooling darker at the edges. A mask, tinted by the pigment.
func _splat() -> ImageTexture:
	if _splat_tex == null:
		_splat_tex = _shape_tex(30, 30, _fn_splat)
	return _splat_tex

func _fn_splat(uv: Vector2) -> Color:
	var ang := atan2(uv.y, uv.x)
	var wob: float = 0.62 + 0.08 * sin(ang * 3.0 + 0.7) + 0.05 * sin(ang * 6.0)
	var e: float = uv.length() / wob
	var body: float = 1.0 - smoothstep(0.92, 1.04, e)
	var a := body
	var edge := smoothstep(0.55, 0.95, e) * body
	for d_v in [[0.75, -0.55, 0.14], [-0.70, 0.60, 0.11], [0.15, 0.85, 0.09], [-0.82, -0.30, 0.08]]:
		var d: Array = d_v
		var c := Vector2(float(d[0]), float(d[1]))
		var r: float = float(d[2])
		var drop: float = 1.0 - smoothstep(r * 0.8, r * 1.1, (uv - c).length())
		# the neck of paint between the body and the drop
		var neck: float = 1.0 - smoothstep(r * 0.35, r * 0.6,
			_seg_dist_c(uv, c * 0.55, c * 0.9))
		a = maxf(a, maxf(drop, neck * 0.9))
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	var b: float = 1.0 - 0.38 * edge
	return Color(b, b, b, a)

func _seg_dist_c(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-5), 0.0, 1.0)
	return (p - (a + ab * t)).length()

func _honey_drop() -> ImageTexture:
	if _honey_tex == null:
		_honey_tex = _shape_tex(16, 22, _fn_honey_drop)
	return _honey_tex

func _fn_honey_drop(uv: Vector2) -> Color:
	# Teardrop: a circle at the bottom pulled up into a point.
	var t := clampf((uv.y + 1.0) * 0.5, 0.0, 1.0)
	var half := 0.74 * pow(t, 0.75) * sqrt(clampf(1.0 - pow(maxf(t - 0.62, 0.0) / 0.38, 2.0), 0.0, 1.0))
	var a := 1.0 - smoothstep(half - 0.09, half, absf(uv.x))
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	var u: float = absf(uv.x) / maxf(half, 0.001)
	# Thick liquid: light drives through the middle and darkens toward the rim.
	var col := Color(0.42, 0.20, 0.02).lerp(Color(1.00, 0.72, 0.14), 1.0 - u * u)
	col = col.lerp(Color(1.00, 0.88, 0.46), clampf(0.5 - t, 0.0, 0.5))
	var spec: float = pow(clampf(1.0 - (uv - Vector2(-0.24, 0.16)).length() * 2.2, 0.0, 1.0), 3.0)
	col = col.lerp(Color(1.00, 0.99, 0.88), spec * 0.85)
	return Color(col.r, col.g, col.b, a)

## A broken cell of comb: a wax hexagon with a thick beveled rim and a darker
## well. Tinted from the theme's own honey tones, so this one is greyscale.
func _wax_cell() -> ImageTexture:
	if _waxcell_tex == null:
		_waxcell_tex = _shape_tex(20, 20, _fn_wax_cell)
	return _waxcell_tex

func _fn_wax_cell(uv: Vector2) -> Color:
	# Regular hexagon: the max of three rotated slab distances.
	var hexd := 0.0
	for k in 3:
		var th := float(k) * PI / 3.0
		hexd = maxf(hexd, absf(uv.x * cos(th) + uv.y * sin(th)))
	var a := 1.0 - smoothstep(0.80, 0.90, hexd)
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	# A thick lit rim around a well that falls away — comb has depth, and a flat
	# hexagon would read as a UI icon rather than a piece of wax.
	var rim := smoothstep(0.52, 0.78, hexd)
	var b := 0.34 + rim * 0.52
	b += clampf((-uv.x - uv.y) * 0.16, -0.12, 0.20)
	b += pow(clampf(1.0 - (uv - Vector2(-0.34, -0.36)).length() * 1.8, 0.0, 1.0), 3.0) * 0.30
	b = clampf(b, 0.0, 1.0)
	return Color(b, b, b, a)

# --- Butterflies (baked in FULL colour; emitters tint white) ------------------
## The three the grove flies: 0 blue morpho, 1 the pale luminous white, 2 a
## violet-teal. A butterfly is one of the few shapes where a silhouette alone
## fails — the pattern IS the animal — so these carry their own colour and the
## flock never tints them.
##
## They are the celebration twins of BoardFx `_bfly_morpho` / `_bfly_fairy`, and
## they carry a baked HALO for the same reason those do: Butterfly Grove is a
## midnight-blue clearing lit by a cold moon, and its butterflies glow. This set
## used to be a monarch, a morpho and a swallowtail — orange and yellow, the two
## colours that palette cannot contain, so a celebration threw insects that had
## nothing to do with the ones that had been flying through the frame all game.
func _butterfly(variant: int) -> ImageTexture:
	if variant == 0:
		if _butterfly_a_tex == null:
			_butterfly_a_tex = _shape_tex(34, 30, _fn_butterfly_a)
		return _butterfly_a_tex
	if variant == 1:
		if _butterfly_b_tex == null:
			_butterfly_b_tex = _shape_tex(34, 30, _fn_butterfly_b)
		return _butterfly_b_tex
	if _butterfly_c_tex == null:
		_butterfly_c_tex = _shape_tex(34, 30, _fn_butterfly_c)
	return _butterfly_c_tex

func _fn_butterfly_a(uv: Vector2) -> Color:
	return _butterfly_wings(uv, 0)

func _fn_butterfly_b(uv: Vector2) -> Color:
	return _butterfly_wings(uv, 1)

func _fn_butterfly_c(uv: Vector2) -> Color:
	return _butterfly_wings(uv, 2)

func _butterfly_wings(uv: Vector2, variant: int) -> Color:
	var field := Color(0.12, 0.34, 0.94)      # 0 blue morpho
	var outer := Color(0.40, 0.82, 1.00)
	var frame := Color(0.02, 0.04, 0.14)
	var spot := Color(0.86, 0.95, 1.00)
	var aura := Color(0.34, 0.62, 1.00)
	var glow := 0.30
	if variant == 1:
		field = Color(0.72, 0.90, 1.00)       # 1 the pale one
		outer = Color(1.00, 1.00, 1.00)
		frame = Color(0.42, 0.66, 0.98)
		spot = Color(1.00, 1.00, 1.00)
		aura = Color(0.74, 0.90, 1.00)
		glow = 0.42
	elif variant == 2:
		field = Color(0.42, 0.26, 0.92)       # 2 violet-teal
		outer = Color(0.44, 0.94, 0.92)
		frame = Color(0.08, 0.04, 0.20)
		spot = Color(0.92, 0.86, 1.00)
		aura = Color(0.52, 0.44, 1.00)
		glow = 0.34
	var ax := absf(uv.x)
	# NORMALISED radii, not coverage masks: the frame, the venation and the
	# margin spots all need to know how far INTO the wing a pixel sits, and a
	# 0..1 coverage mask only knows about the last few pixels at the edge —
	# which is why the first pass painted its border where the wing had
	# already faded out, i.e. nowhere.
	var fr := Vector2((ax - 0.46) / 0.50, (uv.y + 0.30) / 0.60).length()
	var hr := Vector2((ax - 0.38) / 0.42, (uv.y - 0.40) / 0.46).length()
	if variant == 2 and uv.y > 0.30:
		# Swallowtail tails: a thin spur trailing off each hindwing.
		hr = minf(hr, absf(ax - 0.50) / 0.10 + 0.55 * smoothstep(1.0, 0.30, uv.y))
	var rw := minf(fr, hr)                    # 0 wing centre .. 1 wing edge
	var body := Vector2(uv.x * 7.5, uv.y * 1.02).length()
	var wing: float = maxf(1.0 - smoothstep(0.96, 1.06, rw), 1.0 - smoothstep(0.86, 1.04, body))
	# The halo, RADIAL from the thorax. A fall-off on `rw` looks like the
	# obvious choice and is not: outside the wings, min() of two ellipse fields
	# is a rounded RECTANGLE, so every butterfly glows as a little blue square.
	var gr: float = Vector2(uv.x * 0.62, uv.y * 0.72).length()
	var halo: float = pow(clampf(1.0 - gr, 0.0, 1.0), 1.8) * glow
	var a: float = clampf(maxf(wing, halo), 0.0, 1.0)
	if a <= 0.015:
		return Color(0, 0, 0, 0)
	if wing <= 0.02:
		return Color(aura.r, aura.g, aura.b, a)
	var th := atan2(uv.y + 0.06, ax + 0.05)   # fan angle out of the wing root
	# Structural colour BRIGHTENS outward instead of fading — the opposite of a
	# pigment wing, and the whole reason a morpho reads as metal.
	var col: Color = field.lerp(outer, smoothstep(0.05, 0.80, rw))
	# Fine venation fanning from the root, fading before it reaches the margin.
	var vein: float = pow(absf(sin(th * 7.0)), 10.0) * (1.0 - smoothstep(0.72, 0.96, rw))
	col = col.lerp(frame, vein * 0.45)
	# The dark margin band, well INSIDE the silhouette so it actually shows.
	col = col.lerp(frame, smoothstep(0.70, 0.93, rw))
	# Pale spots riding that band — a monarch's white margin dots.
	if rw > 0.76 and rw < 0.94 and sin(th * 11.0) > 0.60:
		col = col.lerp(spot, 0.80)
	if body < 0.9:
		col = frame.lerp(Color(0.30, 0.40, 0.62), 0.45)
	if halo > wing:
		col = col.lerp(aura, clampf((halo - wing) * 1.4, 0.0, 1.0))
	return Color(col.r, col.g, col.b, a)

## Butterfly Grove's celebration: a live flock, flown as butterflies actually
## fly. The bats (see _bat_flock) erupt in straight accelerating lines because
## that is what a startled colony does; a butterfly does the opposite, so this
## one wanders through three waypoints on an EASE_IN_OUT curve, drifts rather
## than accelerates, and beats its wings slower and wider.
func _butterfly_flock(w: float, h: float) -> void:
	_ttl = 7.5
	# A grove, not a handful: at a dozen-odd the screen read as a few stray
	# insects rather than a lift-off.
	var n := clampi(int(float(_amount) / 7.0), 26, 48)
	for i in n:
		var fly := TextureRect.new()
		fly.texture = _butterfly(i % 3)
		fly.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fly.stretch_mode = TextureRect.STRETCH_SCALE
		fly.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var fw := randf_range(46.0, 88.0)
		fly.size = Vector2(fw, fw * 0.88)     # the bake is 34x30
		fly.pivot_offset = fly.size * 0.5
		fly.modulate = Color(1, 1, 1, 0.0)
		# Lift off low and wide, then wander up and out past the top edge.
		var start := Vector2(w * randf_range(0.10, 0.90), h * randf_range(0.72, 0.98))
		var mid := Vector2(clampf(start.x + randf_range(-0.34, 0.34) * w, -0.1 * w, 1.1 * w),
			h * randf_range(0.34, 0.58))
		var target := Vector2(w * randf_range(-0.20, 1.20), -h * randf_range(0.08, 0.26))
		fly.position = start - fly.size * 0.5
		# A butterfly holds its wings level to the ground, so it stays near
		# upright and only banks a little into each turn.
		fly.rotation = deg_to_rad(randf_range(-16.0, 16.0))
		add_child(fly)
		var path := fly.create_tween()
		path.tween_interval(float(i) * 0.06)
		path.tween_property(fly, "modulate:a", 1.0, 0.25)
		path.parallel().tween_property(fly, "position", mid - fly.size * 0.5,
			randf_range(1.5, 2.4)).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		path.tween_property(fly, "position", target - fly.size * 0.5,
			randf_range(1.8, 2.8)).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		path.tween_callback(fly.queue_free)
		# The wing-beat: slower and deeper than the bats', and never fully
		# closed — a butterfly at full close shows nothing but a hairline.
		var flap := fly.create_tween().set_loops()
		flap.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		flap.tween_property(fly, "scale:x", 0.36, randf_range(0.18, 0.28))
		flap.tween_property(fly, "scale:x", 1.0, randf_range(0.18, 0.28))
		# A lazy bank either way, so no two follow the same line.
		var bank := fly.create_tween().set_loops()
		bank.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		bank.tween_property(fly, "rotation", fly.rotation + deg_to_rad(14.0), randf_range(0.7, 1.2))
		bank.tween_property(fly, "rotation", fly.rotation - deg_to_rad(14.0), randf_range(0.7, 1.2))

# --- Koi Garden: the school ----------------------------------------------------
## Koi Garden's celebration: the pond answers. The screen is the water seen from
## above, so the koi come up THROUGH it — a school crossing the frame on eased,
## curving paths, each fish flexing about its heading and each opening a ripple
## ring on the surface where it passes. The blossom emitters keep running over
## the top of them, so what is celebrated is the whole garden.
##
## Two things this is deliberately NOT. It is not the old recipe, where koi fell
## as confetti among the petals — a fish raining out of the sky reads as a dead
## one. And it is not a pure flock like the bats or the songbirds, which return
## before any particle path runs: here the pieces matter, because blossom on the
## water is half the picture.
##
## Every fish is a wrapper Control carrying the HEADING with the sprite inside it
## carrying the body flex, because those are two rotations about the same node
## and a single tween cannot own both.
func _koi_school(w: float, h: float) -> void:
	_live_ttl = maxf(_live_ttl, 7.3)
	var pal := _pal()
	# Ripples read as light on dark water; on a LIGHT palette white is invisible,
	# so they take the theme's own accent instead (the _detonation precedent).
	var ripple: Color = Color(1, 1, 1)
	if bool(pal.get("is_light", false)):
		ripple = (pal["accent"] as Color).darkened(0.3)
	var blown := _bomb_strength >= 0.0
	var n := clampi(int(float(_amount) / 12.0), 9, 16)
	var centre := Vector2(w * 0.5, h * 0.5)
	for i in n:
		var fw := randf_range(64.0, 132.0)
		var swim := Control.new()
		swim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		swim.size = Vector2(fw, fw * (76.0 / 44.0))     # the bake is 44x76, nose UP
		swim.pivot_offset = swim.size * 0.5
		swim.modulate = Color(1, 1, 1, 0.0)
		var tex := _koi(i % 3)
		# The fish's own shadow, cast down onto the pond floor a little behind
		# it. It is what puts the koi UNDER the water rather than printed on it,
		# and it costs one more sprite in the same wrapper.
		var shadow := TextureRect.new()
		shadow.texture = tex
		shadow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		shadow.stretch_mode = TextureRect.STRETCH_SCALE
		shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		shadow.size = swim.size * 1.04
		shadow.position = swim.size * Vector2(0.06, 0.10)
		shadow.pivot_offset = shadow.size * 0.5
		shadow.modulate = Color(0.02, 0.06, 0.07, 0.34)
		swim.add_child(shadow)
		var fish := TextureRect.new()
		fish.texture = tex
		fish.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fish.stretch_mode = TextureRect.STRETCH_SCALE
		fish.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fish.size = swim.size
		fish.pivot_offset = swim.size * 0.5
		swim.add_child(fish)
		var start: Vector2
		var target: Vector2
		if blown:
			# Something hit the water: the school breaks outward from the splash.
			start = centre + Vector2(randf_range(-0.10, 0.10) * w, randf_range(-0.10, 0.10) * h)
			var ang := randf_range(0.0, TAU)
			target = centre + Vector2(cos(ang), sin(ang)) * maxf(w, h) * randf_range(0.75, 1.15)
		else:
			# In off one side and out of the other, crossing the whole pond.
			var ltr := randf() < 0.5
			start = Vector2(
				w * (randf_range(-0.24, -0.06) if ltr else randf_range(1.06, 1.24)),
				h * randf_range(0.04, 0.96))
			target = Vector2((w * 1.24) if ltr else (-0.24 * w), h * randf_range(0.04, 0.96))
		# A fish under water is always turning, so the crossing is two eased legs
		# through a waypoint rather than one straight line — a koi on a ruled
		# path reads as a torpedo whatever the sprite looks like.
		var mid := start.lerp(target, randf_range(0.42, 0.58)) \
			+ Vector2(randf_range(-0.10, 0.10) * w, randf_range(-0.24, 0.24) * h)
		swim.position = start - swim.size * 0.5
		swim.rotation = (mid - start).angle() + PI * 0.5   # the bake swims nose-up
		swim.add_to_group("koi_school")   # the smoke asserts the school actually swam
		add_child(swim)
		var delay := float(i) * (0.03 if blown else 0.13)
		var d1 := randf_range(1.5, 2.3)
		var d2 := randf_range(1.5, 2.3)
		var path := swim.create_tween()
		path.tween_interval(delay)
		path.tween_property(swim, "modulate:a", 1.0, 0.45)
		path.parallel().tween_property(swim, "position", mid - swim.size * 0.5, d1) \
			.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		path.tween_property(swim, "position", target - swim.size * 0.5, d2) \
			.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		path.tween_callback(swim.queue_free)
		# Come round onto the second leg as it is taken, or the fish crabs
		# sideways through the back half of its own crossing.
		var turn := swim.create_tween()
		turn.tween_interval(delay + d1 * 0.62)
		turn.tween_property(swim, "rotation", (target - mid).angle() + PI * 0.5,
			d1 * 0.55).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		# The body flex: a koi swims by sweeping its whole length, so the sprite
		# rocks about its middle rather than beating like a wing.
		var sweep := deg_to_rad(randf_range(5.0, 9.0))
		var period := randf_range(0.34, 0.52)
		for flexed: TextureRect in [fish, shadow]:
			var beat := flexed.create_tween().set_loops()
			beat.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
			beat.tween_property(flexed, "rotation", sweep, period)
			beat.tween_property(flexed, "rotation", -sweep, period)
		# The wake: a ripple opens on the surface every so often as it passes.
		var wake := swim.create_tween()
		wake.tween_interval(delay + randf_range(0.5, 1.0))
		for k in 3:
			wake.tween_callback(_wake_ring.bind(swim, ripple, fw))
			wake.tween_interval(randf_range(0.75, 1.25))

## One ripple opening where a fish is RIGHT NOW — bound to the swimmer rather
## than to a position, because the fish is mid-tween when this fires and a
## position captured at bind time would leave rings along the start of the path.
func _wake_ring(from: Control, tint: Color, fish_w: float) -> void:
	if not is_inside_tree() or not is_instance_valid(from):
		return
	var ring := TextureRect.new()
	ring.texture = _shock_ring()
	ring.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ring.stretch_mode = TextureRect.STRETCH_SCALE
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var centre := from.position + from.size * 0.5
	var r0 := fish_w * 0.7
	var r1 := fish_w * 3.2
	ring.size = Vector2(r0, r0)
	ring.position = centre - ring.size * 0.5
	ring.modulate = Color(tint.r, tint.g, tint.b, 0.38)
	add_child(ring)
	move_child(ring, 0)          # the water is UNDER the fish that disturbed it
	var t := ring.create_tween().set_parallel(true)
	t.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	t.tween_property(ring, "size", Vector2(r1, r1), 1.5)
	t.tween_property(ring, "position", centre - Vector2(r1, r1) * 0.5, 1.5)
	t.tween_property(ring, "modulate:a", 0.0, 1.5)
	t.set_parallel(false)
	t.tween_callback(ring.queue_free)

# --- Origami Sky: the cranes take flight ---------------------------------------
## Origami Sky's celebration: a thousand cranes. The folded paper still comes
## down (the recipe keeps its darts and squares), but the CRANES fly — paper
## folded into a bird is the one piece in a paper shower that should never
## tumble, which is exactly what the old recipe had them doing.
##
## They GLIDE: long eased crossings, banking through the turn, wings breathing
## slowly the way a fold flexes in moving air. Nothing here flaps. A paper crane
## that beats its wings is a bird costume; the stillness is the point.
func _crane_flight(w: float, h: float) -> void:
	_live_ttl = maxf(_live_ttl, 7.7)
	var blown := _bomb_strength >= 0.0
	var n := clampi(int(float(_amount) / 14.0), 8, 14)
	var centre := Vector2(w * 0.5, h * 0.5)
	for i in n:
		var crane := TextureRect.new()
		crane.texture = _crane()
		crane.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		crane.stretch_mode = TextureRect.STRETCH_SCALE
		crane.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cw := randf_range(104.0, 208.0)
		crane.size = Vector2(cw, cw * (48.0 / 76.0))    # the bake is 76x48
		crane.pivot_offset = crane.size * 0.5
		# A thousand cranes are folded from a thousand papers, so the flight wears
		# the same sheet colours as the shower it flies over.
		var paper: Color = _colors[i % _colors.size()] if not _colors.is_empty() else Color(1, 1, 1)
		crane.modulate = Color(paper.r, paper.g, paper.b, 0.0)
		var start: Vector2
		var target: Vector2
		if blown:
			# The blast throws the whole flight outward, still gliding.
			start = centre + Vector2(randf_range(-0.08, 0.08) * w, randf_range(-0.08, 0.08) * h)
			var ang := randf_range(0.0, TAU)
			target = centre + Vector2(cos(ang), sin(ang)) * maxf(w, h) * randf_range(0.8, 1.2)
		else:
			var ltr := randf() < 0.5
			start = Vector2(
				w * (randf_range(-0.26, -0.06) if ltr else randf_range(1.06, 1.26)),
				h * randf_range(0.14, 0.92))
			target = Vector2((w * 1.26) if ltr else (-0.26 * w),
				start.y - h * randf_range(0.10, 0.42))   # a glide loses height slowly
		var mid := start.lerp(target, randf_range(0.44, 0.58)) \
			+ Vector2(0.0, randf_range(-0.10, 0.06) * h)
		crane.position = start - crane.size * 0.5
		# The bake faces LEFT (the neck is on -x), so a leftward flight flies as
		# baked and a rightward one is mirrored before it is banked onto its line.
		var heading := (mid - start).angle()
		if absf(heading) > PI * 0.5:
			crane.rotation = heading - PI
		else:
			crane.flip_h = true
			crane.rotation = heading
		crane.add_to_group("crane_flight")   # the smoke asserts the flight took off
		add_child(crane)
		var path := crane.create_tween()
		path.tween_interval(float(i) * (0.03 if blown else 0.14))
		path.tween_property(crane, "modulate:a", 1.0, 0.4)
		path.parallel().tween_property(crane, "position", mid - crane.size * 0.5,
			randf_range(1.7, 2.6)).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		path.tween_property(crane, "position", target - crane.size * 0.5,
			randf_range(1.7, 2.6)).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		path.tween_callback(crane.queue_free)
		# The wings breathing — paper flexing in the air, not a wingbeat: slow,
		# shallow, and never anywhere near closed.
		var flex := crane.create_tween().set_loops()
		flex.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		flex.tween_property(crane, "scale:y", randf_range(0.82, 0.90), randf_range(0.7, 1.1))
		flex.tween_property(crane, "scale:y", 1.0, randf_range(0.7, 1.1))
		# A lazy bank either way, so no two cranes ride the same line.
		var bank := crane.create_tween().set_loops()
		bank.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		bank.tween_property(crane, "rotation", crane.rotation + deg_to_rad(7.0),
			randf_range(1.1, 1.8))
		bank.tween_property(crane, "rotation", crane.rotation - deg_to_rad(7.0),
			randf_range(1.1, 1.8))

## Daybreak's celebration: the dawn chorus — a live flock of songbirds, and
## ONLY the flock (like the bats and the butterflies; the leaves and motes that
## once rode along were cut as clutter). Flown BETWEEN the two flock styles —
## quicker and straighter than the butterflies (a bird commits to a line), but
## on eased waypoints rather than the bats' straight panic — and the wing-beat
## comes in BURSTS with a glide between them, which is the one rhythm that
## reads as bird. On a bomb the blast startles the flock: every bird breaks
## outward-and-UP from the centre (a bird scattering downward reads as shot,
## not startled) under the detonation flash.
func _dawn_flock(w: float, h: float) -> void:
	_ttl = 6.4
	var blown := _bomb_strength >= 0.0
	var n := clampi(int(float(_amount) / 9.0), 14, 24)
	if blown:
		n = clampi(int(float(n) * 1.5), 20, 32)
	var centre := Vector2(w * 0.5, h * 0.5)
	if blown:
		_detonation(centre, w, h)
	for i in n:
		var variant := i % 2
		var bird := TextureRect.new()
		bird.texture = _bird(variant, 1)
		bird.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bird.stretch_mode = TextureRect.STRETCH_SCALE
		bird.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# DEPTH. A sky has birds at every distance, and that is most of what
		# separates a flock from a sticker sheet: far ones small, pale and
		# unhurried, near ones big, solid and quick across the frame. The roll is
		# biased toward the far end so the few big birds stay events.
		var depth := pow(randf(), 1.7)                 # 0 far .. 1 near
		var bw := lerpf(56.0, 178.0, depth)
		bird.size = Vector2(bw, bw * (44.0 / 56.0))    # the bake is 56x44
		bird.pivot_offset = bird.size * 0.5
		var solid := lerpf(0.60, 1.0, depth)
		bird.modulate = Color(1, 1, 1, 0.0)
		var start: Vector2
		var target: Vector2
		if blown:
			start = centre
			# The upper half only: a bird scattering DOWNWARD reads as shot,
			# not startled.
			var ang := randf_range(-PI * 0.92, -PI * 0.08)
			target = centre + Vector2(cos(ang), sin(ang)) * maxf(w, h) * randf_range(0.7, 1.1)
		else:
			# A real flock does not share one line. Each bird enters on its OWN
			# edge and leaves well away from it, so the sky fills with crossings
			# at every angle. Every bird used to be launched low on one side and
			# aimed high past the other, which put the whole chorus on a single
			# shallow diagonal - one stripe of birds, not a morning.
			# A real flock does not share one line. The archetypes are DEALT
			# round-robin rather than rolled per bird: a per-bird roll can still
			# hand you a flock that comes out all one shape by chance, and
			# "usually varied" is the bug being left behind, not a fix for it.
			# Dealing them means every morning has level crossers, climbers, a
			# bird dropping through and one going over the top.
			var arch := i % 10
			if arch == 8:
				# Up and over the viewer.
				start = Vector2(w * randf_range(0.04, 0.96), 1.20 * h)
				target = Vector2(w * randf_range(-0.18, 1.18), -0.20 * h)
			elif arch == 9:
				# And one dropping in to land.
				start = Vector2(w * randf_range(0.04, 0.96), -0.20 * h)
				target = Vector2(w * randf_range(-0.18, 1.18), 1.20 * h)
			else:
				# The bulk of the chorus CROSSES the sky, each at its own height
				# and its own pitch. A nose-down bird reads as falling, so the
				# climbing share leans upward: a morning bird is going somewhere.
				var climb := 0.0
				if arch == 3 or arch == 6:
					climb = -randf_range(0.20, 0.46)       # climbing away
				elif arch == 4:
					climb = randf_range(0.14, 0.32)        # losing height
				else:
					climb = randf_range(-0.11, 0.11)       # crossing level
				var ltr := randf() < 0.5
				var y0 := h * randf_range(0.06, 0.94)
				var y1 := clampf(y0 + h * climb, -0.10 * h, 1.05 * h)
				start = Vector2(-0.20 * w if ltr else 1.20 * w, y0)
				target = Vector2(1.20 * w if ltr else -0.20 * w, y1)
		# Birds do not fly ruler-straight: the crossing bends through a waypoint.
		var mid := start.lerp(target, randf_range(0.42, 0.58)) \
			+ Vector2(randf_range(-0.10, 0.10) * w, randf_range(-0.12, 0.12) * h)
		bird.position = start - bird.size * 0.5
		# The bake faces RIGHT: mirror for leftward flights, then bank the beak
		# onto the flight line (a mirrored nose starts at PI, hence the -PI).
		var heading := (mid - start).angle()
		if absf(heading) > PI * 0.5:
			bird.flip_h = true
			bird.rotation = heading - PI
		else:
			bird.rotation = heading
		bird.add_to_group("dawn_flock")   # the smoke measures the flock's pitches
		add_child(bird)
		if depth < 0.45:
			move_child(bird, 0)      # the far birds fly behind the near ones
		var delay := float(i) * (0.02 if blown else 0.07)
		var cross := lerpf(3.1, 1.7, depth)
		if blown:
			cross = randf_range(1.2, 1.9)
		var d1 := cross * randf_range(0.45, 0.58)
		var d2 := cross - d1
		var path := bird.create_tween()
		path.tween_interval(delay)
		path.tween_property(bird, "modulate:a", solid, 0.22)
		path.parallel().tween_property(bird, "position", mid - bird.size * 0.5, d1) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
		path.tween_property(bird, "position", target - bird.size * 0.5, d2) \
			.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
		path.tween_callback(bird.queue_free)
		# Come round onto the second leg as it is flown. Held in the SAME mirror
		# frame the launch chose (flip_h cannot change mid-flight without a pop),
		# and wrapped to the short way round so no bird spins a full turn.
		var h2 := (target - mid).angle()
		var r2: float = (h2 - PI) if bird.flip_h else h2
		r2 = bird.rotation + wrapf(r2 - bird.rotation, -PI, PI)
		var turn := bird.create_tween()
		turn.tween_interval(delay + d1 * 0.55)
		turn.tween_property(bird, "rotation", r2, d1 * 0.75) \
			.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		# The wingbeat: a real FLIPBOOK - up / level / down / level - in bursts of
		# three beats with a GLIDE between them, which is the one rhythm that
		# reads as bird. It replaces a `scale:y` squash, which on a profile bird
		# flattened the whole animal instead of moving its wing. Far birds beat
		# slower, the way distance flattens motion.
		var dt := lerpf(0.085, 0.052, depth)
		var beat := bird.create_tween().set_loops()
		beat.tween_interval(delay)
		for k in 3:
			for fr_v in [0, 1, 2, 1]:
				var fr: int = fr_v
				beat.tween_callback(_bird_frame.bind(bird, variant, fr))
				beat.tween_interval(dt * randf_range(0.9, 1.1))
		beat.tween_callback(_bird_frame.bind(bird, variant, 1))
		beat.tween_interval(randf_range(0.30, 0.70))

## One frame of the wingbeat. Guarded because the beat tween loops for the
## bird's whole crossing and the path tween frees it at the far edge.
func _bird_frame(bird: TextureRect, variant: int, frame: int) -> void:
	if is_instance_valid(bird):
		bird.texture = _bird(variant, frame)

# --- Dawn songbirds (baked in FULL colour; emitters tint white) ---------------
## A dawn songbird, in profile facing RIGHT, at one position of its wingbeat.
## Variant 0 is a barn swallow (steel violet-blue over cream, rust throat),
## variant 1 an amber dawn finch; frame 0 is the up-stroke, 1 level, 2 the
## down-stroke. The flock cycles them (see _dawn_flock), which is what makes a
## bird read as ALIVE - the previous flock squashed one static sprite on
## `scale:y`, and squashing a PROFILE bird just flattens the whole animal
## instead of moving its wing.
func _bird(variant: int, frame: int) -> ImageTexture:
	if _bird_frames.is_empty():
		_bird_frames.resize(6)
	var idx := clampi(variant, 0, 1) * 3 + clampi(frame, 0, 2)
	if _bird_frames[idx] == null:
		var v := idx / 3
		var f := idx % 3
		_bird_frames[idx] = _shape_tex(56, 44,
			func(uv: Vector2) -> Color: return _bird_body(uv, v, f))
	return _bird_frames[idx]

const _BIRD_CREAM := Color(0.98, 0.93, 0.84)

## Variant 0 is a barn swallow (steel violet-blue over cream, rust throat),
## variant 1 an amber dawn finch. STATIC with the painters so BoardFx's world
## birds and the celebration flock are provably the same two birds.
static func _bird_mantle(variant: int) -> Color:
	return Color(0.74, 0.45, 0.18) if variant == 1 else Color(0.30, 0.32, 0.66)

static func _bird_throat(variant: int) -> Color:
	return Color(0.95, 0.70, 0.30) if variant == 1 else Color(0.85, 0.44, 0.30)

## Where the near wingtip sits at each frame of the beat, measured from the
## shoulder at _BIRD_SHOULDER. The level pose is deliberately well ABOVE the
## back line: laid along the spine the wing merges into the mantle and the bird
## reads as wingless, which is how the middle frame first came out.
const _BIRD_TIPS := [Vector2(-0.34, -0.94), Vector2(-0.76, -0.60), Vector2(-0.40, 0.68)]
const _BIRD_SHOULDER := Vector2(0.20, -0.02)

## A REAL small bird in side PROFILE, the way every morning-sky illustration
## draws one: a plump body with a round head set INTO it, a pointed beak, a dark
## bead of an eye, the near wing swept to this frame's wingtip, a hint of the far
## wing behind it, and a forked swallow tail. (An early cut was a symmetric
## seen-from-below splay, which read as a moth; a bird's identity lives in its
## profile.) The flock flips and banks it along the flight line.
static func _bird_body(uv: Vector2, variant: int, frame: int) -> Color:
	var p := uv
	# Body: a horizontal teardrop, chest full at the front thinning to the rear.
	var brx := 0.40 + 0.09 * smoothstep(-0.6, 0.4, p.x)
	var bodyf := (p.x + 0.02) * (p.x + 0.02) / (brx * brx) \
		+ (p.y - 0.06) * (p.y - 0.06) / 0.055
	var body := 1.0 - smoothstep(0.82, 1.05, bodyf)
	# Head: a round cap set into the body's shoulders, beak off its face.
	var headr := (p - Vector2(0.44, -0.12)).length()
	var head := 1.0 - smoothstep(0.165, 0.235, headr)
	var beak := _tri(p, Vector2(0.58, -0.20), Vector2(0.58, -0.04), Vector2(0.92, -0.13))
	# Near wing: a scythe swept from the shoulder to this frame's wingtip.
	var tip: Vector2 = _BIRD_TIPS[clampi(frame, 0, 2)]
	var wing_v := _taper4(p, _BIRD_SHOULDER, tip, 0.175, 0.028)
	var wing := wing_v.x
	var wt := wing_v.y
	# The far wing: the same stroke, foreshortened and dimmer behind the body.
	var ftip := _BIRD_SHOULDER.lerp(tip, 0.60)
	var far_v := _taper4(p, _BIRD_SHOULDER - Vector2(0.10, -0.06), ftip, 0.110, 0.020)
	var farw := far_v.x
	# The forked swallow tail: a fan with the centre cut short. Two hairline
	# streamers were tried first and simply vanish at flock size.
	var tail := 0.0
	if p.x < -0.24:
		var tt := clampf((-0.24 - p.x) / 0.72, 0.0, 1.0)
		var yc := 0.05 + 0.07 * tt
		var half := 0.050 + 0.185 * tt
		var lobe := 1.0 - smoothstep(half * 0.78, half + 0.045, absf(p.y - yc))
		var fk := clampf(absf(p.y - yc) / 0.22, 0.0, 1.0)
		tail = lobe * (1.0 - smoothstep(0.38 + 0.40 * fk, 0.60 + 0.40 * fk, tt))
	var a := maxf(maxf(body, head), maxf(maxf(wing, tail), maxf(beak, farw)))
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	var cream := _BIRD_CREAM
	var mantle := _bird_mantle(variant)
	var throat := _bird_throat(variant)
	var dark := Color(mantle.r * 0.34, mantle.g * 0.34, mantle.b * 0.46)
	# Back to belly, SOFT and rolled around the barrel of the body rather than a
	# flat two-tone split. A hard boundary between mantle and belly is most of
	# what made this read as a vector sticker instead of an animal.
	var col := mantle.lerp(cream, smoothstep(-0.02, 0.26, p.y))
	col = dark.lerp(col, smoothstep(0.0, 0.22, p.y + 0.30))         # shaded upper back
	var streak := 0.06 * sin(p.x * 14.0) * smoothstep(0.10, 0.34, p.y)
	col = Color(col.r - streak, col.g - streak, col.b - streak * 0.6)
	if head > body:
		col = mantle.lerp(cream, smoothstep(-0.14, 0.06, p.y))
		col = dark.lerp(col, smoothstep(0.0, 0.20, p.y + 0.36))     # the dark cap
		col = col.lerp(throat, 1.0 - smoothstep(0.07, 0.16, (p - Vector2(0.45, 0.05)).length()))
		col = col.lerp(cream, 0.34 * (1.0 - smoothstep(0.03, 0.09,
			(p - Vector2(0.39, -0.04)).length())))                   # the pale cheek
	if wing > maxf(body, head):
		# The wing is a separate PLANE lying over the back, so it is always
		# darker than the mantle - at mantle tone it disappears into it, which is
		# exactly how the level frame lost its wing.
		col = Color(mantle.r * 0.74, mantle.g * 0.74, mantle.b * 0.82).lerp(dark,
			smoothstep(0.20, 0.95, wt))
		if wt > 0.42:
			# Primaries. Kept LOW frequency on purpose: anything finer than a few
			# pixels aliases into a fishbone once the sprite scales up in flight.
			var sep := pow(absf(sin((wt - 0.42) * 15.0)), 6.0) * smoothstep(0.42, 0.58, wt)
			col = Color(col.r * (1.0 - 0.30 * sep), col.g * (1.0 - 0.30 * sep),
				col.b * (1.0 - 0.24 * sep))
	elif farw > maxf(body, head):
		col = Color(dark.r * 0.86, dark.g * 0.88, dark.b * 0.96)
	elif tail > maxf(body, head):
		col = Color(mantle.r * 0.62, mantle.g * 0.62, mantle.b * 0.72).lerp(dark,
			smoothstep(0.1, 0.9, clampf((-0.24 - p.x) / 0.72, 0.0, 1.0)))
	if beak > maxf(maxf(body, head), wing):
		col = Color(0.28, 0.20, 0.14)
	# The eye: a dark bead with a CATCH-LIGHT. The catch-light is two pixels and
	# it is the whole difference between an eye and a hole.
	var eye := 1.0 - smoothstep(0.026, 0.052, (p - Vector2(0.47, -0.155)).length())
	col = col.lerp(Color(0.08, 0.07, 0.09), eye * maxf(head, body))
	col = col.lerp(Color(1.0, 0.96, 0.90),
		(1.0 - smoothstep(0.010, 0.022, (p - Vector2(0.485, -0.175)).length())) * eye)
	# The dawn RIM, taken off the EDGE of each part rather than from "anything
	# high up": a broad wash over the back just bleaches the mantle and the bird
	# loses the dark silhouette that was carrying it.
	var upper := 1.0 - smoothstep(-0.12, 0.10, p.y)
	var rim: float = smoothstep(0.62, 0.90, bodyf) * (1.0 - smoothstep(0.90, 1.04, bodyf)) * upper
	rim = maxf(rim, smoothstep(0.115, 0.160, headr) * (1.0 - smoothstep(0.160, 0.200, headr))
		* (1.0 - smoothstep(-0.26, -0.08, p.y)))
	if wing > maxf(body, head):
		var wr := wing_v.z / maxf(wing_v.w, 0.001)
		rim = maxf(rim, smoothstep(0.55, 0.95, wr) * (1.0 - smoothstep(0.95, 1.15, wr)) * 0.8)
	col = col.lerp(Color(1.0, 0.84, 0.58), clampf(rim, 0.0, 1.0) * 0.62)
	# A touch of top-light so the sprite reads round, not flat.
	var lit := clampf(1.0 - 0.14 * smoothstep(-0.4, 0.8, p.y), 0.0, 1.0)
	return Color(col.r * lit, col.g * lit, col.b * lit, clampf(a, 0.0, 1.0))

## The same two birds SITTING: head up and forward, body leaning back off the
## perch, the wing folded flat along the flank, tail down and back, and two legs
## gripping. Its own pose rather than a rotation of the flying sprite - a bird
## in the air and a bird on a branch share almost no silhouette, and turning one
## into the other is exactly what makes a scene read as clip-art.
##
## The bake sits FEET-DOWN at uv.y 0.90, so a host places it by subtracting
## 0.95 of the sprite height from the perch point (see BoardFx._dawn_perch_at).
static func _bird_perch_body(uv: Vector2, variant: int) -> Color:
	const AX := -0.87                # the body's long axis, up-and-forward
	var cream := _BIRD_CREAM
	var mantle := _bird_mantle(variant)
	var throat := _bird_throat(variant)
	var dark := Color(mantle.r * 0.34, mantle.g * 0.34, mantle.b * 0.46)
	# The legs, and the body sitting over them.
	var leg := 0.0
	for pair_v in [Vector2(-0.02, 0.00), Vector2(0.14, 0.16)]:
		var pair: Vector2 = pair_v
		leg = maxf(leg, _taper(uv, Vector2(pair.x, 0.40), Vector2(pair.y, 0.86),
			0.034, 0.026).x)
	var bodyf := _ellip(uv, Vector2(0.06, 0.04), AX, 0.44, 0.34)
	var body := 1.0 - smoothstep(0.84, 1.06, bodyf)
	# Head: overlapping the shoulders, because a songbird has no visible neck.
	var headr := (uv - Vector2(0.30, -0.46)).length()
	var head := 1.0 - smoothstep(0.255, 0.315, headr)
	var beak := _tri(uv, Vector2(0.55, -0.53), Vector2(0.55, -0.39), Vector2(0.94, -0.46))
	# Tail: continuing the body's line down and back, slim.
	var tail_v := _taper(uv, Vector2(-0.20, 0.32), Vector2(-0.80, 0.74), 0.115, 0.075)
	var tail := tail_v.x
	var a: float = maxf(maxf(body, head), maxf(maxf(beak, tail), leg))
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	# Back to belly ACROSS the body's own axis, so the shading leans with it.
	var d := uv - Vector2(0.06, 0.04)
	var cc := cos(-AX)
	var ss := sin(-AX)
	var across := d.x * ss + d.y * cc
	var col := mantle.lerp(cream, smoothstep(-0.02, 0.24, across))
	col = dark.lerp(col, smoothstep(0.0, 0.22, across + 0.26))
	if head > body:
		col = mantle.lerp(cream, smoothstep(-0.56, -0.28, uv.y))
		col = dark.lerp(col, smoothstep(0.0, 0.18, uv.y + 0.70))
		col = col.lerp(throat, 1.0 - smoothstep(0.10, 0.20, (uv - Vector2(0.24, -0.26)).length()))
	# The folded wing, laid flat along the flank.
	var wing := 1.0 - smoothstep(0.80, 1.05, _ellip(uv, Vector2(0.02, 0.06), AX, 0.34, 0.155))
	if body > 0.5 and wing > 0.02:
		var along := clampf(((uv.x - 0.02) * cc - (uv.y - 0.06) * ss) / 0.68 + 0.5, 0.0, 1.0)
		col = col.lerp(dark.lerp(
			Color(mantle.r * 0.72, mantle.g * 0.72, mantle.b * 0.82), along), wing)
	if tail > maxf(body, head):
		col = Color(mantle.r * 0.60, mantle.g * 0.60, mantle.b * 0.70).lerp(dark,
			smoothstep(0.1, 0.9, tail_v.y))
	if leg > maxf(body, tail):
		col = Color(0.32, 0.25, 0.21)
	if beak > maxf(body, head):
		col = Color(0.28, 0.20, 0.14)
	var eye := 1.0 - smoothstep(0.032, 0.060, (uv - Vector2(0.36, -0.52)).length())
	col = col.lerp(Color(0.08, 0.07, 0.09), eye * head)
	col = col.lerp(Color(1.0, 0.96, 0.90),
		(1.0 - smoothstep(0.013, 0.028, (uv - Vector2(0.375, -0.545)).length())) * eye)
	# The dawn rim, off the top edge of head and back.
	var rim: float = smoothstep(0.62, 0.92, bodyf) * (1.0 - smoothstep(0.92, 1.06, bodyf)) \
		* (1.0 - smoothstep(-0.24, 0.02, across))
	rim = maxf(rim, smoothstep(0.195, 0.258, headr) * (1.0 - smoothstep(0.258, 0.318, headr))
		* (1.0 - smoothstep(-0.62, -0.40, uv.y)))
	col = col.lerp(Color(1.0, 0.84, 0.58), clampf(rim, 0.0, 1.0) * 0.62)
	return Color(col.r, col.g, col.b, clampf(a, 0.0, 1.0))

## Normalised radius inside a ROTATED ellipse: <1 inside, 1 on the edge. The
## perched bird is a stack of ellipses that all lean along one axis.
static func _ellip(p: Vector2, c: Vector2, ang: float, ra: float, rb: float) -> float:
	var d := p - c
	var ca := cos(-ang)
	var sa := sin(-ang)
	var rx := d.x * ca - d.y * sa
	var ry := d.x * sa + d.y * ca
	return (rx / ra) * (rx / ra) + (ry / rb) * (ry / rb)

## The perched bird, baked. 44x56 (taller than wide) because a sitting bird is.
static var _bird_perch_tex: Array[ImageTexture] = []

func _bird_perched(variant: int) -> ImageTexture:
	if _bird_perch_tex.is_empty():
		_bird_perch_tex.resize(2)
	var v := clampi(variant, 0, 1)
	if _bird_perch_tex[v] == null:
		_bird_perch_tex[v] = _shape_tex(44, 56,
			func(uv: Vector2) -> Color: return _bird_perch_body(uv, v))
	return _bird_perch_tex[v]

# --- Peacock feather (baked in FULL colour; emitters tint white) --------------
## A train feather: a pale quill, loose wisps of herl along its lower half, a
## broad airy plume of DARK GREEN swelling under the tip, and the ocellus riding
## on the very end — indigo kidney pupil, cobalt iris, a copper crescent, a
## thin bronze rim, green. The eye is what says peacock; the green says feather.
##
## The first bake was 20x40 with a brown vane, and at that size all that
## survived was a tan cone with a dot on it — cardboard fletching. What makes
## this one read as a real feather, each of which costs pixels (hence 56x140;
## the plumage recipe scales its emitters back down and throws far fewer):
##
##   * The vane is DARK GREEN, the register of the plumage world behind the
##     board: deep emerald at the shaft, dark teal-green through the body, a
##     dull olive at the barb tips, with iridescent bands of blue-teal and
##     bronze running across it. Nothing on it is bright: a light-green or
##     yellow-green vane came out as "ears of wheat", and a wide gold ring
##     round the eye turned the shower into fried eggs.
##   * The barbs CURVE toward the tip and the plume is AIRY: alpha dips between
##     barbs so light comes through, and the outer barbs come apart into
##     filaments that end at their own lengths. A solid envelope is a leaf.
##   * The lower half is not vane at all: it is HERL, separate soft barbs that
##     leave the quill and end at their own lengths.
##   * Past the eye's edge, loose filaments radiate outward, so the tip is
##     hairy instead of a stamped disc.
##
## Twin of BoardFx._fn_eye_feather; keep the profile and the eye in step.
func _feather() -> ImageTexture:
	if _feather_tex == null:
		_feather_tex = _shape_tex(56, 140, _fn_feather)
	return _feather_tex

func _fn_feather(uv: Vector2) -> Color:
	const AR := 2.5       # bake 56x140: x in [-1, 1], sy in [-AR, AR], isotropic
	var sy: float = uv.y * AR
	var t: float = clampf((sy + AR) / (AR * 2.0), 0.0, 1.0)     # 0 tip .. 1 base
	# A train feather bows; everything is measured off the bowed centre line.
	var cx: float = uv.x - 0.08 * sin(t * PI)
	var ax: float = absf(cx)
	var side: float = 1.0 if cx >= 0.0 else -1.0
	var a := 0.0
	var col := Color(0, 0, 0)
	var eye_y: float = -AR + 1.05

	# Barbs leave the quill at ~30 degrees and CURVE toward the tip. A point's
	# barb index is its y plus a share of its x; `barb` is 0 on a barb, 1 between.
	var idx: float = (sy + ax * 0.55 + 0.20 * ax * ax) * 11.0
	var barb: float = absf(fposmod(idx, 1.0) - 0.5) * 2.0
	var bi: float = floorf(idx)
	var h1: float = fposmod(sin(bi * 12.99) * 437.58, 1.0)     # per-barb noise
	var h2: float = fposmod(sin(bi * 7.13 + 1.7) * 251.31, 1.0)

	# --- The plume: one smooth envelope, widest under the eye, closed at the base.
	var env: float = exp(-pow((sy - (eye_y + 1.15)) / 1.60, 2.0))
	var plume: float = 0.84 * env
	if plume > 0.05:
		var along: float = ax / maxf(plume, 0.01)
		var body: float = 1.0 - smoothstep(0.46, 0.86, along)
		# The fringe: the outer barbs come apart into filaments and end at their
		# own distances, so the outline is soft and ragged, never a cut edge.
		var jag: float = 0.98 + 0.30 * h1 + 0.05 * sin(idx * 3.1)
		var fil: float = 1.0 - smoothstep(0.22, 0.58, barb)
		var fringe: float = fil * smoothstep(0.40, 0.56, along) \
			* (1.0 - smoothstep(jag - 0.24, jag, along))
		var va: float = clampf(maxf(body, fringe), 0.0, 1.0)
		# Airy: the alpha dips between barbs, so the world shows through the vane.
		va *= 0.70 + 0.30 * (1.0 - smoothstep(0.30, 0.80, barb))
		va *= smoothstep(0.020, 0.060, ax)                      # the gap beside the quill
		va *= smoothstep(eye_y - 0.15, eye_y + 0.25, sy)        # nothing above the eye
		if va > a:
			a = va
			# Emerald at the shaft, dark teal-green through the body, dull olive
			# at the barb tips; the striation is a brightness ripple, not a hole.
			var shade: float = 0.78 + 0.34 * (1.0 - barb)
			col = Color(0.02, 0.14, 0.09).lerp(Color(0.04, 0.34, 0.24), smoothstep(0.0, 0.50, along))
			col = col.lerp(Color(0.13, 0.36, 0.13), smoothstep(0.55, 1.0, along) * 0.80)
			# Iridescence: BANDS of deep blue-teal and dark bronze cross the vane
			# at a slant, the way structural colour shifts along a real train.
			var band: float = 0.5 + 0.5 * sin(sy * 2.6 + ax * 1.8 + side * 0.9)
			col = col.lerp(Color(0.04, 0.26, 0.42), band * 0.45 * (1.0 - along * 0.5))
			col = col.lerp(Color(0.36, 0.30, 0.10), (1.0 - band) * 0.28 * along)
			col = Color(col.r * shade, col.g * shade, col.b * shade)
			# A sweep of light across the plume: the flash a train throws. Dim,
			# because a dark feather with a bright stripe is a dark feather with
			# a bright stripe.
			var gl: float = pow(clampf(1.0 - absf(cx * 0.9 + (sy - eye_y - 1.2) * 0.55 + 0.25) * 1.6, 0.0, 1.0), 2.0)
			col = col.lerp(Color(0.26, 0.60, 0.48), gl * 0.20 * (1.0 - along))

	# --- The herl: loose barbs along the bare lower shaft, each its own length.
	if sy > eye_y + 1.3:
		var reach: float = 0.16 + 0.60 * h1 * h1 * (1.0 - smoothstep(0.55, 1.0, t))
		var thin: float = 1.0 - smoothstep(0.14, 0.44, barb)
		var ha: float = thin * (1.0 - smoothstep(reach - 0.12, reach, ax)) \
			* smoothstep(0.030, 0.070, ax) * (0.60 + 0.40 * h2)
		ha *= 1.0 - smoothstep(0.90, 1.0, t)
		if ha > a:
			a = ha
			# Bronze-green: the herl is the dull part of a train feather.
			col = Color(0.06, 0.20, 0.10).lerp(Color(0.24, 0.28, 0.10), h2 * 0.7 + ax * 0.4)

	# --- The quill: pale bronze, darker at its edges, running up INTO the eye.
	var quill: float = 0.048 - 0.024 * (1.0 - t)
	if ax < quill and sy > eye_y - 0.10 and t < 0.985:
		a = 1.0
		var q: float = clampf(1.0 - ax / maxf(quill, 0.001), 0.0, 1.0)
		col = Color(0.30, 0.23, 0.10).lerp(Color(0.66, 0.56, 0.34), q)

	# --- The ocellus: the widest part of the feather, on the tip.
	var ex: float = cx / 0.70
	var ey: float = (sy - eye_y) / 0.58
	var r: float = Vector2(ex, ey).length()
	var ang: float = atan2(ey, ex)
	r *= 1.0 + 0.045 * sin(ang * 3.0 + 0.6) + 0.025 * sin(ang * 7.0 - 1.1)
	if r < 1.80:
		# A KIDNEY pupil: a disc with a smaller disc bitten out of its lower edge.
		var pr: float = Vector2(ex / 0.42, (ey + 0.08) / 0.36).length()
		var bite: float = Vector2(ex / 0.30, (ey + 0.50) / 0.26).length()
		var pupil: float = (1.0 - smoothstep(0.86, 1.06, pr)) * smoothstep(0.82, 1.08, bite)
		# The field is GREEN and the gold is a thin bronze rim inside it: a wide
		# yellow ring is what turned every piece of the shower into a fried egg.
		var c := Color(0.06, 0.30, 0.16)                                          # dark green field
		c = c.lerp(Color(0.50, 0.38, 0.12), (1.0 - smoothstep(0.90, 1.08, r)) * 0.80)  # thin bronze rim
		var copper: float = (1.0 - smoothstep(0.66, 0.92, r)) \
			* clampf(0.55 + 0.45 * sin(ang + 1.9), 0.0, 1.0)
		c = c.lerp(Color(0.42, 0.18, 0.05), copper)                                # copper crescent
		c = c.lerp(Color(0.03, 0.28, 0.34), 1.0 - smoothstep(0.50, 0.76, r))       # inner teal
		c = c.lerp(Color(0.06, 0.26, 0.62), 1.0 - smoothstep(0.30, 0.54, r))       # cobalt iris
		c = c.lerp(Color(0.02, 0.03, 0.12), pupil)                                 # the pupil
		# The barbs run through the eye too, packed tighter.
		var eb: float = absf(fposmod(idx * 1.5, 1.0) - 0.5) * 2.0
		c = Color(c.r, c.g, c.b) * (0.86 + 0.24 * (1.0 - eb))
		# ONE hot spot, off centre, kept off the pupil.
		var spec: float = 1.0 - smoothstep(0.0, 0.80, Vector2(ex + 0.32, ey + 0.36).length())
		c = c.lerp(Color(0.50, 0.82, 0.74), spec * 0.24 * smoothstep(0.20, 0.50, r))
		# The eye's edge FADES into the plume: painted over it, not max()-ed.
		var ea: float = 1.0 - smoothstep(1.02, 1.36, r)
		# ...and past that edge, loose filaments radiate outward over the upper
		# half of the eye, each to its own length, so the tip is hairy.
		var fidx: float = ang * 14.0
		var fb: float = absf(fposmod(fidx, 1.0) - 0.5) * 2.0
		var fh: float = fposmod(sin(floorf(fidx) * 9.7) * 311.7, 1.0)
		var fr: float = 1.30 + 0.45 * fh
		var fa: float = (1.0 - smoothstep(0.20, 0.55, fb)) * smoothstep(1.00, 1.15, r) \
			* (1.0 - smoothstep(fr - 0.15, fr, r)) * 0.85 * (1.0 - smoothstep(-0.2, 0.5, ey))
		if fa > ea:
			c = Color(0.26, 0.38, 0.11).lerp(Color(0.08, 0.28, 0.14), fh)
			ea = fa
		if ea > 0.01:
			col = c if a <= 0.02 else col.lerp(c, ea)
			a = maxf(a, ea)
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	return Color(col.r, col.g, col.b, clampf(a, 0.0, 1.0))
# --- Cut diamond (baked in FULL colour; emitters tint white) ------------------
## A round brilliant that actually DISPERSES: near-white facets carrying split
## spectral fire — red and gold one side, cyan and violet the other. A diamond
## rendered as a pale grey gem is indistinguishable from glass, and beside the
## gold and silver rains it would have looked like a third metal.
func _diamond_stone() -> ImageTexture:
	if _diamond_tex == null:
		_diamond_tex = _shape_tex(20, 20, _fn_diamond_stone)
	return _diamond_tex

func _fn_diamond_stone(uv: Vector2) -> Color:
	var r := uv.length()
	var a := 1.0 - smoothstep(0.88, 1.0, r)
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	var ang := atan2(uv.y, uv.x)
	var wedge := floorf(fposmod(ang + PI, TAU) / (TAU / 8.0))
	var b := 0.16 + 0.40 * fposmod(wedge, 2.0) + 0.14 * fposmod(wedge, 3.0)
	b += clampf((-uv.x - uv.y) * 0.26, -0.18, 0.26)
	b += (1.0 - smoothstep(0.26, 0.38, r)) * 0.34                  # the table
	b += smoothstep(0.70, 0.80, r) * (1.0 - smoothstep(0.84, 0.94, r)) * 0.30
	var glint: float = pow(clampf(1.0 - (uv - Vector2(-0.28, -0.32)).length() * 2.6, 0.0, 1.0), 6.0)
	b = clampf(b + glint * 0.60, 0.0, 1.0)
	# Cold slate through to blown white. The WIDE value range is the point: a
	# stone whose facets all sit in one pastel band reads as a PEARL, which is
	# exactly what the first bake produced. Contrast is what says diamond.
	var col := Color(0.13, 0.19, 0.30).lerp(Color(1.00, 1.00, 1.00), b)
	var fire := Color(1.00, 0.34, 0.30)
	if wedge == 1.0:
		fire = Color(1.00, 0.80, 0.22)
	elif wedge == 3.0:
		fire = Color(0.24, 0.94, 0.96)
	elif wedge == 5.0:
		fire = Color(0.62, 0.38, 1.00)
	elif wedge == 7.0:
		fire = Color(0.34, 1.00, 0.56)
	elif wedge != 0.0:
		fire = Color(1, 1, 1)
	# Fire rides the BRIGHT facets only (b squared), so it flashes in a few
	# places as the stone turns instead of tinting the whole disc.
	col = col.lerp(fire, 0.42 * smoothstep(0.34, 0.90, r) * b * b)
	return Color(col.r, col.g, col.b, a)

# --- Storm wind (tintable) ----------------------------------------------------
## A driven raindrop: a long thin smear with a slightly fuller head and a tail
## thinning to nothing — what rain looks like once the wind has hold of it and
## the eye can only catch the streak.
func _rainstreak() -> ImageTexture:
	if _rainstreak_tex == null:
		_rainstreak_tex = _shape_tex(8, 40, _fn_rainstreak)
	return _rainstreak_tex

func _fn_rainstreak(uv: Vector2) -> Color:
	var wdt := 0.34 + 0.44 * smoothstep(-1.0, 0.75, uv.y)   # thin tail -> fuller head
	var d := absf(uv.x) / maxf(wdt, 0.001)
	var a := (1.0 - smoothstep(0.40, 1.0, d)) * (1.0 - smoothstep(0.74, 1.0, absf(uv.y)))
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	var b := clampf(0.52 + 0.48 * (1.0 - d), 0.0, 1.0)
	return Color(b, b, b, a)

# --- Cut diamonds (baked in FULL colour; emitters tint white) -----------------
## THE diamond silhouette: a flat table across the top, the crown flaring out to
## the girdle, then the pavilion running to a point. Every other gem in the
## catalogue is already a disc or a lozenge, and shape is what the eye reads
## first — which is why a round brilliant in near-white came out looking like a
## PEARL however carefully its facets were shaded. The kite says diamond before
## any colour does.
func _diamond_kite() -> ImageTexture:
	if _diamond_kite_tex == null:
		_diamond_kite_tex = _shape_tex(24, 26, _fn_diamond_kite)
	return _diamond_kite_tex

func _diamond_baguette() -> ImageTexture:
	if _diamond_baguette_tex == null:
		_diamond_baguette_tex = _shape_tex(16, 24, _fn_diamond_baguette)
	return _diamond_baguette_tex

## Diamond's colour response: cold slate in shadow through to blown white, with
## the spectral fire kept to a few facets. Shared by both cuts.
func _diamond_tone(b: float, fire: float) -> Color:
	var col := Color(0.09, 0.14, 0.24).lerp(Color(1, 1, 1), clampf(b, 0.0, 1.0))
	if fire > 0.001:
		var spectrum := Color(1.00, 0.28, 0.24)
		if fire < 0.30:
			spectrum = Color(1.00, 0.80, 0.20)
		elif fire < 0.55:
			spectrum = Color(0.22, 0.96, 0.98)
		elif fire < 0.80:
			spectrum = Color(0.58, 0.34, 1.00)
		# Fire only shows where there is light to split, so it rides b squared —
		# a spectral wash over the dark facets is how a diamond turns into an
		# opal, which is exactly what the first bake did.
		col = col.lerp(spectrum, 0.44 * b * b)
	return col

func _fn_diamond_kite(uv: Vector2) -> Color:
	var y := uv.y
	if y < -0.68:
		return Color(0, 0, 0, 0)
	var half := 0.0
	if y < -0.34:
		half = lerpf(0.52, 0.95, (y + 0.64) / 0.30)              # the crown flare
	else:
		half = lerpf(0.95, 0.02, pow((y + 0.34) / 1.30, 0.92))   # the pavilion
	var d := absf(uv.x)
	var aa := maxf(half * 0.12, 0.035)
	# Feather the flat top; the girdle and point are handled by half().
	var a := (1.0 - smoothstep(half - aa, half, d)) * smoothstep(-0.68, -0.62, y)
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	# Panels are indexed in NORMALISED width, so they converge to the point on
	# their own — that convergence is what reads as a cut pavilion.
	var u := uv.x / maxf(half, 0.001)
	var panel := floorf((u + 1.0) * 4.0)
	var b := 0.20 + 0.44 * fposmod(panel, 2.0) + 0.12 * fposmod(panel, 3.0)
	if y < -0.34:
		b = 0.44 + 0.34 * fposmod(panel, 2.0)                    # crown facets
	if y < -0.50 and absf(u) < 0.72:
		b = 0.98                                                 # the table, blazing
	b += smoothstep(0.030, 0.0, absf(y + 0.34)) * 0.30           # lit girdle line
	b += clampf((-uv.x - uv.y) * 0.22, -0.16, 0.24)
	var glint: float = pow(clampf(1.0 - (uv - Vector2(-0.24, -0.50)).length() * 2.2, 0.0, 1.0), 5.0)
	b = clampf(b + glint * 0.60, 0.0, 1.0)
	# Fire on the BRIGHT pavilion panels (the odd ones), one per spectral band,
	# so a turning stone throws gold, cyan, violet and red rather than one hue.
	# Aimed at the dark panels it simply vanishes — there is no light to split.
	var fire := 0.0
	if y > -0.34 and fposmod(panel, 2.0) > 0.5:
		fire = panel * 0.13 + 0.06
	return _with_alpha(_diamond_tone(b, fire), a)

func _fn_diamond_baguette(uv: Vector2) -> Color:
	# A baguette: a straight step-cut bar. Falling beside the kites it gives the
	# shower a second silhouette, and its long flat facets throw broad flashes
	# where the kite throws points.
	var a := (1.0 - smoothstep(0.56, 0.66, absf(uv.x))) \
		* (1.0 - smoothstep(0.86, 0.96, absf(uv.y)))
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	var step := floorf((uv.y + 1.0) * 2.6)
	var b := 0.24 + 0.34 * fposmod(step, 2.0)
	if absf(uv.x) < 0.30:
		b = 0.92                                                 # the long table
	b += smoothstep(0.50, 0.58, absf(uv.x)) * 0.24               # lit bevel
	b += clampf((-uv.x - uv.y) * 0.20, -0.14, 0.22)
	var glint: float = pow(clampf(1.0 - (uv - Vector2(-0.16, -0.44)).length() * 2.4, 0.0, 1.0), 5.0)
	b = clampf(b + glint * 0.55, 0.0, 1.0)
	# Fire stays OFF the table: across the full width it stopped being a glint
	# and became a stripe of colour painted through the stone.
	var fire := 0.0
	if fposmod(step, 3.0) == 1.0 and absf(uv.x) >= 0.30:
		fire = fposmod(step * 0.31, 1.0)
	return _with_alpha(_diamond_tone(b, fire), a)

# --- More of the hive ---------------------------------------------------------
## Distance to the edge of a regular hexagon centred on the origin (1.0 at the
## flat sides). The comb shapes are all built from this.
func _hex_d(p: Vector2) -> float:
	var d := 0.0
	for k in 3:
		var th := float(k) * PI / 3.0
		d = maxf(d, absf(p.x * cos(th) + p.y * sin(th)))
	return d

## A broken CHUNK of comb — three cells still joined. One lone hexagon reads as
## a UI icon however it is shaded; three joined cells read as a piece torn out
## of a hive, which is the whole difference on a screen full of falling pieces.
func _comb_chunk() -> ImageTexture:
	if _comb_chunk_tex == null:
		_comb_chunk_tex = _shape_tex(28, 28, _fn_comb_chunk)
	return _comb_chunk_tex

func _fn_comb_chunk(uv: Vector2) -> Color:
	var s := 0.54
	var d := minf(minf(
		_hex_d((uv - Vector2(0.0, -0.46)) / s),
		_hex_d((uv - Vector2(-0.42, 0.24)) / s)),
		_hex_d((uv - Vector2(0.42, 0.24)) / s))
	var a := 1.0 - smoothstep(0.80, 0.94, d)
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	# Thick lit walls around wells that fall away — comb has depth, and a flat
	# fill would read as a sticker.
	var rim := smoothstep(0.44, 0.78, d)
	var b := 0.26 + rim * 0.62
	b += clampf((-uv.x - uv.y) * 0.16, -0.12, 0.20)
	b += pow(clampf(1.0 - (uv - Vector2(-0.34, -0.40)).length() * 1.7, 0.0, 1.0), 3.0) * 0.26
	b = clampf(b, 0.0, 1.0)
	return Color(b, b, b, a)

## A drizzle of honey: a thick S-curved ribbon, dark amber at its edges where
## the liquid is deepest and lit down the middle, with a wet highlight running
## its length. Falling drops alone read as rain; a ribbon reads as honey.
func _honey_ribbon() -> ImageTexture:
	if _honey_ribbon_tex == null:
		_honey_ribbon_tex = _shape_tex(20, 34, _fn_honey_ribbon)
	return _honey_ribbon_tex

func _fn_honey_ribbon(uv: Vector2) -> Color:
	var t := clampf((uv.y + 1.0) * 0.5, 0.0, 1.0)
	var cx := 0.40 * sin(t * PI * 1.7 + 0.35)
	var wdt := 0.30 * (0.50 + 0.50 * sin(PI * clampf(t, 0.0, 1.0)))
	var d := absf(uv.x - cx)
	var a := 1.0 - smoothstep(wdt - 0.09, wdt, d)
	if a <= 0.02:
		return Color(0, 0, 0, 0)
	var u: float = d / maxf(wdt, 0.001)
	var col := Color(0.40, 0.19, 0.02).lerp(Color(1.00, 0.72, 0.14), 1.0 - u * u)
	col = col.lerp(Color(1.00, 0.90, 0.50), clampf(0.45 - u, 0.0, 0.45))
	# The wet highlight, offset off the ribbon's spine like light on a curve.
	var hl: float = 1.0 - smoothstep(0.05, 0.17, absf(uv.x - cx + wdt * 0.38))
	col = col.lerp(Color(1.00, 0.97, 0.82), hl * 0.34)
	return Color(col.r, col.g, col.b, a)

## Attach an alpha to a colour without restating its channels.
func _with_alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)

## Thunderstorm's celebration: the STORM, not its lightning. Bolts as tumbling
## pieces were tried and they read as litter — a discharge is a thing that
## happens in an instant across the whole sky, and chopping it into confetti
## sized scraps fights that. So the screen is swept by WIND instead: fine spray,
## heavier rain streaks and a few long gust curls, every piece aligned to its
## flight, over the double lightning flash that still opens the whole thing.
##
## The wind blows down-and-right, so pieces enter from the top edge AND the left
## edge — a top-only curtain leaves a growing empty wedge down the left of the
## screen as the field slants away from it.
func _storm_wind(w: float, h: float, intensity: float = 1.0) -> void:
	_ttl = 5.0
	var dir := Vector2(0.74, 0.67).normalized()
	var k: float = clampf(intensity, 1.0, 2.0)
	# Far spray: dense, tiny, faint and fastest — this is the layer that reads
	# as "driving", because speed at small scale is what the eye calls wind.
	_wind_layer(w, h, dir, int(_amount * 1.5 * k), 0.30, 0.75,
		1500.0, 2400.0, 0.34, Color(0.80, 0.90, 1.00), 0.0)
	# The rain itself.
	_wind_layer(w, h, dir, int(_amount * 0.9 * k), 0.9, 2.0,
		1050.0, 1750.0, 0.70, Color(0.90, 0.96, 1.00), 0.0)
	# A few long gust curls, orbiting slightly so the air visibly turns.
	_wind_layer(w, h, dir, maxi(int(_amount * 0.16 * k), 4), 2.6, 5.2,
		700.0, 1250.0, 0.22, Color(1.00, 1.00, 1.00), 0.06)

## One layer of the storm: the same field emitted from the top edge and the left
## edge so the slanted sweep covers the whole screen instead of a wedge of it.
func _wind_layer(w: float, h: float, dir: Vector2, amount: int,
		smin: float, smax: float, vmin: float, vmax: float,
		alpha: float, tint: Color, orbit: float) -> void:
	var edges: Array[Dictionary] = [
		{"pos": Vector2(w * 0.5, -70.0), "ext": Vector2(w * 0.62, 12.0)},
		{"pos": Vector2(-70.0, h * 0.5), "ext": Vector2(12.0, h * 0.62)},
	]
	for e in edges:
		var ps := CPUParticles2D.new()
		ps.position = e["pos"]
		ps.one_shot = true
		ps.explosiveness = 0.0          # a continuous sweep, not a burst
		ps.amount = maxi(int(amount * 0.5), 1)
		ps.lifetime = 2.6
		ps.lifetime_randomness = 0.25
		ps.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		ps.emission_rect_extents = e["ext"]
		ps.direction = dir
		ps.spread = 7.0
		ps.gravity = Vector2(0, 220.0)
		ps.damping_min = 0.0
		ps.damping_max = 8.0
		ps.initial_velocity_min = vmin
		ps.initial_velocity_max = vmax
		ps.orbit_velocity_min = -orbit
		ps.orbit_velocity_max = orbit
		ps.scale_amount_min = smin
		ps.scale_amount_max = smax
		# Aligned to flight and never spinning: rain that tumbles is confetti.
		ps.particle_flag_align_y = true
		ps.angle_min = 0.0
		ps.angle_max = 0.0
		ps.angular_velocity_min = 0.0
		ps.angular_velocity_max = 0.0
		ps.texture = _rainstreak()
		ps.color = Color(tint.r, tint.g, tint.b, alpha)
		var fade := Gradient.new()
		fade.offsets = PackedFloat32Array([0.0, 0.12, 0.80, 1.0])
		fade.colors = PackedColorArray([
			Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
		ps.color_ramp = fade
		add_child(ps)
		ps.emitting = true

## The long-press bomb, Butterfly Grove's way. A blast cone is the wrong verb for
## a butterfly, so the grove lifts as one and spins out in a VORTEX instead:
## every butterfly on its own expanding spiral, ALL turning the same way, which
## is what makes it read as one rising column of wings rather than as debris
## thrown from a centre. Sampled along the spiral as tween waypoints — a tween
## cannot express a parametric curve, and twelve linear steps at this speed are
## indistinguishable from one.
func _butterfly_spiral(w: float, h: float) -> void:
	_ttl = 8.0
	var centre := Vector2(w * 0.5, h * 0.52)
	var strength := clampf(_bomb_strength, 0.0, 1.0)
	# The bomb's opening beat, shared with _blast — flash only: a shockwave ring
	# belongs to an explosion, and this one is a vortex the flock turns inside.
	_detonation(centre, w, h, false)

	var n := clampi(int(lerpf(36.0, 66.0, strength)), 36, 66)
	var far := maxf(w, h) * 0.95
	var spin := 1.0 if (randi() % 2 == 0) else -1.0
	var steps := 12
	for i in n:
		var fly := TextureRect.new()
		fly.texture = _butterfly(i % 3)
		fly.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		fly.stretch_mode = TextureRect.STRETCH_SCALE
		fly.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var fw := randf_range(42.0, 92.0)
		fly.size = Vector2(fw, fw * 0.88)
		fly.pivot_offset = fly.size * 0.5
		fly.modulate = Color(1, 1, 1, 0.0)
		var a0 := float(i % 3) * (TAU / 3.0) + float(i) * 0.10 + randf_range(-0.10, 0.10)
		var turns := randf_range(1.1, 2.1) * (0.8 + 0.5 * strength)
		var r0 := randf_range(8.0, 64.0)
		var rise := randf_range(0.10, 0.44) * h     # the column drifts upward as it turns
		var dur := randf_range(2.6, 3.9)
		fly.position = centre + Vector2(cos(a0), sin(a0)) * r0 - fly.size * 0.5
		add_child(fly)
		var path := fly.create_tween()
		path.tween_interval(float(i) * 0.015)
		path.tween_property(fly, "modulate:a", 1.0, 0.16)
		for s in range(1, steps + 1):
			var u := float(s) / float(steps)
			var ang := a0 + spin * turns * TAU * u
			# y is squashed so the vortex reads as a tilted disc seen in
			# perspective rather than a flat circle drawn on the glass.
			var p := centre + Vector2(cos(ang), sin(ang) * 0.70) * lerpf(r0, far, pow(u, 0.82))
			p.y -= rise * u
			path.tween_property(fly, "position", p - fly.size * 0.5,
				dur / float(steps)).set_trans(Tween.TRANS_LINEAR)
		path.tween_callback(fly.queue_free)
		# Turning with the vortex, and beating the whole way out.
		var turn := fly.create_tween()
		turn.tween_property(fly, "rotation", spin * TAU * turns * 0.5, dur) \
			.set_trans(Tween.TRANS_LINEAR)
		var flap := fly.create_tween().set_loops()
		flap.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
		flap.tween_property(fly, "scale:x", 0.34, randf_range(0.14, 0.22))
		flap.tween_property(fly, "scale:x", 1.0, randf_range(0.14, 0.22))

## One Skywriter wind-wave: a translucent sine-band drawn as a polyline whose
## ends feather to nothing, rolling sideways while it fades in, lifts a touch
## and melts away. Each wave frees itself when its life is spent.
class _SkyWave extends Control:
	var y0 := 0.0
	var amp := 16.0
	var wavelen := 400.0
	var speed := 1.6          # phase roll, radians / s
	var thickness := 3.0
	var col := Color(1, 1, 1)
	var delay := 0.0
	var dur := 2.6
	var _t := 0.0

	func _process(dt: float) -> void:
		_t += dt
		if _t > delay + dur:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var t := _t - delay
		if t < 0.0:
			return
		var u := clampf(t / dur, 0.0, 1.0)
		# Envelope: a quick fade-in, then a long melt-out; the band also lifts
		# gently, like a gust passing through.
		var env := u / 0.25 if u < 0.25 else 1.0 - (u - 0.25) / 0.75
		var alpha := 0.32 * clampf(env, 0.0, 1.0)
		var lift := -20.0 * u
		var steps := 48
		var pts := PackedVector2Array()
		var cols := PackedColorArray()
		for s in steps + 1:
			var fx := float(s) / float(steps)
			var x := size.x * fx
			var y := y0 + lift + sin(x / wavelen * TAU + _t * speed) * amp
			pts.append(Vector2(x, y))
			# Feather the band's ends so it never cuts off at the screen edge.
			var edge := pow(sin(PI * fx), 0.7)
			cols.append(Color(col.r, col.g, col.b, alpha * edge))
		draw_polyline_colors(pts, cols, thickness, true)
		# A thinner echo floating above gives the current a soft depth.
		for s in pts.size():
			pts[s].y -= thickness * 2.2
			cols[s].a *= 0.45
		draw_polyline_colors(pts, cols, thickness * 0.6, true)

## Anime's concentration lines (see _speed_burst): radial ink wedges anchored at
## the frame edges pointing in toward a CLEAR centre — the manga panel border
## for one beat. Each ray snaps in fast, then retreats toward its edge and fades
## over ~half a second; the whole node frees itself when the beat is over.
class _SpeedLines extends Control:
	var strength := 1.0
	var tint := Color(0.16, 0.13, 0.2)
	var _t := 0.0
	var _rays: Array = []   # [{ang, len, wid, off}]
	const DUR := 0.5

	func _ready() -> void:
		var n := int(round(30.0 * strength))
		for i in n:
			_rays.append({
				"ang": (float(i) + randf() * 0.8) / float(n) * TAU,
				"len": randf_range(0.16, 0.34),   # reach, as a fraction of the half-diagonal
				"wid": randf_range(0.014, 0.034), # angular half-width (radians)
				"off": randf() * 0.12,            # per-ray stagger (seconds)
			})

	func _process(dt: float) -> void:
		_t += dt
		if _t > DUR + 0.15:
			queue_free()
			return
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var reach := c.length() * 1.05   # past the corners, so no ray ends mid-frame
		for ray_v in _rays:
			var ray: Dictionary = ray_v
			var off: float = ray["off"]
			var u := clampf((_t - off) / DUR, 0.0, 1.0)
			if u <= 0.0 or u >= 1.0:
				continue
			# Snap in fast, melt out; the tip also retreats toward the edge.
			var env := minf(u / 0.18, 1.0) * (1.0 - smoothstep(0.35, 1.0, u))
			var ang: float = ray["ang"]
			var ln: float = ray["len"]
			var wid: float = ray["wid"]
			var tip := c + Vector2(cos(ang), sin(ang)) * reach * (1.0 - ln * (1.0 - u * 0.65))
			var p1 := c + Vector2(cos(ang - wid), sin(ang - wid)) * reach
			var p2 := c + Vector2(cos(ang + wid), sin(ang + wid)) * reach
			draw_colored_polygon(PackedVector2Array([p1, p2, tip]),
				Color(tint.r, tint.g, tint.b, 0.5 * env))
