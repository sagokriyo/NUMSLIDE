extends "res://regression/headless/harness/script_test_base.gd"
## Headless unit tests for the Entitlements catalog (pure data, no autoloads).
## Run:  godot --headless --path . --script res://regression/headless/harness/headless_boot.gd -- --test=res://tests/test_entitlements.gd
##
## Mirrors tests/test_game_board.gd: pure static logic, deterministic, exits
## non-zero on any failure so it can gate CI later. This locks down the free vs
## premium split so an accidental edit to the catalog is caught immediately.

func run_tests() -> void:
	_test_modes()
	_test_themes()
	_test_capabilities()
	_test_undo_limit()

func _test_modes() -> void:
	print("test_modes:")
	check("classic is free", not Entitlements.mode_requires_premium("classic"))
	check("sprint is free", not Entitlements.mode_requires_premium("sprint"))
	check("lock is free", not Entitlements.mode_requires_premium("lock"))
	check("twist is free", not Entitlements.mode_requires_premium("twist"))
	check("fog is premium", Entitlements.mode_requires_premium("fog"))
	for m in GameModes.all():
		check("free mode '%s' is a real mode" % m.id, GameModes.has_mode(m.id))
	for id in Entitlements.FREE_MODES:
		check("FREE_MODES entry '%s' names a real mode" % id, GameModes.has_mode(id))
	check("retired colossus defaults to premium", Entitlements.mode_requires_premium("colossus"))
	check("dormant 'zen' defaults to premium", Entitlements.mode_requires_premium("zen"))
	check("unknown mode defaults to premium", Entitlements.mode_requires_premium("nonexistent"))

func _test_themes() -> void:
	print("test_themes:")
	check("starforged (the boot default) is free",
		not Entitlements.theme_requires_premium("starforged"))
	check("koi_garden is not ALSO on the gem ladder",
		not Entitlements.theme_is_shop("koi_garden"))
	# The swap, both halves. Bioluminescence took Koi Garden's slot whole — price,
	# ladder position and badge — so half a swap (a free theme still for sale, or a
	# shop slot with no grandfathering road) has to fail here rather than on a shelf.
	check("bioluminescence took Koi Garden's shop slot at its price",
		Entitlements.theme_is_shop("bioluminescence")
			and Entitlements.theme_price("bioluminescence") == 25)
	check("...and its perfect_run badge, so the slot keeps a grandfathering road",
		Entitlements.legacy_reward_badge("bioluminescence") == "perfect_run")
	check("koi_garden kept no legacy badge once it went free",
		Entitlements.legacy_reward_badge("koi_garden").is_empty())
	check("perfect_run now reverses to bioluminescence",
		Entitlements.badge_legacy_theme("perfect_run") == "bioluminescence")
	check("arctic is now a shop theme", Entitlements.theme_is_shop("arctic"))
	check("arctic is priced in gems", Entitlements.theme_price("arctic") > 0)
	check("arctic is not premium-gated (shop themes never are)",
		not Entitlements.theme_requires_premium("arctic"))
	# The legacy badge map is what grandfathers players who EARNED a theme back
	# when it was a badge payout. Losing this entry would silently repossess the
	# theme from everyone who did the work for it.
	check("arctic is the First Board reward",
		Entitlements.legacy_reward_badge("arctic") == "first_solve")
	check("badge_legacy_theme reverses the map",
		Entitlements.badge_legacy_theme("first_solve") == "arctic")
	# A row naming a crown that is not in DEFS is a theme nobody can ever earn.
	for theme_id: String in Entitlements.LEGACY_REWARD_BADGES:
		check("'%s' names a real crown" % theme_id,
			Achievements.DEFS.has(String(Entitlements.LEGACY_REWARD_BADGES[theme_id])))
	check("an unmapped badge reverses to nothing",
		Entitlements.badge_legacy_theme("not_a_badge").is_empty())
	check("skywriter is premium, not shop",
		Entitlements.theme_requires_premium("skywriter") and not Entitlements.theme_is_shop("skywriter"))
	check("star_atlas is premium, not shop",
		Entitlements.theme_requires_premium("star_atlas") and not Entitlements.theme_is_shop("star_atlas"))
	# A premium theme is not for sale at any price — theme_price must not become
	# a back door into the premium catalog.
	check("premium themes carry no gem price", Entitlements.theme_price("skywriter") == 0)
	check("free themes carry no gem price", Entitlements.theme_price("starforged") == 0)
	check("daybreak is now premium", Entitlements.theme_requires_premium("daybreak"))
	check("obsidian is free (the neon-dark set)", not Entitlements.theme_requires_premium("obsidian"))
	check("koi_garden is premium here", Entitlements.theme_requires_premium("koi_garden"))
	check("paper is now premium", Entitlements.theme_requires_premium("paper"))
	check("ocean is now premium", Entitlements.theme_requires_premium("ocean"))
	# Every theme that has ever been in the free set and is not in it now. A
	# retier that forgets to take one back leaves the tier quietly wider than
	# the one theme this catalogue claims to give away.
	check("space is now premium", Entitlements.theme_requires_premium("space"))
	check("carnival is now premium", Entitlements.theme_requires_premium("carnival"))
	check("candy_pop is now premium", Entitlements.theme_requires_premium("candy_pop"))
	check("luxe theme raining_gold is premium", Entitlements.theme_requires_premium("raining_gold"))
	check("luxe theme crystal_storm is premium", Entitlements.theme_requires_premium("crystal_storm"))
	check("the free set is the neon-dark five", Entitlements.FREE_THEMES.size() == 5)

func _test_capabilities() -> void:
	print("test_capabilities:")
	check("unlimited_undo is premium", Entitlements.capability_requires_premium("unlimited_undo"))
	check("no_ads is premium", Entitlements.capability_requires_premium("no_ads"))
	check("cloud_sync is premium", Entitlements.capability_requires_premium("cloud_sync"))
	check("unknown capability defaults to free", not Entitlements.capability_requires_premium("teleport"))

func _test_undo_limit() -> void:
	print("test_undo_limit:")
	check("free undo limit is 1", Entitlements.free_undo_limit() == 1)
