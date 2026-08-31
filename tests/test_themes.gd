extends "res://regression/headless/harness/script_test_base.gd"
## Headless sanity tests for the theme catalog.
## Run:  godot --headless --path . --script res://regression/headless/harness/headless_boot.gd -- --test=res://tests/test_themes.gd
##
## Validates every theme .tres against the feature contract (valid fx_style /
## board_style / background_id), that the manifest and files agree, and that the
## free/premium gating is exactly the curated set. Pure data — no autoloads — so
## it runs under --script. Exits non-zero on any failure.

const ThemeIds := preload("res://data/themes/theme_ids.gd")
const THEME_DIR := "res://data/themes/"

# Must mirror theme_data.gd @export_enum + theme_manager.gd ramps/accents.
const VALID_FX := ["calm", "playful", "arcade", "living", "vivid"]
const VALID_BOARD := ["plain", "gold", "silver", "crystal", "molten",
	"deep", "jade", "phantom", "shadow", "desert", "toxic", "rose", "emerald",
	"ruby", "biolum", "amethyst", "bronze", "matrix",
	"rgb", "void", "astral", "ink", "plasma", "nova", "comet", "atlas",
	# Added so no theme falls back to the generic accent->gold ramp (which ended
	# gold whatever the palette was) or shares another theme's tiles.
	"aurora", "dawn", "firefly", "stellar", "storm", "press", "sand", "onyx",
	"origami", "hoarfrost", "foliage", "bloodmoon", "coral", "koi", "duskbloom",
	"lantern", "lacquer", "nebula", "vapor",
	"cel", "crt", "confect", "bigtop", "pastelpop",
	"honey", "diamond", "morpho", "plume",
	"marble", "noir", "mono", "wash", "bismuth", "azure", "lagoon",
	"savanna", "redwood"]
# Every motif BoardFx._rebuild()'s dispatch knows how to render.
const VALID_MOTIF := ["snow", "petals", "rain", "code", "embers", "bubbles",
	"stars", "space", "fireflies", "firefly_night", "aurora", "fog", "confetti", "neon", "neon_rain",
	"motes", "gradient", "arcade_pop", "candy", "lightdust", "stardrift", "flecks", "anime",
	"rain_gold", "rain_silver", "rain_diamond", "crystal",
	"embers_lux", "deep_sea", "biolum", "moonlit", "phantom", "shadow",
	"desert_night", "desert", "toxic", "blood_moon", "sunset", "nebula", "grid", "leaves",
	"lanterns", "gems", "balloons", "fireworks", "hearts",
	"bonsai", "zen_sand", "origami",
	"circuit", "blackhole", "starmap", "inkwash", "serpent",
	"koi", "metaballs", "katana", "gears", "stained_glass",
	"forge", "skywriter", "star_atlas",
	"honeycomb", "butterflies", "plumage",
	"marble", "noir", "mono", "wash", "bismuth", "altitude", "lagoon",
	"savanna", "redwood"]
# Must mirror Achievements.DEFS keys. A constant copy, NOT a load of the autoload
# script: compiling an autoload from a --script test runs before the autoload
# globals exist, and the cached failed compile breaks the real singleton.
func run_tests() -> void:
	_test_manifest_and_files()
	_test_each_theme_contract()
	_test_gating()

func _test_manifest_and_files() -> void:
	var seen := {}
	for id in ThemeIds.IDS:
		check("no duplicate id: %s" % id, not seen.has(id))
		seen[id] = true
		check("%s.tres exists" % id, ResourceLoader.exists(THEME_DIR + String(id) + ".tres"))

func _test_each_theme_contract() -> void:
	for id in ThemeIds.IDS:
		var path := THEME_DIR + String(id) + ".tres"
		if not ResourceLoader.exists(path):
			continue
		var td := load(path) as ThemeData
		check("%s loads as ThemeData" % id, td != null)
		if td == null:
			continue
		check("%s has a display_name" % id, not td.display_name.is_empty())
		check("%s fx_style valid (%s)" % [id, td.fx_style], VALID_FX.has(td.fx_style))
		check("%s board_style valid (%s)" % [id, td.board_style], VALID_BOARD.has(td.board_style))
		check("%s background_id renderable (%s)" % [id, td.background_id],
			VALID_MOTIF.has(td.background_id))
		check("%s category valid (%s)" % [id, td.category],
			["minimal", "aesthetic", "fun", "premium", "shop"].has(td.category))
		# Shop themes and the "shop" category must agree both ways: a .tres that
		# says "shop" with no price would be unbuyable, and a priced theme whose
		# .tres says otherwise would sit in the wrong picker section.
		check("%s shop category <-> SHOP_THEMES agree" % id,
			(td.category == "shop") == Entitlements.theme_is_shop(String(id)))

func _test_gating() -> void:
	# The free set is exactly Koi Garden, which is also the boot theme; everything
	# else is premium by the default-premium rule (shop themes excepted).
	check("exactly 5 free themes", Entitlements.FREE_THEMES.size() == 5)
	for id in ["starforged", "obsidian", "neon_blue", "cosmic_nebula", "vaporwave"]:
		check("%s stays free" % id, not Entitlements.theme_requires_premium(id))
	for id in ["ocean", "firefly_night", "sakura_pink", "space", "koi_garden",
			"emerald", "ruby", "crystal_storm",
			"autumn", "daybreak", "paper",
			"lantern_festival", "carnival", "candy_pop",
			# Never on the reward ladder, and not on the shop ladder either.
			"skywriter", "star_atlas",
			# The ten of 2026-08-27: premium by the default rule, no wiring of their own.
			"carrara", "noir", "mono", "aquarelle", "bismuth", "altitude",
			"lagoon", "savanna", "redwood"]:
		check("%s is premium" % id, Entitlements.theme_requires_premium(id))
	# Arctic left the free set for the shop ladder, and opens it as the cheapest.
	check("arctic is a shop theme", Entitlements.theme_is_shop("arctic"))
	_test_shop_themes()

func _test_shop_themes() -> void:
	# Shop themes: bought with gems, never with money, never premium-gated, each
	# in the manifest with a .tres on disk and a real price.
	check("the shop has 11 themes", Entitlements.SHOP_THEMES.size() == 11)
	for id in Entitlements.SHOP_THEMES:
		var sid := String(id)
		check("%s has a positive gem price" % sid, Entitlements.theme_price(sid) > 0)
		check("%s is not premium-gated" % sid, not Entitlements.theme_requires_premium(sid))
		check("%s is flagged as shop" % sid, Entitlements.theme_is_shop(sid))
		check("%s is in the theme manifest" % sid, ThemeIds.IDS.has(sid))
		check("%s is not also free" % sid, not Entitlements.FREE_THEMES.has(sid))

	# GRANDFATHERING INTEGRITY. These twelve used to be earned with a badge, and
	# EntitlementManager still honours that badge so nobody loses a theme they
	# worked for. Every shop theme must therefore keep a legacy badge, and every
	# legacy badge must be a REAL one — a typo here silently repossesses a theme
	# from every player who earned it, and nothing at runtime would say so.
	check("every shop theme keeps a legacy badge",
		Entitlements.LEGACY_REWARD_BADGES.size() == Entitlements.SHOP_THEMES.size())
	for id in Entitlements.SHOP_THEMES:
		var badge := Entitlements.legacy_reward_badge(String(id))
		check("%s has a legacy badge" % id, not badge.is_empty())
		check("%s legacy badge '%s' exists in Achievements.DEFS" % [id, badge],
			Achievements.DEFS.has(badge))
	# The legacy pairing stays 1:1 — two themes grandfathered off one badge would
	# hand a second theme to anyone holding it.
	var seen := {}
	for id in Entitlements.LEGACY_REWARD_BADGES:
		var badge := Entitlements.legacy_reward_badge(String(id))
		check("legacy badge '%s' maps to only one theme" % badge, not seen.has(badge))
		seen[badge] = true
	# The prices are a LADDER, not a flat rate — a shop where everything costs the
	# same has no entry point and no showpiece.
	var prices := {}
	for id in Entitlements.SHOP_THEMES:
		prices[Entitlements.theme_price(String(id))] = true
	check("shop prices span more than one value", prices.size() > 1)
	check("arctic is the cheapest shop theme",
		Entitlements.theme_price("arctic") == prices.keys().min())
