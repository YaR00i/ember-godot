extends SceneTree
## Native item authoring contract: editor, inventory, equipment and economy all
## resolve the same per-item Resource while the shared icon/catalog JSON stays immutable.

const ITEM_ID := "herb"
const Catalog = preload("res://scripts/ember_item_catalog.gd")
const Store = preload("res://addons/ember_import/ember_item_store.gd")
const ItemEditor = preload("res://addons/ember_import/ember_item_editor.gd")
const ShopEditor = preload("res://addons/ember_import/ember_shop_editor.gd")


func _init() -> void:
	quit(_run())


func _run() -> int:
	var errors: Array[String] = []
	var previous := Catalog.snapshot(ITEM_ID)
	var catalog_path := EmberPack.item_catalog_path()
	var legacy_text := FileAccess.get_file_as_string(catalog_path)
	Catalog.delete_native(ITEM_ID)
	_test_legacy_editor(errors)
	_test_migration_and_runtime(errors, legacy_text)
	Catalog.restore(previous)
	if FileAccess.get_file_as_string(catalog_path) != legacy_text:
		errors.append("item authoring mutated the shared JOI items/catalog.json")
	if not errors.is_empty():
		printerr("FAIL item Resource migration")
		for error in errors:
			printerr(" - ", error)
		return 1
	print("PASS item Resource migration")
	print("  legacy item stays read-only until explicit per-item migration")
	print("  inventory, consumable and economy resolve the native .tres")
	print("  Undo/Redo restores owner and values without touching JOI JSON")
	print("  shop listing exposes the embedded item editor")
	return 0


func _test_legacy_editor(errors: Array[String]) -> void:
	if Store.owner(ITEM_ID) != "legacy":
		errors.append("legacy item fixture did not become canonical")
		return
	var editor := ItemEditor.new() as EmberItemEditor
	root.add_child(editor)
	editor.setup(ITEM_ID, "unused")
	var save := editor.find_child("SaveItem", true, false) as Button
	var migrate := editor.find_child("MigrateItemResource", true, false) as Button
	var owner := editor.find_child("ItemStorageOwner", true, false) as Label
	if save == null or not save.disabled:
		errors.append("legacy item editor did not lock destructive save")
	if migrate == null or migrate.disabled:
		errors.append("legacy item editor did not expose migration")
	if owner == null or owner.text != "Legacy JSON":
		errors.append("legacy item owner is not visible")
	editor.free()


func _test_migration_and_runtime(errors: Array[String], legacy_text: String) -> void:
	var history := UndoRedo.new()
	var actions := EmberObjectInspectorActions.new()
	actions.configure(history)
	var context := Node.new()
	if not actions.migrate_item(ITEM_ID, context):
		errors.append("editor action rejected valid item migration")
	else:
		_assert_runtime(errors, "Погребальная трава", 4, 1)
		_test_native_editor_and_shop_bridge(errors)
		var edited := Store.document(ITEM_ID)
		edited["nameRu"] = "Тестовая лечебная трава"
		edited["hpRestore"] = 11
		edited["sellPrice"] = 9
		if not actions.save_item(edited, context):
			errors.append("native item save was rejected")
		else:
			_assert_runtime(errors, "Тестовая лечебная трава", 11, 9)
			if FileAccess.get_file_as_string(EmberPack.item_catalog_path()) != legacy_text:
				errors.append("native item save mutated its legacy fallback")
			history.undo()
			_assert_runtime(errors, "Погребальная трава", 4, 1)
			history.undo()
			if Store.owner(ITEM_ID) != "legacy" or FileAccess.file_exists(Catalog.native_path(ITEM_ID)):
				errors.append("Undo migration did not restore legacy-only owner")
			history.redo()
			_assert_runtime(errors, "Погребальная трава", 4, 1)
			history.redo()
			_assert_runtime(errors, "Тестовая лечебная трава", 11, 9)
	history.clear_history(false)
	history.free()
	context.free()


func _test_native_editor_and_shop_bridge(errors: Array[String]) -> void:
	var editor := ItemEditor.new() as EmberItemEditor
	root.add_child(editor)
	editor.setup(ITEM_ID, "unused")
	var save := editor.find_child("SaveItem", true, false) as Button
	var owner := editor.find_child("ItemStorageOwner", true, false) as Label
	var mana := editor.find_child("ItemMpRestore", true, false) as SpinBox
	var revive := editor.find_child("ItemReviveHp", true, false) as SpinBox
	var combat_range := editor.find_child("ItemCombatRange", true, false) as SpinBox
	if save == null or save.disabled or owner == null or owner.text != "Godot Resource":
		errors.append("native item did not reopen as editable Resource")
	if mana == null or revive == null or combat_range == null:
		errors.append("native item editor does not expose combat restoration and range")
	var invalid_combat := Store.normalized_document({
		"id": "empty_tonic", "nameRu": "Пустышка", "kind": "consumable",
		"slot": "none", "rarity": "common", "useIn": "arena",
	})
	if Store.validation_errors(invalid_combat).is_empty():
		errors.append("combat consumable without HP/MP/revive effect passed validation")
	editor.free()

	var shop := ShopEditor.new() as EmberShopEditor
	root.add_child(shop)
	shop.setup("", "test_item_shop")
	shop.call("_add_listing", {"itemId": ITEM_ID, "buyPrice": 3, "sellPrice": 1}, true)
	var edit := shop.find_child("EditShopItem", true, false) as Button
	if edit == null or edit.disabled:
		errors.append("editable shop listing did not expose item authoring")
	else:
		edit.pressed.emit()
		if shop.find_child("EmberItemEditor", true, false) == null:
			errors.append("shop listing did not open the embedded item editor")
	shop.free()


func _assert_runtime(errors: Array[String], expected_name: String, expected_heal: int, expected_sell: int) -> void:
	if Store.owner(ITEM_ID) != "native":
		errors.append("native item Resource did not become canonical")
		return
	var items := EmberInteractionContent.item_definitions()
	var item: Dictionary = items.get(ITEM_ID, {})
	if str(item.get("nameRu", "")) != expected_name:
		errors.append("inventory catalog reopened stale item values")
	var use := EmberEquipment.use_item({ITEM_ID: 1}, EmberEquipment.empty(), ITEM_ID, items)
	if not bool(use.get("ok", false)) or int(use.get("heal", -1)) != expected_heal:
		errors.append("consumable runtime read stale hpRestore")
	var sell: Variant = EmberEconomy.resolve_sell_price(ITEM_ID, {"id": "empty", "listings": []}, items)
	if sell == null or int(sell) != expected_sell:
		errors.append("economy runtime read stale item sellPrice")
	if ITEM_ID not in EmberInteractionContent.item_ids():
		errors.append("native item is missing from shared editor/runtime IDs")
