extends SceneTree
## Compare rim/light options on the ordinary rock. In-memory only; nothing under res:// is
## written. Argument after "--": output directory.
const Materials = preload("res://scripts/ember_voxel_surface_materials.gd")
var output: String
var scene: Node
var prop: EmberVoxelProp
var visual: MeshInstance3D
var camera: Camera3D
var game_pose: Transform3D
var game_fov: float

func _initialize() -> void: run.call_deferred()
func frames(count := 8) -> void:
	for i in count: await process_frame
	await RenderingServer.frame_post_draw
func shot(name: String) -> void:
	await frames()
	root.get_texture().get_image().save_png(output.path_join(name + ".png"))
func view_pose(view: int) -> void:
	camera.fov = game_fov; camera.global_transform = game_pose
	if view == 1: camera.fov = 40; camera.global_position = Vector3(3, 3.1, 6.5); camera.look_at(Vector3(2, 1.1, 2.5))
	if view == 2:
		var centre: Vector3 = visual.global_transform * (visual.mesh as ArrayMesh).get_aabb().get_center()
		camera.fov = 38; camera.global_position = centre + Vector3(-1.2, 2.7, 4.6); camera.look_at(centre + Vector3(0, 0.2, 0))

func run() -> void:
	output = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(output)
	scene = load("res://scenes/compact_environment_material_review.tscn").instantiate()
	root.add_child(scene); current_scene = scene
	while not scene.ready_for_play: await process_frame
	scene.player.set_physics_process(false); scene.camera.set_process(false)
	camera = scene.camera._cam; game_pose = camera.global_transform; game_fov = camera.fov
	prop = scene.get_node("Map/Props/PaintedRockGroup"); visual = prop.get_node("Mesh")
	var material := visual.get_active_material(0) as ShaderMaterial
	var base: EmberCompactTerrainPattern = Materials.load_compact_terrain_variant("cartoon_stone")
	var options := {
		"W0": {"width": 0.0}, "Wa": {"width": 4.0}, "Wb": {"width": 10.0}, "Wc": {"width": 20.0},
	}
	for id in options:
		var option: Dictionary = options[id]
		var pattern := base.duplicate(true) as EmberCompactTerrainPattern
		pattern.style_rim_width_mm = option.width
		prop.preview_solid_material_light(pattern, "cartoon_stone")
		for preset in 3:
			scene.set_lighting(preset, 1)
			for view in 3:
				view_pose(view)
				await shot("%s-%d-%d" % [id, preset, view])
	print("ROCK_LOOK_OPTIONS PASS")
	quit()
