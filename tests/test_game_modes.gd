extends "res://regression/headless/harness/script_test_base.gd"
## The mode catalog and every table that must move with it. A mode that lands in
## GameModes but not in one of these catalogs fails HERE rather than shipping
## silently unreachable, unpaid, uncrowned or unranked.

## Home lists EVERY mode now: there is no second screen to hide any on.
const HOME_FEATURED := ["classic", "sprint", "lock", "twist", "fog"]

func run_tests() -> void:
	_test_catalog_shape()
	_test_rules_registry()
	_test_home_lists_every_mode()
	_test_every_mode_in_every_catalog()
	_test_themes_named_by_modes_exist()
	_test_board_arithmetic()

func _test_catalog_shape() -> void:
	print("test_catalog_shape:")
	var modes := GameModes.all()
	check_eq("five modes", modes.size(), 5)
	var seen := {}
	for m in modes:
		check("'%s' id is unique" % m.id, not seen.has(m.id))
		seen[m.id] = true
		check("'%s' has a title" % m.id, not m.title.is_empty())
		check("'%s' has a tagline under 60 chars" % m.id,
			not m.tagline.is_empty() and m.tagline.length() <= 60)
		check("'%s' tagline has no em dash" % m.id, not m.tagline.contains("—"))
		check("'%s' board is at least 3 wide" % m.id, m.board_size >= 2)
		check("'%s' win target is at least 1" % m.id, m.win_target >= 1)
		check("'%s' tier is launch, w2 or w3" % m.id, m.tier in ["launch", "w2", "w3"])
		check("'%s' has a lesson line" % m.id, not m.lesson.is_empty())
		check("'%s' play icon is a play circle" % m.id, m.play_icon.begins_with("play_"))
		# THE BOARD STATES ITS OWN TERMS. There is nobody on the other side of a
		# sliding puzzle, so a mode with no challenge line would open onto a tray
		# that never says what it is asking of the player.
		check("'%s' states what it asks" % m.id,
			not m.challenge.is_empty() and m.challenge.length() <= 70)
		check("'%s' challenge has no em dash" % m.id, not m.challenge.contains("—"))
		for n in m.sizes:
			check("'%s' offers a sane size %d" % [m.id, n], n >= 3 and n <= 5)
	check_eq("four launch modes", GameModes.in_tier("launch").size(), 4)
	check("get_mode falls back to the first mode", GameModes.get_mode("nope").id == modes[0].id)
	check("has_mode is honest", GameModes.has_mode("classic") and not GameModes.has_mode("nope"))
	check("only Classic offers a size choice",
		GameModes.get_mode("classic").has_size_choice()
		and not GameModes.get_mode("lock").has_size_choice())

func _test_rules_registry() -> void:
	print("test_rules_registry:")
	for m in GameModes.all():
		check("'%s' rule '%s' is a registered rule" % [m.id, m.rule], GameModes.RULES.has(m.rule))
	for r in GameModes.RULES:
		var used := false
		for m in GameModes.all():
			if m.rule == r:
				used = true
		check("rule '%s' is used by a mode" % r, used)
	# ONE RULE, ONE MODE, and there is no exception. Five modes over five rules
	# classes: nothing in the catalogue is another mode's board with a word
	# changed. A sliding puzzle with a clock bolted on is not a second mode, and
	# this check is what stops the next one arriving by accident. Rush earns its
	# place because solving does not END a run there, it re-deals one.
	var by_class := {}
	for m in GameModes.all():
		var cls := SlideRules.class_for(m.rule)
		if not by_class.has(cls):
			by_class[cls] = [] as Array[String]
		(by_class[cls] as Array[String]).append(m.id)
	for cls: String in by_class:
		var ids: Array[String] = by_class[cls]
		check_eq("%s belongs to one mode (%s)" % [cls, ", ".join(ids)], ids.size(), 1)
	check("twist has no hole in it", GameModes.get_mode("twist").no_blank)
	check("twist is played on the junctions", GameModes.get_mode("twist").is_twist())
	check("blind hides its numbers", GameModes.get_mode("fog").blind)
	check("only Rush carries a clock", GameModes.get_mode("sprint").has_timer
		and not GameModes.get_mode("classic").has_timer)

## HOME LISTS EVERY MODE. There is no second modes screen to hide one behind, so
## "listed somewhere" and "listed on Home" are now the same statement, and a mode
## added to the catalogue and not to Home is invisible.
func _test_home_lists_every_mode() -> void:
	print("test_home_lists_every_mode:")
	var home_script: Variant = load("res://scenes/home/home.gd")
	var featured: Array = home_script.FEATURED_MODE_IDS
	check_eq("Home features every mode", featured.size(), GameModes.all().size())
	for id in HOME_FEATURED:
		check("Home features '%s'" % id, featured.has(id))
	for m in GameModes.all():
		check("'%s' is on Home" % m.id, featured.has(m.id))
	for id in featured:
		check("Home entry '%s' is a real mode" % id, GameModes.has_mode(String(id)))
	var colors: Dictionary = home_script.MODE_COLORS
	for m in GameModes.all():
		check("'%s' has a Home colour story" % m.id, colors.has(m.id))

func _test_every_mode_in_every_catalog() -> void:
	print("test_every_mode_in_every_catalog:")
	for m in GameModes.all():
		check("'%s' has a win crown" % m.id, Achievements.MODE_WIN_ACHIEVEMENT.has(m.id))
		var crown := String(Achievements.MODE_WIN_ACHIEVEMENT.get(m.id, ""))
		check("'%s' crown '%s' is a real achievement" % [m.id, crown], Achievements.DEFS.has(crown))
		check("'%s' pays first-clear gems" % m.id, EconomyRules.MODE_WIN_GEMS.has(m.id))
		check("'%s' has a leaderboard slot" % m.id,
			PlayGamesIds.LEADERBOARD_BEST_SCORE_BY_MODE.has(m.id))
		check("'%s' icon '%s' resolves" % [m.id, m.icon_path],
			IconLibrary.has_icon(m.icon_path) or ResourceLoader.exists(m.icon_path))
	for id in Achievements.MODE_MASTERY_ACHIEVEMENT:
		check("mastery '%s' rides on a crown" % id, Achievements.MODE_WIN_ACHIEVEMENT.has(id))
	for id in EconomyRules.MODE_MULTIPLIER:
		check("multiplier '%s' names a real mode" % id, GameModes.has_mode(String(id)))
	for id in Entitlements.FREE_MODES:
		check("free mode '%s' is real" % id, GameModes.has_mode(String(id)))
	for id in GameModes.RANKED_MODES:
		check("ranked mode '%s' is real" % id, GameModes.has_mode(String(id)))
	check("the Daily rides on a real mode", GameModes.has_mode(GameModes.DAILY_MODE))

func _test_themes_named_by_modes_exist() -> void:
	print("test_themes_named_by_modes_exist:")
	var ids: Array = ThemeManager.all_theme_ids()
	for m in GameModes.all():
		if m.theme_id.is_empty():
			continue
		check("'%s' atmosphere theme '%s' exists" % [m.id, m.theme_id], ids.has(m.theme_id))

func _test_board_arithmetic() -> void:
	print("test_board_arithmetic:")
	var classic := GameModes.get_mode("classic")
	check_eq("a 4x4 tray carries fifteen tiles", classic.tiles_at(4), 15)
	check_eq("a 3x3 tray carries eight", classic.tiles_at(3), 8)
	check_eq("the twist tray carries every cell", GameModes.get_mode("twist").tiles_at(4), 16)
	check_eq("mastery default", classic.mastery_yardstick(), GameModes.MASTERY_DEFAULT)
	check_eq("Rush names its own mastery", GameModes.get_mode("sprint").mastery_yardstick(), 6)
	check_eq("the classic caption names the shape", classic.board_caption(4), "4×4 · 15 tiles")
	check_eq("the twist caption says there is no hole",
		GameModes.get_mode("twist").board_caption(4), "4×4 · no hole")
	# The Daily is one board for everyone: the same date is the same seed.
	var d := {"year": 2026, "month": 8, "day": 31}
	check_eq("the daily seed is the date", GameModes.daily_seed(d), 20260831)
	check_eq("the same date deals the same seed", GameModes.daily_seed(d), GameModes.daily_seed(d))
	check("a different day deals a different seed",
		GameModes.daily_seed(d) != GameModes.daily_seed({"year": 2026, "month": 9, "day": 1}))
