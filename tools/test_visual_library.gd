extends SceneTree
## Visual-library contract: pixel glyphs are decoded from the canonical catalog,
## tiled search keeps stable IDs, and item/shop editors expose the shared picker.

const ItemVisuals = preload("res://scripts/ember_item_visuals.gd")
const VisualPicker = preload("res://addons/ember_import/ember_visual_library_picker.gd")
const ItemEditor = preload("res://addons/ember_import/ember_item_editor.gd")
const ShopEditor = preload("res://addons/ember_import/ember_shop_editor.gd")
const VnAssets = preload("res://scripts/ember_vn_assets.gd")
const VnVisuals = preload("res://scripts/ember_vn_visuals.gd")


const Fixture = preload("res://tools/fixtures/ember_vn_test_fixture.gd")
var _state: Dictionary

func _init() -> void:
	_state = Fixture.prepare(self)
	if _state.refused:
		quit.call_deferred(2)
		return
	_run_deferred.call_deferred()

func _run_deferred() -> void:
	quit(_run())


func _run() -> int:
	var errors: Array[String] = []
	_test_pixel_decode(errors)
	_test_tiled_picker(errors)
	_test_editor_projection(errors)
	_test_vn_projection(errors)
	if not errors.is_empty():
		printerr("FAIL visual asset library")
		for error in errors:
			printerr(" - ", error)
		return 1
	print("PASS visual asset library")
	print("  canonical pixel icon rows decode without a second asset owner")
	print("  ItemList tiles search and return stable icon IDs")
	print("  item and shop editors expose previews plus the shared library")
	print("  VN backgrounds, speakers and expressions reuse the same tile contract")
	return 0


func _test_pixel_decode(errors: Array[String]) -> void:
	var image := ItemVisuals.icon_image("herb")
	if image.get_size() != Vector2i(16, 16):
		errors.append("herb icon did not preserve its canonical 16x16 grid")
		return
	if image.get_pixel(0, 0).a != 0.0:
		errors.append("transparent pixel glyph cells became opaque")
	if image.get_pixel(8, 1).a < 0.99:
		errors.append("palette-backed herb pixel was not decoded")


func _test_tiled_picker(errors: Array[String]) -> void:
	var picker := VisualPicker.new() as EmberVisualLibraryPicker
	root.add_child(picker)
	picker.setup("Иконки", ItemVisuals.icon_entries(), "herb")
	var items := picker.find_child("VisualLibraryList", true, false) as ItemList
	var search := picker.find_child("LibrarySearch", true, false) as LineEdit
	if items == null or items.icon_mode != ItemList.ICON_MODE_TOP or items.fixed_icon_size != Vector2i(56, 56):
		errors.append("visual picker is not using the native tiled ItemList contract")
	if picker.selected_id() != "herb":
		errors.append("visual picker lost the current canonical ID")
	search.text = "трава"
	picker.call("_refresh")
	if items.item_count != 1 or str(items.get_item_metadata(0)) != "herb":
		errors.append("visual picker search does not resolve localized name to icon ID")
	var chosen: Array[String] = []
	picker.value_chosen.connect(func(value: String) -> void: chosen.append(value))
	items.item_activated.emit(0)
	if chosen != ["herb"]:
		errors.append("double activation did not return the stable icon ID")
	picker.free()


func _test_editor_projection(errors: Array[String]) -> void:
	var item_editor := ItemEditor.new() as EmberItemEditor
	root.add_child(item_editor)
	item_editor.setup("", "visual_test_item")
	if item_editor.find_child("ItemIconPreview", true, false) == null:
		errors.append("item editor has no selected-icon preview")
	if item_editor.find_child("OpenItemIconLibrary", true, false) == null:
		errors.append("item editor has no visual icon library action")
	item_editor.free()

	var shop_editor := ShopEditor.new() as EmberShopEditor
	root.add_child(shop_editor)
	shop_editor.setup("", "visual_test_shop")
	shop_editor.call("_add_listing", {"itemId": "herb"}, true)
	if shop_editor.find_child("ShopItemPreview", true, false) == null:
		errors.append("shop listing has no selected-item preview")
	if shop_editor.find_child("ShopItemLibrary", true, false) == null:
		errors.append("shop listing has no tiled item library action")
	shop_editor.free()


func _test_vn_projection(errors: Array[String]) -> void:
	var background := Fixture.import_fixture(_state, false)
	var portrait := Fixture.import_fixture(_state, true)
	if not background.get("ok", false) or not portrait.get("ok", false):
		errors.append("native VN visual fixture import failed")
		return
	var assets := VnAssets.new() as EmberVnAssets
	var art_entries := VnVisuals.background_entries(assets, "Наследовать", "Фон сцены", null, background.id)
	if art_entries.size() < 2 or str(art_entries[0].get("id", "missing")) != "" or not _entries_have_id(art_entries, background.id):
		errors.append("VN visual adapter lost native background/inheritance tiles")
	var speakers := VnVisuals.speaker_entries(assets, "fixture_speaker")
	if not _entries_have_id(speakers, "fixture_speaker"): errors.append("native speaker tile missing")
	var portraits := VnVisuals.portrait_entries(assets, "fixture_speaker", portrait.portraitKey)
	if not _entries_have_id(portraits, portrait.portraitKey): errors.append("native expression tile missing")
	var missing_background := VnVisuals.background_entries(assets, "", "", null, "retired_art")
	var missing_speaker := VnVisuals.speaker_entries(assets, "retired_speaker")
	var missing_portrait := VnVisuals.portrait_entries(assets, "retired_speaker", "retired_expression")
	if not _entries_have_id(missing_background, "retired_art") or not _entries_have_id(missing_speaker, "retired_speaker") or not _entries_have_id(missing_portrait, "retired_expression"):
		errors.append("missing saved VN ID erased")
	Fixture.check_detached(_state, errors)



func _entries_have_id(entries: Array[Dictionary], expected: String) -> bool:
	for entry in entries:
		if str(entry.get("id", "")) == expected:
			return true
	return false
