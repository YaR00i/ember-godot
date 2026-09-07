extends SceneTree
## Native shop authoring contract: legacy catalog entries are read-only until
## explicitly migrated, then editor/runtime/economy share one Resource owner.

const SHOP_ID := "village_kiosk"
const Catalog = preload("res://scripts/ember_shop_catalog.gd")
const Store = preload("res://addons/ember_import/ember_shop_store.gd")
const ShopEditor = preload("res://addons/ember_import/ember_shop_editor.gd")
const ActionChainEditor = preload("res://addons/ember_import/ember_action_chain_editor.gd")


func _init() -> void:
	quit(_run())


func _run() -> int:
	var errors: Array[String] = []
	var previous := Catalog.snapshot(SHOP_ID)
	var catalog_path := EmberPack.shop_catalog_path()
	var legacy_text := FileAccess.get_file_as_string(catalog_path)
	Catalog.delete_native(SHOP_ID)
	_test_legacy_editor(errors)
	_test_migration_and_runtime(errors, legacy_text)
	Catalog.restore(previous)
	if FileAccess.get_file_as_string(catalog_path) != legacy_text:
		errors.append("shop authoring mutated the shared JOI shops/catalog.json")
	if not errors.is_empty():
		printerr("FAIL shop Resource migration")
		for error in errors:
			printerr(" - ", error)
		return 1
	print("PASS shop Resource migration")
	print("  legacy shop stays read-only until explicit per-shop migration")
	print("  native editor save and runtime economy resolve the same .tres")
	print("  Undo/Redo restores owner and values without touching JOI JSON")
	print("  open_shop action exposes the embedded shop editor")
	return 0


func _test_legacy_editor(errors: Array[String]) -> void:
	if Store.owner(SHOP_ID) != "legacy":
		errors.append("legacy fixture did not become the initial canonical owner")
		return
	var editor := ShopEditor.new() as EmberShopEditor
	root.add_child(editor)
	editor.setup(SHOP_ID, "unused")
	var save := editor.find_child("SaveShop", true, false) as Button
	var migrate := editor.find_child("MigrateShopResource", true, false) as Button
	var owner := editor.find_child("ShopStorageOwner", true, false) as Label
	if save == null or not save.disabled:
		errors.append("legacy shop editor did not lock destructive save")
	if migrate == null or migrate.disabled:
		errors.append("legacy shop editor did not expose explicit migration")
	if owner == null or owner.text != "Legacy JSON":
		errors.append("legacy storage owner is not visible in the editor")
	editor.free()


func _test_migration_and_runtime(errors: Array[String], legacy_text: String) -> void:
	var history := UndoRedo.new()
	var actions := EmberObjectInspectorActions.new()
	actions.configure(history)
	var context := Node.new()
	if not actions.migrate_shop(SHOP_ID, context):
		errors.append("editor action rejected a valid legacy shop migration")
	else:
		_assert_runtime(errors, "Киоск деревни", 6)
		_test_native_editor_bridge(errors)
		var edited := Store.document(SHOP_ID)
		edited["nameRu"] = "Киоск тестовой миграции"
		var listings: Array = edited.get("listings", [])
		if listings.is_empty():
			errors.append("migrated shop lost its listings")
		else:
			(listings[0] as Dictionary)["buyPrice"] = 17
			if not actions.save_shop(edited, context):
				errors.append("native shop save was rejected")
			else:
				_assert_runtime(errors, "Киоск тестовой миграции", 17)
				if FileAccess.get_file_as_string(EmberPack.shop_catalog_path()) != legacy_text:
					errors.append("native shop save mutated its legacy fallback")
				history.undo()
				_assert_runtime(errors, "Киоск деревни", 6)
				history.undo()
				if Store.owner(SHOP_ID) != "legacy" or FileAccess.file_exists(Catalog.native_path(SHOP_ID)):
					errors.append("Undo migration did not restore the legacy-only owner")
				history.redo()
				_assert_runtime(errors, "Киоск деревни", 6)
				history.redo()
				_assert_runtime(errors, "Киоск тестовой миграции", 17)
	history.clear_history(false)
	history.free()
	context.free()


func _test_native_editor_bridge(errors: Array[String]) -> void:
	var editor := ShopEditor.new() as EmberShopEditor
	root.add_child(editor)
	editor.setup(SHOP_ID, "unused")
	var save := editor.find_child("SaveShop", true, false) as Button
	var owner := editor.find_child("ShopStorageOwner", true, false) as Label
	var listings := editor.find_child("ShopListings", true, false) as VBoxContainer
	var listing_count := -1 if listings == null else listings.get_child_count()
	if save == null or save.disabled or owner == null or owner.text != "Godot Resource":
		errors.append("native shop did not reopen as editable Resource")
	if listing_count != Store.document(SHOP_ID).get("listings", []).size():
		errors.append("shop editor did not project every canonical listing")
	editor.free()

	var chain := ActionChainEditor.new() as EmberActionChainEditor
	root.add_child(chain)
	chain.setup("", "test_shop_chain")
	chain.call("_add_step", {"type": "open_shop", "shopId": SHOP_ID})
	var edit := chain.find_child("EditShop", true, false) as Button
	if edit == null:
		errors.append("open_shop step did not expose shop authoring")
	else:
		edit.pressed.emit()
		if chain.find_child("EmberShopEditor", true, false) == null:
			errors.append("open_shop step did not open the embedded shop editor")
	chain.free()


func _assert_runtime(errors: Array[String], expected_name: String, expected_first_price: int) -> void:
	if Store.owner(SHOP_ID) != "native":
		errors.append("native shop Resource did not become canonical")
		return
	var editor_document := Store.document(SHOP_ID)
	var runtime_view := EmberInteractionContent.shop_view(SHOP_ID)
	var listings: Array = runtime_view.get("listings", [])
	if str(editor_document.get("nameRu", "")) != expected_name:
		errors.append("shop store reopened stale values")
	if str(runtime_view.get("nameRu", "")) != expected_name or listings.is_empty():
		errors.append("runtime did not resolve the native shop Resource")
	elif int((listings[0] as Dictionary).get("buyPrice", -1)) != expected_first_price:
		errors.append("runtime economy read a stale legacy price")
	if SHOP_ID not in EmberInteractionContent.shop_ids():
		errors.append("native shop is missing from the shared editor/runtime IDs")
