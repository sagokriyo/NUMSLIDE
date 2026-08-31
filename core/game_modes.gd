class_name GameModes
extends RefCounted
## GameModes — every way to slide, as data.
##
## A mode is a config dictionary, never code: the gameplay conductor reads the
## flags to pick a board shape, a rule plug-in, a clock and a scramble depth.
## Adding a mode is adding a config here (plus its lesson, icon and achievement,
## which the suites check for). The engine stays untouched.
##
## The field names `board_size`, `win_target`, `mastery_target`, `allow_undo`,
## `has_timer`, `time_limit`, `show_elapsed` and `topology` are kept from the
## sibling projects on purpose: the shell screens (Home, Badge, Profile,
## Statistics, Leaderboard, Mode Select) read them by name.

## A single mode's rules. RefCounted so it is cheap to pass around.
class Mode extends RefCounted:
	var id: String
	var title: String
	var tagline: String
	var icon: String              # fallback glyph when no icon image is present
	var icon_path: String         # IconLibrary id or PNG path (preferred over glyph)
	## Which glossy play circle deals this board (IconLibrary's six variants).
	var play_icon: String = "play_blue"
	## The tray is board_size wide and `rows` tall (0 = square).
	var board_size: int = 4
	var rows: int = 0
	## The rule plug-in the engine loads. One of RULES below.
	var rule: String = "classic"
	## Board shapes the player may pick before a run. Empty = only board_size.
	## Only Classic offers a choice; every other mode is authored at one size,
	## because its rule was tuned for that size.
	var sizes: Array[int] = []
	## Kept for the shell, which counts a finished board as a won "series" of one.
	var win_target: int = 1
	## Boards solved on this mode that count as "mastered" on the rank ladder.
	## 0 = same as MASTERY_DEFAULT. See mastery_yardstick().
	var mastery_target: int = 0
	var continue_after_win: bool = true
	var has_timer: bool = false
	var time_limit: float = 0.0   # seconds on the clock (0 = none)
	var move_time: float = 0.0    # unused here; the shell reads it
	var allow_undo: bool = true
	var deterministic: bool = false  # date-seeded (the Daily board)
	var show_elapsed: bool = false
	## Board shape. "square" for a flat tray, "twist" for the tray played on the
	## junctions between tiles.
	var topology: String = "square"
	## True when the tray has no hole in it and moves rotate whole lines.
	var no_blank: bool = false
	## Tile numbers hide once the run starts.
	var blind: bool = false
	## The world this mode wears regardless of the player's theme ("" = theirs).
	var theme_id: String = ""
	## Release wave: "launch" | "w2" | "w3".
	var tier: String = "launch"
	## The one line the Academy teaches first.
	var lesson: String = ""
	## What the board says it is asking of you, shown under the title. The
	## sibling project put a rival's line here; a puzzle has no rival, so the
	## board states its own terms.
	var challenge: String = ""

	func _init(cfg: Dictionary) -> void:
		id = cfg.get("id", "classic")
		title = cfg.get("title", "Classic")
		tagline = cfg.get("tagline", "")
		icon = cfg.get("icon", "▤")
		icon_path = cfg.get("icon_path", "")
		play_icon = cfg.get("play_icon", "play_blue")
		board_size = cfg.get("board_size", 4)
		rows = cfg.get("rows", 0)
		rule = cfg.get("rule", "classic")
		var raw_sizes: Array = cfg.get("sizes", [])
		sizes = []
		for s in raw_sizes:
			sizes.append(int(s))
		win_target = cfg.get("win_target", 1)
		mastery_target = cfg.get("mastery_target", 0)
		continue_after_win = cfg.get("continue_after_win", true)
		has_timer = cfg.get("has_timer", false)
		time_limit = cfg.get("time_limit", 0.0)
		move_time = cfg.get("move_time", 0.0)
		allow_undo = cfg.get("allow_undo", true)
		deterministic = cfg.get("deterministic", false)
		show_elapsed = cfg.get("show_elapsed", false)
		topology = cfg.get("topology", "square")
		no_blank = cfg.get("no_blank", false)
		blind = cfg.get("blind", false)
		theme_id = cfg.get("theme_id", "")
		tier = cfg.get("tier", "launch")
		lesson = cfg.get("lesson", "")
		challenge = cfg.get("challenge", "")

	## Boards solved that the rank ladder asks for on this mode.
	func mastery_yardstick() -> int:
		return mastery_target if mastery_target > 0 else MASTERY_DEFAULT

	## Kept for the shell: a NUMSLIDE run is one board, so a "series" is one round.
	func best_of() -> int:
		return win_target * 2 - 1

	func is_twist() -> bool:
		return topology == "twist"

	## True when the player may pick a board size before the run.
	func has_size_choice() -> bool:
		return sizes.size() > 1

	## The size to deal when the player has not picked one.
	func default_size() -> int:
		return board_size

	# Kept for the shell: nothing here is a board of boards, a globe or a solid.
	func is_cube() -> bool:
		return false

	func is_meta() -> bool:
		return false

	func is_globe() -> bool:
		return false

	func is_hex() -> bool:
		return false

	func is_lattice() -> bool:
		return false

	func is_antimatter() -> bool:
		return false

	## Tiles a board of `n` carries, holes excluded.
	func tiles_at(n: int) -> int:
		var h := rows if rows > 0 else n
		var cells := n * h
		return cells if no_blank else cells - 1

	## Human-readable board shape for the screen header and the mode cards.
	func board_caption(n: int = 0) -> String:
		var size := n if n > 0 else board_size
		if is_twist():
			return "%d×%d · no hole" % [size, size]
		var h := rows if rows > 0 else size
		if h != size:
			return "%d wide · %d tall · %d tiles" % [size, h, tiles_at(size)]
		return "%d×%d · %d tiles" % [size, size, tiles_at(size)]

## Boards solved that count as mastering a mode when the config names no number.
const MASTERY_DEFAULT := 10

## Every rule plug-in the engine knows. A config's `rule` must be one of these
## (test_game_modes pins it), so a typo cannot ship a mode the engine cannot load.
##
## ONE RULE, ONE MODE, no exceptions. `test_game_modes` fails a rule claimed by
## two modes: five modes over five rules classes. A sliding puzzle with a clock
## on it is not a second mode, it is Classic with a clock, and a catalogue of
## those is what the sibling project spent a release learning to stop shipping.
## Rush earns its place because solving does not END a run there, it re-deals
## one; the clock is the board.
const RULES: Array[String] = ["classic", "sprint", "lock", "twist", "fog"]

const _CONFIGS := [
	# --- Launch ---------------------------------------------------------------
	{
		"id": "classic", "title": "Classic", "icon": "▤",
		"icon_path": "classic_slide", "play_icon": "play_gold",
		"tagline": "Slide the numbers back into order.",
		"board_size": 4, "sizes": [3, 4, 5], "rule": "classic",
		"allow_undo": true, "show_elapsed": true, "tier": "launch",
		"challenge": "Every board is dealt with a par. Come in under it.",
		"lesson": "Tap a tile in the hole's row or column. The whole run slides.",
	},
	{
		"id": "sprint", "title": "Rush", "icon": "⏱",
		"icon_path": "rush", "play_icon": "play_challenger",
		"tagline": "One clock. The boards never stop.",
		"board_size": 4, "rule": "sprint",
		"has_timer": true, "time_limit": 60.0,
		"allow_undo": false, "show_elapsed": false,
		"mastery_target": 6, "tier": "launch",
		"challenge": "Solving does not end the run. It buys you seconds.",
		"lesson": "Every board you clear pays time back. Clear faster than it drains.",
	},
	{
		"id": "lock", "title": "Lockdown", "icon": "⊡",
		"icon_path": "lockdown", "play_icon": "play_grand",
		"tagline": "A tile that gets home is welded there.",
		"board_size": 4, "rule": "lock",
		"allow_undo": true, "show_elapsed": true, "tier": "launch",
		"challenge": "Place them in the right order or place them never.",
		"lesson": "Tiles lock in order. The lit cells are the ones you may finish now.",
	},
	{
		"id": "twist", "title": "Twist", "icon": "⟳",
		"icon_path": "twist", "play_icon": "play_blue",
		"tagline": "No hole. Four tiles turn around the point you tap.",
		"board_size": 3, "rule": "twist", "topology": "twist", "no_blank": true,
		"allow_undo": true, "show_elapsed": true, "tier": "launch",
		"challenge": "Every turn you make fixes one tile and spins three others.",
		"lesson": "Tap a corner where four tiles meet. They pinwheel a quarter turn.",
	},
	# --- Wave 2 ---------------------------------------------------------------
	{
		"id": "fog", "title": "Blind", "icon": "◐",
		"icon_path": "blind", "play_icon": "play_silver",
		"tagline": "The numbers go out. You keep sliding.",
		"board_size": 4, "rule": "fog", "blind": true,
		"allow_undo": false, "show_elapsed": true,
		"theme_id": "shadow_fog", "tier": "w2",
		"challenge": "Only the hole lights the board. Solved tiles stay lit.",
		"lesson": "Study the board. From your first slide, only what touches the hole shows.",
	},
]

## The boards whose results may be RANKED AGAINST EACH OTHER: the three that
## deal one 4x4 tray and score it on moves against par. Rush scores boards
## cleared, Blind is played without the numbers and Cube is a different solid,
## so each of those keeps its record per mode on the Statistics screen.
const RANKED_MODES: Array[String] = ["classic", "lock", "twist"]

## The mode the Daily board is dealt on. The Daily is a FEATURE over Classic's
## rules, seeded by the date so every phone gets the same scramble. It is not a
## seventh mode and it does not get a rule of its own; the sibling project shipped
## a Daily as a mode, found it duplicated Classic exactly, and cut it.
const DAILY_MODE := "classic"
const DAILY_SIZE := 4

## True when `id`'s record belongs in the cross-board ranking.
static func is_ranked(id: String) -> bool:
	return RANKED_MODES.has(id)

## The rankable boards as Modes, in catalogue order.
static func ranked() -> Array[Mode]:
	var out: Array[Mode] = []
	for cfg in _CONFIGS:
		if RANKED_MODES.has(String(cfg["id"])):
			out.append(Mode.new(cfg))
	return out

static func all() -> Array[Mode]:
	var out: Array[Mode] = []
	for cfg in _CONFIGS:
		out.append(Mode.new(cfg))
	return out

## The modes of one release wave, in catalogue order.
static func in_tier(tier: String) -> Array[Mode]:
	var out: Array[Mode] = []
	for cfg in _CONFIGS:
		if String(cfg.get("tier", "launch")) == tier:
			out.append(Mode.new(cfg))
	return out

static func has_mode(id: String) -> bool:
	for cfg in _CONFIGS:
		if cfg["id"] == id:
			return true
	return false

static func get_mode(id: String) -> Mode:
	for cfg in _CONFIGS:
		if cfg["id"] == id:
			return Mode.new(cfg)
	return Mode.new(_CONFIGS[0])

## The seed the Daily board is dealt from, for a given date. Every phone that
## asks on the same day gets the same number, so everyone slides one board.
static func daily_seed(date: Dictionary) -> int:
	var y: int = int(date.get("year", 2026))
	var m: int = int(date.get("month", 1))
	var d: int = int(date.get("day", 1))
	return y * 10000 + m * 100 + d

## Today's Daily seed.
static func today_seed() -> int:
	return daily_seed(Time.get_date_dict_from_system())
