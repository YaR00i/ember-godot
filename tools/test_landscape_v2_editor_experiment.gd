extends SceneTree
## Disposable editor-path gate: same stroke math, Surface delta and Undo/Redo.

const Experiment = preload("res://addons/ember_import/ember_landscape_v2_experiment.gd")
const World = preload("res://addons/ember_import/ember_world_editor.gd")
const Model = preload("res://addons/ember_import/ember_voxel_sculpt_model.gd")
const SurfaceProjection = preload("res://scripts/ember_voxel_surface_projection.gd")
var errors: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, reason: String) -> void:
	if not ok:
		errors.append(reason)


func _surface() -> EmberVoxelModelResource:
	var surface := EmberVoxelModelResource.new()
	surface.model_id = "landscape_v2_editor_test"
	surface.size_blocks = Vector3i(5, 1, 5)
	surface.voxels_per_block = 16
	surface.height_voxels = 32
	surface.palette = PackedColorArray([Color.TRANSPARENT, Color("#705447"), Color("#80a46d"), Color("#d1a55f")])
	var size := surface.grid_size()
	surface.voxels.resize(size.x * size.y * size.z)
	var values := surface.voxels
	for y in 16:
		for column in size.x * size.z:
			values[column + y * size.x * size.z] = 1
	surface.voxels = values
	surface.surface_fill_levels.resize(size.x * size.z)
	surface.surface_fill_levels.fill(20)
	surface.surface_fill_materials.resize(size.x * size.z)
	surface.surface_fill_materials.fill(1)
	surface.surface_fill_palette.resize(size.x * size.z)
	surface.surface_fill_palette.fill(2)
	return surface


func _run() -> void:
	if "--overlap-only" in OS.get_cmdline_user_args():
		await _two_stroke_preview_palette_case()
		if errors.is_empty(): print("PASS Landscape v2 overlap: pending exact, next stroke, cancel, palette and history")
		else:
			for reason in errors: printerr("FAIL Landscape v2 overlap: ", reason)
		quit(0 if errors.is_empty() else 1)
		return
	var scene := load("res://scenes/landscape_v2_experimental.tscn") as PackedScene
	_check(scene != null, "isolated scene copy missing")
	var authored := load("res://content/world_surfaces/world_canvas_surface.tres") as EmberVoxelModelResource
	var copied := load("res://content/world_surfaces/landscape_v2_experimental_surface.tres") as EmberVoxelModelResource
	_check(authored != null and copied != null and authored != copied, "experimental Surface must be a distinct resource")
	if copied != null:
		_check(copied.model_id == "landscape_v2_experimental_surface", "experimental Surface has wrong identity")
		_check(copied.voxels == authored.voxels, "test-copy voxel baseline is not identical to source")
		_check(copied.surface_fill_levels == authored.surface_fill_levels, "test-copy water is not identical to source")
		var wet_columns := 0
		for fill_level in copied.surface_fill_levels:
			if fill_level > 0: wet_columns += 1
		_check(wet_columns > 0, "test copy has no water for the shore gate")
	if scene != null:
		var copy_root := scene.instantiate()
		_check(copy_root.get_node("Map").visual_surface == copied, "test scene does not reference the isolated Surface")
		var gate := World.new()
		gate.scene = copy_root
		gate.entry = {"object_session": null, "path": "res://content/world_surfaces/landscape_v2_experimental_surface.tres", "resource": copied}
		_check(gate._experimental_allowed(), "feature flag is unavailable on the test copy")
		gate.entry.path = "res://content/world_surfaces/world_canvas_surface.tres"
		_check(not gate._experimental_allowed(), "feature flag escaped to a different Surface")
		gate.free()
		copy_root.free()
	for mode in ["level", "raise", "lower"]:
		await _stroke_case(mode)
	await _two_stroke_preview_palette_case()
	if copied != null:
		await _copied_preview_case(copied)
	if errors.is_empty():
		print("PASS Landscape v2 editor experiment: gated copy, level/raise/lower, water preservation and Undo/Redo")
	else:
		for reason in errors: printerr("FAIL Landscape v2 editor experiment: ", reason)
	quit(0 if errors.is_empty() else 1)


func _copied_preview_case(copied: EmberVoxelModelResource) -> void:
	var draft := copied.duplicate_model()
	var original_voxels := draft.voxels.duplicate()
	var parent := Node3D.new()
	root.add_child(parent)
	var experiment := Experiment.new()
	experiment.begin_prepare(draft, parent, Transform3D.IDENTITY)
	var deadline := Time.get_ticks_msec() + 90000
	while not experiment.prepare_step(10000) and Time.get_ticks_msec() < deadline:
		await process_frame
	_check(experiment.prepared, "coastal map preview did not prepare")
	if experiment.prepared:
		_check(experiment.field.size == copied.grid_size(), "coastal preview has wrong full-resolution grid")
		_check(experiment.preview.mesh_creations > 0, "coastal preview has no reusable GPU regions")
		_check(draft.voxels == original_voxels, "coastal preview preparation changed fine Surface")
		_check(draft.surface_fill_levels == copied.surface_fill_levels, "coastal preview preparation changed water")
		var size := copied.grid_size()
		var coast_column := -1
		for column in copied.surface_fill_levels.size():
			if copied.surface_fill_levels[column] > 0 and int(experiment.field.heights[column]) >= 4:
				coast_column = column
				break
		_check(coast_column >= 0, "coastal copy has no water-bearing ground column")
		if coast_column >= 0:
			var point := Vector3i(coast_column % size.x, int(experiment.field.heights[coast_column]) - 1, coast_column / size.x)
			var target_top := point.y - 2
			experiment.begin_stroke(copied, "level", 6, 4, target_top, 2, Rect2i(), null)
			experiment.apply_sample(point, point)
			experiment.begin_bake()
			var expected := copied.voxels.duplicate()
			var reference: Dictionary = Model.level_segment_changes(copied, point, point, target_top, 2, 6)
			for index in reference:
				expected[int(index)] = int(reference[index].after)
			var baked := draft.voxels
			while not experiment.bake_done():
				var part: Dictionary = experiment.bake_step(copied, 10000)
				for index in part:
					baked[int(index)] = int(part[index].after)
			draft.voxels = baked
			_check(draft.voxels == expected, "coastal level bake differs from current brush")
			_check(draft.surface_fill_levels == copied.surface_fill_levels, "coastal level bake changed water")
	experiment.clear()
	parent.free()


func _two_stroke_preview_palette_case() -> void:
	var baseline := _surface()
	var visual_capture := "--visual-capture" in OS.get_cmdline_user_args()
	if visual_capture: baseline.surface_fill_levels.fill(0)
	var draft := baseline.duplicate_model()
	var viewport: SubViewport
	if visual_capture:
		viewport = SubViewport.new()
		viewport.size = Vector2i(640, 480)
		viewport.own_world_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		var camera := Camera3D.new()
		viewport.add_child(camera)
		camera.position = Vector3(2.5, 6.0, 7.5)
		camera.look_at(Vector3(2.5, 1.0, 2.5))
		camera.current = true
		var light := DirectionalLight3D.new()
		viewport.add_child(light)
		light.rotation_degrees = Vector3(-50, -25, 0)
	var parent := Node3D.new()
	if visual_capture: viewport.add_child(parent)
	else: root.add_child(parent)
	var experiment := Experiment.new()
	experiment.begin_prepare(draft, parent, Transform3D.IDENTITY)
	var attempts := 0
	while not experiment.prepare_step(10000) and attempts < 1000:
		attempts += 1
	_check(experiment.prepared, "two-stroke preview did not prepare")
	if not experiment.prepared:
		parent.free()
		return
	var center := Vector3i(40, 15, 40)
	var size := draft.grid_size()
	var column := center.x + center.z * size.x
	var projection := SurfaceProjection.new()
	parent.add_child(projection)
	projection.configure(draft, 1.0, Vector2i(5, 5), null, false)
	while projection.drain_next_chunk(): pass
	if visual_capture: projection.set_process(false)
	var history := UndoRedo.new()
	var actions := EmberVoxelSculptActions.new()
	actions.configure(history)
	experiment.begin_stroke(baseline, "raise", 8, 4, center.y, 2, Rect2i(), projection)
	experiment.apply_sample(center, center)
	var preview_region: Dictionary = experiment.preview.region_views[Vector2i.ZERO]
	_check((preview_region.color_image as Image).get_pixel(2, 2).a < 0.5, "untouched terrain was replaced by the flat preview")
	var visible_ground := 0
	for visual in projection._chunks.values():
		for surface_index in visual.mesh.get_surface_count():
			var surface_name: StringName = visual.mesh.surface_get_name(surface_index)
			if surface_name not in ["water", "water_foam"] and visual.get_surface_override_material(surface_index) == null:
				visible_ground += 1
	_check(visible_ground > 0, "untouched exact terrain was hidden")
	experiment.begin_bake()
	var baked := draft.voxels
	var writes := 0
	var first_changed := PackedInt32Array()
	var first_delta := {}
	while not experiment.bake_done():
		var part: Dictionary = experiment.bake_step(baseline, 10000)
		for index in part:
			baked[int(index)] = int(part[index].after)
			first_changed.append(int(index))
			first_delta[int(index)] = Vector2i(int(part[index].before), int(part[index].after))
			writes += 1
	draft.voxels = baked
	actions.commit_applied_delta(draft, {"__sizes": {}, "voxels": first_delta}, first_changed, "first")
	draft.notify_geometry_changed(first_changed)
	_check(projection.pending_chunk_count() > 0, "first exact projection did not remain pending")
	if visual_capture:
		for unused in 3: await process_frame
		await RenderingServer.frame_post_draw
		(viewport.get_texture().get_image() as Image).save_png("user://qa_landscape_v2_editor_pending.png")
		while projection.drain_next_chunk(): pass
		experiment.preview.visible = false
		for visual in projection._chunks.values():
			for surface_index in visual.mesh.get_surface_count():
				var surface_name: StringName = visual.mesh.surface_get_name(surface_index)
				if surface_name not in ["water", "water_foam"]:
					visual.set_surface_override_material(surface_index, null)
		for unused in 3: await process_frame
		await RenderingServer.frame_post_draw
		(viewport.get_texture().get_image() as Image).save_png("user://qa_landscape_v2_editor_first_exact.png")
		experiment.preview.visible = true
		experiment.ensure_ground_hidden()
		draft.notify_geometry_changed(first_changed)
	_check(writes > 0, "first raise did not change fine voxels")
	var exact_top: int = Model._top_filled_y(draft.voxels, size, center.x, center.z)
	_check(exact_top > center.y, "first raise did not lift the chosen column")
	if exact_top > center.y:
		_check(int(draft.voxels[column + exact_top * size.x * size.z]) == 2, "first raise did not apply selected palette")
	var second_baseline := draft.duplicate_model()
	experiment.begin_stroke(second_baseline, "lower", 8, 4, exact_top, 2, Rect2i(), projection)
	_check(experiment.preview.visible and projection.pending_chunk_count() > 0, "next stroke cannot begin while exact projection is pending")
	var prior_heights: PackedInt32Array = experiment.field.heights.duplicate()
	var prior_controls: PackedByteArray = experiment.field.controls.duplicate()
	experiment.apply_sample(Vector3i(center.x, exact_top, center.z), Vector3i(center.x, exact_top, center.z))
	experiment.cancel_stroke()
	_check(experiment.field.heights == prior_heights and experiment.field.controls == prior_controls and experiment.preview.visible, "cancel while previous projection is pending lost the committed preview")
	experiment.begin_stroke(second_baseline, "lower", 8, 4, exact_top, 2, Rect2i(), projection)
	_check(int(experiment.field.controls[column]) == 2, "second stroke control map still shows pre-bake ground palette")
	preview_region = experiment.preview.region_views[Vector2i.ZERO]
	var preview_color: Color = (preview_region.color_image as Image).get_pixel(center.x, center.z)
	var exact_color: Color = draft.palette[2]
	_check(preview_color.is_equal_approx(exact_color), "second stroke preview still shows pre-bake ground color")
	experiment.apply_sample(Vector3i(center.x, exact_top, center.z), Vector3i(center.x, exact_top, center.z))
	experiment.begin_bake()
	baked = draft.voxels
	var second_changed := PackedInt32Array()
	var second_delta := {}
	while not experiment.bake_done():
		var part: Dictionary = experiment.bake_step(second_baseline, 10000)
		for index in part:
			baked[int(index)] = int(part[index].after)
			second_changed.append(int(index))
			second_delta[int(index)] = Vector2i(int(part[index].before), int(part[index].after))
	draft.voxels = baked
	actions.commit_applied_delta(draft, {"__sizes": {}, "voxels": second_delta}, second_changed, "second")
	draft.notify_geometry_changed(second_changed)
	while projection.drain_next_chunk(): pass
	_check(projection.is_projection_complete(), "exact projection did not catch up after two strokes")
	var lowered_top: int = Model._top_filled_y(draft.voxels, size, center.x, center.z)
	_check(lowered_top < exact_top, "second lower did not expose the previous ground")
	var applied := draft.voxels.duplicate()
	history.undo()
	history.undo()
	_check(draft.voxels == baseline.voxels, "two-stroke Undo did not restore fine Surface")
	history.redo()
	history.redo()
	_check(draft.voxels == applied, "two-stroke Redo did not restore fine Surface")
	_check(draft.surface_fill_levels == baseline.surface_fill_levels, "overlapping strokes changed water")
	experiment.end_visual()
	if visual_capture:
		for unused in 3: await process_frame
		await RenderingServer.frame_post_draw
		(viewport.get_texture().get_image() as Image).save_png("user://qa_landscape_v2_editor_exact.png")
	experiment.begin_stroke(draft, "raise", 8, 4, lowered_top, 2, Rect2i(), null)
	preview_region = experiment.preview.region_views[Vector2i.ZERO]
	var lowered_palette: int = int(draft.voxels[column + lowered_top * size.x * size.z])
	_check(int(experiment.field.controls[column]) == lowered_palette, "third stroke control map does not match exposed fine ground")
	_check((preview_region.color_image as Image).get_pixel(center.x, center.z).a < 0.5, "fresh stroke preview hides settled exact ground")
	experiment.field.last_input_regions.clear()
	experiment.field.last_changed_samples.clear()
	experiment.field.set_height_sample(Vector2i(64, 40), 17)
	experiment.preview.update_regions(experiment.field.sorted_regions(experiment.field.last_input_regions), experiment.field.last_changed_samples)
	var right_region: Dictionary = experiment.preview.region_views[Vector2i(1, 0)]
	_check((preview_region.color_image as Image).get_pixel(64, 40).a > 0.5 and (right_region.color_image as Image).get_pixel(0, 40).a > 0.5, "edited preview chunk split at a region seam")
	experiment.preview.clear_edited_chunks()
	_check((preview_region.color_image as Image).get_pixel(64, 40).a < 0.5 and (right_region.color_image as Image).get_pixel(0, 40).a < 0.5, "settled preview mask remained at a region seam")
	history.clear_history()
	history.free()
	experiment.clear()
	parent.free()
	if visual_capture: viewport.free()


func _stroke_case(mode: String) -> void:
	var baseline := _surface()
	var draft := baseline.duplicate_model()
	var parent := Node3D.new()
	root.add_child(parent)
	var experiment := Experiment.new()
	experiment.begin_prepare(draft, parent, Transform3D.IDENTITY)
	var attempts := 0
	while not experiment.prepare_step(10000) and attempts < 1000:
		attempts += 1
	_check(experiment.prepared, "experimental heightfield did not prepare")
	if not experiment.prepared:
		parent.free()
		return
	var from := Vector3i(58, 15, 34)
	var to := Vector3i(73, 15, 47)
	var sample_mode := mode
	var top := 11 if mode == "level" else 15
	var depth := 4
	var radius := 8
	var projection: Node3D
	if mode == "level":
		projection = SurfaceProjection.new()
		parent.add_child(projection)
		projection.configure(draft, 1.0, Vector2i(5, 5), null, false)
		while projection.drain_next_chunk():
			pass
	experiment.begin_stroke(baseline, sample_mode, radius, depth, top, 2, Rect2i(), projection)
	experiment.apply_sample(from, from)
	experiment.apply_sample(from, to)
	if is_instance_valid(projection):
		var hidden_ground := 0
		var visible_water := 0
		for visual in projection._chunks.values():
			for surface_index in visual.mesh.get_surface_count():
				var name: StringName = visual.mesh.surface_get_name(surface_index)
				if name in ["water", "water_foam"]:
					if visual.get_surface_override_material(surface_index) == null: visible_water += 1
				elif visual.get_surface_override_material(surface_index) != null:
					hidden_ground += 1
		_check(hidden_ground > 0 and visible_water > 0, "preview did not hide only the old ground while preserving water")
	var ray_x := 65
	var ray_z := 40
	var ray_column: int = ray_x + ray_z * int(experiment.field.size.x)
	var picked: Dictionary = experiment.pick(Vector3((ray_x + 0.5) / 16.0, 3.0, (ray_z + 0.5) / 16.0), Vector3.DOWN)
	_check(not picked.is_empty() and int(picked.hit.y) == int(experiment.field.heights[ray_column]) - 1, mode + " brush pick did not follow transient height")
	experiment.begin_bake()
	var history := UndoRedo.new()
	var world := World.new()
	world.actions.configure(history)
	world.entry = {"resource": draft}
	world.baseline = baseline
	world.delta = {"__sizes": {}}
	world.stroke_mode = mode
	world.stroke_palette = 2
	var changed := {}
	var guard := 0
	while not experiment.bake_done() and guard < 200:
		var part: Dictionary = experiment.bake_step(baseline, 10000)
		world._apply_batch(part, false)
		for index in part: changed[index] = true
		guard += 1
	_check(experiment.bake_done() and not changed.is_empty(), mode + " bake did not finish with changed voxels")
	var expected := baseline.voxels.duplicate()
	var before_top := {}
	var amount_cache := {}
	for pair in [[from, from], [from, to]]:
		var reference: Dictionary
		if mode == "level":
			reference = Model.level_segment_changes(baseline, pair[0], pair[1], top, 2, radius)
		else:
			reference = Model.relief_segment_changes(baseline, baseline.voxels, pair[0], pair[1], Model.TOOL_RAISE if mode == "raise" else Model.TOOL_LOWER, 2, radius, depth, false, before_top, 0, amount_cache)
		for index in reference: expected[int(index)] = int(reference[index].after)
	_check(draft.voxels == expected, mode + " differs from existing brush on region-boundary fixture")
	_check(draft.surface_fill_levels == baseline.surface_fill_levels and draft.surface_fill_materials == baseline.surface_fill_materials and draft.surface_fill_palette == baseline.surface_fill_palette, mode + " changed independent water")
	var applied := draft.voxels.duplicate()
	world.actions.commit_applied_delta(draft, world.delta, PackedInt32Array(changed.keys()), "Landscape V2 experimental " + mode)
	history.undo()
	_check(draft.voxels == baseline.voxels, mode + " Undo did not restore fine Surface")
	history.redo()
	_check(draft.voxels == applied, mode + " Redo did not restore fine Surface")
	history.clear_history()
	experiment.clear()
	if is_instance_valid(projection):
		for visual in projection._chunks.values():
			for surface_index in visual.mesh.get_surface_count():
				_check(visual.get_surface_override_material(surface_index) == null, "preview did not restore original ground material")
	world.free()
	history.free()
	parent.free()
