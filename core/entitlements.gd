class_name Entitlements
extends RefCounted
## Entitlements — the single switchboard for what is FREE vs PREMIUM.
##
## Pure data + static helpers with ZERO node/engine dependencies, so it is
## unit-testable (see tests/test_entitlements.gd) and callable from anywhere.
## This is the ONE file to edit to move a feature in or out of the premium tier.
##
## Design rule: modes and themes DEFAULT to premium unless explicitly listed as
## free below, so any new content added later rewards buyers automatically.
## Pre-launch you may flip features either way freely; AFTER launch only ever
## LOOSEN (premium -> free), never tighten, or you revoke something free players
## already had.
##
## Premium itself is a ONE-TIME lifetime unlock (not a subscription). This file
## describes *what* is gated; EntitlementManager owns *whether* the player owns
## it; the billing phase owns *where* that ownership comes from.

# --- Modes --------------------------------------------------------------------
## Modes that are free. Everything else (Arena, Quantum, Cube, Orbit) is premium.
const FREE_MODES: Array[String] = ["classic", "sprint", "lock", "twist"]

# --- Themes -------------------------------------------------------------------
## The free set is ONE theme: Koi Garden, which is also what the app boots into.
## Everything else in data/themes/ is premium by the default-premium rule, except
## the shop themes below (bought with earned gems, never with money). The Themes
## picker's sections follow OWNERSHIP, not this catalogue split: My Themes holds
## everything the player can wear (free, bought, grandfathered or premium), and
## Gem Shop / Premium hold only what is still locked (ThemeManager.grouped_themes).
##
## ONE free theme has a consequence worth knowing before you edit this list: a
## player who has bought nothing owns exactly one theme, so "Surprise me" has
## nothing to roll to until they spend their first gems, and every theme-switch
## test has to unlock a second theme deliberately instead of assuming a free pair.
## The free set is the neon-dark five, the game's own look; Starforged is the boot
## default. Everything else is premium by the default-premium rule, except the
## shop themes below.
const FREE_THEMES: Array[String] = [
	"starforged",     # the boot default
	"obsidian",
	"neon_blue",
	"cosmic_nebula",
	"vaporwave",
]

# --- Shop themes (bought with gems, never with money) --------------------------
## theme id -> its price in GEMS. Shop themes live OUTSIDE the free/premium split
## entirely: they are bought with currency the player earns, are never part of
## the premium bundle, and can never be bought with real money — so a lifetime
## buyer and a free player reach them by exactly the same road.
##
## Eleven of these twelve WERE the reward themes: one fixed theme per achievement
## badge. Badges now pay GEMS instead, which buy any theme in any order — the
## same motivation loop with the player choosing the payout. LEGACY_REWARD_BADGES
## below is what keeps that change from taking anything away.
##
## The twelfth is Bioluminescence, which was never earned with anything: it took
## Koi Garden's slot, price and badge when Koi Garden became the free theme.
##
## Prices are a ladder, not a flat rate: Arctic opens the shop cheaply (it was
## the first-merge payout and is still the first thing most players can afford)
## and Nova Forge closes it as the showpiece. The full set costs 415 gems
## against a lifetime supply of roughly 550 — so a completionist gets every
## theme AND the permanent upgrades, but only just, and only by finishing the
## badge list. Retune here and nowhere else; EconomyRules owns the earn side.
const SHOP_THEMES: Dictionary = {
	"arctic":          15,   # Glacier Dawn — the entry purchase
	"circuit_pulse":   20,   # Circuit Pulse (dark motherboard)
	"ink_wash":        25,   # painted in the well
	"bioluminescence": 25,   # the water answers your hands
	"ember_serpent":   30,   # the creature theme
	"antigrav":        30,   # weightless metaballs
	"clockwork":       35,   # like clockwork
	"ronin":           40,   # devotion of the blade
	"event_horizon":   40,   # Infinity — the singularity
	"sanctum":         50,   # the cathedral of the sky
	"nova_forge":      60,   # the forge a star is hammered from
}

## The badge each shop theme USED to be the payout for, back when themes were
## earned rather than bought. Two jobs, neither of them an entitlement:
##
## 1. GRANDFATHERING. A player who already earned a theme keeps it, free,
##    forever — EntitlementManager still honours the badge, so this change can
##    never take a theme off someone who did the work for it. That is the
##    "only ever LOOSEN" rule at the top of this file: reclassifying earned
##    content is a tightening unless the old road stays open.
## 2. COSMETICS. Badge chips and unlock toasts wear their historic theme's
##    accent (ThemeManager.badge_accent), which is a nice bit of identity and
##    costs nothing to keep.
##
## Nothing here gates anything for a NEW player: they see gem prices only.
##
## EVERY ROW MUST NAME A CROWN THIS GAME ACTUALLY HAS. The sibling projects each
## left rows here naming achievements their own DEFS had never carried, so themes
## sat in the shop advertising a reward nobody could earn. These hang off
## NUMSLIDE's own crowns, one per board, so a player who masters a board is
## handed the theme that suits it.
## test_entitlements pins the map's shape; test_themes pins that every badge here
## is a real DEFS id.
const LEGACY_REWARD_BADGES: Dictionary = {
	"arctic":          "first_solve",
	"circuit_pulse":   "classic_series",
	"event_horizon":   "twist_series",
	"ink_wash":        "lock_series",
	"ember_serpent":   "sprint_series",
	"bioluminescence": "perfect_run",
	"antigrav":        "streak_7",
	"ronin":           "streak_30",
	"clockwork":       "lock_master",
	"sanctum":         "fog_series",
	"nova_forge":      "perfect_pace",
}

# --- Capabilities (toggles, not list items) -----------------------------------
## true = the capability requires premium. Unknown ids default to FREE.
const CAPABILITIES := {
	"unlimited_undo": true,
	"no_ads": true,
	"cloud_sync": true,      # reserved for PGS Saved Games (deferred)
	"advanced_stats": true,  # reserved for the stats phase
}

## How many undos a FREE player gets per game (for modes that allow undo at all).
## Premium players (the "unlimited_undo" capability) are uncapped.
const FREE_UNDO_LIMIT := 1

# --- Queries ------------------------------------------------------------------
static func mode_requires_premium(id: String) -> bool:
	return not FREE_MODES.has(id)

static func theme_requires_premium(id: String) -> bool:
	# Shop themes are bought with earned gems, not with money — never premium-gated.
	return not FREE_THEMES.has(id) and not SHOP_THEMES.has(id)

static func theme_is_shop(id: String) -> bool:
	return SHOP_THEMES.has(id)

## What `id` costs in gems (0 for anything that is not a shop theme — free and
## premium themes are not for sale at any price).
static func theme_price(id: String) -> int:
	return int(SHOP_THEMES.get(id, 0))

## The badge that used to pay this theme out ("" for everything else). Callers
## use it for grandfathering and for badge accent colours — NEVER as a price or
## a premium check. See LEGACY_REWARD_BADGES.
static func legacy_reward_badge(id: String) -> String:
	return String(LEGACY_REWARD_BADGES.get(id, ""))

## Reverse lookup: the theme a badge historically paid out ("" if it paid none).
static func badge_legacy_theme(badge: String) -> String:
	for id in LEGACY_REWARD_BADGES:
		if String(LEGACY_REWARD_BADGES[id]) == badge:
			return String(id)
	return ""

static func capability_requires_premium(id: String) -> bool:
	return bool(CAPABILITIES.get(id, false))

static func free_undo_limit() -> int:
	return FREE_UNDO_LIMIT
