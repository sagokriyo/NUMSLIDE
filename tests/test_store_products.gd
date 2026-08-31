extends "res://regression/headless/harness/script_test_base.gd"
## Headless unit tests for the StoreProducts catalog (pure data, no autoloads).
## Run:  godot --headless --path . --script res://regression/headless/harness/headless_boot.gd -- --test=res://tests/test_store_products.gd

func run_tests() -> void:
	_test_product_ids()

func _test_product_ids() -> void:
	print("test_product_ids:")
	check("premium id is 'premium_lifetime'", StoreProducts.PREMIUM_LIFETIME == "premium_lifetime")
	check("ALL contains the premium product", StoreProducts.ALL.has(StoreProducts.PREMIUM_LIFETIME))
	check("ALL has exactly one product", StoreProducts.ALL.size() == 1)
	check("is_premium_product matches the id", StoreProducts.is_premium_product("premium_lifetime"))
	check("is_premium_product rejects others", not StoreProducts.is_premium_product("something_else"))
	check("fallback price is non-empty", not StoreProducts.FALLBACK_PRICE.is_empty())
