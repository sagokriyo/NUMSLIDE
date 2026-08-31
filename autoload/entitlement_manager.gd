extends Node
## EntitlementManager — the single runtime truth for premium ownership.
##
## Screens NEVER check purchases, billing, or the catalog directly: they ask
## this autoload (is_premium / is_mode_unlocked / is_theme_unlocked /
## has_capability). That keeps the SOURCE of premium (Google Play Billing
## ownership, cached locally) swappable without touching a single feature gate.
##
## Premium state loads from the local SaveManager cache plus a debug-only
## override for testing. grant_premium() / revoke_premium() are the seams the
## unlock sources call: BillingService grants when Play Billing reports the
## product purchased or already owned (premium follows the device's Google Play
## account).
##
## TRUST HARDENING (ship-blockers #2 and #5, see docs/premium/README.md and
## security-audit/): at boot, a non-debug build drops any cached premium whose
## source is not Play-verified (the boot-time source check). At runtime,
## BillingService reports every SUCCESSFUL Play ownership answer to
## note_play_ownership(), which revokes on persistent absence under the
## hysteresis + offline-grace rules in core/entitlement_policy.gd — that is
## the whole refund/chargeback story (no server, no RTDN).
##
## Autoload order: declared after SaveManager (it reads/writes a save section)
## and after SettingsManager. `Entitlements` is a class_name global, so it is
## available regardless of autoload order.

signal premium_changed(is_premium: bool)

const SECTION := "entitlements"

## Themes bought with gems. Theme id -> unix purchase second, so a membership
## test is a single top-level key check (the same shape as the achievements
## section, and for the same reason — see is_theme_unlocked). Wallet writes it;
## this autoload only ever reads it.
const OWNED_THEMES_SECTION := "owned_themes"

var _premium := false

func _ready() -> void:
	var data := SaveManager.get_section(SECTION, {})
	_premium = bool(data.get("premium", false))
	_enforce_boot_source_check(OS.is_debug_build())

## Boot-time source check (ship-blocker #5): in a non-debug build, only a
## Play-verified source ("play"/"restore") may keep the cached premium flag.
## Catches a hand-forged save and a tester's "debug" grant surviving an
## upgrade to a release build. A legitimate owner re-grants automatically on
## the next billing connect (queryPurchases → grant_premium("restore")).
## `is_debug` is a parameter so the release path is testable from the
## (debug-build) headless harness.
func _enforce_boot_source_check(is_debug: bool) -> void:
	if not _premium:
		return
	var data := SaveManager.get_section(SECTION, {})
	var source := String(data.get("source", ""))
	if EntitlementPolicy.boot_source_trusted(source, is_debug):
		return
	push_warning("EntitlementManager: dropping cached premium with unverified source '%s' (boot-time source check)." % source)
	_set_premium(false, "boot_source_check")

# --- Queries ------------------------------------------------------------------
func is_premium() -> bool:
	return _premium

func is_mode_unlocked(id: String) -> bool:
	return _premium or not Entitlements.mode_requires_premium(id)

func is_theme_unlocked(id: String) -> bool:
	# Shop themes are bought with earned gems, never with money and never as part
	# of the premium bundle. Read the persisted purchase record DIRECTLY: Wallet
	# (which writes it) loads long after this autoload and ThemeManager asks
	# during boot, so an autoload reference here would be null exactly when it
	# matters. Wallet.buy_theme() persists synchronously, so the section is
	# always current by the time anyone asks.
	if Entitlements.theme_is_shop(id):
		# Membership only — section_has_key answers it without deep-copying the
		# whole section, which get_section() has to do to keep its copy-isolation
		# promise. The Themes screen asks this once per theme.
		if SaveManager.section_has_key(OWNED_THEMES_SECTION, id):
			return true
		# GRANDFATHERING. These twelve used to be earned with an achievement
		# badge. A player who did that work keeps the theme, free, forever — the
		# catalog changing underneath them must never repossess it. New players
		# have no badge here and simply see the gem price.
		var badge := Entitlements.legacy_reward_badge(id)
		return not badge.is_empty() and SaveManager.section_has_key("achievements", badge)
	return _premium or not Entitlements.theme_requires_premium(id)

func has_capability(id: String) -> bool:
	return _premium or not Entitlements.capability_requires_premium(id)

## The undo budget for the current tier. -1 means unlimited (premium); otherwise
## the free per-game cap from the catalog.
func undo_limit() -> int:
	return -1 if has_capability("unlimited_undo") else Entitlements.free_undo_limit()

# --- Play ownership bookkeeping (revoke-on-absence, ship-blocker #2) ----------
## The single entry point BillingService reports every SUCCESSFUL Play
## ownership answer to. `present` = any record of our product came back
## (PENDING counts as present — a UPI "pay later" must never build an absent
## streak). Failed/offline queries are never reported, so offline grace is
## structural: no successful query ⇒ no bookkeeping ⇒ no revocation.
func note_play_ownership(present: bool) -> void:
	if present:
		SaveManager.set_section_fields(SECTION, {
			"last_seen_owned_at": int(Time.get_unix_time_from_system()),
			"absent_connects": 0,
		})
		return
	var data := SaveManager.get_section(SECTION, {})
	var streak: int = int(data.get("absent_connects", 0)) + 1
	SaveManager.set_section_fields(SECTION, {"absent_connects": streak})
	if not _premium:
		return
	var source := String(data.get("source", ""))
	if EntitlementPolicy.revoke_exempt(source, OS.is_debug_build()):
		return
	var last_seen: int = int(data.get("last_seen_owned_at", 0))
	var now := int(Time.get_unix_time_from_system())
	if EntitlementPolicy.should_revoke_on_absence(streak, last_seen, now):
		push_warning("EntitlementManager: revoking premium — product absent from Play ownership %d consecutive connects (last seen owned: %d)." % [streak, last_seen])
		revoke_premium("absent_from_play")

# --- Mutations (called by the unlock sources: purchase / restore / debug) -----
## Grants premium and persists it locally so it survives offline and restarts.
## `source` is recorded for diagnostics ("play", "restore", "debug").
func grant_premium(source: String) -> void:
	if _premium:
		return
	_set_premium(true, source)

## Revokes premium — a refund / chargeback / void from Play, or a debug reset.
func revoke_premium(reason: String) -> void:
	if not _premium:
		return
	_set_premium(false, reason)

func _set_premium(value: bool, source: String) -> void:
	_premium = value
	# A three-field merge, not a whole-section rewrite: the read only ever existed
	# to carry the OTHER keys (last_seen_owned_at / absent_connects) back in, which
	# leaving them in place does for free.
	SaveManager.set_section_fields(SECTION, {
		"premium": value,
		"source": source,
		"updated_at": int(Time.get_unix_time_from_system()),
	})
	premium_changed.emit(value)

# --- Debug (testing only) -----------------------------------------------------
## True only when the debug unlock surfaces (the paywall "simulate" button and the
## debug card) may be live. Centralised so "is a debug build" and "premium
## backdoor enabled" are decided in ONE place — a release export reports false and
## can never reach a grant path. Tighten later (e.g. `and OS.has_feature("dev")`)
## if you want internal-only unlocks separate from all debug builds.
func debug_unlock_enabled() -> bool:
	return OS.is_debug_build()

## Toggle premium without a real purchase. No-op unless debug unlock is enabled.
func debug_toggle_premium() -> void:
	if not debug_unlock_enabled():
		return
	if _premium:
		revoke_premium("debug")
	else:
		grant_premium("debug")
