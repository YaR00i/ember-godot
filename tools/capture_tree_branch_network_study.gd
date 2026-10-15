extends SceneTree
var scene
var output: String
var errors: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(value: bool,message: String) -> void:
	if not value: errors.append(message); printerr("FAIL ",message)
func frames(count:=6) -> void:
	for i in count: await process_frame
	await RenderingServer.frame_post_draw
func capture(name: String) -> Image:
	await frames(); var image := root.get_texture().get_image()
	check(image.save_png(output.path_join(name+".png"))==OK,"capture "+name)
	return image
func floor_geometry() -> int:
	var result: Array = []
	for tile in scene._projection._tiles.values():
		result.append(hash(tile.get_node("Ground").mesh.get_faces()))
		result.append(hash(tile.get_node("GroundPhysics/Shape").shape.get_faces()))
	return hash(result)
func run() -> void:
	output=OS.get_cmdline_user_args()[0]
	scene=load("res://scenes/compact_tree_branch_network_study.tscn").instantiate()
	root.add_child(scene); current_scene=scene
	var deadline := Time.get_ticks_msec()+140000
	while not scene.ready_for_network and Time.get_ticks_msec()<deadline: await process_frame
	check(scene.ready_for_network,"ready")
	if not scene.ready_for_network: quit(1); return
	scene.get_node("Instructions").hide()
	scene.walker.set_physics_process(false); scene.followers.set_physics_process(false)
	scene.follow_camera.set_process(false); scene.follow_camera.set_physics_process(false)
	scene.reset_actors(); scene.set_comparison(0)
	var camera: Camera3D=scene.follow_camera._cam
	var camera_start := camera.global_transform; var fov_start := camera.fov
	var terrain: Resource=scene._projection.document.working_copy()
	var source_hash: String=scene.network_inputs.source.voxels.hex_encode().sha256_text()
	var grass_hash := hash(scene.tuft_visual.multimesh.buffer)
	var mesh_hash := hash(scene.network_wood.mesh.get_faces())
	var floor_hash := floor_geometry()
	scene.set_leaf_cards_mode(1); var game := await capture("game-new")
	scene.set_leaf_cards_mode(0); await capture("game-previous")
	scene.set_leaf_cards_mode(1)
	check(game.get_data()==(await capture("game-return")).get_data(),"return comparison exact")
	var tree_root: Vector3=scene.smooth_tree.global_position
	var center := tree_root+Vector3(0,3.1,0)
	scene.set_lighting_preset(1); scene.set_sun_pose(0)
	var offsets: Array[Vector3] = [Vector3(2,-0.4,11),Vector3(-11,-0.4,2),Vector3(-2,-0.4,-11),Vector3(5,3,9)]
	for pose in offsets.size():
		camera.fov=40; camera.global_position=center+offsets[pose]; camera.look_at(center)
		for mode in 3:
			scene.set_leaf_cards_mode(mode); await capture("view-%d-%d"%[pose,mode])
	if not OS.get_cmdline_user_args().has("--quick"):
		scene.set_leaf_cards_mode(2)
		for preset in 3:
			for light in 2:
				scene.set_lighting_preset(preset); scene.set_sun_pose(light)
				camera.global_position=center+offsets[0];camera.look_at(center)
				await capture("light-%d-%d"%[preset,light])
				camera.global_transform=camera_start;camera.fov=fov_start
				await capture("game-light-%d-%d"%[preset,light])
		scene.set_lighting_preset(1);scene.set_sun_pose(0)
		for i in 8:
			var angle := i*TAU/8
			camera.global_position=center+Vector3(cos(angle)*11,0.5,sin(angle)*11);camera.look_at(center)
			await capture("orbit-%d"%i)
		for name in ["fork","near","far"]:
			var target:=tree_root+Vector3(0,2.9,0) if name=="fork" else center
			camera.global_position=target+(Vector3(1,0.1,3.1) if name=="fork" else offsets[0]*(0.72 if name=="near" else 1.7));camera.look_at(target)
			await capture(name)
		for i in 12:
			camera.global_position=center+Vector3(sin(i*0.07)*11,0.4,cos(i*0.07)*11);camera.look_at(center)
			await frames(2)
		await capture("motion")
	check(scene._projection.document.same_terrain_data(terrain) and grass_hash==hash(scene.tuft_visual.multimesh.buffer),"terrain/paint/grass/physical floor unchanged")
	check(floor_hash==floor_geometry(),"derived ground mesh and collision unchanged")
	check(scene.depth_material.get_shader_parameter("material_depth_amplitude_m")==0.04,"accepted ground POM retained")
	var profile: Resource=load("res://content/terrain_materials/painted_light_grass.tres")
	for key in ["low","cool","warm","tint_strength","shadow_color","shadow_fill"]:
		check(scene.foliage_material.get_shader_parameter("painterly_grass_"+key)==profile.get("grass_light_"+key),"shared accepted light profile "+key)
	check(scene.smooth_tree.find_children("*","CollisionShape3D",true,false).is_empty(),"no tree collider transfer")
	check(source_hash==scene.network_inputs.source.voxels.hex_encode().sha256_text() and mesh_hash==hash(scene.network_wood.mesh.get_faces()),"Source and mesh unchanged by view/light")
	check(not scene.branching_cards.visible and not scene.card_visual.visible,"bare scaffold remains visible without foliage")
	if not OS.get_cmdline_user_args().has("--quick"):
		scene.set_leaf_cards_mode(2);scene.set_network_view(1)
		scene.get_node("Instructions").show();await capture("controls")
	var metrics := {"source_sha256":source_hash,"supports":scene.network_inputs.structure.lines.size(),"branches":scene.network_inputs.layout.size(),"wood_triangles":scene.network_wood.mesh.get_faces().size()/3,"build_ms":scene.network_build_ms,"grass_tufts":scene.tuft_visual.multimesh.instance_count,"pass":errors.is_empty(),"art_acceptance":"OPEN"}
	var file := FileAccess.open(output.path_join("native.json"),FileAccess.WRITE);file.store_string(JSON.stringify(metrics,"\t"));file.close()
	print("TREE_NETWORK_NATIVE ","PASS" if errors.is_empty() else errors)
	quit(0 if errors.is_empty() else 1)
