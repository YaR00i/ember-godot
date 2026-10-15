extends SceneTree
var scene
var output: String
var errors: Array[String]=[]
var timings: Array=[]
var differences: Array=[]
func _initialize() -> void:run.call_deferred()
func check(value: bool,message: String) -> void:
	if not value:errors.append(message);printerr("FAIL ",message)
func frames(count:=8) -> void:
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
func timing(mode: int) -> void:
	await frames(10);var samples: Array[float]=[]
	for i in 30:
		await process_frame;samples.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
	samples.sort();timings.append({"mode":mode,"gpu_median_ms":samples[15],"gpu_p95_ms":samples[28]})
func snapshot() -> int:
	var result: Array=[]
	for node in [scene.tree.get_node("Mesh"),scene.panel]:
		result.append(hash(node.mesh.get_faces()));result.append(node.transform)
	result.append(hash(scene.tree.get_node("Collision/Shape").shape.get_faces()))
	result.append(hash(scene.tuft_visual.multimesh.buffer))
	for tile in scene._projection._tiles.values():
		result.append(hash(tile.get_node("Ground").mesh.get_faces()))
		result.append(hash(tile.get_node("GroundPhysics/Shape").shape.get_faces()))
	return hash(result)
func run() -> void:
	output=OS.get_cmdline_user_args()[0]
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	scene=load("res://scenes/compact_bark_material_study.tscn").instantiate()
	root.add_child(scene);current_scene=scene
	var deadline:=Time.get_ticks_msec()+140000
	while not scene.ready_for_bark and Time.get_ticks_msec()<deadline:await process_frame
	check(scene.ready_for_bark,"ready")
	if not scene.ready_for_bark:quit(1);return
	scene.get_node("Instructions").hide()
	scene.walker.set_physics_process(false);scene.followers.set_physics_process(false)
	scene.follow_camera.set_process(false);scene.follow_camera.set_physics_process(false)
	scene.reset_actors();scene.set_comparison(0)
	await frames(12)
	var camera: Camera3D=scene.follow_camera._cam
	var camera_start:=camera.global_transform;var fov_start:=camera.fov
	var source: Resource=scene._projection.document.working_copy()
	var physical:=snapshot()
	var authored: EmberVoxelModelResource=scene.bark_inputs.source
	var authored_voxels:=authored.voxels.duplicate();var authored_palette:=authored.palette.duplicate();var authored_material:=authored.material.duplicate(true)
	# The same existing collider/vertices survive every material comparison.
	scene.set_bark_mode(0);scene.set_lighting_preset(1);scene.set_sun_pose(1)
	var baseline:=await capture("game-original")
	for mode in [1,2,3]:
		scene.set_bark_mode(mode)
		var image:=await capture("game-mode-%d"%mode)
		differences.append({"mode":mode,"changed_pixels":changed(baseline,image)})
		check(changed(baseline,image)>100,"visible optional material "+str(mode))
		check(snapshot()==physical and scene._projection.document.same_terrain_data(source),"same geometry/physics/tufts/terrain "+str(mode))
		await timing(mode)
	scene.set_bark_mode(0);await timing(0)
	check(baseline.get_data()==(await capture("game-return-original")).get_data(),"return to original shader exact")
	# Disabled feature must also return through the compiled object shader.
	for material in [scene.bark_material,scene.panel_material]:
		material.shader=scene.bark_shader
		material.set_shader_parameter("surface_response_enabled",false)
		material.set_shader_parameter("bark_study_enabled",false)
	check(baseline.get_data()==(await capture("game-disabled")).get_data(),"compiled feature disabled exact")
	for mode in [0,1,2,3]:
		for preset in 3:
			for pose in [0,1]:
				scene.set_bark_mode(mode);scene.set_lighting_preset(preset);scene.set_sun_pose(pose)
				await capture("game-%d-light-%d-pose-%d"%[mode,preset,pose])
	# Close views expose grooves and both faces, while game views remain the gate.
	scene.set_lighting_preset(1);scene.set_sun_pose(1)
	for subject in ["trunk","flat"]:
		var center: Vector3=scene.tree.global_position+Vector3(0,0.85,0)
		if subject=="flat":center=scene.panel.global_transform*scene.panel.mesh.get_aabb().get_center()
		camera.fov=40.0;camera.global_position=center+Vector3(-1.0 if subject=="flat" else 1.0,0.4,2.7)
		camera.look_at(center)
		var close_images: Array[Image]=[]
		for mode in [0,1,2,3]:
			scene.set_bark_mode(mode);close_images.append(await capture(subject+"-mode-%d"%mode))
		differences.append({"subject":subject,"relief_changed_pixels":changed(close_images[1],close_images[3]),"pixel_changed_pixels":changed(close_images[1],close_images[2])})
		check(changed(close_images[1],close_images[3])>100,"shallow relief contributes visibly on "+subject)
		check(changed(close_images[1],close_images[2])>100,"separate pixel sampling on "+subject)
		if subject=="trunk":
			for mode in [1,2]:
				scene.set_bark_mode(mode)
				var original:=camera.global_transform
				for i in 8:
					camera.global_transform=original;camera.global_position+=Vector3(i*0.015,0,-i*0.008)
					await capture("motion-%d-%02d"%[mode,i])
				camera.global_transform=original
			# Move/rotate the object: Source-space field remains the same and
			# its local sun is refreshed, rather than baking world coordinates.
			var transform_before: Transform3D=scene.tree.transform
			scene.tree.rotation.y=0.7;scene.tree.position.x+=0.12;scene._sync_bark_sun()
			await capture("trunk-transformed")
			scene.tree.transform=transform_before;scene._sync_bark_sun()
	# Near/far views with the same fixed source pattern and light.
	for mode in [1,2]:
		scene.set_bark_mode(mode)
		for pair in [["near",4.0],["far",14.0]]:
			var center: Vector3=scene.tree.global_position+Vector3(0,2.0,0)
			camera.global_position=center+Vector3(0.3,0.3,1).normalized()*pair[1];camera.look_at(center)
			await capture("distance-%d-%s"%[mode,pair[0]])
	camera.global_transform=camera_start;camera.fov=fov_start
	scene.set_bark_mode(1);scene.get_node("Instructions").show();await capture("controls")
	check(snapshot()==physical,"transforms and geometry restored")
	check(authored.voxels==authored_voxels and authored.palette==authored_palette and authored.material==authored_material,"authored model and paint unchanged")
	check(scene.bark_field==scene.bark_material.get_shader_parameter("bark_study_field"),"one field for both presentations")
	check(scene.bark_field==scene.panel_material.get_shader_parameter("bark_study_field"),"flat probe shares the same field")
	check(scene.depth_material.get_shader_parameter("material_depth_amplitude_m")==0.04,"terrain POM preserved")
	# Inspectable PNG section; colour and alpha-height are separate evidence.
	var section: Image=scene.bark_layers[scene.bark_layers.size()/2].duplicate()
	var height:=Image.create(section.get_width(),section.get_height(),false,Image.FORMAT_RGB8)
	for y in section.get_height():
		for x in section.get_width():
			var c:=section.get_pixel(x,y);height.set_pixel(x,y,Color(c.a,c.a,c.a));c.a=1.0;section.set_pixel(x,y,c)
	section.resize(section.get_width()*2,section.get_height()*4,Image.INTERPOLATE_NEAREST)
	height.resize(height.get_width()*2,height.get_height()*4,Image.INTERPOLATE_NEAREST)
	section.save_png(output.path_join("field-colour-section.png"));height.save_png(output.path_join("field-height-section.png"))
	var report:={"errors":errors,"timings":timings,"differences":differences,"bake_ms":scene.bake_ms,
		"grid":str(scene.bark_inputs.field_grid),"field_bytes":scene.bark_inputs.field_grid.x*scene.bark_inputs.field_grid.y*scene.bark_inputs.field_grid.z*4,
		"support_count":scene.bark_inputs.support_count,"mark_count":scene.bark_inputs.mark_count,
		"trace_range_m":0.012,"maximum_inward_relief_m":0.00504,"steps":24,"manual_visual_acceptance":"OPEN"}
	FileAccess.open(output.path_join("native.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("BARK_MATERIAL_NATIVE ","PASS" if errors.is_empty() else errors)
	quit(0 if errors.is_empty() else 1)
