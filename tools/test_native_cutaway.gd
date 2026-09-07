extends SceneTree
## Godot-native roof section, Area3D occupancy and renderer-owned fade/shadows.

const SANDBOX_SCENE := "res://scenes/agent_sandbox.tscn"


func _init() -> void:
	_run_and_quit.call_deferred()


func _run_and_quit() -> void:
	quit(await _run())


func _run() -> int:
	var errors: Array[String] = []
	var sections := _test_roof_build(errors)
	await _test_native_volume(sections, errors)
	await _test_live_sandbox(errors)
	if not errors.is_empty():
		printerr("FAIL native cutaway")
		for error in errors:
			printerr(" - ", error)
		return 1
	print("PASS native cutaway")
	print("  ground_z roof -> one scene section per interior volume")
	print("  Area3D reveal -> native transparency + stable structural shadow")
	print("  agent_sandbox opt-in creates one cabin section without scene traversal")
	return 0


func _test_roof_build(errors: Array[String]) -> Array[Dictionary]:
	var raw: Variant = EmberPack.parse_json_file(EmberPack.map_path("agent_sandbox"))
	if typeof(raw) != TYPE_DICTIONARY:
		errors.append("could not parse agent_sandbox map")
		return []
	var sections := EmberTileMesher.build_cutaway_roofs(raw)
	if sections.size() != 1:
		errors.append("agent_sandbox did not build exactly one cutaway section")
		return sections
	var section: Dictionary = sections[0]
	var mesh := section.get("mesh") as ArrayMesh
	if str(section.get("id", "")) != "cabin" or int(section.get("cells", 0)) != 16:
		errors.append("cabin roof did not claim the expanded 4x4 roof section")
	if mesh == null or mesh.get_surface_count() != 1:
		errors.append("cabin roof section has no renderable surface")
	if section.get("origin", Vector3.ZERO) != Vector3(256.0, 0.0, 32.0):
		errors.append("cabin roof section origin diverged from its authored volume")
	return sections


func _test_native_volume(sections: Array[Dictionary], errors: Array[String]) -> void:
	if sections.is_empty():
		return
	var volume := EmberCutawayVolume.new()
	volume.setup(sections[0], EmberVoxelPrefab.voxel_material())
	root.add_child(volume)
	await process_frame
	var roof := volume.roof()
	if roof == null or roof.transparency != 0.0:
		errors.append("native roof did not start opaque")
	if volume.is_processing():
		errors.append("cutaway volume introduced a per-frame process loop")
	volume.set_revealed(true, true)
	if roof.transparency != 1.0:
		errors.append("revealed roof did not use GeometryInstance3D transparency")
	if roof.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
		errors.append("revealed roof stopped casting its stable structural shadow")
	volume.set_revealed(false, true)
	if roof.transparency != 0.0:
		errors.append("closed roof did not restore opaque rendering")
	if roof.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
		errors.append("closed roof lost shadow casting")
	volume.queue_free()
	await process_frame


func _test_live_sandbox(errors: Array[String]) -> void:
	var state := root.get_node_or_null("EmberExploreProgress") as EmberExploreState
	if state:
		state.persistence_enabled = false
		state.restore_enabled = false
		state.reset_new_game()
	if change_scene_to_file(SANDBOX_SCENE) != OK:
		errors.append("could not start agent_sandbox")
		return
	await process_frame
	await process_frame
	var map := current_scene.get_node_or_null("Map") as EmberMapLoader
	if map == null:
		errors.append("agent_sandbox lost Map")
		return
	if map.cutaway_section_count() != 1 or map.cutaway_active_count() != 0:
		errors.append("agent_sandbox did not hydrate one closed cutaway section")
	var volume := map.get_node_or_null("Cutaways/Cutaway_cabin") as EmberCutawayVolume
	if volume == null or volume.roof() == null:
		errors.append("live cabin cutaway nodes were not created")
		return
	map.set_cutaway_preview(true, true)
	if map.cutaway_active_count() != 1 or not volume.is_revealed():
		errors.append("map preview did not reveal the live cutaway section")
	map.set_cutaway_preview(false, true)
	if map.cutaway_active_count() != 0 or volume.is_revealed():
		errors.append("map preview did not restore the live cutaway section")
	var overlay := current_scene.get_node_or_null("CanvasLayer/LightingBenchmark") as EmberBenchmarkOverlay
	if overlay == null:
		errors.append("agent_sandbox lost the benchmark overlay used for F7 preview")
		return
	var event := InputEventKey.new()
	event.keycode = KEY_F7
	event.pressed = true
	overlay._unhandled_input(event)
	if map.cutaway_active_count() != 1 or not volume.is_revealed():
		errors.append("F7 did not reveal the live cutaway section")
	overlay._unhandled_input(event)
	if map.cutaway_active_count() != 0 or volume.is_revealed():
		errors.append("second F7 did not restore the live cutaway section")
