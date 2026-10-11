extends SceneTree
## Native shop authoring contract; guarded fixtures replace historical catalogs.

const SHOP_ID := "shop_authoring_fixture"
const Fixture = preload("res://tools/fixtures/ember_shop_test_fixture.gd")
var _setup: Dictionary
const Catalog = preload("res://scripts/ember_shop_catalog.gd")
const Store = preload("res://addons/ember_import/ember_shop_store.gd")
const ShopEditor = preload("res://addons/ember_import/ember_shop_editor.gd")
const ActionChainEditor = preload("res://addons/ember_import/ember_action_chain_editor.gd")


func _init() -> void:
	_setup = Fixture.prepare(self)
	if _setup.refused:
		quit.call_deferred(2)
		return
	_run_and_quit.call_deferred()


func _run_and_quit() -> void:
	quit(_run())


func _run() -> int:
	var errors: Array[String] = []
	if _setup.error != OK or not _setup.progress_isolated:
		printerr("FAIL native shop fixture preparation")
		return 1
	_test_native_catalog(errors)
	_test_creation_and_runtime(errors)
	Fixture.verify_sources(_setup, errors)
	if FileAccess.get_sha256(_setup.poison_path) != _setup.poison_sha:
		errors.append("shop authoring changed poisoned legacy bytes")
	if not errors.is_empty():
		printerr("FAIL shop Resource migration")
		for error in errors:
			printerr(" - ", error)
		return 1
	print("PASS native shop Resource")
	print("  poisoned/missing JSON has no effect on native IDs, owner or prices")
	print("  native editor save and runtime economy resolve the same .tres")
	print("  create/edit/discard/Undo/Redo and reopen preserve native values")
	print("  open_shop action exposes the embedded shop editor")
	return 0


func _test_native_catalog(errors: Array[String]) -> void:
	var before: Array[String] = Catalog.ids()
	var document := Catalog.definition(Fixture.SHOP)
	var pack: String = _setup.directory.path_join("poison-pack")
	var path := pack.path_join("shops/catalog.json")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"shops": [
		{"id": Fixture.SHOP, "nameRu": "Poison", "listings": [{"itemId": "herb", "buyPrice": 999}]},
		{"id": "retired_shop", "nameRu": "Retired", "listings": []}]}))
	file.close()
	_setup.poison_path = path
	_setup.poison_sha = FileAccess.get_sha256(path)
	ProjectSettings.set_setting("ember/pack_path", pack)
	if Catalog.ids() != before or Catalog.definition(Fixture.SHOP) != document or not Catalog.definition("retired_shop").is_empty() or Catalog.owner("retired_shop") != "":
		errors.append("legacy shops leaked into native catalog")
	if Store.source_path("retired_shop") != "": errors.append("missing shop retained legacy source")
	ProjectSettings.set_setting("ember/pack_path", pack.path_join("missing"))
	if Catalog.ids() != before or Catalog.definition(Fixture.SHOP) != document or Catalog.owner(Fixture.SHOP) != "native":
		errors.append("native shops required physical legacy JSON")
	for id in ["", "../shop_fixture", "Shop_fixture", "retired_shop"]:
		if not Catalog.definition(id).is_empty(): errors.append("invalid/missing shop resolved: " + id)
	var invalid := Fixture.document("invalid_shop")
	invalid.listings.append(invalid.listings[0].duplicate(true))
	if Store.validation_errors(invalid).is_empty(): errors.append("duplicate listing passed validation")
	invalid = Fixture.document("invalid_shop")
	invalid.listings[0].itemId = "retired_item"
	if Store.validation_errors(invalid).is_empty(): errors.append("missing native item passed validation")


func _test_creation_and_runtime(errors: Array[String]) -> void:
	var history := UndoRedo.new()
	var actions := EmberObjectInspectorActions.new()
	actions.configure(history)
	var context := Node.new()
	var editor := ShopEditor.new() as EmberShopEditor
	root.add_child(editor)
	editor.setup("", SHOP_ID)
	(editor.find_child("ShopName", true, false) as LineEdit).text = "Тестовая лавка"
	for listing in Fixture.document(SHOP_ID).listings: editor.call("_add_listing", listing, true)
	var created: Dictionary = {}
	editor.save_requested.connect(func(document: Dictionary) -> void: created.merge(document, true))
	(editor.find_child("SaveShop", true, false) as Button).pressed.emit()
	if created.is_empty() or not actions.save_shop(created, context):
		errors.append("editor action rejected a new native shop")
	else:
		_assert_runtime(errors, "Тестовая лавка", 6)
		_test_native_editor_bridge(errors)
		var edited := Store.document(SHOP_ID)
		edited["nameRu"] = "Правки тестовой лавки"
		var listings: Array = edited.get("listings", [])
		if listings.is_empty():
			errors.append("native shop lost its listings")
		else:
			(listings[0] as Dictionary)["buyPrice"] = 17
			if not actions.save_shop(edited, context):
				errors.append("native shop save was rejected")
			else:
				_assert_runtime(errors, "Правки тестовой лавки", 17)
				history.undo()
				_assert_runtime(errors, "Тестовая лавка", 6)
				history.undo()
				if Store.owner(SHOP_ID) != "" or not Catalog.definition(SHOP_ID).is_empty() or SHOP_ID in Catalog.ids():
					errors.append("Undo create did not remove the shop without fallback")
				history.redo()
				_assert_runtime(errors, "Тестовая лавка", 6)
				history.redo()
				_assert_runtime(errors, "Правки тестовой лавки", 17)
	editor.free()
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
	if editor.find_child("MigrateShopResource", true, false) != null:
		errors.append("native shop retained obsolete migration UI")
	var source_sha := FileAccess.get_sha256(Catalog.native_path(SHOP_ID))
	var first := listings.get_child(0) as PanelContainer
	editor.call("_move_listing", first, 1)
	var draft: Dictionary = editor.call("_document")
	if draft.listings[0].itemId != "meat_bun": errors.append("listing reorder failed")
	editor.call("_remove_listing", first)
	draft = editor.call("_document")
	if draft.listings.size() != 2 or draft.listings[0].has("stock"): errors.append("listing delete lost infinite stock semantics")
	(editor.find_child("CancelShop", true, false) as Button).pressed.emit()
	if FileAccess.get_sha256(Catalog.native_path(SHOP_ID)) != source_sha: errors.append("discard saved a modified shop")
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
		errors.append("shop store reopened stale native values")
	if str(runtime_view.get("nameRu", "")) != expected_name or listings.is_empty():
		errors.append("runtime did not resolve the native shop Resource")
	elif int((listings[0] as Dictionary).get("buyPrice", -1)) != expected_first_price:
		errors.append("runtime economy read a stale native price")
	if SHOP_ID not in EmberInteractionContent.shop_ids():
		errors.append("native shop is missing from the shared editor/runtime IDs")
