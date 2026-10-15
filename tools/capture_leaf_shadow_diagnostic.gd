extends "res://tools/capture_tree_foliage21_study.gd"
func run() -> void:
	output=OS.get_cmdline_user_args()[0]
	scene=load("res://scenes/compact_tree_foliage21_study.tscn").instantiate()
	root.add_child(scene);current_scene=scene
	var deadline:=Time.get_ticks_msec()+140000
	while not scene.ready_for_foliage21 and Time.get_ticks_msec()<deadline:await process_frame
	check(scene.ready_for_foliage21,"sample ready")
	if not scene.ready_for_foliage21:quit(1);return
	scene.get_node("Instructions").hide()
	scene.walker.set_physics_process(false);scene.followers.set_physics_process(false)
	scene.follow_camera.set_process(false);scene.follow_camera.set_physics_process(false)
	scene.reset_actors();scene.set_comparison(0)
	var source_hash: String=scene.parametric_inputs.source.voxels.hex_encode().sha256_text()
	var cards_hash:=hash(scene.foliage21_cards.mesh.surface_get_arrays(0))
	var wood_hash:=hash(scene.parametric_wood.mesh.surface_get_arrays(0))
	var ground_hash:=floor_geometry();var grass_hash:=hash(scene.tuft_visual.multimesh.buffer)
	var texture: Texture2D=scene.leaf_sample_materials[2].get_shader_parameter("painted_leaf_card_albedo")
	var texture_hash:=hash(texture.get_image().get_data())
	scene.set_lighting_preset(1);scene.set_sun_pose(1);scene.show_leaf_samples();scene.set_leaf_sample_stage(2)
	var sun: DirectionalLight3D=scene.get_node("Map/Look/Sun")
	var initial: Dictionary={"angular":sun.light_angular_distance,"bias":sun.shadow_bias,"normal_bias":sun.shadow_normal_bias,"blur":sun.shadow_blur,"shadow":sun.shadow_enabled}
	await capture("baseline")
	sun.shadow_enabled=false;await capture("no-shadow-control");sun.shadow_enabled=initial.shadow
	if not OS.get_cmdline_user_args().has("--baseline"):
		sun.light_angular_distance=0;await capture("angular-zero");sun.light_angular_distance=initial.angular
		sun.shadow_normal_bias=initial.normal_bias*2;await capture("normal-bias-double");sun.shadow_normal_bias=initial.normal_bias
		sun.shadow_bias=initial.bias*2;await capture("bias-double");sun.shadow_bias=initial.bias
		var quality: int=ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality",2)
		RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
		await capture("soft-filter-high")
		RenderingServer.directional_soft_shadow_filter_set_quality(quality)
		var original: ShaderMaterial=scene.leaf_sample_materials[2]
		var control:=original.duplicate() as ShaderMaterial
		var shader:=Shader.new();shader.code=original.shader.code.replace("NORMAL=normalize(leaf_card_group_normal);","NORMAL=normalize(NORMAL);")
		control.shader=shader
		for node in scene.leaf_sample_nodes:node.material_override=control
		await capture("geometry-normal-control")
		var solid:=original.duplicate() as ShaderMaterial
		shader=Shader.new();shader.code=original.shader.code.replace("ALPHA=leaf.a;","ALPHA=1.0;").replace("ALPHA_SCISSOR_THRESHOLD=painted_leaf_card_cutoff;","ALPHA_SCISSOR_THRESHOLD=0.0;")
		solid.shader=shader
		for node in scene.leaf_sample_nodes:node.material_override=solid
		await capture("solid-alpha-control")
		scene.set_leaf_sample_stage(2)
		for value in [0.4,0.8,1.6]:
			sun.shadow_bias=value;await capture("bias-%s"%str(value).replace(".","p"))
		sun.shadow_bias=initial.bias
		sun.shadow_normal_bias=0;await capture("normal-bias-zero");sun.shadow_normal_bias=initial.normal_bias
		var reverse:=sun.shadow_reverse_cull_face
		sun.shadow_reverse_cull_face=not reverse;await capture("reverse-cull-control");sun.shadow_reverse_cull_face=reverse
		var meshes: Array[ArrayMesh]=[]
		for node in scene.leaf_sample_nodes:
			meshes.append(node.mesh)
			var arrays: Array=node.mesh.surface_get_arrays(0).duplicate(true)
			var verts: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var old_normals: PackedVector3Array=arrays[Mesh.ARRAY_NORMAL]
			var normals:=PackedVector3Array();normals.resize(verts.size())
			var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
			for i in range(0,indices.size(),3):
				var a:=indices[i];var b:=indices[i+1];var c:=indices[i+2]
				var normal: Vector3=(verts[b]-verts[a]).cross(verts[c]-verts[a])
				if normal.dot(old_normals[a])<0:normal=-normal
				normals[a]+=normal;normals[b]+=normal;normals[c]+=normal
			for i in normals.size():normals[i]=normals[i].normalized()
			arrays[Mesh.ARRAY_NORMAL]=normals
			var corrected:=ArrayMesh.new()
			corrected.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},(Mesh.ARRAY_CUSTOM_RGBA_FLOAT<<Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT)|(Mesh.ARRAY_CUSTOM_RGBA_FLOAT<<Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT))
			node.mesh=corrected
		await capture("curved-geometry-normals")
		sun.light_angular_distance=0;await capture("curved-normals-angular-zero");sun.light_angular_distance=initial.angular
		for i in scene.leaf_sample_nodes.size():scene.leaf_sample_nodes[i].mesh=meshes[i]
		# Receivers are QA-only. Test a grounded solid caster alongside alpha cards:
		# a clean card must not be obtained by losing its shadow on other objects.
		var receivers:=Node3D.new();scene.leaf_samples.add_child(receivers)
		var floor:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(12,10)
		floor.mesh=plane;floor.position.y=-2.2;receivers.add_child(floor)
		var matte:=StandardMaterial3D.new();matte.albedo_color=Color(0.52,0.52,0.52);matte.roughness=1.0;floor.material_override=matte
		var box:=MeshInstance3D.new();box.mesh=BoxMesh.new();box.position=Vector3(0,-1.7,0.2)
		box.material_override=matte;receivers.add_child(box)
		for preset in 3:
			for pose in 2:
				scene.set_lighting_preset(preset);scene.set_sun_pose(pose)
				sun.shadow_bias=initial.bias;await capture("receivers-%d-%d-before"%[preset,pose])
				sun.shadow_bias=1.6;await capture("receivers-%d-%d-candidate"%[preset,pose])
				sun.shadow_enabled=false;await capture("receivers-%d-%d-no-shadow"%[preset,pose]);sun.shadow_enabled=initial.shadow
		sun.shadow_bias=initial.bias;receivers.queue_free();await frames()
		scene.set_lighting_preset(1);scene.set_sun_pose(1)
		var camera: Camera3D=scene.follow_camera._cam
		var saved_transform:=camera.global_transform
		for view in ["near","far","angle","back"]:
			var offset:=Vector3(0,0.3,5.8) if view=="near" else (Vector3(0,0.3,12) if view=="far" else (Vector3(4.5,0.3,5.6) if view=="angle" else Vector3(0,0.3,-7.2)))
			camera.global_position=scene.leaf_samples.global_position+offset;camera.look_at(scene.leaf_samples.global_position)
			sun.shadow_bias=initial.bias;await capture("view-%s-before"%view)
			sun.shadow_bias=1.6;await capture("view-%s-candidate"%view)
		camera.global_transform=saved_transform;sun.shadow_bias=initial.bias
		var energy:=sun.light_energy;sun.light_energy=0
		var zero:=await capture("zero-sun-before")
		sun.shadow_bias=1.6
		check(zero.get_data()==(await capture("zero-sun-candidate")).get_data(),"bias does not add light without sun")
		sun.light_energy=energy;sun.shadow_bias=initial.bias
	check(source_hash==scene.parametric_inputs.source.voxels.hex_encode().sha256_text(),"source exact")
	check(cards_hash==hash(scene.foliage21_cards.mesh.surface_get_arrays(0)) and wood_hash==hash(scene.parametric_wood.mesh.surface_get_arrays(0)),"tree geometry UV normals exact")
	check(ground_hash==floor_geometry() and grass_hash==hash(scene.tuft_visual.multimesh.buffer),"floor physics grass exact")
	check(texture_hash==hash(texture.get_image().get_data()),"texture mip data exact")
	check(sun.light_angular_distance==initial.angular and sun.shadow_bias==initial.bias and sun.shadow_normal_bias==initial.normal_bias and sun.shadow_enabled==initial.shadow,"all light controls restored")
	check((await capture("baseline-return")).get_data()==Image.load_from_file(output.path_join("baseline.png")).get_data(),"baseline returns pixel-exactly")
	var file:=FileAccess.open(output.path_join("native.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"pass":errors.is_empty(),"source_sha256":source_hash,"sun":initial,"sample_cards":[1,6],"fix":"NOT_APPLIED"},"\t"));file.close()
	print("LEAF_SHADOW_DIAGNOSTIC ","PASS" if errors.is_empty() else errors)
	quit(0 if errors.is_empty() else 1)
