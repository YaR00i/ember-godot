extends SceneTree
## Forward+ visual comparison of two disposable fine Surface results.
## Left = existing fine level brush; right = Macro -> refinement -> fine bake.

const SurfaceProjection = preload("res://scripts/ember_voxel_surface_projection.gd")
const MacroTerrain = preload("res://tools/prototypes/ember_macro_terrain_2_5d.gd")
const TRACE := "res://tools/fixtures/world_edit_level_real_cells_v1.json"
const FINE := "user://qa_macro_reference_surface.res"
const MACRO := "user://qa_macro_baked_surface.res"

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var fine := ResourceLoader.load(FINE, "", ResourceLoader.CACHE_MODE_IGNORE) as EmberVoxelModelResource
	var macro := ResourceLoader.load(MACRO, "", ResourceLoader.CACHE_MODE_IGNORE) as EmberVoxelModelResource
	if fine == null or macro == null:
		printerr("FAIL Macro render: run qa_macro_landscape_2_5d.gd first")
		quit(1)
		return
	var full_fine: Image = await _capture(fine.duplicate_model(), true, false)
	var full_macro: Image = await _capture(macro.duplicate_model(), true, false)
	var close_fine: Image = await _capture(fine.duplicate_model(), false, true)
	var close_macro: Image = await _capture(macro.duplicate_model(), false, true)
	if full_fine != null and full_macro != null:
		_save_pair(full_fine, full_macro, "user://qa_macro_landscape_coast_forward_plus.png")
	if close_fine != null and close_macro != null:
		_save_pair(close_fine, close_macro, "user://qa_macro_landscape_relief_forward_plus.png")
	var preview: Image = await _capture_macro_preview()
	if preview != null:
		if preview.save_png("user://qa_macro_landscape_preview_forward_plus.png") != OK:
			failures.append("could not save Macro preview")
		else:
			print("MACRO_FORWARD_PLUS_PREVIEW ", ProjectSettings.globalize_path("user://qa_macro_landscape_preview_forward_plus.png"))
	if failures.is_empty():
		print("PASS Macro Forward+ visual pair: current fine left, Macro refined right")
	else:
		for reason in failures:
			printerr("FAIL Macro Forward+ render: ", reason)
	quit(0 if failures.is_empty() else 1)


func _capture(surface: EmberVoxelModelResource, water: bool, close: bool) -> Image:
	if water:
		var columns := surface.grid_size().x * surface.grid_size().z
		surface.surface_fill_levels.resize(columns)
		surface.surface_fill_levels.fill(18)
		surface.surface_fill_materials.resize(columns)
		surface.surface_fill_materials.fill(1)
		surface.surface_fill_palette.resize(columns)
		surface.surface_fill_palette.fill(0)
	var view := SubViewport.new()
	view.size = Vector2i(1000, 640)
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var scene := Node3D.new()
	view.add_child(scene)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("#273644")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("#f5ead7")
	settings.ambient_light_energy = 0.7
	environment.environment = settings
	scene.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, 25, 0)
	light.light_energy = 1.35
	scene.add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 8.0 if close else 21.0
	camera.position = Vector3(17.0, 8.0, 2.0) if close else Vector3(20.0, 21.0, -9.0)
	scene.add_child(camera)
	camera.look_at(Vector3(11.6, 1.0, 7.3) if close else Vector3(7.0, 1.0, 7.5))
	camera.current = true
	var projection: Node3D = SurfaceProjection.new()
	scene.add_child(projection)
	projection.configure(surface, 1.0, Vector2i(14, 15), null, false)
	var deadline := Time.get_ticks_msec() + 90000
	while not projection.is_projection_complete() and Time.get_ticks_msec() < deadline:
		await process_frame
	if not projection.is_projection_complete():
		failures.append("fine Surface projection did not settle")
		view.free()
		return null
	for unused in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	var picture := view.get_texture().get_image()
	view.free()
	return picture


func _save_pair(left: Image, right: Image, path: String) -> void:
	left.convert(Image.FORMAT_RGBA8)
	right.convert(Image.FORMAT_RGBA8)
	var pair := Image.create(left.get_width() * 2, left.get_height(), false, Image.FORMAT_RGBA8)
	pair.blit_rect(left, Rect2i(Vector2i.ZERO, left.get_size()), Vector2i.ZERO)
	pair.blit_rect(right, Rect2i(Vector2i.ZERO, right.get_size()), Vector2i(left.get_width(), 0))
	if pair.save_png(path) != OK:
		failures.append("could not save " + path)
	else:
		print("MACRO_FORWARD_PLUS_IMAGE ", ProjectSettings.globalize_path(path))


func _capture_macro_preview() -> Image:
	var file := FileAccess.open(TRACE, FileAccess.READ)
	if file == null:
		failures.append("recorded trace missing for Macro preview")
		return null
	var fixture: Dictionary = JSON.parse_string(file.get_as_text())
	file.close()
	var points: Array = fixture.points
	var macro := MacroTerrain.new()
	macro.configure(Vector2i(14, 15), 32, 3817)
	var previous := Vector3i(int(points[0][1]), int(points[0][2]), int(points[0][3]))
	for point in points:
		var next := Vector3i(int(point[1]), int(point[2]), int(point[3]))
		macro.apply_level_segment(previous, next, 15, 25)
		previous = next
	var view := SubViewport.new()
	view.size = Vector2i(1000, 640)
	view.own_world_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(view)
	var scene := Node3D.new()
	view.add_child(scene)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("#273644")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color("#f5ead7")
	settings.ambient_light_energy = 0.7
	environment.environment = settings
	scene.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, 25, 0)
	light.light_energy = 1.35
	scene.add_child(light)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 21.0
	camera.position = Vector3(20.0, 21.0, -9.0)
	scene.add_child(camera)
	camera.look_at(Vector3(7.0, 1.0, 7.5))
	camera.current = true
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	for chunk in macro.all_chunks():
		var visual := MeshInstance3D.new()
		visual.mesh = macro.preview_chunk(chunk)
		visual.material_override = material
		scene.add_child(visual)
	for unused in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	var picture := view.get_texture().get_image()
	view.free()
	return picture
