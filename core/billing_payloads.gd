class_name BillingPayloads
extends RefCounted
## BillingPayloads — pure parsing of the Dictionary payloads the AndroidIAPP
## plugin (v1.6, Billing Library 8.3.0) emits. Shapes were verified against the
## decompiled release AAR (see docs/premium/phase-2.md). Zero node/autoload
## dependencies so it is unit-tested headlessly by tests/test_billing_parsing.gd;
## BillingService does the plugin wiring and entitlement granting.

const PURCHASE_STATE_PURCHASED := 1   # Play: Purchase.PurchaseState.PURCHASED
const PURCHASE_STATE_PENDING := 2     # Play: Purchase.PurchaseState.PENDING

## Unwrap {purchases_list: [...]} from query_purchases / purchase_updated.
static func purchases_from(data: Dictionary) -> Array:
	var v: Variant = data.get("purchases_list", [])
	return (v as Array) if v is Array else []

## Unwrap {product_details_list: [...]} from query_product_details.
static func details_from(data: Dictionary) -> Array:
	var v: Variant = data.get("product_details_list", [])
	return (v as Array) if v is Array else []

## Human-readable reason from an error payload {response_code, debug_message}.
static func error_text(data: Dictionary) -> String:
	var msg := String(data.get("debug_message", ""))
	return msg if not msg.is_empty() else "error %s" % str(data.get("response_code", "?"))

static func is_our_product(p: Dictionary) -> bool:
	var products: Variant = p.get("products", null)
	if products is Array:
		return (products as Array).has(StoreProducts.PREMIUM_LIFETIME)
	return StoreProducts.is_premium_product(String(p.get("product_id", "")))

## `strict` requires an explicit PURCHASED state (live purchase_updated path,
## which can carry PENDING); non-strict treats a missing state as owned
## (queryPurchases only ever returns owned items).
static func is_purchased(p: Dictionary, strict: bool) -> bool:
	if p.has("purchase_state"):
		return int(p["purchase_state"]) == PURCHASE_STATE_PURCHASED
	return not strict

## True when ANY record of our product appears in the list, in any purchase
## state — the presence signal for revoke-on-absence bookkeeping. PENDING
## deliberately counts as present so a UPI "pay later" can never build an
## absent streak (see security-audit/02-revoke-on-absence.md).
static func contains_our_product(list: Array) -> bool:
	for item in list:
		if item is Dictionary and is_our_product(item):
			return true
	return false

## True when the list holds a PENDING purchase of OUR product (UPI / netbanking
## "pay later" — not owned yet, not failed).
static func has_pending_ours(list: Array) -> bool:
	for item in list:
		if not (item is Dictionary):
			continue
		var p: Dictionary = item
		if is_our_product(p) and int(p.get("purchase_state", -1)) == PURCHASE_STATE_PENDING:
			return true
	return false

static func is_acknowledged(p: Dictionary) -> bool:
	return bool(p.get("is_acknowledged", false))

static func purchase_token(p: Dictionary) -> String:
	return String(p.get("purchase_token", ""))

## The localized formatted price from a product-details dict, or "" if absent.
static func extract_price(d: Dictionary) -> String:
	# One-time products: {one_time_purchase_offer_details: {formatted_price}}.
	if d.has("one_time_purchase_offer_details"):
		var o: Variant = d["one_time_purchase_offer_details"]
		if o is Dictionary and (o as Dictionary).has("formatted_price"):
			return String((o as Dictionary)["formatted_price"])
	# Billing 8 multi-offer variant: a list of such offer dicts.
	if d.has("one_time_purchase_offer_details_list"):
		var l: Variant = d["one_time_purchase_offer_details_list"]
		if l is Array and not (l as Array).is_empty():
			var first: Variant = (l as Array)[0]
			if first is Dictionary and (first as Dictionary).has("formatted_price"):
				return String((first as Dictionary)["formatted_price"])
	return ""
