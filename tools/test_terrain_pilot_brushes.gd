extends SceneTree
## Checks adapted relief, plateau, generator, and smoothing on the playable pilot.

const SCENE := "res://scenes/terrain_region_pilot.tscn"


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(SCENE) as PackedScene
	if packed == null:
		_fail("pilot scene did not load")
		return
	var scene := packed.instantiate() as Node3D
	scene.set("draft_path", "user://ember_terrain_pilot_brushes_test.res")
	root.add_child(scene)
	var projection := scene.get_node("TerrainProjection")
	if not await _settle(projection):
		_fail("pilot terrain did not settle")
		return
	var source: Variant = projection.get("document")
	var x := 200
	var z := 200
	var center: int = source.column_index(x, z)
	var midway: int = source.column_index(x + 8, z)
	var edge: int = source.column_index(x + 16, z)
	var outside: int = source.column_index(x + 17, z)
	var original: int = source.heights[center]
	var middle_original: int = source.heights[midway]
	var edge_original: int = source.heights[edge]
	var outside_original: int = source.heights[outside]
	if original < 16 or original > source.height_limit - 16:
		_fail("test location lacks room for relief")
		return
	var path_middle: int = source.column_index(x + 20, z)
	var path_before: int = source.heights[path_middle]
	scene.call("set_brush_radius_blocks", 1.0 / 16.0)
	scene.call("begin_stroke", 1)
	scene.call("stamp_cell", x, z)
	scene.call("stamp_cell", x + 40, z)
	scene.call("end_stroke")
	if source.heights[path_middle] != path_before + 1:
		_fail("fast pointer path left a gap between small-brush stamps")
		return
	scene.call("undo_stroke")
	if not await _settle(projection) or source.heights[path_middle] != path_before:
		_fail("small-brush path Undo failed")
		return
	var depth := scene.find_child("BrushDepth", true, false) as SpinBox
	var scale := scene.find_child("ReliefScale", true, false) as SpinBox
	var detail := scene.find_child("ReliefDetail", true, false) as SpinBox
	var height := scene.find_child("PlateauWorldHeight", true, false) as SpinBox
	var sample := scene.find_child("PlateauFromPoint", true, false) as CheckBox
	if depth == null or scale == null or detail == null or height == null or sample == null:
		_fail("brush parameter controls are missing")
		return
	scene.call("set_brush_radius_blocks", 1.0)
	depth.value = 6
	scene.call("set_tool_mode", 7)
	scene.call("begin_stroke", 7)
	scene.call("stamp_cell", x, z)
	scene.call("end_stroke")
	if source.heights[center] != original + 6 or source.heights[midway] != middle_original + 3 or source.heights[edge] != edge_original + 1 or source.heights[outside] != outside_original:
		_fail("soft relief footprint, falloff, or depth is wrong")
		return
	if not await _settle(projection):
		_fail("soft relief projection timed out")
		return
	scene.call("undo_stroke")
	if not await _settle(projection) or source.heights[center] != original or source.heights[midway] != middle_original:
		_fail("soft relief Undo failed")
		return
	scene.call("redo_stroke")
	if not await _settle(projection) or source.heights[center] != original + 6:
		_fail("soft relief Redo failed")
		return
	scene.call("set_tool_mode", 9)
	scene.call("begin_stroke", 9)
	scene.call("stamp_cell", x, z)
	scene.call("end_stroke")
	if source.heights[midway] != original + 6 or source.heights[outside] != outside_original or height.value != source.origin_y + original + 6:
		_fail("plateau did not use the touched point height")
		return
	scene.call("undo_stroke")
	if source.heights[midway] != middle_original + 3:
		_fail("sampled plateau Undo failed")
		return
	sample.button_pressed = false
	height.value = source.origin_y + original + 2
	scene.call("begin_stroke", 9)
	scene.call("stamp_cell", x, z)
	scene.call("end_stroke")
	if source.heights[center] != original + 2 or source.heights[midway] != original + 2:
		_fail("explicit plateau height did not apply")
		return
	if not await _settle(projection) or scene.call("save_draft") != OK or not scene.call("reopen_draft") or not await _settle(projection):
		_fail("plateau save/reopen failed")
		return
	source = projection.get("document")
	if source.heights[midway] != original + 2:
		_fail("plateau draft reopened with wrong height")
		return
	scene.call("set_tool_mode", 10)
	scene.call("set_brush_radius_blocks", 2.0)
	depth.value = 8
	scale.value = 16
	detail.value = 0
	var baseline: PackedInt32Array = source.heights.duplicate()
	scene.call("begin_stroke", 10)
	scene.call("stamp_cell", x, z)
	scale.value = 24
	if source.heights != baseline:
		_fail("changing generator parameters did not discard the current stroke")
		return
	scale.value = 16
	scene.call("begin_stroke", 10)
	scene.call("stamp_cell", x, z)
	scene.call("end_stroke")
	var light_result: PackedInt32Array = source.heights.duplicate()
	var light_changes := 0
	for dz in range(-32, 33):
		for dx in range(-32, 33):
			var at: int = source.column_index(x + dx, z + dz)
			var difference: int = light_result[at] - baseline[at]
			if abs(difference) > 2:
				_fail("light detail exceeded two height cells")
				return
			if difference != 0:
				light_changes += 1
	if light_changes == 0:
		_fail("light generator made no terrain variation")
		return
	scene.call("undo_stroke")
	if source.heights != baseline:
		_fail("generator Undo did not restore every height")
		return
	scene.call("begin_stroke", 10)
	scene.call("stamp_cell", x, z)
	scene.call("end_stroke")
	if source.heights != light_result:
		_fail("generator with same seed and parameters changed its result")
		return
	scene.call("undo_stroke")
	scale.value = 64
	detail.value = 3
	scene.call("begin_stroke", 10)
	scene.call("stamp_cell", x, z)
	scene.call("end_stroke")
	if source.heights == light_result:
		_fail("scale and detail controls did not change the terrain pattern")
		return
	scene.call("undo_stroke")
	if not await _settle(projection) or source.heights != baseline:
		_fail("generator variant Undo failed")
		return
	projection.call("apply_heights", PackedInt32Array([center]), PackedInt32Array([original + 20]))
	if not await _settle(projection):
		_fail("smoothing fixture did not settle")
		return
	scene.call("set_tool_mode", 11)
	scene.call("set_brush_radius_blocks", 1.0)
	depth.value = 8
	scene.call("begin_stroke", 11)
	scene.call("stamp_cell", x, z)
	scene.call("end_stroke")
	if source.heights[center] >= original + 20 or source.heights[center] < original + 12:
		_fail("smoothing did not reduce the spike within strength limit")
		return
	scene.call("undo_stroke")
	if source.heights[center] != original + 20:
		_fail("smoothing Undo failed")
		return
	projection.call("apply_heights", PackedInt32Array([center]), PackedInt32Array([original]))
	if not await _settle(projection):
		_fail("smoothing fixture restore did not settle")
		return
	scene.call("set_tool_mode", 10)
	scene.call("set_brush_radius_blocks", 8.0)
	detail.value = 0
	scale.value = 16
	depth.value = 4
	var large_started := Time.get_ticks_msec()
	scene.call("begin_stroke", 10)
	scene.call("stamp_cell", x, z)
	scene.call("end_stroke")
	var large_input_ms := Time.get_ticks_msec() - large_started
	if not await _settle(projection):
		_fail("large generator projection timed out")
		return
	var large_total_ms := Time.get_ticks_msec() - large_started
	scene.call("undo_stroke")
	if not await _settle(projection):
		_fail("large generator Undo timed out")
		return
	detail.value = 3
	depth.value = 8
	var dense_started := Time.get_ticks_msec()
	scene.call("begin_stroke", 10)
	scene.call("stamp_cell", x, z)
	scene.call("end_stroke")
	var dense_input_ms := Time.get_ticks_msec() - dense_started
	if not await _settle(projection):
		_fail("dense large generator projection timed out")
		return
	var dense_total_ms := Time.get_ticks_msec() - dense_started
	scene.call("undo_stroke")
	if not await _settle(projection):
		_fail("dense large generator Undo timed out")
		return
	print("PASS terrain pilot brushes: soft relief, sampled/explicit plateau, deterministic scale/detail generator, smooth, Undo, discard, save/reopen; light_changed=", light_changes, " large_light_input_ms=", large_input_ms, " large_light_total_ms=", large_total_ms, " large_dense_input_ms=", dense_input_ms, " large_dense_total_ms=", dense_total_ms)
	scene.free()
	quit()


func _settle(projection: Node) -> bool:
	var deadline := Time.get_ticks_msec() + 20000
	while projection.call("pending_tile_count") > 0 and Time.get_ticks_msec() < deadline:
		await process_frame
	return projection.call("pending_tile_count") == 0


func _fail(reason: String) -> void:
	printerr("FAIL terrain pilot brushes: ", reason)
	quit(1)
