extends Node
## Text-overflow audit — NOT part of the game. Boots a screen (optionally with
## inflated stats) and prints every Label whose rendered text is WIDER than the
## box it was given, plus every Control whose minimum width outgrew the viewport.
##
## Exists because "the number ran out of its card" has two different causes that
## look identical on screen: a Label with AUTOWRAP_OFF draws past its rect when
## the container refuses to grow, and pushes the whole page off-screen when the
## container obeys. Only measuring tells you which one a given row is doing.
##
##   godot --path . res://tools/text_overflow_audit.tscn --resolution 400x866 -- statistics big
##
## Second user arg "big" seeds a save-sized-for-a-veteran (7-digit scores) so the
## worst case is what gets measured, not the developer's own save.

const SCREENS := {
	"statistics":   "res://scenes/statistics/statistics.tscn",
	"achievements": "res://scenes/achievements/achievements.tscn",
	"badge":        "res://scenes/badge/badge.tscn",
	"leaderboard":  "res://scenes/leaderboard/leaderboard.tscn",
	"profile":      "res://scenes/profile/profile.tscn",
	"home":         "res://scenes/home/home.tscn",
	"gameplay":     "res://scenes/gameplay/gameplay.tscn",
	"settings":     "res://scenes/settings/settings.tscn",
	"themes":       "res://scenes/themes/themes.tscn",
	"how_to_play":  "res://scenes/how_to_play/how_to_play.tscn",
	"shop":         "res://scenes/shop/shop.tscn",
	"premium":      "res://scenes/premium/premium.tscn",
}

## The HUD members every mode screen keeps its live numbers in. Forced to the
## widest a long run reaches, because nobody is going to play to seven figures
## inside a probe.
const HUD_MEMBERS := ["_score_value", "_best_value", "_score_label", "_best_label"]

var _screen: Node
var _t := 0.0
var _done := false
var _key := "statistics"
var _hud_text := "1,234,567"
var _wide_floor := 0.0

func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		_key = String(a[0])
	if a.size() > 1 and String(a[1]) == "big":
		_seed_big()
	if a.size() > 4:
		_wide_floor = float(String(a[4]))
	if a.size() > 3:
		_hud_text = String(a[3])
	if a.size() > 2:
		for part in String(a[2]).split(","):
			SHOTS.append(int(part))
	var path: String = String(SCREENS.get(_key, SCREENS["statistics"]))
	if _key == "gameplay":
		SceneRouter._payload = {"mode": "classic", "continue": false}
	_screen = (load(path) as PackedScene).instantiate()
	add_child(_screen)
	await get_tree().process_frame
	await get_tree().process_frame
	# A live run's SCORE is the number that grows all game; force it to the
	# widest it ever gets rather than waiting for someone to play there.
	for member in HUD_MEMBERS:
		var lbl: Label = _screen.get(member) as Label
		if lbl != null:
			lbl.text = _hud_text

## A veteran's save, IN MEMORY ONLY. Every write goes straight into SaveManager's
## live dictionary rather than through set_section(), because set_section marks
## the store dirty and the debounced writer then persists this fiction over the
## developer's real save — which is exactly what it did the first time this probe
## ran. `_seal()` afterwards tells the lifecycle hook there is nothing to write.
func _seed_big() -> void:
	var s: Dictionary = GameStats._s
	s["best_score"] = 1234567
	s["highest_tile"] = 131072
	s["games_played"] = 12480
	s["games_won"] = 8321
	s["total_score"] = 987654321
	s["total_moves"] = 4562130
	s["total_merges"] = 1250000
	s["total_play_seconds"] = 987654.0
	s["longest_session_seconds"] = 45678.0
	s["current_streak_days"] = 365
	var modes: Dictionary = s["modes"]
	for m in MODES:
		modes[m] = {"games": 2480, "wins": 1200, "time": 123456.0,
			"best": 1234567, "highest": 131072}
	var bests := {}
	for m in MODES:
		bests[m] = 1234567
	SaveManager._data["best_scores"] = bests
	# The Recent Runs rail reads the dated history, not the bests — a rail of
	# four-figure runs proves nothing about a card built for seven.
	var hist: Array = []
	for i in 8:
		hist.append({"score": 1234567 - i * 111111, "mode": "classic",
			"t": 1787557918 - i * 86400})
	SaveManager._data["score_history"] = {"entries": hist}
	_seal()

const MODES := ["classic", "challenger", "grand", "merge_drop", "arena_fling", "tower"]

## Makes the store look already-written, so neither the debounce timer nor the
## close hook can flush this probe's fiction to disk.
func _seal() -> void:
	if SaveManager._flush_timer != null:
		SaveManager._flush_timer.stop()
	SaveManager._dirty = false
	SaveManager._flushed_hash = SaveManager._data.hash()

func _process(delta: float) -> void:
	_t += delta
	if _done or _t < 2.0:
		return
	_done = true
	await get_tree().process_frame
	await get_tree().process_frame
	var vp := get_viewport().get_visible_rect().size
	print("=== %s === viewport %.0fx%.0f" % [_key, vp.x, vp.y])
	# A PanelRail page (Profile) shows ONE tab at a time and each builds its own
	# widgets, so auditing whatever happened to be mounted audits a sixth of it.
	var rail := _find_rail(_screen)
	var tabs: int = rail.tab_count() if rail != null else 1
	for tab in tabs:
		if rail != null:
			rail.select(tab)
			await get_tree().process_frame
			await get_tree().process_frame
			print("-- tab %d --" % tab)
		print("---- labels drawing past their own box ----")
		_walk_spill(_screen)
		print("---- controls whose MIN width exceeds the viewport ----")
		_walk_wide(_screen, 0, _wide_floor if _wide_floor > 0.0 else vp.x)
	if not SHOTS.is_empty():
		await _shoot()
	# Last word before teardown: the close hook re-derives "is there anything to
	# write" from the store's hash, so anything the screens touched while we
	# looked at them is disowned here rather than landing in the real save.
	_seal()
	get_tree().quit()

func _find_rail(n: Node) -> PanelRail:
	var r := n as PanelRail
	if r != null:
		return r
	for c in n.get_children():
		var f := _find_rail(c)
		if f != null:
			return f
	return null

## Scroll offsets to photograph, filled from the third user arg ("0,900,2200").
var SHOTS: Array = []
const OUT := "C:/Users/SAIGOP~1/AppData/Local/Temp/claude/c--Users-SAI-GOPAL-OneDrive-Documents-2048/c9f72021-a7f3-49da-b5a3-d243dc0420b2/scratchpad/shots"

func _shoot() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var sc := _find_scroll(_screen)
	for i in SHOTS.size():
		if sc != null:
			sc.scroll_vertical = int(SHOTS[i])
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var err := img.save_png("%s/of_%s_%d.png" % [OUT, _key, int(SHOTS[i])])
		print("SHOT ", SHOTS[i], " err=", err)

func _find_scroll(n: Node) -> ScrollContainer:
	var sc := n as ScrollContainer
	if sc != null and sc.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
		return sc
	for c in n.get_children():
		var f := _find_scroll(c)
		if f != null:
			return f
	return null

func _walk_spill(n: Node) -> void:
	var l := n as Label
	if l != null and not l.text.is_empty() and l.size.x > 0.0:
		var minw: float = l.get_combined_minimum_size().x
		var box: float = l.size.x
		var f: Font = l.get_theme_font("font")
		var fs: int = l.get_theme_font_size("font_size")
		var w: float = 0.0
		if f != null and fs > 0:
			w = f.get_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		# SQUEEZED: the row could not fit this label and shrank it below its own
		# minimum, so it draws past whatever box it was handed.
		if box < minw - 1.0:
			_report("SQUEEZED", minw - box, l, w, box)
		# CLIPPED: clip_text keeps the layout honest but eats digits off the end.
		elif l.clip_text and w > box + 1.0:
			_report("CLIPPED ", w - box, l, w, box)
		# SPILL: no wrap, no clip — the text simply draws outside its box.
		elif not l.clip_text and w > box + 1.0 				and (l.autowrap_mode == TextServer.AUTOWRAP_OFF 					or not l.text.contains(" ")):
			# Unbreakable text (a numeral, a chevron) overflows even with autowrap
			# on, because there is no space to break at.
			_report("SPILL   ", w - box, l, w, box)
	var c := n as Control
	if c != null and c is Label and c.size.x > 0.0 and not _in_h_scroller(c):
		var r := c.get_global_rect()
		var vw: float = get_viewport().get_visible_rect().size.x
		if r.position.x < -1.0 or r.end.x > vw + 1.0:
			print("  OFFPAGE  x=[%.0f..%.0f] vw=%.0f  \"%s\"  path=%s" % [
				r.position.x, r.end.x, vw, (c as Label).text.substr(0, 30), _short(c)])
	for child in n.get_children():
		_walk_spill(child)

func _report(kind: String, over: float, l: Label, w: float, box: float) -> void:
	print("  %s %+5.0fpx  \"%s\"  (text %.0f, box %.0f) path=%s" % [
		kind, over, l.text.substr(0, 30), w, box, _short(l)])

## A rail that is MEANT to run wider than the screen (the tier rail, the score
## rail, the leaderboard pager) is not an overflow — its scroller owns the width.
func _in_h_scroller(c: Node) -> bool:
	var n: Node = c.get_parent()
	while n != null:
		var sc := n as ScrollContainer
		if sc != null and sc.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
			return true
		n = n.get_parent()
	return false

func _walk_wide(n: Node, depth: int, budget: float) -> void:
	var c := n as Control
	if c != null and not _in_h_scroller(c):
		var mw: float = c.get_combined_minimum_size().x
		if mw > budget:
			var extra := ""
			if c is Label:
				extra = "  \"" + (c as Label).text.substr(0, 24) + "\""
			print("%s%s (%s) min_x=%.0f size_x=%.0f%s" % [
				"  ".repeat(depth), c.name, c.get_class(), mw, c.size.x, extra])
	for child in n.get_children():
		_walk_wide(child, depth + 1, budget)

func _short(c: Control) -> String:
	var parts: Array[String] = []
	var n: Node = c
	var hops := 0
	while n != null and hops < 5:
		parts.push_front(n.name)
		n = n.get_parent()
		hops += 1
	return "/".join(parts)
