extends "res://regression/headless/harness/script_test_base.gd"
## Headless unit tests for Bounties — the daily-task catalogue and its rules.
##
## Run:  godot --headless --path . --script res://regression/headless/harness/headless_boot.gd -- --test=res://tests/test_bounties.gd
##
## Pure data — no autoloads, no clock, no RNG. The selection is derived from the
## DATE STRING, which is the whole reason this is testable: "what does 2026-03-04
## offer?" has one answer, forever, and it is checked here rather than observed.

const SAMPLE_DATES := ["2026-01-01", "2026-01-02", "2026-02-28", "2026-02-29",
	"2026-06-15", "2026-12-31", "2027-03-04", "1999-12-31", "2000-01-01"]

func run_tests() -> void:
	_test_catalogue_integrity()
	_test_selection_is_deterministic()
	_test_selection_is_distinct()
	_test_selection_rotates()
	_test_advance_tallies()
	_test_advance_thresholds()
	_test_completion()
	_test_unknown_ids_are_inert()

func _test_catalogue_integrity() -> void:
	print("test_catalogue_integrity:")
	check("the pool has at least as many tasks as a day needs",
		Bounties.DEFS.size() >= Bounties.DAILY_COUNT)
	var kinds := [Bounties.KIND_TURNS, Bounties.KIND_ROUNDS, Bounties.KIND_RUNS,
		Bounties.KIND_WINS, Bounties.KIND_PACE]
	var seen_ids := {}
	for def: Dictionary in Bounties.DEFS:
		var id := String(def["id"])
		check("'%s' id is unique" % id, not seen_ids.has(id))
		seen_ids[id] = true
		check("'%s' has a known kind (%s)" % [id, String(def["kind"])],
			kinds.has(String(def["kind"])))
		check("'%s' has a positive goal" % id, int(def["goal"]) > 0)
		check("'%s' pays coins" % id, int(def["coins"]) > 0)
		check("'%s' has a title" % id, not String(def.get("title", "")).is_empty())
		check("'%s' has a detail line" % id, not String(def.get("detail", "")).is_empty())
		# A bounty must be worth more than the run it takes, or it is a chore.
		check("'%s' pays more than a mid-sized run" % id,
			int(def["coins"]) > int(EconomyRules.run_payout(
				"classic", 5000, false, 0, false, 0)["coins"]))

	# NO BOUNTY MAY REQUIRE PREMIUM CONTENT. A task demanding Grand would be a
	# daily reminder of a locked door for every free player.
	for def: Dictionary in Bounties.DEFS:
		var blob := (String(def.get("title", "")) + " " + String(def.get("detail", ""))).to_lower()
		for mode in GameModes.all():
			if not Entitlements.mode_requires_premium(mode.id):
				continue
			check("'%s' does not demand premium mode '%s'" % [def["id"], mode.id],
				not blob.contains(mode.title.to_lower()))

func _test_selection_is_deterministic() -> void:
	print("test_selection_is_deterministic:")
	for date: String in SAMPLE_DATES:
		var a := Bounties.for_date(date)
		var b := Bounties.for_date(date)
		check_eq("%s picks the same three every time" % date, str(a), str(b))
		check_eq("%s picks exactly %d" % [date, Bounties.DAILY_COUNT],
			a.size(), Bounties.DAILY_COUNT)
		for id: String in a:
			check("%s -> '%s' is a real bounty" % [date, id],
				not Bounties.definition(id).is_empty())

func _test_selection_is_distinct() -> void:
	print("test_selection_is_distinct:")
	# The day's three must never repeat a task — a card showing "Fuse 50 tiles"
	# twice is the bug the co-prime stride exists to make impossible, so this is
	# checked across a long span rather than on one lucky date.
	var checked := 0
	var dupes := ""
	for month in range(1, 13):
		for day in range(1, 29):
			var date := "2026-%02d-%02d" % [month, day]
			var ids := Bounties.for_date(date)
			var seen := {}
			for id: String in ids:
				if seen.has(id):
					dupes = "%s: %s" % [date, id]
				seen[id] = true
			checked += 1
	check_eq("336 dates checked", checked, 336)
	check("no date ever repeats a bounty (%s)" % ("ok" if dupes == "" else dupes),
		dupes == "")

func _test_selection_rotates() -> void:
	print("test_selection_rotates:")
	# Consecutive days should not all offer the identical set, or "daily" is a
	# fiction. Not every adjacent pair has to differ, but the month must.
	var sets := {}
	var leads := {}
	for day in range(1, 29):
		var ids := Bounties.for_date("2026-05-%02d" % day)
		sets[str(ids)] = true
		leads[ids[0]] = true
	check("a month offers more than one distinct set (%d)" % sets.size(),
		sets.size() > 1)
	# The date must drive the STARTING slot, not only the stride. With a fixed
	# start the sets still appear to rotate (the stride varies) while the first
	# task is silently the same every single day — a partial loss that a
	# set-level check alone cannot see.
	check("the day's FIRST bounty is not always the same task (%d distinct)"
		% leads.size(), leads.size() > 1)
	# And the leading task must not simply be the head of the pool forever.
	var always_first_def := true
	for day in range(1, 29):
		if Bounties.for_date("2026-07-%02d" % day)[0] != String(Bounties.DEFS[0]["id"]):
			always_first_def = false
			break
	check("the day's first bounty is not pinned to DEFS[0]", not always_first_def)

func _test_advance_tallies() -> void:
	print("test_advance_tallies:")
	# A tally kind advances by the amount reported.
	check_eq("rounds advance a round bounty",
		Bounties.advance("rounds_5", Bounties.KIND_ROUNDS, 3), 3)
	check_eq("turns advance a turn bounty",
		Bounties.advance("turns_100", Bounties.KIND_TURNS, 1), 1)
	check_eq("runs advance a run bounty",
		Bounties.advance("runs_3", Bounties.KIND_RUNS, 1), 1)
	check_eq("wins advance a win bounty",
		Bounties.advance("win_3", Bounties.KIND_WINS, 1), 1)
	# THE WRONG EVENT MUST NOT ADVANCE IT. Cross-talk here would mean placing
	# marks quietly finished the task that asks you to win rounds.
	check_eq("turns do not advance a round bounty",
		Bounties.advance("rounds_5", Bounties.KIND_TURNS, 50), 0)
	check_eq("rounds do not advance a win bounty",
		Bounties.advance("win_3", Bounties.KIND_ROUNDS, 99), 0)
	check_eq("a zero amount advances nothing",
		Bounties.advance("rounds_5", Bounties.KIND_ROUNDS, 0), 0)
	check_eq("a negative amount advances nothing",
		Bounties.advance("rounds_5", Bounties.KIND_ROUNDS, -5), 0)

func _test_advance_thresholds() -> void:
	print("test_advance_thresholds:")
	# rival is a THRESHOLD, not a tally: three wins over Steady must never add up to
	# Expert, and a Perfect run finishes the Expert task outright.
	check_eq("a Sharp run does not touch the Expert task",
		Bounties.advance("pace_expert", Bounties.KIND_PACE, 2), 0)
	check_eq("an Expert run completes the Expert task",
		Bounties.advance("pace_expert", Bounties.KIND_PACE, 3), 3)
	check_eq("a Perfect run also completes the Expert task",
		Bounties.advance("pace_expert", Bounties.KIND_PACE, 4), 3)
	check_eq("beating Steady does not touch it either",
		Bounties.advance("pace_expert", Bounties.KIND_PACE, 1), 0)
	# Repeated reports cannot over-fill it either — the step is always the goal.
	check_eq("a threshold step never exceeds the goal",
		Bounties.advance("pace_expert", Bounties.KIND_PACE, 99999),
		Bounties.goal("pace_expert"))

func _test_completion() -> void:
	print("test_completion:")
	check("below the goal is incomplete", not Bounties.complete("turns_100", 99))
	check("exactly the goal completes", Bounties.complete("turns_100", 100))
	check("past the goal stays complete", Bounties.complete("turns_100", 10000))
	check_eq("goal reads from the catalogue", Bounties.goal("turns_100"), 100)
	check_eq("coins read from the catalogue", Bounties.coins("turns_100"), 120)
	check_eq("kind reads from the catalogue",
		Bounties.kind("turns_100"), Bounties.KIND_TURNS)

func _test_unknown_ids_are_inert() -> void:
	print("test_unknown_ids_are_inert:")
	# A save carrying a RETIRED bounty id must not crash the card that renders it
	# or hand out a reward. Goal 0 means it reads as complete, which is the safe
	# direction: an inert leftover, never an unreachable task blocking the row.
	check("an unknown id has no definition", Bounties.definition("__nope__").is_empty())
	check_eq("an unknown id has no goal", Bounties.goal("__nope__"), 0)
	check_eq("an unknown id pays nothing", Bounties.coins("__nope__"), 0)
	check_eq("an unknown id has no kind", Bounties.kind("__nope__"), "")
	check_eq("an unknown id cannot be advanced",
		Bounties.advance("__nope__", Bounties.KIND_TURNS, 100), 0)
	# The stride helper must stay safe at the degenerate sizes.
	check_eq("a one-task pool strides by 1", Bounties.coprime_stride(12345, 1), 1)
	check_eq("an empty pool strides by 1", Bounties.coprime_stride(0, 0), 1)
