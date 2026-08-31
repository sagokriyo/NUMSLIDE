class_name StoreProducts
extends RefCounted
## StoreProducts — pure, testable catalog of the in-app products sold via Google
## Play Billing. No node/plugin dependencies (BillingService does the wiring), so
## it is unit-tested by tests/test_store_products.gd.

## The lifetime premium unlock — a one-time "managed product" / in-app product.
## This string MUST exactly match the product ID created in the Play Console.
const PREMIUM_LIFETIME := "premium_lifetime"

## Shown on the paywall before the store returns a localized price (offline, in
## the editor, or off-Android). On a real device Play provides the localized price
## (e.g. ₹199 in India, $2.99 in the US) which overrides this. Keep in sync with
## the base price set in the Play Console.
const FALLBACK_PRICE := "₹199"

## Every product ID we query / sell. Extend when adding products.
const ALL: Array[String] = [PREMIUM_LIFETIME]

static func is_premium_product(id: String) -> bool:
	return id == PREMIUM_LIFETIME
