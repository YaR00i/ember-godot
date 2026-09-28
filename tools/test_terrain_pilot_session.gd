extends SceneTree
## Exercises the actual playable pilot scene, including its UndoRedo and draft.

const SCENE := "res://scenes/terrain_region_pilot.tscn"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var started := Time.get_ticks_msec()
	var packed := ResourceLoader.load(SCENE, "", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var scene_load_ms := Time.get_ticks_msec() - started
	if packed == null:
		_fail("scene does not load")
		return
	var scene := packed.instantiate() as Node3D
	scene.set("draft_path", "user://ember_terrain_pilot_test_draft.res")
	root.add_child(scene)
	var projection := scene.get_node_or_null("TerrainProjection")
	if projection == null or not await _settle(projection):
		_fail("scene ground not ready")
		return
	print("TERRAIN_PILOT_SCENE_LOAD scene_load_ms=", scene_load_ms, " first_tile_after_scene_ms=", projection.get("first_tile_ms"), " all_tiles_after_scene_ms=", projection.get("all_tiles_ms"), " total_to_all_ms=", Time.get_ticks_msec() - started)
	var source: Variant = projection.get("document")
	var index: int = source.column_index(200, 200)
	var initial: int = source.heights[index]
	scene.call("begin_stroke", 1)
	scene.call("stamp_cell", 200, 200)
	scene.call("stamp_cell", 204, 200)
	scene.call("end_stroke")
	if not await _settle(projection) or source.heights[index] != initial + 1:
		_fail("two-stamp stroke did not apply")
		return
	scene.call("undo_stroke")
	if not await _settle(projection) or source.heights[index] != initial:
		_fail("Undo did not restore the shared source")
		return
	scene.call("redo_stroke")
	if not await _settle(projection) or source.heights[index] != initial + 1:
		_fail("Redo did not restore the shared source")
		return
	if scene.call("save_draft") != OK or not scene.call("reopen_draft") or not await _settle(projection):
		_fail("draft save/reopen failed")
		return
	if projection.get("document").heights[index] != initial + 1:
		_fail("draft reopened without edited height")
		return
	source = projection.get("document")
	var grass_index := -1
	var wet_index := -1
	for cell in source.heights.size():
		if grass_index < 0 and source.top_materials[cell] == 2:
			grass_index = cell
		if wet_index < 0 and source.water_materials[cell] == 5 and source.water_levels[cell] > source.heights[cell]:
			wet_index = cell
		if grass_index >= 0 and wet_index >= 0:
			break
	if grass_index < 0 or wet_index < 0:
		_fail("pilot source lacks grass or water")
		return
	scene.call("begin_stroke", 4)
	scene.call("stamp_cell", grass_index % source.width, grass_index / source.width)
	scene.call("end_stroke")
	if source.top_materials[grass_index] != 3:
		_fail("sand paint did not change material")
		return
	scene.call("undo_stroke")
	if source.top_materials[grass_index] != 2:
		_fail("sand paint Undo did not restore grass")
		return
	scene.call("begin_stroke", 6)
	scene.call("stamp_cell", wet_index % source.width, wet_index / source.width)
	scene.call("end_stroke")
	if source.water_materials[wet_index] != 0:
		_fail("dry brush did not remove water")
		return
	scene.call("undo_stroke")
	if source.water_materials[wet_index] != 5:
		_fail("water Undo did not restore sea")
		return
	var burst_started := Time.get_ticks_msec()
	for step in 10:
		scene.call("begin_stroke", 1 if step % 2 == 0 else 2)
		scene.call("stamp_cell", 165 + step * 5, 195)
		scene.call("stamp_cell", 168 + step * 5, 198)
		scene.call("end_stroke")
	var burst_input_ms := Time.get_ticks_msec() - burst_started
	if not await _settle(projection):
		_fail("ten-stroke burst did not settle")
		return
	print("PASS terrain pilot session: scene ready, two stamps, height/material/water Undo, save/reopen, burst_strokes=10 input_ms=", burst_input_ms, " settle_ms=", Time.get_ticks_msec() - burst_started)
	var large_source: Variant = projection.get("document")
	var center: int = large_source.column_index(200, 200)
	var inside: int = large_source.column_index(320, 200)
	var outside: int = large_source.column_index(329, 200)
	var before_center: int = large_source.heights[center]
	var before_inside: int = large_source.heights[inside]
	var before_outside: int = large_source.heights[outside]
	var size_control := scene.find_child("RadiusBlocks", true, false) as SpinBox
	if size_control == null:
		_fail("brush size control is missing from the pilot HUD")
		return
	for preset in [1, 2, 4, 8]:
		var button := scene.find_child("RadiusPreset_%d" % preset, true, false) as Button
		if button == null:
			_fail("brush size preset is missing")
			return
		button.emit_signal("pressed")
		if scene.call("brush_radius_cells") != preset * 16 or not is_equal_approx(size_control.value, float(preset)):
			_fail("brush size preset did not update the live radius")
			return
	size_control.value = 3.5
	if scene.call("brush_radius_cells") != 56:
		_fail("numeric brush size did not update the live radius")
		return
	(scene.find_child("RadiusPreset_1", true, false) as Button).emit_signal("pressed")
	scene.call("begin_stroke", 1)
	scene.call("stamp_cell", 200, 200)
	(scene.find_child("RadiusPreset_2", true, false) as Button).emit_signal("pressed")
	if large_source.heights[center] != before_center:
		_fail("changing brush size during a stroke did not cancel that stroke")
		return
	(scene.find_child("RadiusPreset_8", true, false) as Button).emit_signal("pressed")
	if scene.call("brush_radius_cells") != 128:
		_fail("maximum brush radius did not map to 128 cells")
		return
	var center_tile := projection.get_node("TerrainTile_3_3/Ground") as MeshInstance3D
	var center_mesh_before: Mesh = center_tile.mesh
	var large_started := Time.get_ticks_msec()
	scene.call("begin_stroke", 1)
	var large_begin_ms := Time.get_ticks_msec() - large_started
	scene.call("stamp_cell", 200, 200)
	var large_stamp_ms := Time.get_ticks_msec() - large_started
	scene.call("end_stroke")
	var large_input_ms := Time.get_ticks_msec() - large_started
	if projection.get("_pending")[0] != Vector2i(3, 3):
		_fail("large brush did not prioritize the tile under the pointer")
		return
	var first_visual_deadline := Time.get_ticks_msec() + 1000
	while center_tile.mesh == center_mesh_before and Time.get_ticks_msec() < first_visual_deadline:
		await process_frame
	if center_tile.mesh == center_mesh_before:
		_fail("large brush did not update the tile under the pointer promptly")
		return
	var first_visual_ms := Time.get_ticks_msec() - large_started
	if large_source.heights[center] != before_center + 1 or large_source.heights[inside] != before_inside + 1 or large_source.heights[outside] != before_outside:
		_fail("large brush footprint is wrong")
		return
	if not await _settle(projection):
		_fail("large brush projection timed out")
		return
	var large_settle_ms := Time.get_ticks_msec() - large_started
	scene.call("undo_stroke")
	if not await _settle(projection) or large_source.heights[center] != before_center or large_source.heights[inside] != before_inside:
		_fail("large brush Undo did not restore all checked cells")
		return
	scene.call("redo_stroke")
	if not await _settle(projection) or large_source.heights[center] != before_center + 1 or large_source.heights[inside] != before_inside + 1:
		_fail("large brush Redo did not restore checked cells")
		return
	if scene.call("save_draft") != OK or not scene.call("reopen_draft") or not await _settle(projection):
		_fail("large brush draft did not reopen")
		return
	if projection.get("document").heights[inside] != before_inside + 1:
		_fail("large brush draft reopened without its far edge")
		return
	print("TERRAIN_PILOT_LARGE_BRUSH radius_blocks=8 radius_cells=128 begin_ms=", large_begin_ms, " stamp_ms=", large_stamp_ms - large_begin_ms, " end_ms=", large_input_ms - large_stamp_ms, " input_ms=", large_input_ms, " first_visual_ms=", first_visual_ms, " settle_ms=", large_settle_ms, " undo_redo_save_reopen=ok")
	large_source = projection.get("document")
	var first_edge: int = large_source.column_index(40, 200)
	var last_edge: int = large_source.column_index(360, 200)
	var before_first_edge: int = large_source.heights[first_edge]
	var before_last_edge: int = large_source.heights[last_edge]
	var drag_started := Time.get_ticks_msec()
	scene.call("begin_stroke", 1)
	for x in [160, 180, 200, 220, 240]:
		scene.call("stamp_cell", x, 200)
	scene.call("end_stroke")
	var drag_input_ms := Time.get_ticks_msec() - drag_started
	if large_source.heights[first_edge] != before_first_edge + 1 or large_source.heights[last_edge] != before_last_edge + 1:
		_fail("large dragged brush missed its endpoints")
		return
	if not await _settle(projection):
		_fail("large dragged brush projection timed out")
		return
	var drag_settle_ms := Time.get_ticks_msec() - drag_started
	scene.call("undo_stroke")
	if not await _settle(projection) or large_source.heights[first_edge] != before_first_edge or large_source.heights[last_edge] != before_last_edge:
		_fail("large dragged brush did not undo as one stroke")
		return
	print("TERRAIN_PILOT_LARGE_DRAG stamps=5 radius_blocks=8 input_ms=", drag_input_ms, " settle_ms=", drag_settle_ms, " undo=ok")
	scene.free()
	quit()


func _settle(projection: Node) -> bool:
	var deadline := Time.get_ticks_msec() + 20000
	while projection.call("pending_tile_count") > 0 and Time.get_ticks_msec() < deadline:
		await process_frame
	return projection.call("pending_tile_count") == 0


func _fail(reason: String) -> void:
	printerr("FAIL terrain pilot session: ", reason)
	quit(1)
