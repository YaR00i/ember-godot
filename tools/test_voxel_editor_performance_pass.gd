extends SceneTree

const Policy := preload("res://addons/ember_import/ember_voxel_editor_perf_policy.gd")
const Context := preload("res://addons/ember_import/ember_voxel_canvas_context.gd")

var errors: Array[String] = []


func check(condition: bool, message: String) -> void:
	if not condition:
		errors.append(message)


func _init() -> void:
	_run.call_deferred()


func _offset_mesh(offset: Vector3) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		offset + Vector3(-1, 0, -1),
		offset + Vector3(1, 0, -1),
		offset + Vector3(1, 0, 1),
		offset + Vector3(-1, 0, 1),
	])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _run() -> void:
	check(Policy.adaptive_preview_chunk_size(Vector3i(96, 32, 96)) == 16, "small chunk policy wrong")
	check(Policy.adaptive_preview_chunk_size(Vector3i(384, 32, 384)) == 32, "384 grid should use 32-voxel chunks")
	check(Policy.adaptive_preview_chunk_size(Vector3i(768, 64, 768)) == 64, "large chunk policy wrong")
	check(Policy.preview_chunk_count(Vector3i(384, 32, 384), 32) == Vector2i(12, 12), "384 grid should be 12x12 adaptive chunks")
	check(not Policy.should_queue_full_rebuild(64, false), "legacy 64 chunks should still rebuild immediately")
	check(Policy.should_queue_full_rebuild(65, false), "legacy queue threshold no longer matches old >64 behavior")
	check(Policy.should_queue_full_rebuild(17, true), "adaptive queue threshold should be >16")
	check(
		Policy.context_opacity_requires_rebuild(true, true, 0.60),
		"optimized 100 -> 60 should require context rebuild",
	)
	check(
		Policy.context_opacity_requires_rebuild(true, false, 1.00),
		"optimized 60 -> 100 should require context rebuild",
	)
	check(
		not Policy.context_opacity_requires_rebuild(true, false, 0.75),
		"optimized 60 -> 75 should not require rebuild",
	)
	check(
		not Policy.context_opacity_requires_rebuild(false, false, 1.00),
		"legacy opacity changes should never require batching rebuild",
	)

	var scene := Node3D.new()
	root.add_child(scene)
	var target := Node3D.new()
	target.name = "Target"
	target.set("block_world_size", 16.0)
	scene.add_child(target)
	var target_mesh := MeshInstance3D.new()
	target_mesh.mesh = BoxMesh.new()
	target.add_child(target_mesh)

	var opaque_material := StandardMaterial3D.new()
	var shared_mesh := BoxMesh.new()
	shared_mesh.material = opaque_material
	for index in 10:
		var instance := MeshInstance3D.new()
		instance.name = "Same_%d" % index
		instance.mesh = shared_mesh
		instance.position = Vector3(float(index) * 4.0, 0.0, 0.0)
		scene.add_child(instance)

	# Node origin is near Target, but actual geometry is far away.
	var far_geometry := MeshInstance3D.new()
	far_geometry.name = "FarGeometryNearOrigin"
	far_geometry.mesh = _offset_mesh(Vector3(400, 0, 0))
	far_geometry.position = Vector3.ZERO
	scene.add_child(far_geometry)

	# Node origin is far away, but local mesh offset places its geometry near Target.
	var near_geometry := MeshInstance3D.new()
	near_geometry.name = "NearGeometryFarOrigin"
	near_geometry.mesh = _offset_mesh(Vector3(-400, 0, 0))
	near_geometry.position = Vector3(400, 0, 0)
	scene.add_child(near_geometry)

	var context := Context.new()
	root.add_child(context)

	var legacy := context.rebuild(
		scene, target, Transform3D.IDENTITY, true, 0.0, false
	)
	check(not legacy.has("error"), "legacy context rebuild failed")
	check(int(legacy.get("source_count", 0)) == 12, "legacy source count changed unexpectedly")
	check(int(legacy.get("visual_count", 0)) == 12, "legacy mode should not batch")

	var optimized_60 := context.rebuild(
		scene,
		target,
		Transform3D.IDENTITY,
		true,
		Policy.context_radius_world(target, 8.0),
		true,
		0.60,
	)
	check(not optimized_60.has("error"), "optimized 60% context rebuild failed")
	check(int(optimized_60.get("source_count", 0)) == 11, "bounds-aware radius culling source count wrong")
	check(int(optimized_60.get("culled_count", 0)) == 1, "far mesh AABB was not culled")
	check(not bool(optimized_60.get("batching_allowed", true)), "60% context incorrectly allowed batching")
	check(int(optimized_60.get("batched_instances", 0)) == 0, "60% context unexpectedly batched")
	check(int(optimized_60.get("visual_count", 0)) == 11, "60% optimized context should preserve individual visuals")

	var optimized_100 := context.rebuild(
		scene,
		target,
		Transform3D.IDENTITY,
		true,
		Policy.context_radius_world(target, 8.0),
		true,
		1.0,
	)
	check(not optimized_100.has("error"), "optimized 100% context rebuild failed")
	check(bool(optimized_100.get("batching_allowed", false)), "100% opaque context did not allow batching")
	check(int(optimized_100.get("batched_instances", 0)) == 10, "opaque identical meshes were not batched at 100%")
	check(int(optimized_100.get("visual_count", 0)) == 2, "100% optimized context visual count wrong")

	# Transparent mesh surfaces must stay individual.
	var transparent_material := StandardMaterial3D.new()
	transparent_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var transparent_mesh := BoxMesh.new()
	transparent_mesh.material = transparent_material
	for index in 2:
		var instance := MeshInstance3D.new()
		instance.name = "Transparent_%d" % index
		instance.mesh = transparent_mesh
		instance.position = Vector3(0, 0, float(index + 1) * 4.0)
		scene.add_child(instance)

	# Transparent material_override must also veto batching even if mesh material
	# is opaque.
	var override_material := StandardMaterial3D.new()
	override_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for index in 2:
		var instance := MeshInstance3D.new()
		instance.name = "OverrideTransparent_%d" % index
		instance.mesh = shared_mesh
		instance.material_override = override_material
		instance.position = Vector3(8, 0, float(index + 1) * 4.0)
		scene.add_child(instance)

	# Same for a transparent overlay.
	var overlay_material := StandardMaterial3D.new()
	overlay_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for index in 2:
		var instance := MeshInstance3D.new()
		instance.name = "OverlayTransparent_%d" % index
		instance.mesh = shared_mesh
		instance.material_overlay = overlay_material
		instance.position = Vector3(-8, 0, float(index + 1) * 4.0)
		scene.add_child(instance)

	var with_transparent := context.rebuild(
		scene,
		target,
		Transform3D.IDENTITY,
		true,
		Policy.context_radius_world(target, 8.0),
		true,
		1.0,
	)
	# Only the original ten plain opaque instances may batch. Six transparent
	# variants must remain individual, plus NearGeometryFarOrigin.
	check(
		int(with_transparent.get("batched_instances", 0)) == 10,
		"transparent override/overlay changed the safe opaque batch",
	)
	check(
		int(with_transparent.get("visual_count", 0)) == 8,
		"transparent surface/override/overlay instances were incorrectly batched",
	)

	context.clear()
	context.queue_free()
	scene.queue_free()

	for message in errors:
		push_error(message)
	print("test_voxel_editor_performance_pass: ", "PASS" if errors.is_empty() else "FAIL", " · ", errors.size())
	quit(0 if errors.is_empty() else 1)
