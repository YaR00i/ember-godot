extends SceneTree
## Shared chunk projection plus EmberMapLoader world wiring. The G3 sandbox
## pilot derives visual, collision and route heights from one Surface Resource.

const ProjectionScript = preload("res://scripts/ember_voxel_surface_projection.gd")
const VoxelModel = preload("res://scripts/ember_voxel_model_resource.gd")
const MapLoader = preload("res://scripts/ember_map_loader.gd")
const WaterContact = preload("res://scripts/ember_water_contact_3d.gd")
const WATER_SHADER_PATH := "res://shaders/ember_voxel_surface_water.gdshader"
const FOAM_SHADER_PATH := "res://shaders/ember_voxel_surface_foam.gdshader"
const CONTACT_SHADER_PATH := "res://shaders/ember_water_contact.gdshader"
const WAKE_SHADER_PATH := "res://shaders/ember_water_wake.gdshader"


func _init() -> void:
	_run_and_quit.call_deferred()


func _run_and_quit() -> void:
	var errors: Array[String] = []
	_test_shared_projection(errors)
	_test_offset_water_chunk(errors)
	await _test_map_wiring(errors)
	await _test_saved_map_fallback(errors)
	if not errors.is_empty():
		printerr("FAIL world surface projection")
		for error in errors:
			printerr(" - ", error)
		quit(1)
		return
	print("PASS world surface projection")
	print("  one shared frame-budgeted projection serves battle and world surfaces")
	print("  opted-in world maps replace legacy visual/collision and expose Surface routes")
	quit(0)


func _test_shared_projection(errors: Array[String]) -> void:
	var water_shader := load(WATER_SHADER_PATH) as Shader
	if (
		water_shader == null
		or "depth_draw_never" not in water_shader.code
		or "depth_prepass_alpha" in water_shader.code
	):
		errors.append("shared water shader can still obscure the authored floor in 3D")
	elif (
		"sky_reflection_color" not in water_shader.code
		or "sparse_glint" not in water_shader.code
		or "normalize(VIEW)" not in water_shader.code
	):
		errors.append("shared water shader lost its restrained reflection/glint layer")
	var host := Node3D.new()
	root.add_child(host)
	var fallback := MeshInstance3D.new()
	fallback.mesh = BoxMesh.new()
	host.add_child(fallback)
	var projection := ProjectionScript.new()
	host.add_child(projection)
	var surface := _surface("shared_projection", "shared_projection")
	var column_count := surface.grid_size().x * surface.grid_size().z
	surface.surface_fill_levels.resize(column_count)
	surface.surface_fill_levels.fill(0)
	surface.surface_fill_materials.resize(column_count)
	surface.surface_fill_materials.fill(0)
	surface.surface_fill_palette.resize(column_count)
	surface.surface_fill_palette.fill(0)
	surface.surface_fill_levels[0] = 2
	surface.surface_fill_materials[0] = 1
	surface.surface_fill_palette[0] = 2
	surface.surface_fill_levels[1] = 2
	surface.surface_fill_materials[1] = 1
	surface.surface_fill_palette[1] = 2
	surface.surface_fill_levels[16] = 2
	surface.surface_fill_materials[16] = 1
	surface.surface_fill_palette[16] = 2
	surface.surface_fill_levels[17] = 2
	surface.surface_fill_materials[17] = 1
	surface.surface_fill_palette[17] = 2
	projection.configure(surface, 16.0, Vector2i.ONE, fallback)
	if not fallback.visible or projection.pending_chunk_count() != 1:
		errors.append("fallback was not retained during initial chunk build")
	projection.drain_next_chunk()
	if fallback.visible or not projection.is_projection_complete():
		errors.append("completed projection did not replace its visual fallback")
	if projection.rendered_chunk_count() != 1 or not is_equal_approx(projection.scale.x, 16.0):
		errors.append("shared projection lost chunk count or authored block scale")
	var water_found := false
	var foam_found := false
	var chunk := projection.get_child(0) as MeshInstance3D
	if chunk != null and chunk.mesh != null:
		for surface_index in chunk.mesh.get_surface_count():
			var surface_name: StringName = chunk.mesh.surface_get_name(surface_index)
			if surface_name not in ["water", "water_foam"]:
				continue
			var material := chunk.mesh.surface_get_material(surface_index) as ShaderMaterial
			if material != null and material.shader != null:
				if surface_name == "water":
					water_found = material.shader.resource_path == WATER_SHADER_PATH
				else:
					foam_found = material.shader.resource_path == FOAM_SHADER_PATH
	if not water_found:
		errors.append("shared Surface projection did not use the dedicated water shader")
	if not foam_found:
		errors.append("shared Surface projection did not use the dedicated shoreline foam shader")
	var wet_sample: Dictionary = projection.water_surface_sample(Vector3(0.5, 0.0, 0.5))
	if (
		not bool(wet_sample.get("wet", false))
		or not is_equal_approx(float(wet_sample.get("block_world_size", 0.0)), 16.0)
		or absf((wet_sample.get("position", Vector3.ZERO) as Vector3).y - 2.085) > 0.01
	):
		errors.append("shared Surface projection returned an invalid world-space water sample")
	var dry_sample: Dictionary = projection.water_surface_sample(Vector3(2.5, 0.0, 0.5))
	if (
		bool(dry_sample.get("wet", true))
		or not is_equal_approx(float(dry_sample.get("block_world_size", 0.0)), 16.0)
	):
		errors.append("dry Surface sample lost the block scale needed by movement effects")
	var target := Node3D.new()
	target.name = "WaterContactTarget"
	target.position = Vector3(0.5, 0.0, 0.5)
	host.add_child(target)
	var contact: Node3D = WaterContact.new()
	# This fixture is a tiny 2x2-art-voxel pool, so use a fitting footprint.
	contact.set("radius_blocks", 0.05)
	contact.set("wake_sample_spacing_blocks", 0.05)
	target.add_child(contact)
	contact.call("refresh_now")
	if not bool(contact.call("is_contact_visible")):
		errors.append("water contact did not appear at a wet actor footprint")
	var contact_ripple := contact.find_child("ContactRipple", false, false) as MeshInstance3D
	var contact_material := (
		(contact_ripple.mesh as QuadMesh).material as ShaderMaterial
		if contact_ripple != null and contact_ripple.mesh is QuadMesh
		else null
	)
	if (
		contact_material == null or contact_material.shader == null
		or contact_material.shader.resource_path != CONTACT_SHADER_PATH
	):
		errors.append("water contact did not use the shared pixel-ring material")
	elif (
		"instance uniform float motion_strength" not in contact_material.shader.code
		or "bow_arc" not in contact_material.shader.code
	):
		errors.append("water contact lost its movement-directed wake")
	target.position += Vector3(1.0, 0.0, 0.0)
	contact.call("sample_motion", 0.1)
	contact.call("refresh_now")
	contact.call("_advance_wake", 0.1)
	if float(contact.call("motion_strength")) <= 0.1:
		errors.append("water contact did not react to horizontal actor movement")
	contact.call("_resize_visual", 16.0)
	var moving_quad := contact_ripple.mesh as QuadMesh
	if moving_quad == null or not is_equal_approx(moving_quad.size.y, moving_quad.size.x):
		errors.append("historical wake stretched the local contact ring")
	var wake_trail := contact.find_child("WakeTrail", false, false) as MeshInstance3D
	var wake_material := (
		wake_trail.mesh.surface_get_material(0) as ShaderMaterial
		if wake_trail != null
		and wake_trail.mesh != null
		and wake_trail.mesh.get_surface_count() > 0
		else null
	)
	if int(contact.call("wake_sample_count")) < 1:
		errors.append("movement did not leave world-history water samples")
	elif (
		wake_material == null or wake_material.shader == null
		or wake_material.shader.resource_path != WAKE_SHADER_PATH
	):
		errors.append("historical water trail did not use its vertex-fade material")
	var travel := Vector3.RIGHT
	var local_forward := Basis(Vector3.UP, float(contact.get("_motion_yaw"))) * Vector3.FORWARD
	if local_forward.dot(travel) > -0.95:
		errors.append("water contact bow orientation no longer matches the visual UV axis")
	target.position += Vector3(0.0, 0.0, 1.0)
	contact.call("sample_motion", 0.1)
	contact.call("refresh_now")
	contact.call("_advance_wake", 0.1)
	var trail_samples: Array = contact.get("_wake_samples")
	if trail_samples.size() < 2:
		errors.append("turning on water did not extend the historical wake")
	else:
		var first_forward: Vector2 = trail_samples[0]["forward"]
		var last_forward: Vector2 = trail_samples[-1]["forward"]
		if first_forward.x < 0.9 or last_forward.y < 0.9:
			errors.append("old water trail samples rotated with the actor instead of preserving the path")
	target.position = Vector3(2.5, 0.0, 0.5)
	contact.call("refresh_now")
	if bool(contact.call("is_contact_visible")):
		errors.append("water contact remained visible after its actor reached dry ground")
	surface.voxels[0] = 2
	surface.emit_changed()
	if fallback.visible or projection.pending_chunk_count() != 1:
		errors.append("resource refresh blanked the existing exact projection")
	projection.drain_next_chunk()
	projection.configure(surface, 16.0, Vector2i(2, 1), fallback)
	if not fallback.visible or projection.visible:
		errors.append("size-mismatched surface replaced semantic fallback")
	host.free()


func _test_offset_water_chunk(errors: Array[String]) -> void:
	if not EmberVoxelNativeMesher.available():
		return
	var surface := VoxelModel.new()
	surface.model_id = "offset_water_chunk"
	surface.display_name = "offset_water_chunk"
	surface.tags = PackedStringArray(["surface", "world", "godot-native"])
	surface.voxels_per_block = 16
	surface.size_blocks = Vector3i(2, 1, 1)
	surface.height_voxels = 2
	surface.palette = PackedColorArray([
		Color(0.0, 0.0, 0.0, 0.0),
		Color("#6f9147"),
		Color("#4bc9ca"),
	])
	surface.material = {"preset": "world_surface", "semanticOwner": "offset_water_chunk"}
	var size := surface.grid_size()
	var voxels := PackedByteArray()
	voxels.resize(size.x * size.y * size.z)
	voxels.fill(0)
	for z in size.z:
		for x in size.x:
			voxels[VoxMesher.cell_index(x, 0, z, size.x, size.z)] = 1
	surface.voxels = voxels
	var column_count := size.x * size.z
	surface.surface_fill_levels.resize(column_count)
	surface.surface_fill_levels.fill(0)
	surface.surface_fill_materials.resize(column_count)
	surface.surface_fill_materials.fill(0)
	surface.surface_fill_palette.resize(column_count)
	surface.surface_fill_palette.fill(0)
	var water_cell := Vector2i(20, 4)
	var water_column := water_cell.x + water_cell.y * size.x
	surface.surface_fill_levels[water_column] = 2
	surface.surface_fill_materials[water_column] = 1
	surface.surface_fill_palette[water_column] = 2
	if EmberVoxelSurfaceMesher.region_has_water_overlay(
		surface, Vector3i.ZERO, Vector3i(16, size.y, 16)
	):
		errors.append("dry native chunk was classified as water-bearing")
	if not EmberVoxelSurfaceMesher.region_has_water_overlay(
		surface, Vector3i(16, 0, 0), Vector3i(16, size.y, 16)
	):
		errors.append("offset water chunk was not routed to the exact Surface mesher")

	var host := Node3D.new()
	root.add_child(host)
	var fallback := MeshInstance3D.new()
	fallback.mesh = BoxMesh.new()
	host.add_child(fallback)
	var projection := ProjectionScript.new()
	host.add_child(projection)
	projection.configure(surface, 1.0, Vector2i(2, 1), fallback)
	while projection.pending_chunk_count() > 0:
		projection.drain_next_chunk()
	var water_chunk := projection.get_node_or_null("SurfaceChunk_1_0") as MeshInstance3D
	var water_vertices := PackedVector3Array()
	if water_chunk != null and water_chunk.mesh != null:
		for surface_index in water_chunk.mesh.get_surface_count():
			if water_chunk.mesh.surface_get_name(surface_index) == "water":
				water_vertices = water_chunk.mesh.surface_get_arrays(surface_index)[Mesh.ARRAY_VERTEX]
				break
	if water_vertices.is_empty():
		errors.append("offset water chunk lost its shader surface")
	else:
		var minimum_x := INF
		var maximum_x := -INF
		for vertex in water_vertices:
			var projected := water_chunk.transform * vertex
			minimum_x = minf(minimum_x, projected.x)
			maximum_x = maxf(maximum_x, projected.x)
		var expected_minimum := float(water_cell.x) / 16.0
		var expected_maximum := float(water_cell.x + 1) / 16.0
		if (
			absf(minimum_x - expected_minimum) > 0.001
			or absf(maximum_x - expected_maximum) > 0.001
		):
			errors.append(
				"offset water geometry drifted from its canonical cell: %.4f..%.4f"
				% [minimum_x, maximum_x]
			)
	host.free()


func _test_map_wiring(errors: Array[String]) -> void:
	var map := MapLoader.new()
	map.map_id = "projection_test_map"
	map.imported_tile_size = 16.0
	map.authored_size_blocks = Vector2i.ONE
	map.use_visual_surface_physics = true
	map.set("_stats", {"width": 1, "height": 1})
	var terrain := Node3D.new()
	terrain.name = "Terrain"
	map.add_child(terrain)
	var terrain_mesh := MeshInstance3D.new()
	terrain_mesh.name = "Mesh"
	terrain_mesh.mesh = BoxMesh.new()
	terrain.add_child(terrain_mesh)
	var terrain_collision := StaticBody3D.new()
	terrain_collision.name = "Collision"
	terrain.add_child(terrain_collision)
	map.visual_surface = _surface("projection_test_map_surface", map.map_id)
	root.add_child(map)
	await process_frame
	var projection := map.get_node_or_null("DerivedVoxelWorldSurface")
	if projection == null:
		errors.append("EmberMapLoader did not create its derived world projection")
		map.queue_free()
		await process_frame
		return
	if not terrain_mesh.visible or not terrain_collision.visible:
		errors.append("world fallback changed before the exact surface was ready")
	projection.call("drain_next_chunk")
	projection.call("drain_next_physics_chunk")
	if terrain_mesh.visible:
		errors.append("completed world projection did not hide legacy Terrain/Mesh")
	if terrain_collision.visible or terrain_collision.collision_layer != 0:
		errors.append("completed physical Surface did not retire legacy Terrain/Collision")
	if int(projection.call("collision_chunk_count")) != 1 or not bool(projection.call("physics_is_ready")):
		errors.append("world projection did not build and activate its derived collision chunk")
	var floor_sample: Dictionary = map.surface_floor_sample(Vector3(0.5, 20.0, 0.5))
	if (
		not bool(floor_sample.get("solid", false))
		or absf((floor_sample.get("position", Vector3.ZERO) as Vector3).y - 1.0) > 0.01
	):
		errors.append("world collision and height query no longer agree on the Surface top")
	var route := map.surface_navigation_path(Vector3(8.0, 0.0, 8.0), Vector3(8.0, 0.0, 8.0))
	if route.size() != 1 or absf(route[0].y - 1.0) > 0.01:
		errors.append("world Surface did not provide its gameplay-block route height")
	map.visual_surface.emit_changed()
	if (
		terrain_collision.collision_layer != 0
		or int(projection.call("pending_physics_chunk_count")) != 1
		or not bool(projection.get("_physics_live"))
	):
		errors.append("Surface refresh dropped live native collision or re-enabled legacy collision")
	projection.call("drain_next_physics_chunk")
	if not bool(projection.call("physics_is_ready")):
		errors.append("physical chunk rebuild did not return to a ready state")
	if not is_equal_approx((projection as Node3D).scale.x, map.imported_tile_size):
		errors.append("world projection block does not match imported tile size")
	map.queue_free()
	await process_frame


func _test_saved_map_fallback(errors: Array[String]) -> void:
	var canonical_path := VoxelModel.world_surface_path("agent_sandbox")
	if canonical_path != "res://content/world_surfaces/agent_sandbox_surface.tres":
		errors.append("runtime canonical Surface path drifted from editor authoring")
		return
	if not ResourceLoader.exists(canonical_path):
		errors.append("agent_sandbox canonical Surface fixture is missing")
		return
	var map := MapLoader.new()
	map.map_id = "agent_sandbox"
	map.imported_tile_size = 16.0
	map.authored_size_blocks = Vector2i(24, 24)
	map.use_visual_surface_physics = true
	var terrain := Node3D.new()
	terrain.name = "Terrain"
	map.add_child(terrain)
	var terrain_mesh := MeshInstance3D.new()
	terrain_mesh.name = "Mesh"
	terrain_mesh.mesh = BoxMesh.new()
	terrain.add_child(terrain_mesh)
	var terrain_collision := StaticBody3D.new()
	terrain_collision.name = "Collision"
	terrain.add_child(terrain_collision)
	root.add_child(map)
	await process_frame
	var resolved := map.call("resolved_visual_surface") as VoxelModel
	var projection := map.get_node_or_null("DerivedVoxelWorldSurface")
	if resolved == null or resolved.resource_path != canonical_path:
		errors.append("map without a saved .tscn link did not resolve its canonical Surface")
	elif projection == null or projection.call("surface") != resolved:
		errors.append("canonical saved Surface did not reach the runtime projection")
	else:
		(projection as Node).set_process(false)
		# A second edit arriving before the worker result is consumed must retire
		# that snapshot and rebuild from the latest canonical bytes.
		resolved.emit_changed()
		if (
			int(projection.call("pending_physics_chunk_count")) != 1
			or not bool(projection.get("_heightfield_restart_requested"))
		):
			errors.append("in-flight heightfield rebuild did not mark its stale snapshot")
		var heightfield_started := Time.get_ticks_usec()
		while int(projection.get("_heightfield_task_id")) >= 0:
			projection.call("drain_next_physics_chunk", false)
			await process_frame
		var heightfield_wall_usec := Time.get_ticks_usec() - heightfield_started
		var physics_started := Time.get_ticks_usec()
		var slowest_physics_chunk_usec := 0
		while int(projection.call("pending_physics_chunk_count")) > 0:
			var chunk_started := Time.get_ticks_usec()
			projection.call("drain_next_physics_chunk")
			slowest_physics_chunk_usec = maxi(
				slowest_physics_chunk_usec, Time.get_ticks_usec() - chunk_started
			)
		var physics_total_usec := Time.get_ticks_usec() - physics_started
		print(
			"  sandbox physics: %.1f ms background heightfield, %.1f ms chunks total, %.1f ms slowest 4x4-block chunk"
			% [
				float(heightfield_wall_usec) / 1000.0,
				float(physics_total_usec) / 1000.0,
				float(slowest_physics_chunk_usec) / 1000.0,
			]
		)
		if int(projection.call("collision_chunk_count")) != 36:
			errors.append(
				"24x24 sandbox Surface produced %d/36 coarse physical chunks"
				% int(projection.call("collision_chunk_count"))
			)
		if terrain_collision.collision_layer != 0 or not bool(projection.call("physics_is_ready")):
			errors.append(
				"sandbox collision switch failed (fallback=%d, ready=%s, pending=%d)"
				% [
					terrain_collision.collision_layer,
					str(projection.call("physics_is_ready")),
					int(projection.call("pending_physics_chunk_count")),
				]
			)
		var route_started := Time.get_ticks_usec()
		var route := map.surface_navigation_path(
			Vector3(200.0, 0.0, 344.0), Vector3(216.0, 0.0, 344.0)
		)
		print(
			"  sandbox route query: %.1f ms"
			% (float(Time.get_ticks_usec() - route_started) / 1000.0)
		)
		if route.size() < 2:
			errors.append("saved sandbox Surface could not route between neighboring start blocks")
		await physics_frame
		var query := PhysicsRayQueryParameters3D.create(
			Vector3(200.0, 64.0, 344.0), Vector3(200.0, -16.0, 344.0), 1
		)
		var hit := map.get_world_3d().direct_space_state.intersect_ray(query)
		var collider := hit.get("collider") as Node
		if collider == null or not (projection as Node).is_ancestor_of(collider):
			errors.append("PhysicsServer ray did not hit the derived sandbox Surface collision")
	var packed := load("res://scenes/agent_sandbox.tscn") as PackedScene
	var reopened := packed.instantiate() if packed != null else null
	var reopened_map := reopened.get_node_or_null("Map") as EmberMapLoader if reopened != null else null
	if (
		reopened_map == null
		or reopened_map.authored_size_blocks != Vector2i(24, 24)
		or not reopened_map.use_visual_surface_physics
	):
		errors.append("agent_sandbox did not persist its physical Surface ownership flags")
	if reopened != null:
		reopened.free()
	map.queue_free()
	await process_frame


func _surface(model_id: String, semantic_owner: String) -> VoxelModel:
	var surface := VoxelModel.new()
	surface.model_id = model_id
	surface.display_name = model_id
	surface.tags = PackedStringArray(["surface", "world", "godot-native"])
	surface.voxels_per_block = 16
	surface.size_blocks = Vector3i.ONE
	surface.height_voxels = 2
	surface.palette = PackedColorArray([
		Color(0.0, 0.0, 0.0, 0.0),
		Color("#6f9147"),
		Color("#b98550"),
	])
	surface.material = {"preset": "world_surface", "semanticOwner": semantic_owner}
	var size := surface.grid_size()
	var voxels := PackedByteArray()
	voxels.resize(size.x * size.y * size.z)
	voxels.fill(0)
	for z in size.z:
		for x in size.x:
			voxels[x + z * size.x] = 1
	surface.voxels = voxels
	return surface
