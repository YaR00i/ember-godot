extends SceneTree
var scene
var output: String
var errors: Array[String]=[]
var changes: Array=[]
var timings: Array=[]
func _initialize() -> void:run.call_deferred()
func check(value: bool,message: String) -> void:
	if not value:errors.append(message);printerr("FAIL ",message)
func frames(count:=6) -> void:
	for i in count:await process_frame
	await RenderingServer.frame_post_draw
func capture(name: String) -> Image:
	await frames();var image:=root.get_texture().get_image()
	check(image.save_png(output.path_join(name+".png"))==OK,"capture "+name)
	return image
func changed(a: Image,b: Image) -> int:
	var left:=a.get_data();var right:=b.get_data();var count:=0
	for i in range(0,left.size(),4):
		if left[i]!=right[i] or left[i+1]!=right[i+1] or left[i+2]!=right[i+2]:count+=1
	return count
func geometry() -> int:
	var result: Array=[]
	for node in scene.smooth_tree.get_children():
		result.append(hash(node.mesh.get_faces()));result.append(node.transform)
		result.append(hash(node.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]))
	for tile in scene._projection._tiles.values():
		result.append(hash(tile.get_node("Ground").mesh.get_faces()));result.append(hash(tile.get_node("GroundPhysics/Shape").shape.get_faces()))
	result.append(hash(scene.tuft_visual.multimesh.buffer))
	return hash(result)
func timing(mode: int) -> void:
	await frames(12);var samples: Array[float]=[]
	for i in 30:
		await process_frame;samples.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
	samples.sort();timings.append({"mode":mode,"gpu_median_ms":samples[15],"gpu_p95_ms":samples[28],
		"visible_primitives":root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),
		"visible_draw_calls":root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME),
		"shadow_primitives":root.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)})
func run() -> void:
	output=OS.get_cmdline_user_args()[0]
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	scene=load("res://scenes/compact_tree_branching_study.tscn").instantiate()
	root.add_child(scene);current_scene=scene
	var deadline:=Time.get_ticks_msec()+140000
	while not scene.ready_for_branching and Time.get_ticks_msec()<deadline:await process_frame
	check(scene.ready_for_branching,"ready")
	if not scene.ready_for_branching:quit(1);return
	scene.get_node("Instructions").hide()
	scene.walker.set_physics_process(false);scene.followers.set_physics_process(false)
	scene.follow_camera.set_process(false);scene.follow_camera.set_physics_process(false)
	scene.reset_actors();scene.set_comparison(0)
	var camera: Camera3D=scene.follow_camera._cam
	var camera_start:=camera.global_transform;var fov_start:=camera.fov
	var source: Resource=scene._projection.document.working_copy();var before:=geometry()
	var new_source_hash: String=scene.branching_inputs.source.voxels.hex_encode().sha256_text()
	var new_normals: PackedFloat32Array=scene.branching_cards.mesh.surface_get_arrays(0)[Mesh.ARRAY_CUSTOM1]
	var palette: PackedColorArray=scene.restored_inputs.source.palette.duplicate()
	var source_hash: String=scene.restored_inputs.source.voxels.hex_encode().sha256_text()
	scene.set_leaf_cards_mode(0)
	var baseline:=await capture("game-0")
	for mode in [1,2]:
		scene.set_leaf_cards_mode(mode)
		var image:=await capture("game-%d"%mode)
		changes.append({"mode":mode,"changed_pixels":changed(baseline,image)})
		check(changed(baseline,image)>100,"visible colour artwork")
		check(geometry()==before and scene._projection.document.same_terrain_data(source),"stored geometry/grass/floor stable through mode switches")
		await timing(mode)
	scene.set_leaf_cards_mode(0);await timing(0)
	check(baseline.get_data()==(await capture("game-return")).get_data(),"return previous artwork exact")
	for mode in 3:
		for preset in 3:
			for pose in [0,1]:
				scene.set_leaf_cards_mode(mode);scene.set_lighting_preset(preset);scene.set_sun_pose(pose)
				await capture("game-%d-light-%d-pose-%d"%[mode,preset,pose])
	scene.set_lighting_preset(1);scene.set_sun_pose(1)
	var root_position: Vector3=scene.smooth_tree.global_position
	for subject in ["overview","trunk","branch","rear","canopy"]:
		var center:=root_position+Vector3(0,0.85,0)
		var offset:=Vector3(1.0,0.4,2.8)
		if subject=="overview":center=root_position+Vector3(0,2.8,0);offset=Vector3(5.0,3.6,9.5)
		if subject=="branch":center=root_position+Vector3(0,2.2,0);offset=Vector3(1.2,0.3,2.6)
		if subject=="rear":offset=Vector3(-1.0,0.4,-2.8)
		if subject=="canopy":center=root_position+Vector3(0.7,4.5,0);offset=Vector3(2.0,1.0,4.0)
		camera.fov=40.0;camera.global_position=center+offset;camera.look_at(center)
		for mode in 3:
			scene.set_leaf_cards_mode(mode);await capture(subject+"-%d"%mode)
		if subject=="overview":
			for mode in 3:
				for preset in 3:
					for pose in [0,1]:
						scene.set_leaf_cards_mode(mode);scene.set_lighting_preset(preset);scene.set_sun_pose(pose)
						await capture("overview-%d-light-%d-pose-%d"%[mode,preset,pose])
			scene.set_lighting_preset(1);scene.set_sun_pose(1)
		if subject in ["trunk","canopy"]:
			var camera_before:=camera.global_transform
			for mode in [1,2]:
				scene.set_leaf_cards_mode(mode)
				for i in 8:
					camera.global_transform=camera_before;camera.global_position+=Vector3(i*0.018,0,-i*0.01)
					await capture(("motion-" if subject=="trunk" else "motion-canopy-")+"%d-%02d"%[mode,i])
			camera.global_transform=camera_before
	# Transform invariance: UV artwork is unchanged by moving/rotating the object.
	var transform_before: Transform3D=scene.smooth_tree.transform
	var pairs: PackedFloat32Array=scene.wood.mesh.surface_get_arrays(0)[Mesh.ARRAY_CUSTOM1]
	var table: Texture2D=scene.wood_material.get_shader_parameter("painted_bark_supports")
	var table_data:=table.get_image().get_data()
	scene.smooth_tree.rotate_y(0.55);scene.smooth_tree.position.x+=0.2
	check(scene.wood.mesh.surface_get_arrays(0)[Mesh.ARRAY_CUSTOM1]==pairs and table.get_image().get_data()==table_data,"object transform preserves source support mapping")
	scene.set_leaf_cards_mode(1);await capture("transformed")
	scene.smooth_tree.transform=transform_before
	for mode in 3:
		scene.set_leaf_cards_mode(mode)
		for pair in [["near",6.0],["far",19.0]]:
			var center:=root_position+Vector3(0,2.8,0)
			camera.global_position=center+Vector3(0.5,0.3,1.0).normalized()*pair[1];camera.look_at(center)
			await capture("distance-%d-%s"%[mode,pair[0]])
	camera.global_transform=camera_start;camera.fov=fov_start
	var card_uv: PackedVector2Array=scene.branching_cards.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	var original_cam:=camera.global_transform
	var look_centre:=root_position+Vector3(0,3.0,0)
	for mode in [1,2]:
		scene.set_leaf_cards_mode(mode)
		for i in 8:
			var phi:=float(i)*TAU/8.0
			camera.global_position=look_centre+Vector3(cos(phi)*9.0,2.2,sin(phi)*9.0);camera.look_at(look_centre)
			await capture("orbit-%d-%02d"%[mode,i])
			check(scene.branching_cards.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]==card_uv and geometry()==before,"camera cannot move cards, their UVs or group normals")
	camera.global_position=root_position+Vector3(0.7,1.4,1.1);camera.look_at(root_position+Vector3(0,4.5,0))
	for mode in [0,1,2]:
		scene.set_leaf_cards_mode(mode);await capture("under-%d"%mode)
	camera.global_transform=original_cam
	check(new_source_hash==scene.branching_inputs.source.voxels.hex_encode().sha256_text() and new_normals==scene.branching_cards.mesh.surface_get_arrays(0)[Mesh.ARRAY_CUSTOM1],"new Source18 and macro normals immutable under camera/light changes")
	check(scene.branching_cards.mesh.get_surface_count()==1,"one batched derived canopy")
	check(scene.card_plain.get_shader_parameter("painted_leaf_card_albedo")==scene.card_painted.get_shader_parameter("painted_leaf_card_albedo"),"plain/painted use the same alpha outline")
	scene.set_leaf_cards_mode(2);scene.get_node("Instructions").show();await capture("controls")
	check(geometry()==before and source_hash==scene.restored_inputs.source.voxels.hex_encode().sha256_text(),"Source and shape unchanged")
	check(palette==scene.restored_inputs.source.palette,"authoring colours unchanged")
	check(scene.depth_material.get_shader_parameter("material_depth_amplitude_m")==0.04,"accepted terrain POM retained")
	var artwork: Texture2D=scene.wood_material.get_shader_parameter("painted_bark_albedo")
	check(artwork.get_image().has_mipmaps(),"authored texture has distance-filtering mipmaps")
	var calm_art: Texture2D=scene.calm_wood_material.get_shader_parameter("painted_bark_albedo")
	var leaf_art: Texture2D=scene.foliage_material.get_shader_parameter("painted_foliage_albedo")
	check(calm_art.get_image().has_mipmaps() and leaf_art.get_image().has_mipmaps(),"new artwork keeps distance filtering")
	var profile: Resource=load("res://content/terrain_materials/painted_light_grass.tres")
	for key in ["low","cool","warm","tint_strength","shadow_color","shadow_fill"]:
		check(scene.foliage_material.get_shader_parameter("painterly_grass_"+key)==profile.get("grass_light_"+key),"accepted shared light profile "+key)
	check(scene.foliage_material.get_shader_parameter("painted_foliage_period_m")==3.5,"leaf artwork uses local metres")
	check(scene.smooth_tree.find_children("*","CollisionShape3D",true,false).is_empty(),"no unapproved tree collision transfer")
	var report:={"errors":errors,"source_sha256":source_hash,"cloud_lobes":scene.restored_inputs.cloud_lobes,
		"hanging_leaves":scene.restored_inputs.hanging_leaves,"wood_segments":scene.restored_inputs.wood_segments,
		"build_ms":scene.build_ms,"card_build_ms":scene.card_build_ms,"cards":scene.branching_inputs.cards.cards,"card_triangles":scene.branching_inputs.cards.triangles,"old_foliage_triangles":int((scene.restored_inputs.meshes.clouds.get_faces().size()+scene.restored_inputs.meshes.leaves.get_faces().size())/3),"timings":timings,"differences":changes,"manual_acceptance":"OPEN",
		"branching_build_ms":scene.branching_build_ms,"branch_count":scene.branching_inputs.layout.size(),"new_supports":scene.branching_inputs.structure.lines.size(),"new_source_sha256":new_source_hash,"new_wood_triangles":scene.branching_inputs.wood.get_faces().size()/3,"previous_card_triangles":scene.card_inputs.triangles,"modes":["previous leaf card tree","new bare scaffold","new scaffold with rooted leaf cards"],"foliage_mapping":"fixed UV alpha cards, group lighting normals, shared grass light math/profile; old Source17 retained; new opt-in Source18 and hierarchy; paint/ground retained",
		"tree_collision":"not integrated; non-interactive restored LAB","bark_depth":"previous calm bark unchanged; no new depth","voxel_variant":"deferred until smooth artwork choice"}
	FileAccess.open(output.path_join("native.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("TREE_BRANCHING_NATIVE ","PASS" if errors.is_empty() else errors)
	quit(0 if errors.is_empty() else 1)
