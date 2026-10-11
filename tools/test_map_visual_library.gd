extends SceneTree
const MixedFixture = preload("res://tools/fixtures/ember_mixed_editor_test_fixture.gd")
## Native saved-region schematics and stable destination IDs in both pickers.
## The test never writes authored scenes or opens them in the runtime tree.

const MapVisuals = preload("res://scripts/ember_map_visuals.gd")
const InteractEditor = preload("res://addons/ember_import/ember_interact_editor.gd")
const ChainEditor = preload("res://addons/ember_import/ember_action_chain_editor.gd")


func _init() -> void:
	if not MixedFixture.prepare(self):
		quit(2)
		return
	quit(_run())


func _run() -> int:
	var errors: Array[String] = []
	var source_path := "res://scenes/editor_fixture_b.tscn"
	var source_hash := FileAccess.get_sha256(source_path)
	var previous_pack: Variant = ProjectSettings.get_setting("ember/pack_path", "")
	ProjectSettings.set_setting("ember/pack_path", "user://missing-map-visual-pack")
	_test_native_schematic(errors)
	_test_map_and_region_entries(errors)
	ProjectSettings.set_setting("ember/pack_path", previous_pack)
	_test_interact_picker(errors)
	_test_action_picker(errors)
	if FileAccess.get_sha256(source_path) != source_hash:
		errors.append("visual projection changed canonical map scene")
	MixedFixture.verify_sources(errors)
	if not errors.is_empty():
		printerr("FAIL map visual library")
		for error in errors:
			printerr(" - ", error)
		return 1
	print("PASS map visual library")
	print("  CPU schematics read saved native regions without JOI")
	print("  region tiles highlight saved map regions without scene execution")
	print("  door and change-map editors keep stable destination IDs")
	print("  canonical map scene stays unchanged")
	return 0


func _test_native_schematic(errors: Array[String]) -> void:
	var image := MapVisuals.map_image("editor_fixture_b")
	if image.get_size() != MapVisuals.PREVIEW_SIZE:
		errors.append("map thumbnail did not preserve the 96x96 preview contract")
	elif _unique_opaque_colors(image) < 3:
		errors.append("native schematic does not show saved region markers")


func _test_map_and_region_entries(errors: Array[String]) -> void:
	var map_entries := MapVisuals.map_entries()
	if map_entries.size() != EmberInteractionContent.map_ids().size():
		errors.append("visual map library dropped canonical map IDs")
	if not _entries_have_id(map_entries, "editor_fixture_b"):
		errors.append("visual map library has no editor_fixture_b card")
	if not _entries_have_id(map_entries, "landscape_compact"):
		errors.append("visual map library has no current landscape_compact card")
	if not _entries_have_id(MapVisuals.region_entries("landscape_compact"), "landscape_compact_start"):
		errors.append("visual region library has no current native entrance")
	var regions := MapVisuals.region_entries("editor_fixture_b")
	if not _entries_have_id(regions, "") or not _entries_have_id(regions, "entry") or not _entries_have_id(regions, "notice"):
		errors.append("region library lost default/start/notice destinations")
	var base := MapVisuals.map_image("editor_fixture_b")
	var highlighted := MapVisuals.map_image("editor_fixture_b", "notice")
	if base.get_data() == highlighted.get_data():
		errors.append("selected region has no visual highlight")


func _test_interact_picker(errors: Array[String]) -> void:
	var editor := InteractEditor.new() as EmberInteractEditor
	root.add_child(editor)
	editor.setup({
		"kind": "door",
		"target_map_id": "editor_fixture_destination",
		"target_region_id": "entry",
	}, false, "editor_fixture_b")
	if editor.find_child("OpenTargetMapLibrary", true, false) == null:
		errors.append("door form has no visual map library button")
	if editor.find_child("OpenTargetRegionLibrary", true, false) == null:
		errors.append("door form has no visual region library button")
	editor.set("_map_library_mode", "map")
	editor.call("_choose_map_library_value", "editor_fixture_b")
	editor.set("_map_library_mode", "region")
	editor.call("_choose_map_library_value", "notice")
	var values: Dictionary = editor.call("_values")
	if str(values.get("target_map_id", "")) != "editor_fixture_b" or str(values.get("target_region_id", "")) != "notice":
		errors.append("door visual picker did not project stable map/region IDs")
	editor.free()


func _test_action_picker(errors: Array[String]) -> void:
	var editor := ChainEditor.new() as EmberActionChainEditor
	root.add_child(editor)
	editor.setup("map_visual_test", "map_visual_test", {
		"id": "map_visual_test",
		"nameRu": "Map visual test",
		"steps": [{
			"type": "change_map",
			"targetMapId": "editor_fixture_destination",
			"targetRegionId": "entry",
		}],
	})
	var map_option := editor.find_child("StepField_targetMapId", true, false) as OptionButton
	var region_option := editor.find_child("StepField_targetRegionId", true, false) as OptionButton
	var region_button := editor.find_child("OpenStepRegionLibrary", true, false) as Button
	var map_button := editor.find_child("OpenStepMapLibrary", true, false) as Button
	if map_button == null or region_button == null:
		errors.append("change-map step has no visual destination buttons")
	elif map_option == null or region_option == null:
		errors.append("change-map step lost its compact destination fields")
	else:
		editor.set("_map_library_mode", "map")
		editor.set("_map_target_option", map_option)
		editor.set("_map_region_option", region_option)
		editor.set("_map_region_library_button", region_button)
		editor.call("_choose_map_library_value", "editor_fixture_b")
		editor.set("_map_library_mode", "region")
		editor.call("_choose_map_library_value", "notice")
		var document: Dictionary = editor.call("_document")
		var steps: Array = document.get("steps", [])
		if steps.size() != 1:
			errors.append("change-map editor changed the action step count")
		else:
			var step: Dictionary = steps[0]
			if str(step.get("targetMapId", "")) != "editor_fixture_b" or str(step.get("targetRegionId", "")) != "notice":
				errors.append("change-map visual picker did not preserve stable IDs")
	editor.free()


func _unique_opaque_colors(image: Image) -> int:
	var colors := {}
	for y in image.get_height():
		for x in image.get_width():
			var color := image.get_pixel(x, y)
			if color.a > 0.9:
				colors[color.to_html(false)] = true
	return colors.size()


func _entries_have_id(entries: Array[Dictionary], expected: String) -> bool:
	for entry in entries:
		if str(entry.get("id", "")) == expected:
			return true
	return false
