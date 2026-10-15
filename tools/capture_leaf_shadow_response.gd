extends "res://tools/capture_tree_foliage21_study.gd"
const STRENGTHS: Array[float]=[1.0,0.6,0.35,0.15]
func run() -> void:
	output=OS.get_cmdline_user_args()[0]
	scene=load("res://scenes/compact_tree_foliage21_study.tscn").instantiate()
	root.add_child(scene);current_scene=scene
	var deadline:=Time.get_ticks_msec()+140000
	while not scene.ready_for_foliage21 and Time.get_ticks_msec()<deadline:await process_frame
	check(scene.ready_for_foliage21,"ready")
	if not scene.ready_for_foliage21:quit(1);return
	scene.get_node("Instructions").hide()
	scene.walker.set_physics_process(false);scene.followers.set_physics_process(false)
	scene.follow_camera.set_process(false);scene.follow_camera.set_physics_process(false)
	scene.reset_actors();scene.set_comparison(0)
	scene.set_lighting_preset(1);scene.set_sun_pose(1);scene.set_network_view(1)
	var before:=OS.get_cmdline_user_args().has("--before")
	var prefix:="old-" if before else ""
	await capture(prefix+"tree")
	scene.show_leaf_samples();scene.set_leaf_sample_stage(2)
	await capture(prefix+"baseline")
	if before:
		print("LEAF_SHADOW_RESPONSE PASS");quit(0);return
	var source_hash: String=scene.parametric_inputs.source.voxels.hex_encode().sha256_text()
	var cards_hash:=hash(scene.foliage21_cards.mesh.surface_get_arrays(0))
	var wood_hash:=hash(scene.parametric_wood.mesh.surface_get_arrays(0))
	var ground_hash:=floor_geometry();var grass_hash:=hash(scene.tuft_visual.multimesh.buffer)
	var texture: Texture2D=scene.leaf_sample_materials[2].get_shader_parameter("painted_leaf_card_albedo")
	var texture_hash:=hash(texture.get_image().get_data())
	var sun: DirectionalLight3D=scene.get_node("Map/Look/Sun")
	var initial: Dictionary={"angular":sun.light_angular_distance,"bias":sun.shadow_bias,"normal_bias":sun.shadow_normal_bias,"shadow":sun.shadow_enabled}
	check(Image.load_from_file(output.path_join("old-baseline.png")).get_data()==Image.load_from_file(output.path_join("baseline.png")).get_data(),"default shader sample exact")
	check(Image.load_from_file(output.path_join("old-tree.png")).get_data()==Image.load_from_file(output.path_join("tree.png")).get_data(),"default whole tree exact")
	# Only QA objects: an opaque receiver and grounded caster. Their shadow path
	# must remain pixel-exact while the leaves' receiving response changes.
	var receivers:=Node3D.new();scene.leaf_samples.add_child(receivers)
	var matte:=StandardMaterial3D.new();matte.albedo_color=Color(0.52,0.52,0.52);matte.roughness=1.0
	var floor:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(12,10)
	floor.mesh=plane;floor.position.y=-2.2;floor.material_override=matte;receivers.add_child(floor)
	var box:=MeshInstance3D.new();box.mesh=BoxMesh.new();box.position=Vector3(0,-1.7,0.2)
	box.material_override=matte;receivers.add_child(box)
	for preset in 3:
		for pose in 2:
			scene.set_lighting_preset(preset);scene.set_sun_pose(pose)
			for index in STRENGTHS.size():
				scene.set_leaf_sample_shadow_strength(STRENGTHS[index])
				await capture("light-%d-%d-strength-%d"%[preset,pose,index])
	# An opaque panel is placed between the sun and the right-hand leaf group.
	# Shadow-only casting keeps the camera view unobstructed; it still uses the
	# same Godot directional shadow map, with no custom light/renderer.
	scene.set_lighting_preset(1);scene.set_sun_pose(1)
	var blocker:=MeshInstance3D.new();var blocker_mesh:=BoxMesh.new();blocker_mesh.size=Vector3(2.3,2.3,0.15)
	blocker.mesh=blocker_mesh;blocker.material_override=matte
	blocker.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	scene.add_child(blocker)
	blocker.global_transform=Transform3D(sun.global_basis,scene.leaf_sample_nodes[1].global_position+sun.global_basis.z*3.0)
	for index in STRENGTHS.size():
		scene.set_leaf_sample_shadow_strength(STRENGTHS[index])
		blocker.hide();await capture("external-clear-%d"%index)
		blocker.show();await capture("external-blocked-%d"%index)
	blocker.queue_free();receivers.queue_free();await frames()
	var camera: Camera3D=scene.follow_camera._cam
	var saved_transform:=camera.global_transform
	for view in ["near","far","angle","back"]:
		var offset:=Vector3(0,0.3,5.8) if view=="near" else (Vector3(0,0.3,12) if view=="far" else (Vector3(4.5,0.3,5.6) if view=="angle" else Vector3(0,0.3,-7.2)))
		camera.global_position=scene.leaf_samples.global_position+offset;camera.look_at(scene.leaf_samples.global_position)
		for index in [0,1,2]:
			scene.set_leaf_sample_shadow_strength(STRENGTHS[index]);await capture("view-%s-strength-%d"%[view,index])
	camera.global_transform=saved_transform
	var energy:=sun.light_energy;sun.light_energy=0
	scene.set_leaf_sample_shadow_strength(1.0);var zero:=await capture("zero-sun-before")
	scene.set_leaf_sample_shadow_strength(0.35)
	check(zero.get_data()==(await capture("zero-sun-candidate")).get_data(),"no emission at zero sun")
	sun.light_energy=energy
	scene.set_leaf_sample_shadow_strength(1.0)
	check((await capture("baseline-return")).get_data()==Image.load_from_file(output.path_join("baseline.png")).get_data(),"slider returns exact baseline")
	# Point-light control: the setting must not alter local light attenuation.
	sun.light_energy=0
	var local:=OmniLight3D.new();local.omni_range=12;local.light_energy=4
	local.position=scene.leaf_samples.position+Vector3(2,0,4);scene.add_child(local)
	var local_before:=await capture("local-before")
	scene.set_leaf_sample_shadow_strength(0.35)
	check(local_before.get_data()==(await capture("local-candidate")).get_data(),"local light attenuation exact")
	local.queue_free();sun.light_energy=energy;scene.set_leaf_sample_shadow_strength(1.0)
	scene.get_node("Instructions").show();await capture("controls");scene.get_node("Instructions").hide()
	scene.hide_leaf_samples();scene.set_lighting_preset(1);scene.set_sun_pose(1)
	check((await capture("tree-return")).get_data()==Image.load_from_file(output.path_join("old-tree.png")).get_data(),"sample controls never transfer to tree")
	check(source_hash==scene.parametric_inputs.source.voxels.hex_encode().sha256_text(),"source exact")
	check(cards_hash==hash(scene.foliage21_cards.mesh.surface_get_arrays(0)) and wood_hash==hash(scene.parametric_wood.mesh.surface_get_arrays(0)),"tree geometry UV normals exact")
	check(ground_hash==floor_geometry() and grass_hash==hash(scene.tuft_visual.multimesh.buffer),"floor physics grass exact")
	check(texture_hash==hash(texture.get_image().get_data()),"texture mip data exact")
	check(scene.depth_material.get_shader_parameter("material_depth_amplitude_m")==0.04,"POM exact")
	check(sun.light_angular_distance==initial.angular and sun.shadow_bias==initial.bias and sun.shadow_normal_bias==initial.normal_bias and sun.shadow_enabled==initial.shadow,"sun settings exact")
	var file:=FileAccess.open(output.path_join("native.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":errors.is_empty(),"source_sha256":source_hash,"sun":initial,"strengths":STRENGTHS,"sample_cards":[1,6],"art_acceptance":"OPEN","scope":"sample_only"},"\t"));file.close()
	print("LEAF_SHADOW_RESPONSE ","PASS" if errors.is_empty() else errors)
	quit(0 if errors.is_empty() else 1)
