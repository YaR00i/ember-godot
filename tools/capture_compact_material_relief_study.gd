extends SceneTree
## Same terrain/light/camera in both shots. Uses no authored-map writes.

const Materials = preload("res://scripts/ember_voxel_surface_materials.gd")
const OUTPUT := "user://ember-tests/material-relief"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(1280, 720)
	var scene := (load("res://scenes/compact_material_relief_study.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	var study := scene.get_node("PlanarReflection")
	for frame in 600:
		await process_frame
		if study.get("_prepared") and frame > 30 and scene.get_node("Map").get("_visual_surface_projection").pending_tile_count() == 0: break
	var terrain = scene.get_node("Map").get("_visual_surface_projection")
	assert(terrain.pending_tile_count() == 0)
	var material: ShaderMaterial = terrain.get("_ground_material")
	(scene.get_node("CanvasLayer") as CanvasLayer).hide()
	for player in scene.find_children("*", "EmberPlayer", true, false): player.hide()
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 170.0
	camera.far = 2400.0
	camera.position = Vector3(465, 155, 630)
	camera.look_at(Vector3(365, 20, 530))
	camera.make_current()
	var original_ids: PackedStringArray = terrain.document.palette_material_ids.duplicate()
	var builds: int = study.get("_fields_build_count")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT))
	for variant in ["before", "after"]:
		var ids := original_ids.duplicate()
		if variant == "before":
			for index in ids.size(): ids[index] = terrain.document.palette_surface_roles[index]
		Materials.set_compact_terrain_roles(material, terrain.document.palette_surface_roles, ids)
		for frame in 12:
			(study.get("_material") as ShaderMaterial).set_shader_parameter("preview_time", 4.0)
			study.refresh_water_settings()
			await process_frame
		await RenderingServer.frame_post_draw
		assert(root.get_texture().get_image().save_png("%s/%s.png" % [OUTPUT, variant]) == OK)
	assert(study.get("_fields_build_count") == builds)
	print("PASS material Forward+ comparison: same geometry, camera, light, wave phase; no field rebuild")
	quit()
