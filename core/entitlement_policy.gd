class_name EntitlementPolicy
extends RefCounted
## EntitlementPolicy — pure decision rules for the trust-hardening
## ship-blockers (docs/premium/README.md "Security ship-blockers" #2 and #5;
## plans + audit trail in security-audit/). Zero node/engine dependencies so
## every rule is headlessly unit-tested by
## regression/headless/suites/test_entitlement_policy.gd.
##
## The callers are EntitlementManager (boot-time source check, absence
## bookkeeping) and — indirectly — BillingService, which reports every
## SUCCESSFUL Play ownership answer. Failed/offline queries are never
## reported, which is what makes the offline-grace guarantee structural
## rather than a condition here.

## Sources that represent real Play ownership. Anything else — "debug", a
## regression test source, or a value forged into the plaintext save — is
## unverified and must not survive a non-debug boot (ship-blocker #5).
const VERIFIED_SOURCES: Array[String] = ["play", "restore"]

## Hysteresis for revoke-on-absence (ship-blocker #2). Never revoke on a
## single empty result (Play Store cache staleness); a streak of
## REVOKE_ABSENT_CONNECTS successful-but-absent connects always revokes; at
## MIN_ABSENT_CONNECTS the ownership stamp breaks the tie — recent ownership
## is kept, stale (or never-stamped, i.e. forged) ownership is revoked.
const MIN_ABSENT_CONNECTS := 2
const REVOKE_ABSENT_CONNECTS := 3
const REVOKE_ABSENT_WINDOW_SEC := 72 * 60 * 60

static func is_verified_source(source: String) -> bool:
	return VERIFIED_SOURCES.has(source)

## Boot-time source check (#5): may a cached premium flag with this source
## survive boot? Debug builds keep everything (the tester toggle and the
## regression sources must survive their own runs); non-debug builds keep
## ONLY Play-verified sources.
static func boot_source_trusted(source: String, is_debug: bool) -> bool:
	if is_debug:
		return true
	return is_verified_source(source)

## Debug-build exemption for revoke-on-absence: a "debug"-sourced grant (the
## Premium screen's simulate toggle) is never revoked by absence in a debug
## build — testers keep their toggle. Everything else, every build, revokes.
static func revoke_exempt(source: String, is_debug: bool) -> bool:
	return is_debug and source == "debug"

## The revoke-on-absence decision (#2). Called only after a SUCCESSFUL
## ownership query excluded the product (offline grace is upstream).
## `absent_streak` counts consecutive absent answers; `last_seen_owned_at`
## is the unix stamp of the last owned answer (0 = never recorded).
static func should_revoke_on_absence(absent_streak: int, last_seen_owned_at: int, now: int) -> bool:
	if absent_streak < MIN_ABSENT_CONNECTS:
		return false
	if absent_streak >= REVOKE_ABSENT_CONNECTS:
		return true
	if last_seen_owned_at <= 0:
		# Premium was cached but Play NEVER answered "owned" on this install —
		# the forged-flag shape. No ownership stamp to grant grace from.
		return true
	return (now - last_seen_owned_at) >= REVOKE_ABSENT_WINDOW_SEC
