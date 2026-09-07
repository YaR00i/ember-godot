extends SceneTree
const Workspace = preload("res://addons/ember_import/ember_voxel_sculpt_workspace.gd")
const Model = preload("res://addons/ember_import/ember_voxel_sculpt_model.gd")
const Mesher = preload("res://scripts/ember_voxel_surface_mesher.gd")
const Native = preload("res://addons/ember_import/ember_voxel_tools_preview.gd")
const TEMP_PATH := "user://ember_height_slice_test.tres"
var errors: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var resource := _fixture()
	var original := resource.voxels.duplicate()
	var size := resource.grid_size()
	var ray := Vector3(0.5, 2, 0.5)
	_check(Model.pick(resource, ray, Vector3.DOWN).get("hit") == Vector3i(8, 9, 8), "full pick missed roof")
	_check(Model.pick(resource, ray, Vector3.DOWN, 4).get("hit") == Vector3i(8, 3, 8), "slice pick did not reach cut plane")
	_check(Model.pick(resource, ray, Vector3.DOWN, 1).get("hit") == Vector3i(8, 0, 8), "bottom slice off by one")
	_check(Model.pick(resource, ray, Vector3.DOWN, 0).is_empty(), "empty slice was pickable")
	for chunk_x in [0, 16]:
		var start := Vector3i(chunk_x, 0, 0)
		var extent := Vector3i(16, size.y, 16)
		var mesh := Mesher.build_region(resource, start, extent, 1.0 / 16.0, false, true, 4)
		_check_cut_mesh(mesh, Vector3.ZERO, Vector3.ONE)
		var adapter := Native.new()
		if Native.available():
			var result := adapter.build_region(resource.voxels, size, resource.palette,
				PackedByteArray(), start, extent, 1.0 / 16.0, null, null, 4)
			_check_cut_mesh(result.get("mesh"), result.get("position", Vector3.ZERO), result.get("scale", Vector3.ONE))
	var undo := UndoRedo.new()
	var workspace := Workspace.new()
	workspace.setup(null, undo)
	root.add_child(workspace)
	workspace.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	workspace.open_surface(resource, TEMP_PATH, Rect2i(0, 0, 1, 1))
	for frame in 4:
		await process_frame
	var toggle := workspace.find_child("EnableHeightSlice", true, false) as CheckButton
	var height := workspace.find_child("HeightSliceLevel", true, false) as SpinBox
	toggle.button_pressed = true
	height.value = 4
	_check(not workspace.has_unsaved_changes(), "slice dirtied canonical content")
	_check(not bool(workspace.call("_shows_water_overlay")), "slice retained water obscuring the bed")
	for frame in 4:
		await process_frame
	var camera: Camera3D = workspace.get("_camera")
	var viewport: SubViewport = workspace.get("_viewport")
	var container: SubViewportContainer = workspace.get("_viewport_container")
	var screen := camera.unproject_position(Vector3(0.5, 0.25, 0.5)) * container.size / Vector2(viewport.size)
	_check(workspace.call("_pick_at", screen).get("hit", Vector3i(-1, -1, -1)).y == 3, "viewport and slice pick diverged")
	for tool_id in [Model.TOOL_REMOVE, Model.TOOL_ADD, Model.TOOL_PAINT, Model.TOOL_MATERIAL]:
		_check(bool(workspace.call("_activate_tool_id", tool_id)), "slice could not activate compact tool %d" % tool_id)
		var palette: OptionButton = workspace.get("_palette")
		palette.select(1) # Second non-empty color.
		var preset: OptionButton = workspace.get("_material_preset")
		preset.select(1)
		workspace.call("_prepare_stroke", tool_id)
		var centers: Array[Vector3i] = [Vector3i(15, 3, 8)]
		workspace.call("_apply_stroke_centers", centers)
		workspace.call("_finish_stroke")
		_check_hidden(resource, original)
	_check(workspace.has_unsaved_changes(), "brushes made no changes in slice")
	var edited := resource.voxels.duplicate()
	var material := resource.transparency.duplicate()
	undo.undo()
	undo.redo()
	_check(resource.voxels == edited and resource.transparency == material, "slice Undo/Redo diverged")
	_check(bool(workspace.call("_save")), "slice save failed")
	var reopened := ResourceLoader.load(TEMP_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as EmberVoxelModelResource
	_check(reopened != null and reopened.voxels == edited and reopened.grid_size() == size, "save truncated the upper layers")
	_check_hidden(reopened, original)
	# Changing levels while a gesture is held commits it before changing bounds.
	workspace.call("_prepare_stroke", Model.TOOL_PAINT)
	height.value = 1
	_check(not bool(workspace.get("_stroke_active")), "slice switch retained a live stroke")
	height.value = 6
	height.value = 4
	for frame in 4:
		await process_frame
	if "--visual" in OS.get_cmdline_user_args():
		workspace.call("_fit_camera_to_surface")
		for frame in 6:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://ember_height_slice_test.png")
		print("VISUAL: ", ProjectSettings.globalize_path("user://ember_height_slice_test.png"))
	toggle.button_pressed = false
	_check(workspace.call("_pick_at", screen).get("hit", Vector3i(-1, -1, -1)).y != 3, "full view still picked the slice")
	_check(resource.voxels == edited, "leaving slice changed content")
	workspace.free()
	undo.clear_history()
	undo.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_PATH))
	if errors.is_empty():
		print("PASS height slice: cut caps, stock/native mesh, picking, protected upper/region, brushes, save, Undo/Redo")
	else:
		for error in errors:
			printerr(error)
	quit(0 if errors.is_empty() else 1)


func _check_hidden(resource: EmberVoxelModelResource, original: PackedByteArray) -> void:
	var size := resource.grid_size()
	for index in original.size():
		if index >= 4 * size.x * size.z or index % size.x >= 16:
			_check(resource.voxels[index] == original[index], "hidden/out-of-region voxel changed")
			_check(index >= resource.transparency.size() or resource.transparency[index] == 0, "hidden material changed")


func _check_cut_mesh(mesh: Mesh, at: Vector3, scale: Vector3) -> void:
	_check(mesh != null and mesh.get_surface_count() > 0, "slice mesh missing")
	if mesh == null:
		return
	var has_cap := false
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for i in vertices.size():
			var point := at + vertices[i] * scale
			_check(point.y <= 0.2501, "hidden geometry remained above cut")
			if is_equal_approx(point.y, 0.25) and normals[i].y > 0.9:
				has_cap = true
	_check(has_cap, "cut left an open hole instead of a top face")


func _fixture() -> EmberVoxelModelResource:
	var resource := EmberVoxelModelResource.new()
	resource.model_id = "height_slice_test"
	resource.display_name = "Тест среза · верх защищён"
	resource.voxels_per_block = 16
	resource.size_blocks = Vector3i(2, 1, 1)
	resource.height_voxels = 10
	resource.palette = PackedColorArray([Color.TRANSPARENT, Color(0.3, 0.65, 0.45), Color(0.8, 0.5, 0.3)])
	var size := resource.grid_size()
	resource.voxels.resize(size.x * size.y * size.z)
	for y in size.y:
		for z in size.z:
			for x in size.x:
				if y < 6 or y >= 8:
					resource.voxels[Model.index_of(Vector3i(x, y, z), size)] = 1
	return resource


func _check(condition: bool, message: String) -> void:
	if not condition and message not in errors:
		errors.append(message)
