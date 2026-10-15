extends "res://tools/capture_tree_foliage21_study.gd"
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
	var camera: Camera3D=scene.follow_camera._cam
	var game_transform:=camera.global_transform;var game_fov:=camera.fov
	scene.show_tree_leaf_trial(0.4);scene.set_tree_leaf_density(45)
	scene.set_lighting_preset(1);scene.set_sun_pose(0);scene.set_network_view(1)
	var baseline:=await capture("baseline45")
	var mesh: ArrayMesh=scene.foliage21_cards.mesh
	var full_hash:=hash(scene.foliage21_inputs.mesh.surface_get_arrays(0))
	var source_hash: String=scene.parametric_inputs.source.voxels.hex_encode().sha256_text()
	var wood_hash:=hash(scene.parametric_wood.mesh.surface_get_arrays(0))
	var ground_hash:=floor_geometry();var grass_hash:=hash(scene.tuft_visual.multimesh.buffer)
	var material: ShaderMaterial=scene.tree_leaf_trial_material
	var sun: DirectionalLight3D=scene.get_node("Map/Look/Sun")
	var original_cast: int=scene.foliage21_cards.cast_shadow
	var original_shadow:=sun.shadow_enabled
	var environment: Environment=scene.get_node("Map/Look/WorldEnvironment").environment
	var original_ao:=environment.ssao_enabled
	var control:=material.duplicate() as ShaderMaterial
	for preset in 3:
		for pose in 2:
			scene.set_lighting_preset(preset);scene.set_sun_pose(pose)
			for mode in ["current","no-leaf-cast","no-leaf-receive","soft-form","flat-form"]:
				scene.set_network_view(1)
				scene.foliage21_cards.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if mode=="no-leaf-cast" else original_cast
				control.set_shader_parameter("painted_leaf_shadow_strength",0.0 if mode=="no-leaf-receive" else 0.4)
				control.set_shader_parameter("painterly_grass_low",0.55 if mode=="soft-form" else (0.8 if mode=="flat-form" else 0.24))
				scene.foliage21_cards.material_override=control
				await capture("tree-%d-%d-%s"%[preset,pose,mode])
				camera.global_transform=game_transform;camera.fov=game_fov
				await capture("game-%d-%d-%s"%[preset,pose,mode])
	scene.set_lighting_preset(1);scene.set_sun_pose(0);scene.set_network_view(1)
	scene.foliage21_cards.cast_shadow=original_cast
	control.set_shader_parameter("painted_leaf_shadow_strength",0.4)
	control.set_shader_parameter("painterly_grass_low",0.24)
	environment.ssao_enabled=false;await capture("ao-off");environment.ssao_enabled=original_ao
	sun.shadow_enabled=false;await capture("all-shadow-off");sun.shadow_enabled=original_shadow
	# This isolates dark macro-normal shading with all receiving shadows removed,
	# including screen-space contact darkening. Caster and whole-world light remain.
	control.set_shader_parameter("painted_leaf_shadow_strength",0.0)
	environment.ssao_enabled=false;await capture("receive-and-ao-off");environment.ssao_enabled=original_ao
	# External opaque blocker: no-leaf-cast must still receive its real shadow;
	# receive0 must ignore it. The shield itself is QA-only and invisible to camera.
	var blocker:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(3.5,4,0.2)
	blocker.mesh=box;blocker.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	scene.add_child(blocker)
	blocker.global_transform=Transform3D(sun.global_basis,scene.smooth_tree.global_position+Vector3(0,4.3,0)+sun.global_basis.z*5)
	for mode in ["current","no-leaf-cast","no-leaf-receive","soft-form","flat-form"]:
		scene.foliage21_cards.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if mode=="no-leaf-cast" else original_cast
		control.set_shader_parameter("painted_leaf_shadow_strength",0.0 if mode=="no-leaf-receive" else 0.4)
		control.set_shader_parameter("painterly_grass_low",0.55 if mode=="soft-form" else (0.8 if mode=="flat-form" else 0.24))
		blocker.hide();await capture("external-clear-"+mode)
		blocker.show();await capture("external-blocked-"+mode)
	blocker.queue_free();await frames()
	scene.foliage21_cards.cast_shadow=original_cast
	scene.foliage21_cards.material_override=material
	check(baseline.get_data()==(await capture("baseline-return")).get_data(),"all diagnostic controls restored exactly")
	check(scene.foliage21_cards.mesh==mesh and full_hash==hash(scene.foliage21_inputs.mesh.surface_get_arrays(0)),"positions density UV normals unchanged")
	check(source_hash==scene.parametric_inputs.source.voxels.hex_encode().sha256_text() and wood_hash==hash(scene.parametric_wood.mesh.surface_get_arrays(0)),"source wood exact")
	check(ground_hash==floor_geometry() and grass_hash==hash(scene.tuft_visual.multimesh.buffer),"physical floor grass exact")
	check(sun.shadow_enabled==original_shadow and environment.ssao_enabled==original_ao,"world shadow/AO restored")
	var file:=FileAccess.open(output.path_join("native.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":errors.is_empty(),"source_sha256":source_hash,"density":45,"cards":scene.tree_leaf_density_inputs.cards,"puffs":scene.tree_leaf_density_inputs.puffs,"grass_cast_shadow":scene.tuft_visual.cast_shadow,"leaf_cast_shadow":original_cast,"ssao":original_ao,"installed_change":"NONE","art_acceptance":"OPEN"},"\t"));file.close()
	print("TREE_SHADOW_MODES ","PASS" if errors.is_empty() else errors)
	quit(0 if errors.is_empty() else 1)
