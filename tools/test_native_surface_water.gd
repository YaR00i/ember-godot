extends SceneTree
## Offset wet chunks must retain stock water/foam geometry and shader space.
const Native = preload("res://scripts/ember_voxel_native_mesher.gd")
const Surface = preload("res://scripts/ember_voxel_surface_mesher.gd")
const Materials = preload("res://scripts/ember_voxel_surface_materials.gd")
const Workspace = preload("res://addons/ember_import/ember_voxel_sculpt_workspace.gd")
const ProjectionScript = preload("res://scripts/ember_voxel_surface_projection.gd")
var errors: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func check(condition: bool, message: String) -> void:
	if not condition:
		errors.append(message)


func fixture() -> EmberVoxelModelResource:
	var source := EmberVoxelModelResource.new()
	source.model_id = "native_surface_water_fixture"
	source.display_name = "Native Surface water"
	source.tags = PackedStringArray(["surface", "world", "godot-native"])
	source.material = {"preset": "world_surface", "semanticOwner": source.model_id}
	source.size_blocks = Vector3i(4, 2, 4)
	source.height_voxels = 32
	source.palette = PackedColorArray([Color.TRANSPARENT, Color("aa8844"), Color("33bbbb")])
	source.voxels.resize(64 * 32 * 64)
	for y in 8:
		for z in 64:
			for x in 64:
				source.voxels[x + z * 64 + y * 4096] = 1
	source.surface_fill_levels.resize(4096)
	source.surface_fill_materials.resize(4096)
	source.surface_fill_palette.resize(4096)
	for z in range(10, 40):
		for x in range(28, 60):
			var column := x + z * 64
			source.surface_fill_levels[column] = 16
			source.surface_fill_materials[column] = 1
			source.surface_fill_palette[column] = 2
	# A shallow tint on an opaque column uses the other canonical water channel.
	source.transparency.resize(source.voxels.size())
	source.transparency[20 + 20 * 64 + 7 * 4096] = 160
	# A rock crosses the water plane, and a cavity crosses a chunk boundary.
	for z in range(18, 23):
		for x in range(34, 39):
			for y in range(8, 19):
				source.voxels[x + z * 64 + y * 4096] = 1
	for z in range(25, 27):
		for x in range(31, 35):
			for y in 8:
				source.voxels[x + z * 64 + y * 4096] = 0
	return source


func surface_index(mesh: Mesh, name: String) -> int:
	for index in mesh.get_surface_count():
		if mesh.surface_get_name(index) == name:
			return index
	return -1


func verify_overlay(visual: MeshInstance3D, expected: Mesh, label: String) -> void:
	check(visual != null and visual.mesh != null, label + " missing mesh")
	if visual == null or visual.mesh == null:
		return
	check(visual.transform.is_equal_approx(Transform3D.IDENTITY), label + " changed shader coordinates/scale")
	for name in ["water", "water_foam"]:
		var actual_index := surface_index(visual.mesh, name)
		var expected_index := surface_index(expected, name)
		check((actual_index >= 0) == (expected_index >= 0), label + " missing/unexpected " + name)
		if actual_index < 0 or expected_index < 0:
			continue
		var actual := visual.mesh.surface_get_arrays(actual_index)
		var wanted := expected.surface_get_arrays(expected_index)
		for channel in Mesh.ARRAY_MAX:
			check(actual[channel] == wanted[channel], label + " changed " + name + " channel " + str(channel))


func terrain_faces(mesh: Mesh, transform: Transform3D) -> Dictionary:
	# Compare exposed face area per plane/normal/color, independent of greedy
	# triangulation. This catches holes, moved ground and palette/normal changes.
	var result := {}
	for surface in mesh.get_surface_count():
		if str(mesh.surface_get_name(surface)).begins_with("water"):
			continue
		var arrays := mesh.surface_get_arrays(surface)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			for index in points.size():
				indices.append(index)
		for triangle in range(0, indices.size(), 3):
			var a := indices[triangle]
			var p := transform * points[a]
			var q := transform * points[indices[triangle + 1]]
			var r := transform * points[indices[triangle + 2]]
			# GPU normal compression introduces tiny off-axis components; compare
			# the actual cube axis and voxel plane rather than that quantization.
			var decoded := normals[a]
			var normal := Vector3(roundi(decoded.x), roundi(decoded.y), roundi(decoded.z))
			check(decoded.distance_to(normal) < 0.001, "terrain normal is not a cube face")
			var key := "%s/%d/%s" % [normal, roundi(p.dot(normal) * 16), colors[a].to_html()]
			result[key] = float(result.get(key, 0.0)) + (q - p).cross(r - p).length() * 0.5
	return result


func _run() -> void:
	check(Native.available(), "native voxel backend is missing")
	if not Native.available():
		quit(1)
		return
	var source := fixture()
	var before := source.to_definition()
	check(source.validation_errors().is_empty(), "invalid source fixture")
	var native := Native.new()
	var opaque := Materials.opaque_material()
	var water := Materials.water_material()
	var wet_visuals: Array[MeshInstance3D] = []
	var stock_visuals: Array[MeshInstance3D] = []
	for chunk in [Vector2i(1, 1), Vector2i(2, 1)]:
		var minimum := Vector3i(chunk.x * 16, 0, chunk.y * 16)
		var extent := Vector3i(16, 32, 16)
		var expected := Surface.build_region(source, minimum, extent, 1.0 / 16)
		check(surface_index(expected, "water_foam") >= 0, "fixture must exercise shoreline foam")
		var built := native.build_surface_region(source, minimum, extent, 1.0 / 16, opaque, water)
		var visual := MeshInstance3D.new()
		visual.mesh = built.get("mesh")
		visual.position = built.get("position", Vector3.INF)
		visual.scale = built.get("scale", Vector3.ZERO)
		verify_overlay(visual, expected, str(chunk))
		var actual_faces := terrain_faces(visual.mesh, visual.transform)
		var expected_faces := terrain_faces(expected, Transform3D.IDENTITY)
		check(actual_faces.size() == expected_faces.size(), "terrain face planes/colors differ")
		for key in expected_faces:
			check(is_equal_approx(float(actual_faces.get(key, -1)), expected_faces[key]), "terrain coverage differs: " + key)
		wet_visuals.append(visual)
		var stock := MeshInstance3D.new()
		stock.mesh = expected
		stock_visuals.append(stock)
		for options in [[false, -1], [true, 6]]:
			var dry := native.build_surface_region(source, minimum, extent, 1.0 / 16, opaque, water, options[0], options[1])
			check(surface_index(dry.mesh, "water") < 0, "hidden water remained in bottom-only/height slice")
			check(dry.scale == Vector3.ONE / 16, "dry/slice lost native local coordinates")
	# Canvas and runtime must both call the composition adapter.
	var canvas := Workspace.new()
	var undo := UndoRedo.new()
	canvas.setup(null, undo)
	root.add_child(canvas)
	canvas.open_surface(source, "")
	var runtime := ProjectionScript.new()
	root.add_child(runtime)
	runtime.configure(source, 1.0, Vector2i(4, 4), null)
	while runtime.pending_chunk_count() > 0:
		runtime.drain_next_chunk()
	for chunk in [Vector2i(1, 1), Vector2i(2, 1)]:
		canvas.call("_rebuild_chunk", chunk, false)
		var expected := Surface.build_region(source, Vector3i(chunk.x * 16, 0, chunk.y * 16), Vector3i(16, 32, 16), 1.0 / 16)
		verify_overlay(canvas.get("_chunk_meshes")[chunk], expected, "Canvas")
		verify_overlay(runtime.get_node("SurfaceChunk_%d_%d" % [chunk.x, chunk.y]), expected, "runtime")
	# Missing native support must still use the exact stock caller fallback.
	var disabled := Native.new()
	disabled.set("_mesher", null)
	check(disabled.build_surface_region(source, Vector3i.ZERO, source.grid_size(), 1.0 / 16, opaque, water).is_empty(), "unavailable native adapter did not return fallback")
	canvas.set("_native_preview", disabled)
	canvas.call("_rebuild_chunk", Vector2i(2, 1), false)
	verify_overlay(canvas.get("_chunk_meshes")[Vector2i(2, 1)], Surface.build_region(source, Vector3i(32, 0, 16), Vector3i(16, 32, 16), 1.0 / 16), "stock fallback")
	canvas.free()
	undo.free()
	runtime.free()
	check(source.to_definition() == before, "projection changed canonical source")
	if DisplayServer.get_name() != "headless":
		await _compare_render(wet_visuals, stock_visuals)
	else:
		for visual in wet_visuals + stock_visuals:
			visual.free()
	for error in errors:
		push_error(error)
	print("PASS native Surface water" if errors.is_empty() else "FAIL native Surface water", " · ", errors.size())
	quit(0 if errors.is_empty() else 1)


func _compare_render(actual: Array[MeshInstance3D], expected: Array[MeshInstance3D]) -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(512, 384)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var host := Node3D.new()
	# Include the real parent transform used by scaled/rotated placed surfaces.
	host.scale = Vector3.ONE * 16
	host.rotation.y = 0.2
	host.position = Vector3(15, 3, -9)
	viewport.add_child(host)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("233e46")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.65
	host.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -30, 0)
	host.add_child(light)
	var camera := Camera3D.new()
	host.add_child(camera)
	camera.position = Vector3(3, 5, 6)
	camera.look_at(host.to_global(Vector3(2, 0.8, 1.5)))
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 60
	camera.current = true
	var material := Materials.water_material().duplicate() as ShaderMaterial
	material.set_shader_parameter("preview_time", 0.0)
	var foam := Materials.foam_material().duplicate() as ShaderMaterial
	var shader := Shader.new()
	shader.code = foam.shader.code.replace("TIME", "0.0")
	foam.shader = shader
	for visual in actual + expected:
		# Isolate auxiliary surfaces: compare coordinates/patterns without any
		# differences from native ground triangulation or vertex compression.
		var overlay := ArrayMesh.new()
		for name in ["water", "water_foam"]:
			var surface := surface_index(visual.mesh, name)
			if surface < 0:
				continue
			overlay.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, visual.mesh.surface_get_arrays(surface))
			overlay.surface_set_material(overlay.get_surface_count() - 1, material if name == "water" else foam)
		visual.mesh = overlay
		host.add_child(visual)
		visual.visible = visual in actual
	for frame in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	RenderingServer.force_draw(false)
	var first := viewport.get_texture().get_image()
	for visual in actual:
		visual.visible = false
	for visual in expected:
		visual.visible = true
	for frame in 8:
		await process_frame
	await RenderingServer.frame_post_draw
	RenderingServer.force_draw(false)
	var second := viewport.get_texture().get_image()
	for visual in expected:
		visual.visible = false
	for frame in 4:
		await process_frame
	await RenderingServer.frame_post_draw
	RenderingServer.force_draw(false)
	var empty := viewport.get_texture().get_image()
	var different := 0
	var visible := 0
	for y in first.get_height():
		for x in first.get_width():
			var a := first.get_pixel(x, y)
			var b := second.get_pixel(x, y)
			if maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))) > 0.01:
				different += 1
			if a != empty.get_pixel(x, y):
				visible += 1
	check(visible > 100, "render comparison was blank")
	check(different < 30, "native water/foam shader pattern differs from stock")
	var path := "user://native_surface_water.png"
	first.save_png(path)
	print("NATIVE_WATER_RENDER different=", different, " visible=", visible, " capture=", ProjectSettings.globalize_path(path))
	viewport.free()
