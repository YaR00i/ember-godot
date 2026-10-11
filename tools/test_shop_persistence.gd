extends SceneTree
## Buy/sell + save v2 round-trip on guarded neutral native shop fixtures.

const Fixture = preload("res://tools/fixtures/ember_shop_test_fixture.gd")
var _setup: Dictionary


func _init() -> void:
	_setup = Fixture.prepare(self)
	if _setup.refused:
		quit.call_deferred(2)
		return
	_run.call_deferred()


func _run() -> void:
	var errors: Array[String] = []
	if _setup.error != OK or not _setup.progress_isolated:
		printerr("FAIL native shop persistence fixture preparation")
		quit(1)
		return
	_test_economy(errors)
	_test_save_round_trip(errors)
	Fixture.verify_sources(_setup, errors)
	if errors.is_empty():
		print("PASS shop persistence")
		print("  native buy/sell preserves prices, stock, stack and unsellable rules")
		print("  save v2 round-trip keeps inventory + per-shop stock beside party data")
		quit(0)
		return
	printerr("FAIL shop persistence")
	for error in errors:
		printerr(" - ", error)
	quit(1)


func _fresh_state() -> EmberExploreState:
	var state := EmberExploreState.new()
	state.persistence_enabled = false
	state.reset_new_game()
	state.set_world_context("shop_fixture_map", null, 16.0)
	return state


func _test_economy(errors: Array[String]) -> void:
	var state := _fresh_state()
	var initial := state.shop_view(Fixture.SHOP)
	if int(initial.get("wallet", -1)) != 20:
		errors.append("new explore state no longer starts with the established 20 coin")
	var listings: Array = initial.get("listings", [])
	if listings.size() != 3 or int(listings[2].get("stock", -1)) != 12:
		errors.append("neutral native shop listings/stock did not load")

	var bought := state.buy(Fixture.SHOP, "herb")
	if not bool(bought.get("ok", false)):
		errors.append("buy herb failed")
	elif int(state.inventory.get("coin", -1)) != 17 or int(state.inventory.get("herb", 0)) != 1:
		errors.append("buy did not exchange 3 coin for one herb")
	elif int(state.shop_stock.get(Fixture.SHOP, {}).get("herb", -1)) != 11:
		errors.append("buy did not decrement finite stock")

	var sold := state.sell(Fixture.SHOP, "herb")
	if not bool(sold.get("ok", false)):
		errors.append("sell herb failed")
	elif int(state.inventory.get("coin", -1)) != 18 or state.inventory.has("herb"):
		errors.append("sell did not remove herb and pay its sell price")
	elif int(state.shop_stock.get(Fixture.SHOP, {}).get("herb", -1)) != 12:
		errors.append("sell did not return listed item to finite stock")

	state.shop_stock[Fixture.SHOP]["herb"] = 1
	state.inventory = {"coin": 20}
	state.buy(Fixture.SHOP, "herb")
	if int(state.shop_stock.get(Fixture.SHOP, {}).get("herb", -1)) != 0:
		errors.append("last purchase lost explicit zero stock")
	elif str(state.buy(Fixture.SHOP, "herb").get("reason", "")) != "out_of_stock":
		errors.append("zero stock did not block the next purchase")

	state.shop_stock[Fixture.SHOP]["herb"] = 12
	state.inventory = {"coin": 2, Fixture.KEY: 1}
	var broke := state.buy(Fixture.SHOP, "herb")
	if bool(broke.get("ok", true)) or str(broke.get("reason", "")) != "broke":
		errors.append("buy did not reject insufficient wallet")
	var forbidden := state.sell(Fixture.SHOP, Fixture.KEY)
	if bool(forbidden.get("ok", true)) or str(forbidden.get("reason", "")) != "unsellable":
		errors.append("sell did not preserve item unsellable contract")
	var preserved_inventory := state.inventory.duplicate(true)
	var preserved_stock := state.shop_stock.duplicate(true)
	for rejected in [state.buy("retired_shop", "herb"), state.sell("retired_shop", "herb")]:
		if bool(rejected.get("ok", true)) or rejected.get("reason") != "unknown_shop": errors.append("missing shop accepted a trade")
	if state.inventory != preserved_inventory or state.shop_stock != preserved_stock: errors.append("failed trade changed persistent state")
	state.inventory = {"coin": 20}
	state.shop_view(Fixture.OTHER)
	state.buy(Fixture.OTHER, "herb")
	if state.shop_stock[Fixture.OTHER].herb != 11 or state.shop_stock[Fixture.SHOP].herb != 12: errors.append("stock leaked between native shops")
	state.inventory = {"coin": 20}
	state.buy(Fixture.SHOP, "meat_bun")
	state.buy(Fixture.SHOP, "meat_bun")
	if state.inventory.get("meat_bun") != 2 or state.inventory.coin != 12 or state.shop_stock[Fixture.SHOP].has("meat_bun"): errors.append("infinite stock became finite")
	state.inventory = {"coin": 20, "herb": 99}
	state.buy(Fixture.SHOP, "herb")
	if state.inventory.herb != 99 or state.inventory.coin != 17: errors.append("existing full-stack purchase semantics changed")
	state.free()


func _test_save_round_trip(errors: Array[String]) -> void:
	var nonce := "%s_%s" % [Time.get_unix_time_from_system(), randi()]
	var root := "user://ember-tests/shop-persistence-%s" % nonce
	var state := _fresh_state()
	state.persistence_enabled = true
	state.storage_root = root
	state.inventory = {"coin": 17, "herb": 1}
	state.shop_stock = {Fixture.SHOP: {"herb": 11, "qingxin_tea": 0}, Fixture.OTHER: {"herb": 3}, "retired_shop": {"retired_item": 0}}
	if not state.save_slot(0):
		errors.append("save slot write failed")
		return
	var raw: Variant = EmberPack.parse_json_file(state.save_path(0))
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("saved payload is not JSON object")
	else:
		if int(raw.get("version", -1)) != 2 or str(raw.get("packId", "")) != "ember_p1":
			errors.append("save payload diverged from Ember save v2 identity")
		if not raw.has("party") or not raw.has("openedChests") or not raw.has("flags"):
			errors.append("save payload omitted required Ember save v2 fields")
		if raw.has("equipment") or raw.has("maxHp"):
			errors.append("save v2 duplicated leader or derived state")

	var loaded := EmberExploreState.new()
	loaded.persistence_enabled = true
	loaded.storage_root = root
	if not loaded.load_slot(0):
		errors.append("save slot load failed")
	elif loaded.inventory != {"coin": 17, "herb": 1}:
		errors.append("inventory did not survive save/reload")
	elif int(loaded.shop_stock.get(Fixture.SHOP, {}).get("herb", -1)) != 11:
		errors.append("per-shop stock did not survive save/reload")
	elif int(loaded.shop_stock.get(Fixture.SHOP, {}).get("qingxin_tea", -1)) != 0:
		errors.append("sold-out zero stock did not survive save/reload")

	if loaded.shop_stock != state.shop_stock: errors.append("saved stock IDs/counts were dropped or mixed")
	loaded.buy("retired_shop", "herb")
	if loaded.shop_stock != state.shop_stock or loaded.inventory != {"coin": 17, "herb": 1}: errors.append("missing retired shop altered saved progress")
	loaded.persistence_enabled = false
	if loaded.buy(Fixture.SHOP, "qingxin_tea").get("reason") != "out_of_stock": errors.append("reopened zero stock allowed a purchase")
	var file_path := state.save_path(0)
	if FileAccess.file_exists(file_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path))
	state.free()
	loaded.free()
