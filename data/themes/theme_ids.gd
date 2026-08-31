## Manifest of all theme IDs in data/themes/.
## Update this list whenever a new .tres is added.
## ThemeManager loads from this list instead of DirAccess so themes
## work reliably inside the Android APK's packed filesystem.
const IDS = [
	"daybreak",
	"anime", "arcade", "aurora", "autumn",
	"blood_moon", "candy_pop", "carnival",
	"coral_depths", "cosmic_nebula", "crystal_storm",
	"desert_midnight", "emerald",
	"firefly_night", "first_bloom", "kawaii", "koi_garden",
	"lantern_festival", "moonlit_bamboo",
	"neon_blue", "obsidian", "ocean",
	"origami_sky", "paper", "phantom_realm",
	"raining_gold", "raining_silver", "ruby", "sakura_pink",
	"shadow_fog", "space",
	"thunderstorm", "vaporwave", "zen_garden",
	"skywriter", "star_atlas",
	# Shop themes — bought with gems (Entitlements.SHOP_THEMES). Listed in price
	# order, cheapest first, so the picker's Shop section reads as a ladder the
	# player climbs; Arctic opens it and Nova Forge closes it.
	"arctic", "circuit_pulse", "ink_wash", "bioluminescence",
	"ember_serpent", "antigrav", "clockwork", "ronin",
	"event_horizon", "starforged", "sanctum", "nova_forge",
	# Premium by the default-premium rule (Entitlements): no free-set entry and
	# no SHOP_THEMES price, so they need no entitlement wiring of their own.
	"honeycomb", "raining_diamond", "butterfly_grove", "peacock",
	# The ten of 2026-08-27 (docs/themes/ten-premium-themes.md), premium by the
	# same default rule. Listed light to dark down the picker's Premium section:
	# Carrara opens it, the two showpieces sit in the middle, Noir closes it.
	"carrara", "mono", "aquarelle", "altitude", "lagoon",
	"bismuth", "savanna", "redwood", "noir",
]
