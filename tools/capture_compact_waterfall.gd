extends SceneTree
## Native Forward+ motion with pinned time; never saves the authored scene.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene := (load("res://scenes/compact_waterfall_study.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	var study := scene.get_node("PlanarReflection")
	var projection: Node3D = scene.get_node("Map").get("_visual_surface_projection")
	for frame in 600:
		await process_frame
		projection = scene.get_node("Map").get("_visual_surface_projection")
		if study.get("_prepared") and frame > 30 and projection.pending_tile_count() == 0: break
	assert(study.get("_prepared") and projection.pending_tile_count() == 0)
	var field: RefCounted = study.get("_waterfall")
	assert(not field.info.is_empty() and not field.tiles.is_empty())
	var vertices := 0
	for mesh in projection.find_children("Water", "MeshInstance3D", true, false):
		if mesh.mesh.get_surface_count() == 0: continue
		for uv in mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]:
			if uv.x < -3.0: vertices += 1
	assert(vertices > 0)
	(scene.get_node("CanvasLayer") as CanvasLayer).hide()
	for player in scene.find_children("*", "EmberPlayer", true, false): (player as Node3D).hide()
	var hero := study.get("_hero_target") as Node3D
	if is_instance_valid(hero): hero.hide()
	for mesh in scene.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh is CapsuleMesh or mesh.name == "Facing": mesh.hide()
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.fov = 55
	camera.far = 2400
	var target := Vector3(field.info.impact.x, lerpf(field.info.bottom, field.info.top, 0.4), field.info.impact.y)
	camera.position = target + Vector3(53, 32, -65)
	camera.look_at(target)
	camera.make_current()
	var output := "user://ember-tests/waterfall"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var material: ShaderMaterial = study.get("_material")
	var builds: int = study.get("_fields_build_count")
	var total_us := 0
	var max_us := 0
	for frame in 52:
		material.set_shader_parameter("preview_time", frame * 0.10)
		study.refresh_water_settings()
		total_us += field.update_us
		max_us = maxi(max_us, field.update_us)
		await process_frame
		await RenderingServer.frame_post_draw
		assert(root.get_texture().get_image().save_png(output + "/fall-%02d.png" % frame) == OK)
	assert(study.get("_fields_build_count") == builds and projection.pending_tile_count() == 0)
	print("WATERFALL info=", field.info, " vertices=", vertices, " update_us avg=", total_us / 52, " max=", max_us)
	print("PASS WATERFALL capture: actual shared mesh/material, animated stream/impact, no remesh")
	quit()
