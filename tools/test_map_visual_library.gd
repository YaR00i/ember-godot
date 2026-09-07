extends SceneTree
## One contract for runtime terrain projection and the visual destination picker.
## The test never writes map JSON or opens map scenes.

const MapVisuals = preload("res://scripts/ember_map_visuals.gd")
const InteractEditor = preload("res://addons/ember_import/ember_interact_editor.gd")
const ChainEditor = preload("res://addons/ember_import/ember_action_chain_editor.gd")


func _init() -> void:
	quit(_run())


func _run() -> int:
	var errors: Array[String] = []
	var source_path := EmberPack.map_path("agent_sandbox")
	var source_hash := FileAccess.get_sha256(source_path)
	_test_surface_projection(errors)
	_test_map_and_region_entries(errors)
	_test_interact_picker(errors)
	_test_action_picker(errors)
	if FileAccess.get_sha256(source_path) != source_hash:
		errors.append("visual projection changed canonical map JSON")
	if not errors.is_empty():
		printerr("FAIL map visual library")
		for error in errors:
			printerr(" - ", error)
		return 1
	print("PASS map visual library")
	print("  CPU map thumbnails reuse the runtime top-surface projection")
	print("  region tiles highlight canonical map regions without scene execution")
	print("  door and change-map editors keep stable destination IDs")
	print("  canonical map JSON stays unchanged")
	return 0


func _test_surface_projection(errors: Array[String]) -> void:
	var map: Dictionary = EmberPack.parse_json_file(EmberPack.map_path("agent_sandbox"))
	var surface := EmberTileMesher.surface_grid(map)
	var built := EmberTileMesher.build(map)
	if int(surface.get("cells", -1)) <= 0:
		errors.append("shared surface grid has no visible cells")
	if int(surface.get("cells", -1)) != int(built.get("cells", -2)):
		errors.append("map preview and runtime terrain disagree about visible cells")
	var image := MapVisuals.map_image("agent_sandbox")
	if image.get_size() != MapVisuals.PREVIEW_SIZE:
		errors.append("map thumbnail did not preserve the 96x96 preview contract")
	elif _unique_opaque_colors(image) < 3:
		errors.append("map thumbnail does not show the map's actual tile palette")


func _test_map_and_region_entries(errors: Array[String]) -> void:
	var map_entries := MapVisuals.map_entries()
	if map_entries.size() != EmberInteractionContent.map_ids().size():
		errors.append("visual map library dropped canonical map IDs")
	if not _entries_have_id(map_entries, "agent_sandbox"):
		errors.append("visual map library has no agent_sandbox card")
	var regions := MapVisuals.region_entries("agent_sandbox")
	if not _entries_have_id(regions, "") or not _entries_have_id(regions, "start") or not _entries_have_id(regions, "notice"):
		errors.append("region library lost default/start/notice destinations")
	var base := MapVisuals.map_image("agent_sandbox")
	var highlighted := MapVisuals.map_image("agent_sandbox", "notice")
	if base.get_data() == highlighted.get_data():
		errors.append("selected region has no visual highlight")


func _test_interact_picker(errors: Array[String]) -> void:
	var editor := InteractEditor.new() as EmberInteractEditor
	root.add_child(editor)
	editor.setup({
		"kind": "door",
		"target_map_id": "agent_sandbox_interior",
		"target_region_id": "start",
	}, false, "agent_sandbox")
	if editor.find_child("OpenTargetMapLibrary", true, false) == null:
		errors.append("door form has no visual map library button")
	if editor.find_child("OpenTargetRegionLibrary", true, false) == null:
		errors.append("door form has no visual region library button")
	editor.set("_map_library_mode", "map")
	editor.call("_choose_map_library_value", "agent_sandbox")
	editor.set("_map_library_mode", "region")
	editor.call("_choose_map_library_value", "notice")
	var values: Dictionary = editor.call("_values")
	if str(values.get("target_map_id", "")) != "agent_sandbox" or str(values.get("target_region_id", "")) != "notice":
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
			"targetMapId": "agent_sandbox_interior",
			"targetRegionId": "start",
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
		editor.call("_choose_map_library_value", "agent_sandbox")
		editor.set("_map_library_mode", "region")
		editor.call("_choose_map_library_value", "notice")
		var document: Dictionary = editor.call("_document")
		var steps: Array = document.get("steps", [])
		if steps.size() != 1:
			errors.append("change-map editor changed the action step count")
		else:
			var step: Dictionary = steps[0]
			if str(step.get("targetMapId", "")) != "agent_sandbox" or str(step.get("targetRegionId", "")) != "notice":
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
