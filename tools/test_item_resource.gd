extends SceneTree
## Native catalog/editor/runtime gate; mutations require a disposable project.

const Fixture = preload("res://tools/fixtures/ember_party_test_fixture.gd")
const Catalog = preload("res://scripts/ember_item_catalog.gd")
const Store = preload("res://addons/ember_import/ember_item_store.gd")
const ItemEditor = preload("res://addons/ember_import/ember_item_editor.gd")
const ShopEditor = preload("res://addons/ember_import/ember_shop_editor.gd")
const ITEM_ID := "catalog_fixture_tonic"
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
		printerr("FAIL native item fixture preparation")
		quit(1)
		return
	_test_native_catalog(errors)
	_test_editor_history(errors)
	_test_retired_save_ids(errors)
	Fixture.verify_sources(_setup, errors)
	if not errors.is_empty():
		printerr("FAIL native item Resource")
		for error in errors: printerr(" - ", error)
		quit(1)
		return
	print("PASS native item Resource")
	print("  native items/icons ignore poisoned and missing legacy JSON")
	print("  editor create/edit/cancel/validation, Undo/Redo and reopen share one owner")
	print("  runtime heal/sell/save preserve native values and retired saved counts")
	quit(0)


func _test_native_catalog(errors: Array[String]) -> void:
	var before := Catalog.definitions()
	var icons := Catalog.icon_definitions()
	var pack: String = _setup.directory.path_join("poison-pack")
	var path := pack.path_join("items/catalog.json")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"items": [{"id": "herb", "nameRu": "Poison", "hpRestore": 999}, {"id": "retired_only", "kind": "armor"}],
		"icons": [{"id": "herb", "size": 1, "palette": {"X": "#ff0000"}, "rows": ["X"]}, {"id": "retired_icon"}]}))
	file.close()
	_setup.poison_path = path
	_setup.poison_sha = FileAccess.get_sha256(path)
	ProjectSettings.set_setting("ember/pack_path", pack)
	if Catalog.definitions() != before or Catalog.ids() != Catalog.native_ids() or not Catalog.definition("retired_only").is_empty() or Catalog.owner("retired_only") != "":
		errors.append("poisoned legacy item JSON leaked into native catalog")
	if Catalog.icon_definitions() != icons or "retired_icon" in Catalog.icon_ids() or Catalog.icon_definition("herb") != icons.get("herb"):
		errors.append("poisoned legacy icon JSON leaked into native library")
	# First image reads happen with a conflicting legacy icon present.
	for id in ["coin", "herb", "bun", "potion", "tunic", "tofu"]:
		var image := EmberItemVisuals.icon_image(id)
		if image.get_width() != 16 or image.get_height() != 16 or image.is_invisible(): errors.append("native pixel icon absent: " + id)
	ProjectSettings.set_setting("ember/pack_path", pack.path_join("missing"))
	if Catalog.definitions() != before or Catalog.icon_definitions() != icons or Store.source_path("retired_only") != "":
		errors.append("native catalog depended on physical legacy item JSON")
	for id in Catalog.ids():
		if Catalog.owner(id) != "native" or Catalog.definition(id).is_empty(): errors.append("native item did not resolve: " + id)
	for id in ["", "../herb", "Herb", "retired_only"]:
		if not Catalog.definition(id).is_empty() or not Catalog.icon_definition(id).is_empty(): errors.append("invalid/missing ID resolved: " + id)
	for id in ["coin", "herb", "meat_bun", "qingxin_tea", "revival_spark", "traveler_tunic", "almond_tofu"]:
		if not Store.validation_errors(Catalog.definition(id)).is_empty(): errors.append("current native item failed editor validation: " + id)


func _test_editor_history(errors: Array[String]) -> void:
	var history := UndoRedo.new()
	var actions := EmberObjectInspectorActions.new()
	actions.configure(history)
	var context := Node.new()
	var editor := ItemEditor.new() as EmberItemEditor
	root.add_child(editor)
	editor.setup("", ITEM_ID)
	var created: Dictionary = {}
	editor.save_requested.connect(func(document: Dictionary) -> void: created.merge(document, true))
	(editor.find_child("ItemNameRu", true, false) as LineEdit).text = "Тестовый настой"
	(editor.find_child("SaveItem", true, false) as Button).pressed.emit()
	if created.is_empty() or not Store.validation_errors(created).is_empty(): errors.append("new native editor did not emit a valid document")
	created.merge({"kind": "consumable", "hpRestore": 4, "sellPrice": 1, "iconId": "herb", "useIn": "both"}, true)
	if not actions.save_item(created, context):
		errors.append("new native item save was rejected")
	else:
		_assert_runtime(errors, 4, 1)
		var reopened := ItemEditor.new() as EmberItemEditor
		root.add_child(reopened)
		reopened.setup(ITEM_ID, "unused")
		var owner := reopened.find_child("ItemStorageOwner", true, false) as Label
		if owner == null or owner.text != "Godot Resource" or reopened.find_child("MigrateItemResource", true, false) != null:
			errors.append("native editor retained legacy migration UI")
		if reopened.find_child("ItemMpRestore", true, false) == null or reopened.find_child("ItemReviveHp", true, false) == null or reopened.find_child("ItemCombatRange", true, false) == null:
			errors.append("native editor lost combat fields")
		var source_sha := FileAccess.get_sha256(Catalog.native_path(ITEM_ID))
		(reopened.find_child("ItemHpRestore", true, false) as SpinBox).value = 99
		(reopened.find_child("CancelItem", true, false) as Button).pressed.emit()
		if FileAccess.get_sha256(Catalog.native_path(ITEM_ID)) != source_sha: errors.append("discard wrote the item Resource")
		reopened.free()
		var edited := Store.document(ITEM_ID)
		edited.merge({"hpRestore": 11, "sellPrice": 9}, true)
		if not actions.save_item(edited, context): errors.append("native edit was rejected")
		_assert_runtime(errors, 11, 9)
		history.undo()
		_assert_runtime(errors, 4, 1)
		history.undo()
		if Catalog.owner(ITEM_ID) != "" or not Catalog.definition(ITEM_ID).is_empty() or ITEM_ID in Catalog.ids(): errors.append("Undo create exposed a fallback item")
		history.redo()
		_assert_runtime(errors, 4, 1)
		history.redo()
		_assert_runtime(errors, 11, 9)
		var invalid := Store.document(ITEM_ID)
		invalid.iconId = "retired_icon"
		if actions.save_item(invalid, context) or Store.validation_errors(invalid).is_empty(): errors.append("unknown native icon passed validation")
		invalid = Store.normalized_document({"id": "empty_tonic", "nameRu": "Пустышка", "kind": "consumable", "useIn": "arena"})
		if Store.validation_errors(invalid).is_empty(): errors.append("effectless combat consumable passed validation")
		var shop := ShopEditor.new() as EmberShopEditor
		root.add_child(shop)
		shop.setup("", "test_item_shop")
		shop.call("_add_listing", {"itemId": ITEM_ID, "buyPrice": 3, "sellPrice": 1}, true)
		var edit := shop.find_child("EditShopItem", true, false) as Button
		if edit == null or edit.disabled: errors.append("shop did not expose embedded item editor")
		else:
			edit.pressed.emit()
			if shop.find_child("EmberItemEditor", true, false) == null: errors.append("shop did not open embedded item editor")
		shop.free()
	editor.free()
	history.clear_history(false)
	history.free()
	context.free()
	if FileAccess.get_sha256(_setup.poison_path) != _setup.poison_sha: errors.append("item authoring touched the legacy poison catalog")


func _assert_runtime(errors: Array[String], heal: int, sell_price: int) -> void:
	var items := EmberInteractionContent.item_definitions()
	if Catalog.owner(ITEM_ID) != "native" or ITEM_ID not in EmberInteractionContent.item_ids(): errors.append("native item absent from shared runtime IDs")
	var use := EmberEquipment.use_item({ITEM_ID: 1}, EmberEquipment.empty(), ITEM_ID, items)
	if not bool(use.get("ok", false)) or int(use.get("heal", -1)) != heal: errors.append("runtime healing read stale native values")
	var sell: Variant = EmberEconomy.resolve_sell_price(ITEM_ID, {"listings": []}, items)
	if sell == null or int(sell) != sell_price: errors.append("runtime economy read stale native values")
	var state := EmberExploreState.new()
	state.persistence_enabled = false
	state.reset_new_game()
	state.hp = 1
	state.inventory = {ITEM_ID: 1}
	var consumed := state.use_item(ITEM_ID, false)
	if not bool(consumed.get("ok", false)) or state.hp != 1 + heal or state.inventory.has(ITEM_ID): errors.append("progress consumable bypassed native definition")
	state.free()


func _test_retired_save_ids(errors: Array[String]) -> void:
	var state := EmberExploreState.new()
	state.storage_root = _setup.directory.path_join("retired-save")
	state.reset_new_game()
	state.set_world_context(_setup.map_id, null, 16.0)
	var payload := state.capture_save()
	payload.inventory = {"retired_only": 250, "coin": 23}
	payload.party.mira.equipment.weapon = "retired_only"
	state._apply_v2_payload(payload, false)
	if state.inventory.get("retired_only") != 251 or state.party.mira.equipment.weapon != null: errors.append("retired saved equipment/counts were lost")
	if not state.save_slot(0): errors.append("retired counts could not be saved")
	var loaded := EmberExploreState.new()
	loaded.storage_root = state.storage_root
	if not loaded.load_slot(0) or loaded.inventory.get("retired_only") != 251: errors.append("retired counts changed on save reopen")
	loaded.capture_save()
	loaded.capture_save()
	if loaded.inventory.get("retired_only") != 251: errors.append("retired equipment was returned repeatedly")
	loaded.free()
	state.free()
	var legacy_state := EmberExploreState.new()
	legacy_state.storage_root = _setup.directory.path_join("retired-v1-upgrade")
	legacy_state.legacy_storage_root = _setup.directory.path_join("retired-v1-source")
	var legacy_path := legacy_state.legacy_save_path(0)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(legacy_path.get_base_dir()))
	var legacy_file := FileAccess.open(legacy_path, FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify({"version": 1, "packId": "ember_p1", "slot": 0,
		"mapId": _setup.map_id, "inventory": {"retired_only": 250, "coin": 23},
		"equipment": {"weapon": "retired_only"}, "hp": 50, "maxHp": 100}))
	legacy_file.close()
	var legacy_sha := FileAccess.get_sha256(legacy_path)
	if not legacy_state.load_slot(0) or legacy_state.inventory.get("retired_only") != 251 or legacy_state.hp != 10:
		errors.append("retired v1 equipment/counts or HP ratio were lost")
	if FileAccess.get_sha256(legacy_state.migration_backup_path(0)) != legacy_sha or FileAccess.get_sha256(legacy_path) != legacy_sha:
		errors.append("v1 migration changed original saved bytes")
	legacy_state.free()
