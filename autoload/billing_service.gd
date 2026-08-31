extends Node
## BillingService — the Google Play Billing adapter (Layer 3 unlock source).
##
## Wraps the AndroidIAPP native plugin behind a clean GDScript API and turns a
## purchase of the lifetime product into EntitlementManager.grant_premium("play").
## When the native plugin is absent — in the editor, on desktop, or in an Android
## build without the plugin — every method no-ops gracefully and is_available()
## returns false, so the rest of the app (and the debug "simulate purchase" path)
## keep working unchanged.
##
## ⚠️ CLIENT-TRUST: this grants premium as soon as Play reports the product
## owned — the Play Billing client library is the whole trust boundary; no
## server verification exists. Connect-time queryPurchases is the overriding
## ownership authority: every SUCCESSFUL ownership answer is reported to
## EntitlementManager.note_play_ownership(), which implements revoke-on-absence
## under the hysteresis + offline-grace rules in core/entitlement_policy.gd
## (ship-blocker #2; the boot-time source check is #5 — both implemented, see
## docs/premium/README.md "Security ship-blockers" and security-audit/).
##
## Autoload order: declared after EntitlementManager (it calls grant_premium),
## before SceneRouter.

signal purchase_succeeded()
signal purchase_failed(reason: String)        # reason == "cancelled" for user-cancel
## The buyer picked a deferred payment method (UPI collect / netbanking "pay
## later"): not owned yet, not failed. Ownership lands via purchase_updated if
## we're still running, else via the connect-time queryPurchases on a later launch.
signal purchase_pending()
signal purchases_restored(count: int)         # -1 = the ownership query failed (e.g. offline)
signal price_changed(formatted_price: String)
## A plugin event was recorded in the diagnostics log (debug billing card refresh).
signal diagnostics_changed()

# --- Native plugin adapter ----------------------------------------------------
# Pinned to the AndroidIAPP plugin v1.6 (Google Play Billing Library 8.3.0) in
# addons/android_IAPP. Method signatures, signal names and payload shapes below
# were verified against the DECOMPILED release AAR (javap + bytecode), not the
# repo README (which documents a newer API) — see docs/premium/phase-2.md.
const BILLING_SINGLETON := "AndroidIAPP"

# Methods. The JNI bridge can't see Kotlin default arguments, so EVERY declared
# parameter must be passed explicitly, and String[] parameters need a
# PackedStringArray (a plain Array won't match the Java signature).
const M_START := "startConnection"                # ()
const M_QUERY_PRODUCTS := "queryProductDetails"   # (ids: String[], type: String)
const M_PURCHASE := "purchase"                    # (ids: String[], is_offer_personalized: bool)
const M_QUERY_PURCHASES := "queryPurchases"       # (type: String, include_suspended: bool)
const M_ACKNOWLEDGE := "acknowledgePurchase"      # (purchase_token: String)

# Signals. connected carries no args; every other one below emits exactly ONE
# Dictionary payload. Error payloads carry {response_code, debug_message}.
const S_CONNECTED := "connected"                             # no args
const S_DISCONNECTED := "disconnected"                       # no args
const S_QUERY_PURCHASES_OK := "query_purchases"              # {purchases_list: Array}
const S_QUERY_PURCHASES_ERR := "query_purchases_error"
const S_PRODUCT_DETAILS_OK := "query_product_details"        # {product_details_list: Array}
const S_PRODUCT_DETAILS_ERR := "query_product_details_error"
const S_PURCHASE_UPDATED := "purchase_updated"               # {purchases_list: Array} — PURCHASED and PENDING both arrive here
const S_PURCHASE_CANCELLED := "purchase_cancelled"           # user backed out of the sheet
const S_PURCHASE_UPDATE_ERR := "purchase_update_error"       # purchase flow ended in an error
const S_PURCHASE_LAUNCH_ERR := "purchase_error"              # purchase flow failed to LAUNCH
const S_ACKNOWLEDGE_OK := "purchase_acknowledged"            # + {purchase_token}
const S_ACKNOWLEDGE_ERR := "purchase_acknowledged_error"     # + {purchase_token}

const PRODUCT_TYPE_INAPP := "inapp"

## Diagnostics ring buffer size (debug billing card).
const LOG_MAX := 24

var _plugin: Object = null
var _display_price := ""
## True between a Restore tap and the resulting query_purchases[_error] signal, so
## the silent connect-time ownership query doesn't toast "restored" at the user.
var _restore_in_flight := false
## Store-connection state, for diagnostics only (never gates the API — a call made
## before `connected` simply fails through the plugin's own error signal).
var _store_connected := false
## True once queryProductDetails has actually returned OUR product. The plugin can
## only launch a purchase for a product whose ProductDetails it has cached in its
## own map — purchase() fails with "Product ID ... not found. You must query product
## details first." otherwise. Verified on device.
var _product_ready := false
## A purchase() is waiting for that details query to land before it can launch.
var _purchase_awaiting_details := false
var _log: Array[String] = []

func _ready() -> void:
	if not Engine.has_singleton(BILLING_SINGLETON):
		# Not on Android, or the plugin isn't installed — stay dormant.
		_log_event("plugin ABSENT — no '%s' singleton (editor/desktop, or missing from the build)" % BILLING_SINGLETON)
		return
	_plugin = Engine.get_singleton(BILLING_SINGLETON)
	_log_event("plugin FOUND ('%s') → startConnection()" % BILLING_SINGLETON)
	_connect_plugin_signals()
	_plugin_call(M_START)

# --- Public API ---------------------------------------------------------------
func is_available() -> bool:
	return _plugin != null

## Diagnostics only: has the store answered `connected` yet?
func is_store_connected() -> bool:
	return _store_connected

## Diagnostics only: the redacted plugin event log, oldest first. Purchase tokens
## are NEVER recorded (only whether one was present, and its length).
func diagnostics_log() -> Array[String]:
	return _log.duplicate()

## Fetch the localized price / ProductDetails. Called on connect, on demand from the
## debug card, and lazily by purchase() when the details aren't cached yet.
func query_products() -> void:
	if not is_available():
		_log_event("→ queryProductDetails SKIPPED (plugin absent)")
		return
	_log_event("→ queryProductDetails(%s, '%s')" % [str(StoreProducts.ALL), PRODUCT_TYPE_INAPP])
	_plugin_call(M_QUERY_PRODUCTS, [PackedStringArray(StoreProducts.ALL), PRODUCT_TYPE_INAPP])

## The localized price for the unlock, or the configured fallback before the store
## has answered (offline / editor / off-Android).
func display_price() -> String:
	return _display_price if not _display_price.is_empty() else StoreProducts.FALLBACK_PRICE

func purchase() -> void:
	if not is_available():
		_log_event("→ purchase SKIPPED (plugin absent)")
		purchase_failed.emit("unavailable")
		return
	if _product_ready:
		_launch_purchase()
		return
	# The plugin can ONLY launch a purchase for a product whose ProductDetails it has
	# already cached (it looks them up in its own map). If the connect-time query
	# hasn't landed yet — a tap right after launch, a flaky network, or a store
	# reconnect — fetch them first and launch when they arrive, instead of failing
	# with a baffling "product not found".
	_log_event("purchase DEFERRED — product details not cached; querying first")
	_purchase_awaiting_details = true
	query_products()

func _launch_purchase() -> void:
	_log_event("→ purchase(['%s'], false)" % StoreProducts.PREMIUM_LIFETIME)
	# Second arg: EU "personalized price" disclosure — we don't personalize prices.
	_plugin_call(M_PURCHASE, [PackedStringArray([StoreProducts.PREMIUM_LIFETIME]), false])
	# Result arrives via purchase_updated / purchase_cancelled / *_error signals.

func restore() -> void:
	if not is_available():
		_log_event("→ restore SKIPPED (plugin absent)")
		purchases_restored.emit(0)
		return
	_restore_in_flight = true
	_log_event("→ queryPurchases('%s', false)  [explicit restore]" % PRODUCT_TYPE_INAPP)
	_plugin_call(M_QUERY_PURCHASES, [PRODUCT_TYPE_INAPP, false])
	# Count is reported from _on_query_purchases / _on_query_purchases_error.

# --- Plugin signal handlers ---------------------------------------------------
func _on_connected() -> void:
	_store_connected = true
	_log_event("✓ connected")
	# Localized pricing for the paywall (and the ProductDetails the plugin needs
	# cached before it will launch a purchase).
	query_products()
	# Silently reflect any existing ownership (same Play account / reinstall).
	_log_event("→ queryPurchases('%s', false)  [silent restore]" % PRODUCT_TYPE_INAPP)
	_plugin_call(M_QUERY_PURCHASES, [PRODUCT_TYPE_INAPP, false])

func _on_disconnected() -> void:
	_store_connected = false
	# A new billing client means a fresh (empty) ProductDetails cache, so the next
	# purchase must re-query. _on_connected re-queries on reconnect.
	_product_ready = false
	_log_event("✗ disconnected (the plugin auto-reconnects)")

func _on_query_purchases(data: Dictionary) -> void:
	# queryPurchases returns only OWNED purchases, so a missing state field is
	# treated as owned (strict = false). Runs for both the silent connect-time
	# restore and an explicit Restore tap; only the latter reports back to the UI.
	var owned := BillingPayloads.purchases_from(data)
	# A SUCCESSFUL ownership answer — feed the revoke-on-absence bookkeeping
	# (ship-blocker #2) before granting. The error handler reports nothing, so
	# offline can never revoke (offline grace).
	var ours_present := BillingPayloads.contains_our_product(owned)
	EntitlementManager.note_play_ownership(ours_present)
	var n := _handle_purchase_list(owned, true, false)
	_log_event("← query_purchases: %s → granted %d%s" % [_summarize_purchases(owned), n,
		"" if ours_present else "  [OURS ABSENT]"])
	if _restore_in_flight:
		_restore_in_flight = false
		purchases_restored.emit(n)

func _on_query_purchases_error(data: Dictionary) -> void:
	_log_event("← query_purchases_ERROR: %s" % BillingPayloads.error_text(data))
	push_warning("BillingService: queryPurchases failed — %s" % BillingPayloads.error_text(data))
	if _restore_in_flight:
		_restore_in_flight = false
		purchases_restored.emit(-1)

func _on_purchase_updated(data: Dictionary) -> void:
	var purchases := BillingPayloads.purchases_from(data)
	# Live updates can include PENDING purchases (e.g. UPI / netbanking "pay
	# later"), so only an explicit PURCHASED state grants here (strict = true).
	var n := _handle_purchase_list(purchases, false, true)
	var pending := BillingPayloads.has_pending_ours(purchases)
	_log_event("← purchase_updated: %s → granted %d%s"
		% [_summarize_purchases(purchases), n, "  [PENDING]" if pending else ""])
	if n > 0:
		# A live PURCHASED grant is also an ownership sighting — stamp it so the
		# revoke-on-absence window starts from real ownership, not zero.
		EntitlementManager.note_play_ownership(true)
		purchase_succeeded.emit()
	elif pending:
		purchase_pending.emit()

func _on_purchase_cancelled(_data: Dictionary) -> void:
	_log_event("← purchase_cancelled (user backed out)")
	purchase_failed.emit("cancelled")

## Shared by purchase_error (flow failed to launch, e.g. unknown product) and
## purchase_update_error (flow ended in an error) — same UX outcome.
func _on_purchase_flow_error(data: Dictionary) -> void:
	_log_event("← purchase_ERROR: %s" % BillingPayloads.error_text(data))
	purchase_failed.emit(BillingPayloads.error_text(data))

func _on_product_details(data: Dictionary) -> void:
	var details := BillingPayloads.details_from(data)
	_log_event("← query_product_details: %s" % _summarize_details(details))
	for item in details:
		if not (item is Dictionary):
			continue
		var d: Dictionary = item
		if String(d.get("product_id", "")) != StoreProducts.PREMIUM_LIFETIME:
			continue
		# The plugin has now cached this product's ProductDetails, so a purchase can
		# actually be launched.
		_product_ready = true
		var price := BillingPayloads.extract_price(d)
		if not price.is_empty():
			_display_price = price
			price_changed.emit(price)
		break
	_resume_or_fail_deferred_purchase("product unavailable")

## The query came back OK but with no product (not created / not active in Play
## Console), or it errored — either way a purchase waiting on it can't proceed.
func _on_product_details_error(data: Dictionary) -> void:
	# Non-fatal for the paywall: it keeps showing StoreProducts.FALLBACK_PRICE.
	var reason := BillingPayloads.error_text(data)
	_log_event("← query_product_details_ERROR: %s" % reason)
	push_warning("BillingService: queryProductDetails failed — %s" % reason)
	_resume_or_fail_deferred_purchase(reason)

## Launch a purchase that was waiting on the product details, or fail it if they
## never arrived (so the paywall's "Processing…" state is always cleared).
func _resume_or_fail_deferred_purchase(failure_reason: String) -> void:
	if not _purchase_awaiting_details:
		return
	_purchase_awaiting_details = false
	if _product_ready:
		_launch_purchase()
	else:
		_log_event("deferred purchase ABORTED — %s" % failure_reason)
		purchase_failed.emit(failure_reason)

func _on_acknowledged(_data: Dictionary) -> void:
	_log_event("← purchase_acknowledged ✓")

func _on_acknowledge_error(data: Dictionary) -> void:
	# The purchase stays owned-but-unacknowledged; the connect-time queryPurchases
	# on a later connect re-acknowledges it (within Play's 3-day auto-refund
	# window). An auto-refunded purchase vanishes from queryPurchases, leaving a
	# stale local grant for revoke-on-absence to catch — client-only
	# reconciliation, ship-blockers #8 and #2 in docs/premium/README.md.
	_log_event("← purchase_acknowledged_ERROR: %s" % BillingPayloads.error_text(data))
	push_warning("BillingService: acknowledge failed — %s" % BillingPayloads.error_text(data))

# --- Purchase handling --------------------------------------------------------
## `strict` requires an explicit PURCHASED state (live purchase_updated path);
## non-strict treats a missing state as owned (queryPurchases only returns owned).
func _handle_purchase_list(list: Array, is_restore: bool, strict: bool) -> int:
	var granted := 0
	for item in list:
		if item is Dictionary and _handle_purchase(item, is_restore, strict):
			granted += 1
	return granted

## Acknowledge (required by Play within 3 days, else auto-refund) THEN grant.
func _handle_purchase(p: Dictionary, is_restore: bool, strict: bool) -> bool:
	if not BillingPayloads.is_our_product(p) or not BillingPayloads.is_purchased(p, strict):
		return false
	if BillingPayloads.is_acknowledged(p):
		EntitlementManager.grant_premium("restore" if is_restore else "play")
		return true
	# Unacknowledged purchases MUST be acknowledged or Play auto-refunds them in 3
	# days. If there's no token to acknowledge with, refuse to grant rather than
	# hand out premium that will silently refund and leave a stale local flag.
	var token := BillingPayloads.purchase_token(p)
	if token.is_empty():
		push_warning("BillingService: owned purchase has no token to acknowledge; not granting.")
		return false
	_plugin_call(M_ACKNOWLEDGE, [token])
	EntitlementManager.grant_premium("restore" if is_restore else "play")
	return true

# --- Diagnostics --------------------------------------------------------------
## Record a redacted one-line summary of a plugin event. Also print()s it so it
## lands in `adb logcat` from a debug export (release builds strip stdout — see
## the debug-keystore trick in docs/premium/phase-play-games.md).
## SECURITY: purchase tokens are never recorded — only their presence and length.
func _log_event(line: String) -> void:
	_log.append(line)
	if _log.size() > LOG_MAX:
		_log.remove_at(0)
	print("BillingService: %s" % line)
	diagnostics_changed.emit()

func _summarize_purchases(list: Array) -> String:
	if list.is_empty():
		return "0 purchases"
	var parts: Array[String] = []
	for item in list:
		if not (item is Dictionary):
			parts.append("<non-dict>")
			continue
		var p: Dictionary = item
		var token := BillingPayloads.purchase_token(p)
		parts.append("{%s state=%s ack=%s token=%s}" % [
			str(p.get("products", p.get("product_id", "?"))),
			str(p.get("purchase_state", "<absent>")),
			str(BillingPayloads.is_acknowledged(p)),
			("yes(%d chars)" % token.length()) if not token.is_empty() else "NONE",
		])
	return "%d purchase(s): %s" % [list.size(), ", ".join(parts)]

func _summarize_details(list: Array) -> String:
	if list.is_empty():
		return "0 products (product not found / not active in Play Console)"
	var parts: Array[String] = []
	for item in list:
		if not (item is Dictionary):
			parts.append("<non-dict>")
			continue
		var d: Dictionary = item
		var price := BillingPayloads.extract_price(d)
		parts.append("{%s price=%s}" % [
			String(d.get("product_id", "?")),
			price if not price.is_empty() else "<none — check the price keys>",
		])
	return "%d product(s): %s" % [list.size(), ", ".join(parts)]

# --- Plugin call/connect helpers ----------------------------------------------
func _connect_plugin_signals() -> void:
	_safe_connect(S_CONNECTED, _on_connected)
	_safe_connect(S_DISCONNECTED, _on_disconnected)
	_safe_connect(S_QUERY_PURCHASES_OK, _on_query_purchases)
	_safe_connect(S_QUERY_PURCHASES_ERR, _on_query_purchases_error)
	_safe_connect(S_PURCHASE_UPDATED, _on_purchase_updated)
	_safe_connect(S_PURCHASE_CANCELLED, _on_purchase_cancelled)
	_safe_connect(S_PURCHASE_UPDATE_ERR, _on_purchase_flow_error)
	_safe_connect(S_PURCHASE_LAUNCH_ERR, _on_purchase_flow_error)
	_safe_connect(S_PRODUCT_DETAILS_OK, _on_product_details)
	_safe_connect(S_PRODUCT_DETAILS_ERR, _on_product_details_error)
	_safe_connect(S_ACKNOWLEDGE_OK, _on_acknowledged)
	_safe_connect(S_ACKNOWLEDGE_ERR, _on_acknowledge_error)

func _safe_connect(sig: String, cb: Callable) -> void:
	if _plugin and _plugin.has_signal(sig) and not _plugin.is_connected(sig, cb):
		_plugin.connect(sig, cb)
	elif _plugin and not _plugin.has_signal(sig):
		# A name mismatch shows up HERE, at startup, rather than as a silent no-op —
		# exactly what the on-device smoke test is looking for.
		_log_event("⚠ plugin has NO SIGNAL '%s' — adapter name mismatch!" % sig)
		push_warning("BillingService: plugin has no signal '%s' — adjust the adapter." % sig)

func _plugin_call(method: String, args: Array = []) -> Variant:
	if _plugin == null:
		return null
	# NOTE: Object.has_method() is unreliable for Android plugin singletons —
	# @UsedByGodot methods often report false even though they ARE callable. So we
	# call directly. A genuinely missing method logs an error but won't crash.
	return _plugin.callv(method, args)
