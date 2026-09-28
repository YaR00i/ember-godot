extends SceneTree
## A wide hover must only move a shader overlay across existing terrain tiles.

const TerrainResource = preload("res://scripts/prototypes/ember_terrain_pilot_resource.gd")
const WorldEditor = preload("res://addons/ember_import/ember_world_editor.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var visible_forward := DisplayServer.get_name() != "headless" and RenderingServer.get_current_rendering_method() == "forward_plus"
	if visible_forward:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(Vector2i(1280, 720))
		root.size = Vector2i(1280, 720)
	var terrain := TerrainResource.new()
	terrain.width = 768
	terrain.depth = 768
	terrain.palette = PackedColorArray([Color.TRANSPARENT, Color.BROWN, Color.GREEN])
	var columns := terrain.width * terrain.depth
	terrain.heights.resize(columns)
	terrain.heights.fill(8)
	terrain.top_materials.resize(columns)
	terrain.top_materials.fill(2)
	terrain.base_materials.resize(columns)
	terrain.base_materials.fill(1)
	terrain.cap_depths.resize(columns)
	terrain.cap_depths.fill(4)
	terrain.water_levels.resize(columns)
	terrain.water_materials.resize(columns)
	var heights_before := terrain.heights.duplicate()
	var projection := EmberTerrainPilotProjection.new()
	projection.source = terrain
	root.add_child(projection)
	while projection.pending_tile_count() > 0:
		await process_frame
	var camera: Camera3D
	if visible_forward:
		camera = Camera3D.new()
		camera.position = Vector3(384, 1000, 900)
		camera.far = 3000.0
		root.add_child(camera)
		camera.look_at(Vector3(384, 8, 384))
		camera.make_current()
		DisplayServer.window_move_to_foreground()
		await RenderingServer.frame_post_draw
	var editor := WorldEditor.new()
	var initial_children := projection.get_child_count(true)
	var first_ground := projection.get_node("TerrainTile_0_0/Ground") as MeshInstance3D
	var first_mesh := first_ground.mesh
	var frame_intervals: Array[int] = []
	var focused_frames := 0
	var last_draw_usec := Time.get_ticks_usec()
	for index in 144:
		var key := Vector2i(index % 12, index / 12)
		var center := Vector2(key * 64) + Vector2(32, 32)
		editor._sync_compact_grid_overlay(projection, center, 8.0, 24.0, 0, center - Vector2(4, 4), 8)
		assert(projection.get_child_count(true) == initial_children)
		assert(first_ground.mesh == first_mesh)
		if index == 0:
			assert(first_ground.material_overlay == editor._compact_grid_material)
		if index == 143:
			assert(first_ground.material_overlay == null)
		if visible_forward:
			await RenderingServer.frame_post_draw
			last_draw_usec = Time.get_ticks_usec()
	for index in range(143, -1, -1):
		var key := Vector2i(index % 12, index / 12)
		var center := Vector2(key * 64) + Vector2(32, 32)
		editor._sync_compact_grid_overlay(projection, center, 8.0, 24.0, 0, center - Vector2(4, 4), 8)
		assert(projection.get_child_count(true) == initial_children)
		assert(first_ground.mesh == first_mesh)
		if visible_forward:
			await RenderingServer.frame_post_draw
			last_draw_usec = Time.get_ticks_usec()
	assert(first_ground.material_overlay == editor._compact_grid_material)
	var far_apart: Array[Vector2i] = [Vector2i(2, 2), Vector2i(9, 9), Vector2i(2, 9), Vector2i(9, 2)]
	for index in 80:
		var key: Vector2i = far_apart[index % far_apart.size()]
		var center := Vector2(key * 64) + Vector2(32, 32)
		editor._sync_compact_grid_overlay(projection, center, 128.0, 144.0, 0, center - Vector2(4, 4), 8)
		assert(projection.get_child_count(true) == initial_children)
		assert(first_ground.mesh == first_mesh)
		if visible_forward:
			await RenderingServer.frame_post_draw
			var now := Time.get_ticks_usec()
			if DisplayServer.window_is_focused():
				focused_frames += 1
				frame_intervals.append(now - last_draw_usec)
			last_draw_usec = now
	assert(terrain.heights == heights_before and projection.document.heights == heights_before)
	frame_intervals.sort()
	var p95_ms := float(frame_intervals[clampi(ceili(float(frame_intervals.size()) * 0.95) - 1, 0, frame_intervals.size() - 1)]) / 1000.0 if not frame_intervals.is_empty() else -1.0
	var max_ms := float(frame_intervals.back()) / 1000.0 if not frame_intervals.is_empty() else -1.0
	print("COMPACT_GRID_SHADER tiles=144 children=", initial_children,
		" radius8_hops=80 terrain=unchanged focused_frames=", focused_frames,
		" measured_frames=", frame_intervals.size(), " p95_ms=", p95_ms, " max_ms=", max_ms)
	editor._clear_compact_grid_overlay()
	assert(first_ground.material_overlay == null)
	editor.free()
	if is_instance_valid(camera): camera.queue_free()
	projection.queue_free()
	await process_frame
	quit()
