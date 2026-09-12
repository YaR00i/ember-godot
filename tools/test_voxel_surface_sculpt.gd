extends SceneTree
## Style gate: a 4x4 high-density surface uses the shared voxel owner/mesher,
## supports volumetric picking, coarse strokes, Undo/Redo and save/reopen.

const Model = preload("res://addons/ember_import/ember_voxel_sculpt_model.gd")
const Actions = preload("res://addons/ember_import/ember_voxel_sculpt_actions.gd")
const WorldSelector = preload("res://addons/ember_import/ember_world_surface_selector.gd")
const SurfaceMesher = preload("res://scripts/ember_voxel_surface_mesher.gd")
const TEMP_PATH := "user://ember_surface_sculpt_test.tres"


class BoundWorldSelector extends WorldSelector:
	var selected_map: EmberMapLoader

	func _resolve_map() -> EmberMapLoader:
		return selected_map


func _init() -> void:
	if "--native-selector-probe" in OS.get_cmdline_user_args():
		quit(_native_selector_probe())
		return
	quit(_run())


func _run() -> int:
	var errors: Array[String] = []
	var resource := Model.make_pilot()
	errors.append_array(resource.validation_errors())
	if resource.normalized_density() != 32 or resource.size_blocks != Vector3i(4, 1, 4):
		errors.append("pilot does not use the accepted 4x4 / 32-grid contract")
	var size := resource.grid_size()
	if size != Vector3i(128, 24, 128):
		errors.append("unexpected pilot grid: %s" % size)
	var full_started := Time.get_ticks_usec()
	var mesh := VoxMesher.build_from_ember_model(
		resource.to_definition().get("model", {}),
		1.0 / float(resource.normalized_density()),
	)
	var full_elapsed := Time.get_ticks_usec() - full_started
	if mesh.get_surface_count() == 0:
		errors.append("shared VoxMesher produced an empty surface")
	_test_chunk_projection(resource, mesh, full_elapsed, errors)

	var pick := Model.pick(resource, Vector3(2.0, 2.0, 2.0), Vector3.DOWN)
	if pick.is_empty():
		errors.append("top-down ray did not hit the connected surface")
	else:
		var adjacent: Vector3i = pick.get("adjacent", Model.INVALID_CELL)
		if adjacent == Model.INVALID_CELL:
			errors.append("surface hit has no adjacent cell for extrusion")
		else:
			_test_stroke_undo(resource, adjacent, errors)
	_test_interpolated_drag(errors)
	_test_oriented_fixed_layer(errors)
	_test_material_brush(errors)
	_test_surface_level_fill(errors)
	_test_relief_brush(errors)
	_test_generative_relief(errors)
	_test_swept_relief(errors)
	_test_shell_relief(errors)
	_test_shell_lower(errors)
	_test_level_brush(errors)
	_test_smooth_brush(errors)
	_test_ramp_brush(errors)
	_test_heightfield_storage_profiles(errors)
	_test_region_mask(errors)
	_test_world_surface_seed(errors)

	var absolute := ProjectSettings.globalize_path(TEMP_PATH)
	if FileAccess.file_exists(absolute):
		DirAccess.remove_absolute(absolute)
	var save_error := ResourceSaver.save(resource, TEMP_PATH)
	if save_error != OK:
		errors.append("save failed: %s" % error_string(save_error))
	else:
		var reopened := ResourceLoader.load(TEMP_PATH, "", ResourceLoader.CACHE_MODE_REPLACE) as EmberVoxelModelResource
		if reopened == null or reopened.voxels != resource.voxels:
			errors.append("save/reopen changed the sculpted voxel source")
		elif reopened.transparency != resource.transparency:
			errors.append("save/reopen changed the painted material channel")
	if FileAccess.file_exists(absolute):
		DirAccess.remove_absolute(absolute)

	if not errors.is_empty():
		printerr("FAIL voxel surface sculpt")
		for error in errors:
			printerr(" - ", error)
		return 1
	print("PASS voxel surface sculpt")
	print("  connected 4x4 canvas · color/material · relief · terrace · smoothing · two-point ramp")
	print("  one-gesture Undo/Redo · save/reopen · opaque floor + water level fill")
	return 0


func _test_heightfield_storage_profiles(errors: Array[String]) -> void:
	var size := Vector3i(8, 4, 8)
	var sparse := PackedByteArray()
	sparse.resize(size.x * size.y * size.z)
	sparse[Model.index_of(Vector3i(1, 0, 1), size)] = 1
	sparse[Model.index_of(Vector3i(1, 3, 1), size)] = 2
	sparse[Model.index_of(Vector3i(7, 2, 7), size)] = 2
	var sparse_heights := Model.column_heights(sparse, size, 2)
	if sparse_heights[1 + size.x] != 3 or sparse_heights[7 + 7 * size.x] != 2:
		errors.append("sparse palette-indexed heightfield lost top voxels")
	var dense := PackedByteArray()
	dense.resize(size.x * size.y * size.z)
	dense.fill(1)
	dense[Model.index_of(Vector3i(4, 3, 4), size)] = 2
	var dense_heights := Model.column_heights(dense, size, 2)
	if dense_heights.count(3) != size.x * size.z:
		errors.append("dense column heightfield path did not retain the top layer")


func _test_surface_level_fill(errors: Array[String]) -> void:
	var resource := EmberVoxelModelResource.new()
	resource.model_id = "surface_fill_fixture"
	resource.voxels_per_block = 16
	resource.size_blocks = Vector3i.ONE
	resource.height_voxels = 4
	resource.palette = PackedColorArray([
		Color.TRANSPARENT, Color("#6f9147"), Color("#4bbfbb"),
	])
	var size := resource.grid_size()
	resource.voxels.resize(size.x * size.y * size.z)
	resource.voxels.fill(0)
	for z in size.z:
		for x in size.x:
			var top := 0 if x in range(6, 10) and z in range(6, 10) else 2
			for y in range(top + 1):
				resource.voxels[Model.index_of(Vector3i(x, y, z), size)] = 1
	var heights := Model.column_heights(resource.voxels, size)
	var selection := Model.surface_fill_selection(
		resource, Vector3i(7, 0, 7), 0, Rect2i(), heights
	)
	var columns := selection.get("columns", PackedInt32Array()) as PackedInt32Array
	if bool(selection.get("open", false)) or int(selection.get("level", -1)) != 3:
		errors.append("auto level fill did not find the basin spill height")
	if columns.size() != 16:
		errors.append("auto level fill selected %d columns; expected 16" % columns.size())
	var inset_selection := Model.surface_fill_selection(
		resource,
		Vector3i(7, 0, 7),
		0,
		Rect2i(),
		heights,
		Model.MAX_SURFACE_FILL_COLUMNS,
		1,
	)
	if (
		int(inset_selection.get("spill_level", -1)) != 3
		or int(inset_selection.get("level", -1)) != 2
	):
		errors.append("shore inset did not lower auto water one voxel below spill height")
	var open_selection := Model.surface_fill_selection(
		resource, Vector3i(1, 2, 1), 1, Rect2i(), heights
	)
	if not bool(open_selection.get("open", false)):
		errors.append("manual level fill did not reject an open surface")
	var levels := Model.normalized_int_channel(resource.surface_fill_levels, size.x * size.z)
	var materials := Model.normalized_channel(resource.surface_fill_materials, size.x * size.z)
	var palettes := Model.normalized_channel(resource.surface_fill_palette, size.x * size.z)
	for column in columns:
		levels[int(column)] = 3
		materials[int(column)] = Model.SURFACE_FILL_WATER
		palettes[int(column)] = 2
	var undo := UndoRedo.new()
	var actions := Actions.new() as EmberVoxelSculptActions
	actions.configure(undo)
	if not actions.apply_surface_fill(resource, levels, materials, palettes, columns):
		errors.append("surface level fill was not registered in Undo")
		undo.free()
		return
	if resource.surface_fill_materials.size() != size.x * size.z:
		errors.append("surface level fill did not populate canonical column channels")
	var lower_columns := PackedInt32Array([
		7 + 7 * size.x,
		8 + 7 * size.x,
		7 + 8 * size.x,
		8 + 8 * size.x,
	])
	var replacement := Model.surface_fill_replacement_columns(
		resource,
		Vector2i(7, 7),
		lower_columns,
		Model.SURFACE_FILL_WATER,
	)
	var affected := replacement.get("columns", PackedInt32Array()) as PackedInt32Array
	if affected.size() != columns.size():
		errors.append("lowering water did not include the complete previous fill mask")
	var lower_levels := levels.duplicate()
	var lower_materials := materials.duplicate()
	var lower_palettes := palettes.duplicate()
	for column in affected:
		lower_levels[int(column)] = 0
		lower_materials[int(column)] = 0
		lower_palettes[int(column)] = 0
	for column in lower_columns:
		lower_levels[int(column)] = 2
		lower_materials[int(column)] = Model.SURFACE_FILL_WATER
		lower_palettes[int(column)] = 2
	if not actions.apply_surface_fill(
		resource, lower_levels, lower_materials, lower_palettes, affected
	):
		errors.append("lowered replacement fill was not registered in Undo")
	else:
		var remaining := 0
		for value in resource.surface_fill_materials:
			if int(value) != Model.SURFACE_FILL_NONE:
				remaining += 1
		if remaining != lower_columns.size():
			errors.append("lowered replacement left stale high-water columns")
		undo.undo()
		if resource.surface_fill_levels != levels:
			errors.append("lowered replacement Undo did not restore the high fill")
		undo.redo()
		if resource.surface_fill_levels != lower_levels:
			errors.append("lowered replacement Redo did not clear the old fringe")
		undo.undo()
	var repair_resource := resource.duplicate(true) as EmberVoxelModelResource
	var mixed_levels := levels.duplicate()
	for column in lower_columns:
		mixed_levels[int(column)] = 2
	repair_resource.surface_fill_levels = mixed_levels
	var isolated_column := 1 + size.x
	repair_resource.surface_fill_levels[isolated_column] = 2
	repair_resource.surface_fill_materials[isolated_column] = Model.SURFACE_FILL_WATER
	var repair := Model.surface_fill_replacement_columns(
		repair_resource,
		Vector2i(7, 7),
		lower_columns,
		Model.SURFACE_FILL_WATER,
	)
	var repair_affected := repair.get("columns", PackedInt32Array()) as PackedInt32Array
	if repair_affected.size() != columns.size() or isolated_column in repair_affected:
		errors.append("mixed stale rings were not isolated from a separate pond")
	var scoped := EmberVoxelModelResource.new()
	scoped.model_id = "surface_fill_scope_fixture"
	scoped.voxels_per_block = 16
	scoped.size_blocks = Vector3i(2, 1, 1)
	scoped.height_voxels = 1
	var scoped_size := scoped.grid_size()
	var scoped_count := scoped_size.x * scoped_size.z
	scoped.surface_fill_levels.resize(scoped_count)
	scoped.surface_fill_levels.fill(0)
	scoped.surface_fill_materials.resize(scoped_count)
	scoped.surface_fill_materials.fill(0)
	scoped.surface_fill_palette.resize(scoped_count)
	scoped.surface_fill_palette.fill(0)
	for scoped_column in [15, 16]:
		scoped.surface_fill_levels[scoped_column] = 2
		scoped.surface_fill_materials[scoped_column] = Model.SURFACE_FILL_WATER
	var clipped_replacement := Model.surface_fill_replacement_columns(
		scoped,
		Vector2i(15, 0),
		PackedInt32Array(),
		Model.SURFACE_FILL_NONE,
		Rect2i(0, 0, 1, 1),
	)
	if not bool(clipped_replacement.get("escaped_scope", false)):
		errors.append("replacement did not reject a work region cutting through water")
	var definition_model: Dictionary = resource.to_definition().get("model", {})
	if (definition_model.get("surfaceFillLevels", []) as Array).size() != size.x * size.z:
		errors.append("surface level fill is missing from the native definition")
	var mesh := SurfaceMesher.build_region(
		resource, Vector3i.ZERO, size, 1.0 / 16.0
	)
	var water_indices := 0
	var foam_indices := 0
	var water_has_depth_band := false
	for surface_index in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface_index)
		var mesh_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if mesh.surface_get_name(surface_index) == "water":
			water_indices += mesh_indices.size()
			var water_uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			for uv in water_uvs:
				if uv.x > 0.0:
					water_has_depth_band = true
					break
		elif mesh.surface_get_name(surface_index) == "water_foam":
			foam_indices += mesh_indices.size()
	if water_indices != 6 or foam_indices <= 0 or foam_indices >= 96:
		errors.append(
			"level fill did not build one water plane and sparse basin shoreline: %d/%d"
			% [water_indices, foam_indices]
		)
	if not water_has_depth_band:
		errors.append("level fill water mesh lost its derived depth UV band")
	var connected := Model.connected_surface_fill_columns(resource, Vector2i(7, 7))
	var connected_columns := connected.get("columns", PackedInt32Array()) as PackedInt32Array
	if connected_columns.size() != columns.size():
		errors.append("surface fill erase selection lost connected columns")
	undo.undo()
	if not resource.surface_fill_materials.is_empty():
		errors.append("surface fill Undo did not restore sparse empty channels")
	undo.redo()
	if resource.surface_fill_levels != levels:
		errors.append("surface fill Redo did not restore the authored plane")
	undo.free()
	var fill_temp := "user://ember_surface_fill_test.tres"
	var fill_absolute := ProjectSettings.globalize_path(fill_temp)
	if FileAccess.file_exists(fill_absolute):
		DirAccess.remove_absolute(fill_absolute)
	if ResourceSaver.save(resource, fill_temp) != OK:
		errors.append("surface fill Resource did not save")
	else:
		var reopened := ResourceLoader.load(
			fill_temp, "", ResourceLoader.CACHE_MODE_REPLACE
		) as EmberVoxelModelResource
		if reopened == null or reopened.surface_fill_levels != levels:
			errors.append("surface fill Resource did not reopen losslessly")
		elif not reopened.validation_errors().is_empty():
			errors.append("reopened surface fill Resource failed validation")
	if FileAccess.file_exists(fill_absolute):
		DirAccess.remove_absolute(fill_absolute)


func _test_material_brush(errors: Array[String]) -> void:
	var resource := Model.make_pilot()
	var size := resource.grid_size()
	var pick := Model.pick(resource, Vector3(2.0, 2.0, 2.0), Vector3.DOWN)
	var center: Vector3i = pick.get("hit", Model.INVALID_CELL)
	if center == Model.INVALID_CELL:
		errors.append("material brush test could not pick the pilot surface")
		return
	var indices := Model.material_stroke_indices(resource, center, 4, false)
	if indices.is_empty():
		errors.append("material brush did not find filled surface voxels")
		return
	var clipped := Model.indices_in_block_region(
		indices, size, resource.normalized_density(), Rect2i(1, 1, 1, 1)
	)
	for index in clipped:
		var flat := int(index) % (size.x * size.z)
		var cell_block := Vector2i(
			(flat % size.x) / resource.normalized_density(),
			(flat / size.x) / resource.normalized_density(),
		)
		if cell_block != Vector2i(1, 1):
			errors.append("material brush escaped the selected block region")
			break
	var before := resource.transparency.duplicate()
	var after := Model.normalized_channel(before, resource.voxels.size())
	for index in indices:
		after[int(index)] = 152
	resource.transparency = after
	var undo := UndoRedo.new()
	var actions := Actions.new() as EmberVoxelSculptActions
	actions.configure(undo)
	if not actions.commit_applied_transparency_stroke(resource, before, after, indices):
		errors.append("material stroke was not registered in Undo")
		undo.free()
		return
	var mesh := SurfaceMesher.build_region(
		resource,
		Vector3i(maxi(0, center.x - 5), 0, maxi(0, center.z - 5)),
		Vector3i(11, size.y, 11),
		1.0 / float(resource.normalized_density()),
	)
	var has_water_surface := false
	var has_opaque_floor := false
	for surface_index in mesh.get_surface_count():
		if mesh.surface_get_name(surface_index) == "water":
			has_water_surface = true
		elif mesh.surface_get_name(surface_index) == "opaque":
			has_opaque_floor = true
	if not has_water_surface or not has_opaque_floor:
		errors.append("Surface water did not preserve an opaque floor under its overlay")
	var overlay_fixture := EmberVoxelModelResource.new()
	overlay_fixture.model_id = "single_water_overlay"
	overlay_fixture.voxels_per_block = 16
	overlay_fixture.size_blocks = Vector3i.ONE
	overlay_fixture.height_voxels = 1
	overlay_fixture.palette = PackedColorArray([Color.TRANSPARENT, Color("#4bbfbb")])
	var overlay_size := overlay_fixture.grid_size()
	overlay_fixture.voxels.resize(overlay_size.x * overlay_size.y * overlay_size.z)
	overlay_fixture.voxels.fill(0)
	overlay_fixture.voxels[0] = 1
	overlay_fixture.transparency.resize(overlay_fixture.voxels.size())
	overlay_fixture.transparency.fill(0)
	overlay_fixture.transparency[0] = 208
	var overlay_mesh := SurfaceMesher.build_region(
		overlay_fixture,
		Vector3i.ZERO,
		overlay_size,
		1.0 / 16.0,
	)
	var opaque_indices := 0
	var water_indices := 0
	var foam_indices := 0
	for surface_index in overlay_mesh.get_surface_count():
		var arrays := overlay_mesh.surface_get_arrays(surface_index)
		var index_array: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if overlay_mesh.surface_get_name(surface_index) == "opaque":
			opaque_indices += index_array.size()
		elif overlay_mesh.surface_get_name(surface_index) == "water":
			water_indices += index_array.size()
		elif overlay_mesh.surface_get_name(surface_index) == "water_foam":
			foam_indices += index_array.size()
	if opaque_indices != 36 or water_indices != 6 or foam_indices != 24:
		errors.append(
			"single water mask did not produce an opaque cube, overlay and four foam edges"
		)
	var floor_only_mesh := SurfaceMesher.build_region(
		overlay_fixture,
		Vector3i.ZERO,
		overlay_size,
		1.0 / 16.0,
		false,
		false,
	)
	for surface_index in floor_only_mesh.get_surface_count():
		if floor_only_mesh.surface_get_name(surface_index) in ["water", "water_foam"]:
			errors.append("floor-only Surface preview still contains water decoration")
			break
	var seam_fixture := EmberVoxelModelResource.new()
	seam_fixture.model_id = "water_chunk_seam"
	seam_fixture.voxels_per_block = 16
	seam_fixture.size_blocks = Vector3i(2, 1, 1)
	seam_fixture.height_voxels = 1
	seam_fixture.palette = PackedColorArray([Color.TRANSPARENT, Color("#4bbfbb")])
	var seam_size := seam_fixture.grid_size()
	seam_fixture.voxels.resize(seam_size.x * seam_size.y * seam_size.z)
	seam_fixture.voxels.fill(0)
	seam_fixture.transparency.resize(seam_fixture.voxels.size())
	seam_fixture.transparency.fill(0)
	for x in [15, 16]:
		var seam_index: int = int(x) + seam_size.x
		seam_fixture.voxels[seam_index] = 1
		seam_fixture.transparency[seam_index] = 208
	var seam_mesh := SurfaceMesher.build_region(
		seam_fixture,
		Vector3i.ZERO,
		Vector3i(16, 1, 16),
		1.0 / 16.0,
	)
	var seam_foam_indices := 0
	for surface_index in seam_mesh.get_surface_count():
		if seam_mesh.surface_get_name(surface_index) != "water_foam":
			continue
		var arrays := seam_mesh.surface_get_arrays(surface_index)
		var index_array: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		seam_foam_indices += index_array.size()
	if seam_foam_indices != 18:
		errors.append("water foam treated a neighboring preview chunk as shoreline")
	undo.undo()
	if resource.transparency != before:
		errors.append("material Undo did not restore the sparse channel")
	undo.redo()
	if resource.transparency != after:
		errors.append("material Redo did not restore the painted channel")
	undo.free()

	var connected := EmberVoxelModelResource.new()
	connected.model_id = "connected_material_fixture"
	connected.voxels_per_block = 16
	connected.size_blocks = Vector3i.ONE
	connected.height_voxels = 4
	connected.palette = PackedColorArray([
		Color.TRANSPARENT,
		Color("#336699"),
		Color("#34679a"),
		Color("#b98550"),
	])
	var connected_size := connected.grid_size()
	connected.voxels.resize(
		connected_size.x * connected_size.y * connected_size.z
	)
	connected.voxels.fill(0)
	for fixture in [
		[Vector3i(1, 1, 1), 1],
		[Vector3i(2, 1, 1), 2],
		[Vector3i(3, 1, 1), 3],
		[Vector3i(8, 1, 8), 1],
		[Vector3i(2, 2, 2), 1],
	]:
		var cell: Vector3i = fixture[0]
		for y in range(cell.y + 1):
			connected.voxels[Model.index_of(Vector3i(cell.x, y, cell.z), connected_size)] = (
				int(fixture[1]) if y == cell.y else 3
			)
	var exact: PackedInt32Array = Model.connected_surface_material_indices(
		connected, Vector3i(1, 1, 1), 0.0
	).get("indices", PackedInt32Array())
	if exact.size() != 1:
		errors.append("exact smart water selection crossed a floor color boundary")
	var similar: PackedInt32Array = Model.connected_surface_material_indices(
		connected, Vector3i(1, 1, 1), 0.05
	).get("indices", PackedInt32Array())
	if similar.size() != 2:
		errors.append("similar-color water selection ignored tolerance or crossed height/gap")
	var capped: Dictionary = Model.connected_surface_material_indices(
		connected, Vector3i(1, 1, 1), 0.05, Rect2i(), PackedInt32Array(), 1
	)
	if not bool(capped.get("truncated", false)) or not (capped.get("indices") as PackedInt32Array).is_empty():
		errors.append("oversized smart material selection did not fail atomically")


func _test_world_surface_seed(errors: Array[String]) -> void:
	# Capture stderr too: missing pack reads log ERROR but do not fail Godot's
	# process exit code. This reproduces the editor's automatic context bind.
	var output: Array = []
	var code := OS.execute(OS.get_executable_path(), PackedStringArray([
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--script", "res://tools/test_voxel_surface_sculpt.gd", "--", "--native-selector-probe",
	]), output, true)
	var probe_text := "\n".join(output)
	if code != 0 or "ERROR" in probe_text or "NATIVE_SELECTOR_PASS" not in probe_text:
		errors.append("native editor selector probe failed: %s" % probe_text)
	var selector := WorldSelector.new()
	var toolbar := selector.build_toolbar()
	for control_name in [
		"WorldSurfaceRegionToggle",
		"WorldSurfaceOpenRegionButton",
		"WorldSurfaceMoreMenu",
		"WorldSurfaceSelectionStatus",
	]:
		if toolbar.find_child(control_name, true, false) == null:
			errors.append("world Surface toolbar lost %s" % control_name)
	if toolbar.visible:
		errors.append("world Surface toolbar remains visible without a world-map context")
	toolbar.free()
	var grid := {
		"width": 2,
		"depth": 2,
		"heights": PackedInt32Array([1, 2, 0, 3]),
		"tileIds": PackedInt32Array([4, 7, 0, 4]),
	}
	var surface := Model.make_world_surface(
		"test map",
		"Test Map",
		grid,
		{4: Color("#6f9147"), 7: Color("#2f7775")},
	)
	if surface.normalized_density() != 16 or surface.size_blocks != Vector3i(2, 1, 2):
		errors.append("world Surface did not preserve the legacy 16-grid map footprint")
	if surface.grid_size() != Vector3i(32, surface.height_voxels, 32):
		errors.append("world Surface grid does not match map blocks")
	var size := surface.grid_size()
	if surface.voxels[Model.index_of(Vector3i(1, 0, 1), size)] == 0:
		errors.append("visible legacy map column was not seeded")
	if surface.voxels[Model.index_of(Vector3i(17, 1, 1), size)] == 0:
		errors.append("legacy map height was shifted during Surface seeding")
	if surface.voxels[Model.index_of(Vector3i(1, 0, 17), size)] != 0:
		errors.append("empty legacy map column became solid during Surface seeding")
	if WorldSelector.rectangle_for_cells(Vector2i(5, 7), Vector2i(2, 3)) != Rect2i(2, 3, 4, 5):
		errors.append("world viewport rectangle does not include both clicked cells")
	if WorldSelector.cell_for_local_point(Vector3(31.9, 8.0, 47.9), 16.0, 4, 4) != Vector2i(1, 2):
		errors.append("world viewport local point did not resolve to its map cell")
	if WorldSelector.cell_for_local_point(Vector3(-2.0, 0.0, 64.5), 16.0, 4, 4) != Vector2i(0, 3):
		errors.append("world viewport edge tolerance did not clamp a near-border click")
	if WorldSelector.cell_for_local_point(Vector3(-20.0, 0.0, 10.0), 16.0, 4, 4) != WorldSelector.INVALID_CELL:
		errors.append("world viewport accepted a click far outside the map")
	if Model.world_surface_path("Test Map") != "res://content/world_surfaces/test_map_surface.tres":
		errors.append("world Surface path is not deterministic")
	if Model.world_surface_path("Test Map") != EmberVoxelModelResource.world_surface_path("Test Map"):
		errors.append("editor and runtime disagree about the canonical world Surface path")


func _native_selector_probe() -> int:
	var errors: Array[String] = []
	var packed := load("res://scenes/test_pier.tscn") as PackedScene
	var scene := packed.instantiate()
	var map := scene.get_node("Map") as EmberMapLoader
	var selector := BoundWorldSelector.new()
	selector.selected_map = map
	var toolbar := selector.build_toolbar()
	if toolbar.visible or not selector._grid.is_empty():
		errors.append("primitive pier incorrectly offers a voxel Surface selection")
	# Repeat the exact selection-change callback; no pack read may be logged.
	selector.selected_map = null
	selector.refresh_context()
	selector.selected_map = map
	selector.refresh_context()
	map.authored_size_blocks = Vector2i.ZERO
	if map._expected_world_surface_blocks() != Vector2i.ZERO:
		errors.append("native map with transient unknown dimensions used legacy data")
	var surface := EmberVoxelModelResource.new()
	surface.size_blocks = Vector3i(2, 1, 3)
	surface.material = {"semanticOwner": "test_pier"}
	map.visual_surface = surface
	selector.selected_map = null
	selector.refresh_context()
	selector.selected_map = map
	selector.refresh_context()
	if not toolbar.visible or selector._grid.get("width") != 2 or selector._grid.get("depth") != 3:
		errors.append("native Surface does not supply its own selector dimensions")
	var legacy := EmberMapLoader.new()
	legacy.map_id = "fan_town"
	var expected: Dictionary = EmberTileMesher.surface_grid(
		EmberPack.parse_json_file(EmberPack.map_path("fan_town")))
	if selector._surface_grid_for_map(legacy) != expected:
		errors.append("legacy selector changed its source grid or heights")
	toolbar.free()
	scene.free()
	legacy.free()
	for error in errors:
		push_error(error)
	if errors.is_empty():
		print("NATIVE_SELECTOR_PASS")
	return 0 if errors.is_empty() else 1


func _test_stroke_undo(
	resource: EmberVoxelModelResource,
	center: Vector3i,
	errors: Array[String],
) -> void:
	var before := resource.voxels.duplicate()
	var changes := Model.stroke_changes(resource, center, Model.TOOL_ADD, 5, 4, true)
	if changes.size() < 8:
		errors.append("coarse brush did not affect a volumetric area")
		return
	var undo := UndoRedo.new()
	var actions := Actions.new() as EmberVoxelSculptActions
	actions.configure(undo)
	if not actions.apply_stroke(resource, changes):
		errors.append("stroke action was rejected")
		undo.free()
		return
	var after := resource.voxels.duplicate()
	if after == before:
		errors.append("stroke did not change canonical voxels")
	undo.undo()
	if resource.voxels != before:
		errors.append("Undo did not restore exact canonical voxels")
	undo.redo()
	if resource.voxels != after:
		errors.append("Redo did not restore exact sculpt stroke")
	actions.configure(null)
	undo.clear_history()
	undo.free()


func _test_interpolated_drag(errors: Array[String]) -> void:
	var from := Vector3i(8, 10, 8)
	var to := Vector3i(58, 10, 37)
	var cells := Model.line_cells(from, to)
	if cells.is_empty() or cells.front() != from or cells.back() != to:
		errors.append("drag interpolation lost its first or last cell")
		return
	var seen := {}
	var previous: Vector3i = cells.front()
	for cell in cells:
		if seen.has(cell):
			errors.append("drag interpolation contains duplicate cells")
			return
		seen[cell] = true
		var delta: Vector3i = cell - previous
		if maxi(absi(delta.x), maxi(absi(delta.y), absi(delta.z))) > 1:
			errors.append("drag interpolation contains a hole between %s and %s" % [previous, cell])
			return
		previous = cell
	var resource := Model.make_pilot()
	var before := resource.voxels.duplicate()
	var touched := {}
	for center in cells:
		var changes := Model.stroke_changes(resource, center, Model.TOOL_ADD, 5, 1, false)
		if changes.is_empty():
			continue
		resource.voxels = Model.values_with_changes(resource.voxels, changes, true)
		for raw_index in changes:
			touched[int(raw_index)] = true
	var after := resource.voxels.duplicate()
	if touched.size() < cells.size() or after == before:
		errors.append("interpolated drag did not create a connected canonical stroke")
		return
	var indices := PackedInt32Array()
	for raw_index in touched:
		indices.append(int(raw_index))
	var undo := UndoRedo.new()
	var actions := Actions.new() as EmberVoxelSculptActions
	actions.configure(undo)
	if not actions.commit_applied_stroke(resource, before, after, indices):
		errors.append("completed drag was not registered in Undo history")
	else:
		if resource.voxels != after:
			errors.append("committing a live drag applied its final state twice")
		undo.undo()
		if resource.voxels != before:
			errors.append("one Undo did not restore the entire drag gesture")
		undo.redo()
		if resource.voxels != after:
			errors.append("one Redo did not restore the entire drag gesture")
	actions.configure(null)
	undo.clear_history()
	undo.free()


func _test_oriented_fixed_layer(errors: Array[String]) -> void:
	var normals: Array[Vector3i] = [
		Vector3i.RIGHT, Vector3i.LEFT, Vector3i.UP,
		Vector3i.DOWN, Vector3i.BACK, Vector3i.FORWARD,
	]
	for normal in normals:
		var resource := _fixed_layer_fixture()
		var baseline := resource.voxels.duplicate()
		var hit := Vector3i(8, 8, 8)
		for axis in 3:
			if normal[axis] > 0:
				hit[axis] = 11
			elif normal[axis] < 0:
				hit[axis] = 4
		var removed := Model.oriented_stroke_changes(
			resource, baseline, hit, normal, Model.TOOL_REMOVE, 2, 1, 3, false
		)
		if removed.size() != 3:
			errors.append("fixed Remove depth is not three voxels on normal %s: %d" % [normal, removed.size()])
			continue
		resource.voxels = Model.values_with_changes(resource.voxels, removed, true)
		var revisited := Model.oriented_stroke_changes(
			resource, baseline, hit, normal, Model.TOOL_REMOVE, 2, 1, 3, false
		)
		if revisited.keys() != removed.keys():
			errors.append("same-gesture revisit changed the fixed footprint on normal %s" % normal)
		var next_baseline := resource.voxels.duplicate()
		var next_hit := hit - normal * 3
		var next_layer := Model.oriented_stroke_changes(
			resource, next_baseline, next_hit, normal, Model.TOOL_REMOVE, 2, 1, 2, false
		)
		if next_layer.size() != 2:
			errors.append("new gesture could not remove the next layer on normal %s" % normal)

		var add_resource := _fixed_layer_fixture()
		var add_baseline := add_resource.voxels.duplicate()
		var added := Model.oriented_stroke_changes(
			add_resource, add_baseline, hit + normal, normal,
			Model.TOOL_ADD, 2, 1, 3, false
		)
		if added.size() != 3:
			errors.append("fixed Add depth is not three voxels on normal %s: %d" % [normal, added.size()])

	var paint_resource := _fixed_layer_fixture()
	var paint_baseline := paint_resource.voxels.duplicate()
	var painted := Model.oriented_stroke_changes(
		paint_resource, paint_baseline, Vector3i(8, 11, 8), Vector3i.UP,
		Model.TOOL_PAINT, 2, 1, 2, false
	)
	if painted.size() != 2:
		errors.append("fixed Paint did not use the selected inward depth")
	var material_indices := Model.oriented_material_stroke_indices(
		paint_resource, paint_baseline, Vector3i(8, 11, 8), Vector3i.UP, 1, 2, false
	)
	if material_indices.size() != 2:
		errors.append("fixed Material did not use the selected inward depth")
	var coarse := Model.oriented_stroke_changes(
		paint_resource, paint_baseline, Vector3i(8, 11, 8), Vector3i.UP,
		Model.TOOL_REMOVE, 2, 1, 3, true
	)
	if coarse.size() != 16:
		errors.append("coarse fixed depth did not align to a 2x2x2 grid: %d" % coarse.size())
	var circle := Model.oriented_stroke_changes(
		paint_resource, paint_baseline, Vector3i(8, 11, 8), Vector3i.UP,
		Model.TOOL_REMOVE, 2, 3, 1, false, "circle"
	)
	var square := Model.oriented_stroke_changes(
		paint_resource, paint_baseline, Vector3i(8, 11, 8), Vector3i.UP,
		Model.TOOL_REMOVE, 2, 3, 1, false, "square"
	)
	if circle.size() != 21 or square.size() != 25:
		errors.append("circle/square footprints are not exact: %d/%d" % [circle.size(), square.size()])

	var picked := Model.pick(
		_fixed_layer_fixture(), Vector3(0.5, 0.5, 1.2), Vector3.FORWARD
	)
	if picked.get("normal", Vector3i.ZERO) != Vector3i.BACK:
		errors.append("voxel pick did not report the visible face direction")
	_test_sculpt_stroke_sampling(errors)


func _test_sculpt_stroke_sampling(errors: Array[String]) -> void:
	for density in [16, 32]:
		var stepped := _surface_normal_fixture(density, true)
		var middle: int = density / 2
		var micro_face_hit := Vector3i(middle, 5, middle)
		var micro_axis := Vector3i.ZERO
		for brush_radius in [1, 2]:
			var micro_area := Model.averaged_surface_normal(
				stepped.voxels,
				stepped.grid_size(),
				micro_face_hit,
				Vector3i.LEFT,
				Model.surface_normal_radius(brush_radius),
			)
			micro_axis = Model.stable_surface_axis(
				micro_area, Vector3i.LEFT, Vector3i.UP
			)
			if micro_axis != Vector3i.UP:
				errors.append(
					"density %d radius %d staircase micro-face replaced the averaged top normal: %s"
					% [density, brush_radius, micro_axis]
				)
		var micro_target := Model.oriented_target_cell(
			{
				"hit": micro_face_hit,
				"adjacent": micro_face_hit + Vector3i.LEFT,
				"normal": Vector3i.LEFT,
			},
			micro_axis,
			Model.TOOL_ADD,
			stepped.grid_size(),
		)
		if micro_target != micro_face_hit + Vector3i.UP:
			errors.append(
				"density %d Add still followed the raw staircase face" % density
			)

		var wall := _surface_normal_fixture(density, false)
		var wall_hit := Vector3i(middle - 1, middle, middle)
		var wall_area := Model.averaged_surface_normal(
			wall.voxels,
			wall.grid_size(),
			wall_hit,
			Vector3i.RIGHT,
			Model.surface_normal_radius(2),
		)
		if Model.stable_surface_axis(wall_area, Vector3i.RIGHT, Vector3i.UP) != Vector3i.RIGHT:
			errors.append("density %d real vertical wall did not switch the area normal" % density)

		var island := _thin_island_fixture(density)
		var island_hit := Vector3i(4, 6, middle)
		var island_area := Model.averaged_surface_normal(
			island.voxels,
			island.grid_size(),
			island_hit,
			Vector3i.LEFT,
			Model.surface_normal_radius(4),
			Vector3i.ZERO,
			Vector3(-0.45, 0.80, 0.35),
		)
		if Model.stable_surface_axis(island_area, Vector3i.LEFT) != Vector3i.UP:
			errors.append(
				"density %d thin floating island cancelled its visible top face" % density
			)
		var face_plane := Model.surface_face_plane(island_hit, Vector3i.UP)
		var inside_face := Model.single_face_target_cell(
			island.voxels,
			island.grid_size(),
			{
				"ray_origin": Vector3(4.5, float(density + 4), float(middle) + 0.5) / float(density),
				"ray_direction": Vector3.DOWN,
			},
			Vector3i.UP,
			face_plane,
			Model.TOOL_ADD,
			density,
		)
		if inside_face != Vector3i(4, 7, middle):
			errors.append("density %d single-face plane stopped before the island edge" % density)
		var outside_face := Model.single_face_target_cell(
			island.voxels,
			island.grid_size(),
			{
				# The real pick may hit terrain below; its projection onto the locked
				# island plane is what must decide the edge.
				"hit": Vector3i(2, 0, middle),
				"ray_origin": Vector3(2.5, float(density + 4), float(middle) + 0.5) / float(density),
				"ray_direction": Vector3.DOWN,
			},
			Vector3i.UP,
			face_plane,
			Model.TOOL_ADD,
			density,
		)
		if outside_face != Model.INVALID_CELL:
			errors.append("density %d single-face plane continued onto terrain below" % density)

	var normal := Vector3i.UP
	for area in [Vector3(0.55, 0.50, 0.0), Vector3(0.80, 0.40, 0.0)]:
		normal = Model.stable_surface_axis(area, Vector3i.RIGHT, normal)
	if normal != Vector3i.RIGHT:
		errors.append("surface normal hysteresis did not switch once at a clear corner")
	normal = Model.stable_surface_axis(Vector3(0.50, 0.55, 0.0), Vector3i.UP, normal)
	if normal != Vector3i.RIGHT:
		errors.append("surface normal hysteresis oscillated on near-equal corner samples")

	var one_event := Model.spaced_stroke_segment(
		Vector3i.ZERO, Vector3i(12, 0, 0), 3.0, 3, Vector3i.ZERO
	)
	var one_points: Array[Vector3i] = []
	one_points.assign(one_event.points)
	var many_points: Array[Vector3i] = []
	var previous := Vector3i.ZERO
	var remaining := 3.0
	var last_emitted := Vector3i.ZERO
	for current in [Vector3i(2, 0, 0), Vector3i(5, 0, 0), Vector3i(9, 0, 0), Vector3i(12, 0, 0)]:
		var sampled := Model.spaced_stroke_segment(
			previous, current, remaining, 3, last_emitted
		)
		var sampled_points: Array[Vector3i] = []
		sampled_points.assign(sampled.points)
		many_points.append_array(sampled_points)
		if not sampled_points.is_empty():
			last_emitted = sampled_points[-1]
		remaining = float(sampled.distance_to_next)
		previous = current
	if many_points != one_points or one_points != [
		Vector3i(3, 0, 0), Vector3i(6, 0, 0),
		Vector3i(9, 0, 0), Vector3i(12, 0, 0),
	]:
		errors.append("distance-based dabs changed with input event frequency")

	var benchmark := _surface_normal_fixture(32, true)
	var benchmark_started := Time.get_ticks_usec()
	for sample_index in 100:
		Model.averaged_surface_normal(
			benchmark.voxels,
			benchmark.grid_size(),
			Vector3i(16 + sample_index % 2, 5, 16 + sample_index % 8),
			Vector3i.UP,
			Model.surface_normal_radius(8),
		)
	var benchmark_elapsed := Time.get_ticks_usec() - benchmark_started
	print("  sculpt area-normal benchmark 100 samples: %.2f ms" % (benchmark_elapsed / 1000.0))
	if benchmark_elapsed > 2500000:
		errors.append("area-normal sampling exceeded the 2.5 s editor safety budget")


func _surface_normal_fixture(density: int, stepped: bool) -> EmberVoxelModelResource:
	var resource := EmberVoxelModelResource.new()
	resource.model_id = "surface_normal_fixture_%d" % density
	resource.voxels_per_block = density
	resource.size_blocks = Vector3i.ONE
	resource.height_voxels = density
	resource.palette = PackedColorArray([Color.TRANSPARENT, Color.WHITE])
	var size := resource.grid_size()
	resource.voxels.resize(size.x * size.y * size.z)
	resource.voxels.fill(0)
	var middle: int = density / 2
	for z in size.z:
		for x in size.x:
			var top := 5 if stepped and x >= middle else 4
			if not stepped and x >= middle:
				continue
			for y in range(top + 1):
				resource.voxels[Model.index_of(Vector3i(x, y, z), size)] = 1
	return resource


func _thin_island_fixture(density: int) -> EmberVoxelModelResource:
	var resource := EmberVoxelModelResource.new()
	resource.model_id = "thin_island_fixture_%d" % density
	resource.voxels_per_block = density
	resource.size_blocks = Vector3i.ONE
	resource.height_voxels = density
	resource.palette = PackedColorArray([Color.TRANSPARENT, Color.WHITE])
	var size := resource.grid_size()
	resource.voxels.resize(size.x * size.y * size.z)
	resource.voxels.fill(0)
	for z in range(3, density - 3):
		for x in range(3, density - 3):
			resource.voxels[Model.index_of(Vector3i(x, 6, z), size)] = 1
	return resource


func _fixed_layer_fixture() -> EmberVoxelModelResource:
	var resource := EmberVoxelModelResource.new()
	resource.model_id = "fixed_layer_fixture"
	resource.display_name = "Fixed layer fixture"
	resource.voxels_per_block = 16
	resource.size_blocks = Vector3i.ONE
	resource.height_voxels = 16
	resource.palette = PackedColorArray([
		Color(0, 0, 0, 0), Color(0.35, 0.45, 0.55), Color(0.9, 0.35, 0.2),
	])
	resource.voxels.resize(16 * 16 * 16)
	resource.voxels.fill(0)
	var size := resource.grid_size()
	for y in range(4, 12):
		for z in range(4, 12):
			for x in range(4, 12):
				resource.voxels[Model.index_of(Vector3i(x, y, z), size)] = 1
	return resource


func _smooth_common_fixture() -> EmberVoxelModelResource:
	var resource := EmberVoxelModelResource.new()
	resource.model_id = "smooth_common_fixture"
	resource.display_name = "Smooth common fixture"
	resource.voxels_per_block = 16
	resource.size_blocks = Vector3i.ONE
	resource.height_voxels = 16
	resource.palette = PackedColorArray([Color.TRANSPARENT, Color.WHITE])
	var size := resource.grid_size()
	resource.voxels.resize(size.x * size.y * size.z)
	resource.voxels.fill(0)
	for z in size.z:
		for x in size.x:
			for y in 5:
				resource.voxels[Model.index_of(Vector3i(x, y, z), size)] = 1
	return resource


func _test_relief_brush(errors: Array[String]) -> void:
	if Model.buildup_height(0.0, 8.0, 16) != 1:
		errors.append("relief buildup must start at one art voxel")
	if Model.buildup_height(0.75, 8.0, 16) != 7:
		errors.append("relief buildup speed is not derived from elapsed time")
	if Model.buildup_height(10.0, 8.0, 16) != 16:
		errors.append("relief buildup did not stop at the selected cap")
	var speed_results := PackedInt32Array()
	for rate in [1, 2, 4, 8, 16, 32]:
		speed_results.append(Model.buildup_height(1.0, float(rate), 24))
	if speed_results != PackedInt32Array([2, 3, 5, 9, 17, 24]):
		errors.append("relief speed presets do not produce distinct time-based heights: %s" % speed_results)
	var resource := Model.make_pilot()
	var size := resource.grid_size()
	var center := Vector3i(32, 0, 32)
	var edge := Vector3i(39, 0, 32)
	var baseline := resource.voxels.duplicate()
	var center_before := _column_top(baseline, size, center.x, center.z)
	var edge_before := _column_top(baseline, size, edge.x, edge.z)
	var first_raise := Model.relief_changes(
		resource, baseline, center, Model.TOOL_RAISE, 5, 8, 1, false
	)
	if first_raise.is_empty():
		errors.append("Raise brush produced no relief changes")
		return
	resource.voxels = Model.values_with_changes(resource.voxels, first_raise, true)
	if _column_top(resource.voxels, size, center.x, center.z) - center_before != 1:
		errors.append("first buildup sample did not add exactly one center voxel")
	var mid_raise := Model.relief_changes(
		resource, baseline, center, Model.TOOL_RAISE, 5, 8, 4, false
	)
	resource.voxels = Model.values_with_changes(resource.voxels, mid_raise, true)
	if _column_top(resource.voxels, size, center.x, center.z) - center_before != 4:
		errors.append("progressive buildup did not reach its intermediate target")
	var final_raise := Model.relief_changes(
		resource, baseline, center, Model.TOOL_RAISE, 5, 8, 8, false
	)
	resource.voxels = Model.values_with_changes(resource.voxels, final_raise, true)
	var center_raised := _column_top(resource.voxels, size, center.x, center.z)
	var edge_raised := _column_top(resource.voxels, size, edge.x, edge.z)
	var center_gain := center_raised - center_before
	var edge_gain := edge_raised - edge_before
	if center_gain != 8:
		errors.append("Raise brush ignored its height limit: %d != 8" % center_gain)
	if edge_gain <= 0 or edge_gain >= center_gain:
		errors.append("Raise brush has no readable radial falloff: center %d edge %d" % [center_gain, edge_gain])
	var repeated := Model.relief_changes(
		resource, baseline, center, Model.TOOL_RAISE, 5, 8, 8, false
	)
	if not repeated.is_empty():
		errors.append("Raise brush accumulated past the pointer-down baseline")

	var lower_baseline := resource.voxels.duplicate()
	var lower_before := _column_top(lower_baseline, size, center.x, center.z)
	var lowered := Model.relief_changes(
		resource, lower_baseline, center, Model.TOOL_LOWER, 5, 8, 4, false
	)
	if lowered.is_empty():
		errors.append("Lower brush produced no relief changes")
		return
	resource.voxels = Model.values_with_changes(resource.voxels, lowered, true)
	var lower_after := _column_top(resource.voxels, size, center.x, center.z)
	if lower_before - lower_after != 4:
		errors.append("Lower brush ignored its depth limit: %d != 4" % (lower_before - lower_after))
	var repeated_lower := Model.relief_changes(
		resource, lower_baseline, center, Model.TOOL_LOWER, 5, 8, 4, false
	)
	if not repeated_lower.is_empty():
		errors.append("Lower brush accumulated past the pointer-down baseline")
	_test_incremental_relief_parity(center, errors)


func _test_generative_relief(errors: Array[String]) -> void:
	var resource := _smooth_common_fixture()
	var size := resource.grid_size()
	var baseline := resource.voxels.duplicate()
	var heightfield := Model.column_heights(baseline, size)
	var from := Vector3i(3, 4, 8)
	var to := Vector3i(12, 4, 8)
	var cache := {}
	var changes := Model.generative_relief_segment_changes(
		resource, baseline, from, to, 1, 8, 4, 16, 3, 7, 0, "soil", false,
		{}, cache, heightfield,
	)
	if changes.is_empty():
		errors.append("generative Relief produced no terrain changes")
		return
	var added := 0
	var removed := 0
	for raw_change in changes.values():
		var change: Dictionary = raw_change
		if int(change.after) == 0:
			removed += 1
		else:
			added += 1
	if added == 0 or removed == 0:
		errors.append("signed generative Relief did not produce both bumps and pits")
	var result := Model.values_with_changes(baseline, changes, true)
	resource.voxels = result
	var revisit := Model.generative_relief_segment_changes(
		resource, baseline, to, from, 1, 8, 4, 16, 3, 7, 0, "soil", false,
		{}, cache, heightfield,
	)
	if not revisit.is_empty():
		errors.append("generative Relief accumulated on a revisited stroke footprint")

	var split := _smooth_common_fixture()
	var split_cache := {}
	var first := Model.generative_relief_segment_changes(
		split, baseline, from, Vector3i(8, 4, 8), 1, 8, 4, 16, 3, 7, 0,
		"soil", false, {}, split_cache, heightfield,
	)
	split.voxels = Model.values_with_changes(split.voxels, first, true)
	var second := Model.generative_relief_segment_changes(
		split, baseline, Vector3i(8, 4, 8), to, 1, 8, 4, 16, 3, 7, 0,
		"soil", false, {}, split_cache, heightfield,
	)
	split.voxels = Model.values_with_changes(split.voxels, second, true)
	if split.voxels != result:
		errors.append("generative Relief depends on input-event segment density")

	var alternate := _smooth_common_fixture()
	var alternate_changes := Model.generative_relief_segment_changes(
		alternate, baseline, from, to, 1, 8, 4, 16, 3, 8, 0, "soil", false,
		{}, {}, heightfield,
	)
	if Model.values_with_changes(baseline, alternate_changes, true) == result:
		errors.append("generative Relief variant seed did not change the terrain")

	var light := _smooth_common_fixture()
	var light_changes := Model.generative_relief_segment_changes(
		light, baseline, from, to, 1, 8, 16, 16, 0, 7, 0, "soil", false,
		{}, {}, heightfield,
	)
	light.voxels = Model.values_with_changes(light.voxels, light_changes, true)
	var light_heights := Model.column_heights(light.voxels, size)
	var standard := _smooth_common_fixture()
	var standard_changes := Model.generative_relief_segment_changes(
		standard, baseline, from, to, 1, 8, 16, 16, 1, 7, 0, "soil", false,
		{}, {}, heightfield,
	)
	standard.voxels = Model.values_with_changes(standard.voxels, standard_changes, true)
	var standard_heights := Model.column_heights(standard.voxels, size)
	var light_changed_columns := 0
	var standard_changed_columns := 0
	var maximum_light_offset := 0
	for column_index in heightfield.size():
		var light_offset := absi(light_heights[column_index] - heightfield[column_index])
		var standard_offset := absi(standard_heights[column_index] - heightfield[column_index])
		if light_offset > 0:
			light_changed_columns += 1
		if standard_offset > 0:
			standard_changed_columns += 1
		maximum_light_offset = maxi(maximum_light_offset, light_offset)
	if light_changed_columns == 0:
		errors.append("light generative Relief produced no visible terrain detail")
	if maximum_light_offset > 2:
		errors.append("light generative Relief exceeded its two-voxel ceiling at maximum height")
	if light_changed_columns >= standard_changed_columns:
		errors.append("light generative Relief is not sparser than the established low detail")

	for direction in [-1, 1]:
		var directed := _smooth_common_fixture()
		var directed_changes := Model.generative_relief_segment_changes(
			directed, baseline, from, to, 1, 8, 4, 16, 3, 7, direction,
			"ridges", false, {}, {}, heightfield,
		)
		for raw_change in directed_changes.values():
			var change: Dictionary = raw_change
			if direction > 0 and int(change.after) == 0:
				errors.append("up-only generative Relief removed a voxel")
				break
			if direction < 0 and int(change.after) != 0:
				errors.append("down-only generative Relief added a voxel")
				break
		if direction < 0:
			directed.voxels = Model.values_with_changes(
				directed.voxels, directed_changes, true
			)
			if Model.column_heights(directed.voxels, size).has(-1):
				errors.append("generative Relief punched a through-hole in occupied terrain")


func _test_incremental_relief_parity(
	center: Vector3i,
	errors: Array[String],
) -> void:
	for tool_id in [Model.TOOL_RAISE, Model.TOOL_LOWER]:
		var full_resource := Model.make_pilot()
		var full_baseline := full_resource.voxels.duplicate()
		var full_changes := Model.relief_changes(
			full_resource, full_baseline, center, tool_id, 5, 16, 8, false
		)
		full_resource.voxels = Model.values_with_changes(
			full_resource.voxels, full_changes, true
		)

		var incremental_resource := Model.make_pilot()
		var incremental_baseline := incremental_resource.voxels.duplicate()
		var top_cache := {}
		var amount_cache := {}
		var delta_change_count := 0
		var previous_height := 0
		for height in range(1, 9):
			var delta := Model.relief_changes(
				incremental_resource,
				incremental_baseline,
				center,
				tool_id,
				5,
				16,
				height,
				false,
				top_cache,
				previous_height,
				amount_cache,
			)
			delta_change_count += delta.size()
			incremental_resource.voxels = Model.values_with_changes(
				incremental_resource.voxels, delta, true
			)
			previous_height = height
		if incremental_resource.voxels != full_resource.voxels:
			errors.append(
				"incremental %s differs from one-shot relief"
				% ("Raise" if tool_id == Model.TOOL_RAISE else "Lower")
			)
		if delta_change_count != full_changes.size():
			errors.append(
				"incremental %s revisited changed voxels: %d != %d"
				% [
					"Raise" if tool_id == Model.TOOL_RAISE else "Lower",
					delta_change_count,
					full_changes.size(),
				]
			)

		var overlap_resource := Model.make_pilot()
		var overlap_baseline := overlap_resource.voxels.duplicate()
		var overlap_top_cache := {}
		var overlap_amount_cache := {}
		var path: Array[Vector3i] = []
		for x in range(center.x - 12, center.x + 13, 2):
			path.append(Vector3i(x, center.y, center.z))
		for path_center in path:
			var forward := Model.relief_changes(
				overlap_resource,
				overlap_baseline,
				path_center,
				tool_id,
				5,
				16,
				2,
				false,
				overlap_top_cache,
				0,
				overlap_amount_cache,
			)
			overlap_resource.voxels = Model.values_with_changes(
				overlap_resource.voxels, forward, true
			)
		path.reverse()
		for path_center in path:
			var revisit := Model.relief_changes(
				overlap_resource,
				overlap_baseline,
				path_center,
				tool_id,
				5,
				16,
				2,
				false,
				overlap_top_cache,
				0,
				overlap_amount_cache,
			)
			if not revisit.is_empty():
				errors.append(
					"revisited %s relief footprint produced duplicate changes"
					% ("Raise" if tool_id == Model.TOOL_RAISE else "Lower")
				)
				break


func _test_swept_relief(errors: Array[String]) -> void:
	var resource := Model.make_pilot()
	var size := resource.grid_size()
	var baseline := resource.voxels.duplicate()
	var from := Vector3i(24, 0, 32)
	var to := Vector3i(80, 0, 32)
	var changes := Model.relief_segment_changes(
		resource,
		baseline,
		from,
		to,
		Model.TOOL_RAISE,
		5,
		16,
		8,
		false,
	)
	if changes.is_empty():
		errors.append("swept relief produced no changes")
		return
	resource.voxels = Model.values_with_changes(resource.voxels, changes, true)
	for x in range(from.x, to.x + 1):
		var baseline_top := _column_top(baseline, size, x, from.z)
		var expected_top := mini(size.y - 1, baseline_top + 8)
		var actual_top := _column_top(resource.voxels, size, x, from.z)
		if actual_top != expected_top:
			errors.append(
				"swept relief ridge has a gap at x=%d: %d != %d"
				% [x, actual_top, expected_top]
			)
			return
		for y in range(baseline_top + 1, expected_top + 1):
			if resource.voxels[Model.index_of(Vector3i(x, y, from.z), size)] == 0:
				errors.append("swept relief ridge contains an empty voxel at %s" % Vector3i(x, y, from.z))
				return


func _test_shell_relief(errors: Array[String]) -> void:
	var resource := Model.make_pilot()
	var size := resource.grid_size()
	var baseline := resource.voxels.duplicate()
	var from := Vector3i(24, 0, 32)
	var to := Vector3i(80, 0, 32)
	var top_cache := {}
	var amount_cache := {}
	var foundation_cache := {}
	var changes := Model.shell_relief_segment_changes(
		resource,
		baseline,
		from,
		to,
		5,
		16,
		8,
		false,
		top_cache,
		0,
		amount_cache,
		foundation_cache,
	)
	if changes.is_empty():
		errors.append("shell relief produced no changes")
		return
	resource.voxels = Model.values_with_changes(resource.voxels, changes, true)
	var interior_x := 52
	var baseline_top := _column_top(baseline, size, interior_x, from.z)
	var shell_top := _column_top(resource.voxels, size, interior_x, from.z)
	if shell_top != mini(size.y - 1, baseline_top + 8):
		errors.append("shell relief did not lift the visible top")
		return
	for y in range(baseline_top + 1, shell_top):
		if resource.voxels[Model.index_of(Vector3i(interior_x, y, from.z), size)] != 0:
			errors.append("shell relief filled hidden interior voxel %s" % Vector3i(interior_x, y, from.z))
			return
	for raw_column_index in amount_cache:
		var column_index := int(raw_column_index)
		var x := column_index % size.x
		var z := floori(float(column_index) / float(size.x))
		var top := _column_top(resource.voxels, size, x, z)
		for raw_offset in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
			var offset: Vector2i = raw_offset
			var neighbor: Vector2i = Vector2i(x, z) + offset
			if neighbor.x < 0 or neighbor.y < 0 or neighbor.x >= size.x or neighbor.y >= size.z:
				continue
			var neighbor_top := _column_top(
				resource.voxels, size, neighbor.x, neighbor.y
			)
			if neighbor_top >= top:
				continue
			for y in range(neighbor_top + 1, top + 1):
				if resource.voxels[Model.index_of(Vector3i(x, y, z), size)] == 0:
					errors.append("shell relief left an exposed wall gap at %s" % Vector3i(x, y, z))
					return
	var solid_resource := Model.make_pilot()
	var solid_changes := Model.relief_segment_changes(
		solid_resource,
		solid_resource.voxels.duplicate(),
		from,
		to,
		Model.TOOL_RAISE,
		5,
		16,
		8,
		false,
	)
	solid_resource.voxels = Model.values_with_changes(
		solid_resource.voxels, solid_changes, true
	)
	if changes.size() >= solid_changes.size():
		errors.append(
			"shell relief did not reduce hidden volume: %d >= %d"
			% [changes.size(), solid_changes.size()]
		)
	print(
		"  shell relief visible voxels: %d vs %d solid changes"
		% [changes.size(), solid_changes.size()]
	)
	var region_min := Vector3i(8, 0, 16)
	var region_size := Vector3i(88, size.y, 32)
	var voxel_size := 1.0 / float(resource.normalized_density())
	var shell_mesh := VoxMesher.build_from_packed_voxel_region(
		resource.voxels, size, resource.palette, resource.transparency,
		region_min, region_size, voxel_size,
	)
	var solid_mesh := VoxMesher.build_from_packed_voxel_region(
		solid_resource.voxels, size, solid_resource.palette, solid_resource.transparency,
		region_min, region_size, voxel_size,
	)
	print(
		"  shell/solid exact mesh indices: %d / %d"
		% [_mesh_index_count(shell_mesh), _mesh_index_count(solid_mesh)]
	)
	var incremental := Model.make_pilot()
	var incremental_baseline := incremental.voxels.duplicate()
	var incremental_top_cache := {}
	var incremental_amount_cache := {}
	var incremental_foundation_cache := {}
	for height in range(1, 9):
		var delta := Model.shell_relief_segment_changes(
			incremental,
			incremental_baseline,
			from,
			to,
			5,
			16,
			height,
			false,
			incremental_top_cache,
			height - 1,
			incremental_amount_cache,
			incremental_foundation_cache,
		)
		incremental.voxels = Model.values_with_changes(incremental.voxels, delta, true)
	if incremental.voxels != resource.voxels:
		errors.append("incremental shell relief differs from one-shot result")
	for rate in [1, 4, 16]:
		var timed := Model.make_pilot()
		var timed_baseline := timed.voxels.duplicate()
		var desired_height := Model.buildup_height(0.5, float(rate), 16)
		var timed_changes := Model.shell_relief_segment_changes(
			timed,
			timed_baseline,
			Vector3i(interior_x, 0, from.z),
			Vector3i(interior_x, 0, from.z),
			5,
			4,
			desired_height,
			false,
		)
		timed.voxels = Model.values_with_changes(timed.voxels, timed_changes, true)
		var timed_gain := (
			_column_top(timed.voxels, size, interior_x, from.z)
			- _column_top(timed_baseline, size, interior_x, from.z)
		)
		if timed_gain != desired_height:
			errors.append(
				"shell relief ignored %d vox/sec buildup: %d != %d"
				% [rate, timed_gain, desired_height]
			)


func _test_shell_lower(errors: Array[String]) -> void:
	var resource := Model.make_pilot()
	var size := resource.grid_size()
	var from := Vector3i(28, 0, 32)
	var to := Vector3i(76, 0, 32)
	var original := resource.voxels.duplicate()
	var raised_changes := Model.shell_relief_segment_changes(
		resource, original, from, to, 5, 16, 8, false
	)
	resource.voxels = Model.values_with_changes(resource.voxels, raised_changes, true)
	var raised := resource.voxels.duplicate()
	var center_x := 52
	var raised_top := _column_top(raised, size, center_x, from.z)
	var original_top := _column_top(original, size, center_x, from.z)
	var top_cache := {}
	var amount_cache := {}
	var foundation_cache := {}
	var lowered_changes := Model.shell_lower_segment_changes(
		resource,
		raised,
		from,
		to,
		5,
		8,
		4,
		false,
		top_cache,
		0,
		amount_cache,
		foundation_cache,
	)
	if lowered_changes.is_empty():
		errors.append("shell Lower produced no changes on a raised hollow surface")
		return
	resource.voxels = Model.values_with_changes(resource.voxels, lowered_changes, true)
	var lowered_top := _column_top(resource.voxels, size, center_x, from.z)
	if raised_top - lowered_top != 4:
		errors.append(
			"shell Lower ignored its depth: %d -> %d" % [raised_top, lowered_top]
		)
	if resource.voxels[Model.index_of(Vector3i(center_x, raised_top, from.z), size)] != 0:
		errors.append("shell Lower left its old top inside the hollow volume")
	for y in range(original_top + 1, lowered_top):
		if resource.voxels[Model.index_of(Vector3i(center_x, y, from.z), size)] != 0:
			errors.append("shell Lower filled hidden interior voxel %s" % Vector3i(center_x, y, from.z))
			return
	# A smaller depression inside a previously hollow raise must extend the
	# outside shell walls down to every newly exposed lower neighbor.
	for z in range(from.z - 9, from.z + 10):
		for x in range(from.x - 9, to.x + 10):
			if x < 0 or z < 0 or x >= size.x or z >= size.z:
				continue
			var top := _column_top(resource.voxels, size, x, z)
			for raw_offset in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
				var offset: Vector2i = raw_offset
				var neighbor := Vector2i(x, z) + offset
				if neighbor.x < 0 or neighbor.y < 0 or neighbor.x >= size.x or neighbor.y >= size.z:
					continue
				var neighbor_top := _column_top(resource.voxels, size, neighbor.x, neighbor.y)
				if neighbor_top >= top:
					continue
				for y in range(neighbor_top + 1, top + 1):
					if resource.voxels[Model.index_of(Vector3i(x, y, z), size)] == 0:
						errors.append("shell Lower left an exposed wall gap at %s" % Vector3i(x, y, z))
						return

	var incremental := Model.make_pilot()
	var incremental_original := incremental.voxels.duplicate()
	var incremental_raise := Model.shell_relief_segment_changes(
		incremental, incremental_original, from, to, 5, 16, 8, false
	)
	incremental.voxels = Model.values_with_changes(
		incremental.voxels, incremental_raise, true
	)
	var incremental_baseline := incremental.voxels.duplicate()
	var incremental_top_cache := {}
	var incremental_amount_cache := {}
	var incremental_foundation_cache := {}
	for depth in range(1, 5):
		var delta := Model.shell_lower_segment_changes(
			incremental,
			incremental_baseline,
			from,
			to,
			5,
			8,
			depth,
			false,
			incremental_top_cache,
			depth - 1,
			incremental_amount_cache,
			incremental_foundation_cache,
		)
		incremental.voxels = Model.values_with_changes(incremental.voxels, delta, true)
	if incremental.voxels != resource.voxels:
		errors.append("incremental shell Lower differs from its one-shot result")


func _test_level_brush(errors: Array[String]) -> void:
	var resource := Model.make_pilot()
	var size := resource.grid_size()
	var from := Vector3i(36, 3, 64)
	var to := Vector3i(108, 3, 64)
	var target_top := 3
	var before := resource.voxels.duplicate()
	var changes := Model.level_segment_changes(
		resource, from, to, target_top, 5, 8, false
	)
	if changes.is_empty():
		errors.append("Level brush produced no changes across mixed terraces")
		return
	resource.voxels = Model.values_with_changes(resource.voxels, changes, true)
	for x in range(from.x, to.x + 1):
		var actual_top := _column_top(resource.voxels, size, x, from.z)
		if actual_top != target_top:
			errors.append(
				"Level brush left a gap at x=%d: %d != %d"
				% [x, actual_top, target_top]
			)
			return
	var repeated := Model.level_segment_changes(
		resource, to, from, target_top, 5, 8, false
	)
	if not repeated.is_empty():
		errors.append("Level brush revisited an already completed plane")
	var undo := UndoRedo.new()
	var actions := Actions.new() as EmberVoxelSculptActions
	actions.configure(undo)
	var after := resource.voxels.duplicate()
	var indices := PackedInt32Array()
	for raw_index in changes:
		indices.append(int(raw_index))
	if not actions.commit_applied_stroke(resource, before, after, indices):
		errors.append("Level brush was not registered as one Undo action")
	else:
		undo.undo()
		if resource.voxels != before:
			errors.append("Level brush Undo did not restore the mixed terraces")
		undo.redo()
		if resource.voxels != after:
			errors.append("Level brush Redo did not restore the fixed plane")
	actions.configure(null)
	undo.clear_history()
	undo.free()

	var coarse := Model.make_pilot()
	var coarse_changes := Model.level_segment_changes(
		coarse, Vector3i(32, 4, 32), Vector3i(40, 4, 32), 4, 5, 4, true
	)
	coarse.voxels = Model.values_with_changes(coarse.voxels, coarse_changes, true)
	if _column_top(coarse.voxels, size, 36, 32) != 5:
		errors.append("Coarse Level brush did not align to a complete 2-voxel layer")


func _test_smooth_brush(errors: Array[String]) -> void:
	var resource := Model.make_pilot()
	var size := resource.grid_size()
	var center := Vector3i(48, 0, 48)
	var original_top := _column_top(resource.voxels, size, center.x, center.z)
	var spike_top := mini(size.y - 1, original_top + 8)
	for y in range(original_top + 1, spike_top + 1):
		resource.voxels[Model.index_of(Vector3i(center.x, y, center.z), size)] = 5
	var before := resource.voxels.duplicate()
	var far_before := _column_top(before, size, center.x + 12, center.z)
	var top_cache := {}
	var applied_cache := {}
	var heightfield := Model.column_heights(before, size)
	if heightfield.size() != size.x * size.z:
		errors.append("Smooth brush could not build its pointer-down heightfield")
		return
	var changes := Model.smooth_segment_changes(
		resource,
		before,
		center,
		center,
		5,
		4,
		2,
		false,
		top_cache,
		applied_cache,
		heightfield,
	)
	if changes.is_empty():
		errors.append("Smooth brush produced no changes around a height spike")
		return
	resource.voxels = Model.values_with_changes(resource.voxels, changes, true)
	var center_after := _column_top(resource.voxels, size, center.x, center.z)
	if spike_top - center_after != 2:
		errors.append(
			"Smooth strength did not bound the spike change: %d -> %d"
			% [spike_top, center_after]
		)
	if _column_top(resource.voxels, size, center.x + 12, center.z) != far_before:
		errors.append("Smooth brush changed a column outside its footprint")
	var repeated := Model.smooth_segment_changes(
		resource,
		before,
		center,
		center,
		5,
		4,
		2,
		false,
		top_cache,
		applied_cache,
		heightfield,
	)
	if not repeated.is_empty():
		errors.append("Smooth brush processed a column twice in one gesture")
	var after := resource.voxels.duplicate()
	var indices := PackedInt32Array()
	for raw_index in changes:
		indices.append(int(raw_index))
	var refreshed_heightfield := Model.refresh_column_heights(
		heightfield.duplicate(), after, size, indices
	)
	if refreshed_heightfield != Model.column_heights(after, size):
		errors.append("Smooth incremental heightfield differs from a full rebuild")
	var undo := UndoRedo.new()
	var actions := Actions.new() as EmberVoxelSculptActions
	actions.configure(undo)
	if not actions.commit_applied_stroke(resource, before, after, indices):
		errors.append("Smooth brush was not registered as one Undo action")
	else:
		undo.undo()
		if resource.voxels != before:
			errors.append("Smooth brush Undo did not restore the spike")
		undo.redo()
		if resource.voxels != after:
			errors.append("Smooth brush Redo did not restore the softened surface")
	actions.configure(null)
	undo.clear_history()
	undo.free()

	var coarse := Model.make_pilot()
	var coarse_top := _column_top(coarse.voxels, size, center.x, center.z)
	for y in range(coarse_top + 1, mini(size.y, coarse_top + 9)):
		coarse.voxels[Model.index_of(Vector3i(center.x, y, center.z), size)] = 5
	var coarse_baseline := coarse.voxels.duplicate()
	var coarse_changes := Model.smooth_segment_changes(
		coarse, coarse_baseline, center, center, 5, 4, 1, true, {}, {},
		Model.column_heights(coarse_baseline, size)
	)
	coarse.voxels = Model.values_with_changes(coarse.voxels, coarse_changes, true)
	for z in range(center.z, center.z + 2):
		for x in range(center.x, center.x + 2):
			if _column_top(coarse.voxels, size, x, z) % 2 != 1:
				errors.append("Coarse Smooth did not end on a complete 2-voxel layer")
				return

	var common_center := Vector3i(8, 4, 8)
	var common_bump := _smooth_common_fixture()
	var common_size := common_bump.grid_size()
	for z in range(6, 11):
		for x in range(6, 11):
			for y in range(5, 9):
				common_bump.voxels[Model.index_of(Vector3i(x, y, z), common_size)] = 1
	var bump_before := common_bump.voxels.duplicate()
	var bump_changes := Model.smooth_segment_changes(
		common_bump, bump_before, common_center, common_center, 1, 4, 2, false,
		{}, {}, Model.column_heights(bump_before, common_size), true, true,
	)
	common_bump.voxels = Model.values_with_changes(common_bump.voxels, bump_changes, true)
	if _column_top(common_bump.voxels, common_size, 8, 8) != 6:
		errors.append("Common-level Smooth did not lower a broad bump toward its surrounding level")

	var common_pit := _smooth_common_fixture()
	for z in range(7, 10):
		for x in range(7, 10):
			for y in range(3, 5):
				common_pit.voxels[Model.index_of(Vector3i(x, y, z), common_size)] = 0
	var pit_before := common_pit.voxels.duplicate()
	var pit_heightfield := Model.column_heights(pit_before, common_size)
	var pit_changes := Model.smooth_segment_changes(
		common_pit, pit_before, common_center, common_center, 1, 4, 2, false,
		{}, {}, pit_heightfield, true, true,
	)
	common_pit.voxels = Model.values_with_changes(common_pit.voxels, pit_changes, true)
	if _column_top(common_pit.voxels, common_size, 8, 8) != 4:
		errors.append("Common-level Smooth did not raise a pit when the pits toggle is enabled")
	var peaks_only := _smooth_common_fixture()
	for z in range(7, 10):
		for x in range(7, 10):
			for y in range(3, 5):
				peaks_only.voxels[Model.index_of(Vector3i(x, y, z), common_size)] = 0
	var peaks_before := peaks_only.voxels.duplicate()
	var peaks_changes := Model.smooth_segment_changes(
		peaks_only, peaks_before, common_center, common_center, 1, 4, 2, false,
		{}, {}, Model.column_heights(peaks_before, common_size), true, false,
	)
	if not peaks_changes.is_empty():
		errors.append("Peaks-only Common Smooth changed a pit while its pits toggle was disabled")


func _test_ramp_brush(errors: Array[String]) -> void:
	var resource := Model.make_pilot()
	var size := resource.grid_size()
	var from := Vector3i(24, 2, 100)
	var to := Vector3i(104, 6, 100)
	var before := resource.voxels.duplicate()
	var heightfield := Model.column_heights(before, size)
	var from_top := int(heightfield[from.x + from.z * size.x])
	var to_top := int(heightfield[to.x + to.z * size.x])
	if from_top >= to_top:
		errors.append("Ramp fixture has no height difference")
		return
	var changes := Model.ramp_segment_changes(
		resource, before, from, to, 5, 4, false, heightfield
	)
	if changes.is_empty():
		errors.append("Ramp A -> B produced no changes")
		return
	resource.voxels = Model.values_with_changes(resource.voxels, changes, true)
	var previous_top := from_top
	for x in range(from.x, to.x + 1):
		var progress := float(x - from.x) / float(to.x - from.x)
		var expected_top := roundi(lerpf(float(from_top), float(to_top), progress))
		var actual_top := _column_top(resource.voxels, size, x, from.z)
		if actual_top != expected_top:
			errors.append(
				"Ramp height differs at x=%d: %d != %d" % [x, actual_top, expected_top]
			)
			return
		if absi(actual_top - previous_top) > 1:
			errors.append("Ramp contains a non-walkable height jump at x=%d" % x)
			return
		previous_top = actual_top
	if _column_top(resource.voxels, size, 64, 108) != _column_top(before, size, 64, 108):
		errors.append("Ramp changed terrain outside its selected width")
	var after := resource.voxels.duplicate()
	var indices := PackedInt32Array()
	for raw_index in changes:
		indices.append(int(raw_index))
	var undo := UndoRedo.new()
	var actions := Actions.new() as EmberVoxelSculptActions
	actions.configure(undo)
	if not actions.commit_applied_stroke(resource, before, after, indices):
		errors.append("Ramp was not registered as one Undo action")
	else:
		undo.undo()
		if resource.voxels != before:
			errors.append("Ramp Undo did not restore the original terrain")
		undo.redo()
		if resource.voxels != after:
			errors.append("Ramp Redo did not restore the slope")
	actions.configure(null)
	undo.clear_history()
	undo.free()

	var coarse := Model.make_pilot()
	var coarse_before := coarse.voxels.duplicate()
	var coarse_changes := Model.ramp_segment_changes(
		coarse,
		coarse_before,
		from,
		to,
		5,
		4,
		true,
		Model.column_heights(coarse_before, size),
	)
	coarse.voxels = Model.values_with_changes(coarse.voxels, coarse_changes, true)
	for x in range(from.x, to.x + 1, 2):
		if _column_top(coarse.voxels, size, x, from.z) % 2 != 1:
			errors.append("Coarse Ramp did not end on a complete 2-voxel layer")
			return


func _test_region_mask(errors: Array[String]) -> void:
	var resource := Model.make_pilot()
	var size := resource.grid_size()
	var region := Model.block_region_for_cells(
		Vector3i(90, 0, 70), Vector3i(4, 0, 10), resource.normalized_density(), resource.size_blocks
	)
	if region != Rect2i(0, 0, 3, 3):
		errors.append("Surface edit selection did not normalize its two corners: %s" % region)
		return
	var before := resource.voxels.duplicate()
	var all_changes := Model.level_segment_changes(
		resource, Vector3i(8, 3, 64), Vector3i(112, 3, 64), 10, 5, 4, false
	)
	var selected := Rect2i(1, 1, 1, 2)
	var masked := Model.changes_in_block_region(
		all_changes, size, resource.normalized_density(), selected
	)
	if masked.is_empty() or masked.size() >= all_changes.size():
		errors.append("Surface edit selection did not isolate a strict working subset")
		return
	for raw_index in masked:
		var flat := int(raw_index) % (size.x * size.z)
		var block := Vector2i(
			floori(float(flat % size.x) / float(resource.normalized_density())),
			floori(float(flat / size.x) / float(resource.normalized_density())),
		)
		if not selected.has_point(block):
			errors.append("Surface edit selection leaked a change outside its rectangle")
			return
	resource.voxels = Model.values_with_changes(resource.voxels, masked, true)
	if _column_top(resource.voxels, size, 40, 64) != 10:
		errors.append("Surface edit selection did not apply inside the working rectangle")
	if _column_top(resource.voxels, size, 80, 64) != _column_top(before, size, 80, 64):
		errors.append("Surface edit selection changed visible context outside the rectangle")


func _test_chunk_projection(
	resource: EmberVoxelModelResource,
	full_mesh: ArrayMesh,
	full_elapsed: int,
	errors: Array[String],
) -> void:
	var model: Dictionary = resource.to_definition().get("model", {})
	var voxel_size := VoxMesher.normalized_voxel_size(model)
	var chunk_indices := 0
	var sample_elapsed := 0
	for chunk_z in 8:
		for chunk_x in 8:
			var started := Time.get_ticks_usec()
			var mesh := VoxMesher.build_from_packed_voxel_region(
				resource.voxels,
				resource.grid_size(),
				resource.palette,
				resource.transparency,
				Vector3i(chunk_x * 16, 0, chunk_z * 16),
				Vector3i(16, 24, 16),
				voxel_size,
			)
			var elapsed := Time.get_ticks_usec() - started
			if chunk_x == 3 and chunk_z == 3:
				sample_elapsed = elapsed
			chunk_indices += _mesh_index_count(mesh)
	var full_indices := _mesh_index_count(full_mesh)
	if chunk_indices != full_indices:
		errors.append(
			"chunk preview exposes or drops seam faces: %d != %d" % [chunk_indices, full_indices]
		)
	if sample_elapsed * 5 >= full_elapsed:
		errors.append(
			"local chunk rebuild is not materially cheaper than full mesh: %dus vs %dus"
			% [sample_elapsed, full_elapsed]
		)
	var old_started := Time.get_ticks_usec()
	var old_model: Dictionary = resource.to_definition().get("model", {})
	var old_mesh := VoxMesher.build_from_ember_model_region(
		old_model, Vector3i(32, 0, 32), Vector3i(16, 24, 16), voxel_size
	)
	var old_elapsed := Time.get_ticks_usec() - old_started
	var direct_started := Time.get_ticks_usec()
	var direct_mesh := VoxMesher.build_from_packed_voxel_region(
		resource.voxels,
		resource.grid_size(),
		resource.palette,
		resource.transparency,
		Vector3i(32, 0, 32),
		Vector3i(16, 24, 16),
		voxel_size,
	)
	var direct_elapsed := Time.get_ticks_usec() - direct_started
	if _mesh_index_count(old_mesh) != _mesh_index_count(direct_mesh):
		errors.append("packed preview path differs from Dictionary region mesh")
	if direct_elapsed >= old_elapsed:
		errors.append(
			"packed preview hot path is not cheaper: %dus vs %dus"
			% [direct_elapsed, old_elapsed]
		)
	var draft_started := Time.get_ticks_usec()
	var draft_mesh := VoxMesher.build_heightfield_preview_region(
		resource.voxels,
		resource.grid_size(),
		resource.palette,
		resource.transparency,
		Vector3i(32, 0, 32),
		Vector3i(16, 24, 16),
		voxel_size,
	)
	var draft_elapsed := Time.get_ticks_usec() - draft_started
	if draft_mesh.get_surface_count() == 0:
		errors.append("relief draft preview produced an empty surface")
	if draft_elapsed >= direct_elapsed:
		errors.append(
			"relief draft preview is not cheaper: %dus vs exact %dus"
			% [draft_elapsed, direct_elapsed]
		)
	print("  preview hot path: Dictionary %dus -> Packed %dus" % [old_elapsed, direct_elapsed])
	print("  relief hold preview: Exact %dus -> Draft %dus" % [direct_elapsed, draft_elapsed])


func _mesh_index_count(mesh: ArrayMesh) -> int:
	var count := 0
	for surface_index in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface_index)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		count += indices.size() if not indices.is_empty() else vertices.size()
	return count


func _column_top(values: PackedByteArray, size: Vector3i, x: int, z: int) -> int:
	for y in range(size.y - 1, -1, -1):
		if values[Model.index_of(Vector3i(x, y, z), size)] != 0:
			return y
	return -1
