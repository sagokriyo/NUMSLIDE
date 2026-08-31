extends "res://regression/headless/harness/script_test_base.gd"
## Headless unit tests for BillingPayloads — parsing of the Dictionary payloads
## the AndroidIAPP plugin (v1.6, Billing Library 8.3.0) emits, as verified
## against the decompiled release AAR (see docs/premium/phase-2.md).
## Pure statics, no autoloads, no plugin.
## Run:  godot --headless --path . --script res://regression/headless/harness/headless_boot.gd -- --test=res://tests/test_billing_parsing.gd

func run_tests() -> void:
	_test_payload_extraction()
	_test_purchase_predicates()
	_test_pending_detection()
	_test_price_extraction()
	_test_error_text()

## A purchase dict exactly as AndroidIAPP's convertPurchaseToDictionary builds it.
func _purchase_fixture(overrides: Dictionary = {}) -> Dictionary:
	var p := {
		"order_id": "GPA.1234-5678-9012-34567",
		"package_name": "com.infinity_2048",
		"products": ["premium_lifetime"],
		"purchase_state": 1,
		"purchase_time": 1752300000000,
		"purchase_token": "test-token-abc",
		"quantity": 1,
		"is_acknowledged": false,
		"is_auto_renewing": false,
	}
	for k in overrides:
		p[k] = overrides[k]
	return p

func _test_payload_extraction() -> void:
	print("test_payload_extraction:")
	var purchases := [_purchase_fixture()]
	check("purchases_list is unwrapped",
		BillingPayloads.purchases_from({"response_code": 0, "purchases_list": purchases}).size() == 1)
	check("missing purchases_list -> []",
		BillingPayloads.purchases_from({"response_code": 0}).is_empty())
	check("non-array purchases_list -> []",
		BillingPayloads.purchases_from({"purchases_list": "garbage"}).is_empty())
	check("product_details_list is unwrapped",
		BillingPayloads.details_from({"product_details_list": [{"product_id": "premium_lifetime"}]}).size() == 1)
	check("missing product_details_list -> []",
		BillingPayloads.details_from({}).is_empty())
	check("non-array product_details_list -> []",
		BillingPayloads.details_from({"product_details_list": 42}).is_empty())

func _test_purchase_predicates() -> void:
	print("test_purchase_predicates:")
	check("ours: products array match",
		BillingPayloads.is_our_product(_purchase_fixture()))
	check("not ours: different product",
		not BillingPayloads.is_our_product(_purchase_fixture({"products": ["other_thing"]})))
	check("ours: product_id fallback when products missing",
		BillingPayloads.is_our_product({"product_id": "premium_lifetime"}))
	check("not ours: empty dict",
		not BillingPayloads.is_our_product({}))
	check("PURCHASED state passes strict",
		BillingPayloads.is_purchased(_purchase_fixture(), true))
	check("PENDING state fails strict",
		not BillingPayloads.is_purchased(_purchase_fixture({"purchase_state": 2}), true))
	check("PENDING state fails non-strict too (explicit state wins)",
		not BillingPayloads.is_purchased(_purchase_fixture({"purchase_state": 2}), false))
	var stateless := _purchase_fixture()
	stateless.erase("purchase_state")
	check("missing state fails strict (live path)",
		not BillingPayloads.is_purchased(stateless, true))
	check("missing state passes non-strict (queryPurchases path)",
		BillingPayloads.is_purchased(stateless, false))
	check("acknowledged flag read",
		BillingPayloads.is_acknowledged(_purchase_fixture({"is_acknowledged": true})))
	check("missing acknowledged flag -> false",
		not BillingPayloads.is_acknowledged({}))
	check("token extracted",
		BillingPayloads.purchase_token(_purchase_fixture()) == "test-token-abc")
	check("missing token -> empty",
		BillingPayloads.purchase_token({}).is_empty())

func _test_pending_detection() -> void:
	print("test_pending_detection:")
	check("our PENDING purchase detected",
		BillingPayloads.has_pending_ours([_purchase_fixture({"purchase_state": 2})]))
	check("someone else's PENDING ignored",
		not BillingPayloads.has_pending_ours([_purchase_fixture({"purchase_state": 2, "products": ["other"]})]))
	check("PURCHASED is not pending",
		not BillingPayloads.has_pending_ours([_purchase_fixture()]))
	check("empty list -> no pending",
		not BillingPayloads.has_pending_ours([]))
	check("junk entries tolerated",
		not BillingPayloads.has_pending_ours(["garbage", 7, null]))
	# contains_our_product — the presence signal for revoke-on-absence
	# (security-audit/02): PENDING must count as present.
	check("our PURCHASED product counts as present",
		BillingPayloads.contains_our_product([_purchase_fixture()]))
	check("our PENDING product still counts as present",
		BillingPayloads.contains_our_product([_purchase_fixture({"purchase_state": 2})]))
	check("someone else's product is not ours",
		not BillingPayloads.contains_our_product([_purchase_fixture({"products": ["other"]})]))
	check("empty list -> absent",
		not BillingPayloads.contains_our_product([]))
	check("junk entries tolerated for presence too",
		not BillingPayloads.contains_our_product(["garbage", 7, null]))

func _test_price_extraction() -> void:
	print("test_price_extraction:")
	check("one_time_purchase_offer_details dict",
		BillingPayloads.extract_price({
			"product_id": "premium_lifetime",
			"one_time_purchase_offer_details": {
				"formatted_price": "₹199.00",
				"price_amount_micros": 199000000,
				"price_currency_code": "INR",
			},
		}) == "₹199.00")
	check("offer_details_list fallback (Billing 8 multi-offer)",
		BillingPayloads.extract_price({
			"one_time_purchase_offer_details_list": [{"formatted_price": "$2.99"}],
		}) == "$2.99")
	check("single-offer dict wins over the list",
		BillingPayloads.extract_price({
			"one_time_purchase_offer_details": {"formatted_price": "₹199.00"},
			"one_time_purchase_offer_details_list": [{"formatted_price": "$2.99"}],
		}) == "₹199.00")
	check("no price fields -> empty",
		BillingPayloads.extract_price({"product_id": "premium_lifetime"}).is_empty())
	check("malformed offer details tolerated",
		BillingPayloads.extract_price({"one_time_purchase_offer_details": "junk",
			"one_time_purchase_offer_details_list": [3]}).is_empty())

func _test_error_text() -> void:
	print("test_error_text:")
	check("debug_message preferred",
		BillingPayloads.error_text({"response_code": 6, "debug_message": "Network error."}) == "Network error.")
	check("falls back to response_code",
		BillingPayloads.error_text({"response_code": 6}) == "error 6")
	check("empty payload still yields text",
		not BillingPayloads.error_text({}).is_empty())
