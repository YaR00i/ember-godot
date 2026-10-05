extends SceneTree
## Fixed-camera Forward+ comparison for the separate clear-water study scene.

const STUDY_SCENE := "res://scenes/compact_clear_water_study.tscn"
const OUTPUT_DIR := "user://ember-tests/clear-water-study"


func _initialize() -> void:
	_capture.call_deferred()


func _capture() -> void:
	root.size = Vector2i(1280, 720)
	var scene := (load(STUDY_SCENE) as PackedScene).instantiate()
	root.add_child(scene)
	var canvas := scene.get_node_or_null("CanvasLayer") as CanvasLayer
	if canvas != null:
		canvas.hide()
	var projection: EmberTerrainPilotProjection
	for frame in 720:
		await process_frame
		projection = _find_projection(scene)
		if projection != null and projection.pending_tile_count() == 0 and frame > 25:
			break
	if projection == null or projection.pending_tile_count() > 0:
		push_error("clear water study terrain did not finish")
		quit(1)
		return
	var water := projection.get("_water_material") as ShaderMaterial
	if water == null:
		push_error("clear water study material is missing")
		quit(1)
		return
	var water_vertices := 0
	var water_alpha_range := Vector2(1.0, 0.0)
	for mesh_instance in projection.find_children("Water", "MeshInstance3D", true, false):
		var mesh := (mesh_instance as MeshInstance3D).mesh
		if mesh != null and mesh.get_surface_count() > 0:
			water_vertices += mesh.surface_get_array_len(0)
			var colors := mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR] as PackedColorArray
			for color in colors:
				water_alpha_range.x = minf(water_alpha_range.x, color.a)
				water_alpha_range.y = maxf(water_alpha_range.y, color.a)
	print("CLEAR_WATER water vertices: ", water_vertices, ", tile build ms: ", projection.all_tiles_ms)
	print("CLEAR_WATER vertex depth alpha: ", water_alpha_range)
	var depth_counts := [0, 0, 0, 0]
	var deep_counts := [0, 0, 0, 0]
	var min_depth := 1000000
	var max_depth := 0
	var wet_with_ground := 0
	var wet_top_materials := {}
	var water_level_counts := {}
	var wet_height_counts := {}
	for index in projection.document.water_levels.size():
		var depth: int = projection.document.water_levels[index] - projection.document.heights[index]
		if depth <= 0 or projection.document.water_materials[index] == 0:
			continue
		depth_counts[mini(depth, 4) - 1] += 1
		var level: int = projection.document.water_levels[index]
		water_level_counts[level] = int(water_level_counts.get(level, 0)) + 1
		var height: int = projection.document.heights[index]
		wet_height_counts[height] = int(wet_height_counts.get(height, 0)) + 1
		min_depth = mini(min_depth, depth)
		max_depth = maxi(max_depth, depth)
		deep_counts[0 if depth <= 8 else 1 if depth <= 16 else 2 if depth <= 32 else 3] += 1
		if projection.document.top_materials[index] > 0:
			wet_with_ground += 1
			var top: int = projection.document.top_materials[index]
			wet_top_materials[top] = int(wet_top_materials.get(top, 0)) + 1
	print("CLEAR_WATER wet depth 1/2/3/4+: ", depth_counts, ", wet ground: ", wet_with_ground)
	print("CLEAR_WATER wet depth min/max: ", min_depth, "/", max_depth,
		", depth <=8/<=16/<=32/>32: ", deep_counts)
	print("CLEAR_WATER wet top materials: ", wet_top_materials)
	print("CLEAR_WATER dimensions/origin/limit: ", projection.document.width, "x", projection.document.depth,
		" / ", projection.document.origin_y, " / ", projection.document.height_limit)
	print("CLEAR_WATER water levels: ", water_level_counts, ", wet floor heights: ", wet_height_counts)
	print("CLEAR_WATER palette slot 3: ", projection.document.palette[3],
		", role: ", projection.document.palette_surface_roles[3])
	var directory := ProjectSettings.globalize_path(OUTPUT_DIR)
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		push_error("cannot create clear water study output directory")
		quit(1)
		return
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.far = 2400.0
	for view in ["high", "low", "shore"]:
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE if view == "shore" else Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 460.0 if view == "high" else 370.0
		camera.fov = 55.0
		camera.global_position = Vector3(720.0, 92.0, -170.0) if view == "shore" else Vector3(970.0, 660.0 if view == "high" else 260.0, -470.0)
		camera.look_at(Vector3(360.0, 18.0, 350.0) if view == "shore" else Vector3(350.0, 18.0, 350.0))
		camera.make_current()
		for moment in [0.0, 4.0]:
			water.set_shader_parameter("preview_time", moment)
			for frame in 12:
				await process_frame
			await RenderingServer.frame_post_draw
			var path := "%s/%s-t%d.png" % [OUTPUT_DIR, view, int(moment)]
			if root.get_texture().get_image().save_png(path) != OK:
				push_error("cannot save " + path)
				quit(1)
				return
			print("PASS clear water study capture: ", ProjectSettings.globalize_path(path))
	quit()


func _find_projection(node: Node) -> EmberTerrainPilotProjection:
	if node is EmberTerrainPilotProjection:
		return node as EmberTerrainPilotProjection
	for child in node.get_children():
		var found := _find_projection(child)
		if found != null:
			return found
	return null
