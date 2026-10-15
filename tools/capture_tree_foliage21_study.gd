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
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(),true)
	scene=load("res://scenes/compact_tree_foliage21_study.tscn").instantiate()
	root.add_child(scene); current_scene=scene
	var deadline := Time.get_ticks_msec()+140000
	while not scene.ready_for_foliage21 and Time.get_ticks_msec()<deadline: await process_frame
	check(scene.ready_for_foliage21,"ready")
	if not scene.ready_for_foliage21: quit(1); return
	scene.get_node("Instructions").hide()
	scene.walker.set_physics_process(false); scene.followers.set_physics_process(false)
	scene.follow_camera.set_process(false); scene.follow_camera.set_physics_process(false)
	scene.reset_actors(); scene.set_comparison(0)
	var camera: Camera3D=scene.follow_camera._cam
	var camera_start := camera.global_transform; var fov_start := camera.fov
	var terrain: Resource=scene._projection.document.working_copy()
	var source_hash: String=scene.parametric_inputs.source.voxels.hex_encode().sha256_text()
	var grass_hash := hash(scene.tuft_visual.multimesh.buffer)
	var mesh_hash := hash(scene.parametric_wood.mesh.get_faces())
	var floor_hash := floor_geometry()
	var card_hash:=hash(scene.foliage21_cards.mesh.surface_get_arrays(0))
	if OS.get_cmdline_user_args().has("--minimal-sampling"):
		scene.set_lighting_preset(1);scene.set_sun_pose(0);scene.set_material_revision(3);scene.set_network_view(1)
		var original_material: ShaderMaterial=scene.foliage21_cards.material_override
		var before_sample:=await capture("diagnostic-filtered")
		var nearest_material:=original_material.duplicate() as ShaderMaterial
		var leaf_include:=FileAccess.get_file_as_string("res://shaders/ember_painted_foliage_study.gdshaderinc")
		leaf_include=leaf_include.replace("painted_leaf_card_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_disable","painted_leaf_card_albedo : source_color, filter_nearest, repeat_disable")
		var nearest_shader:=Shader.new()
		nearest_shader.code=original_material.shader.code.replace('#include "res://shaders/ember_painted_foliage_study.gdshaderinc"',leaf_include)
		nearest_material.shader=nearest_shader
		scene.foliage21_cards.material_override=nearest_material
		await capture("diagnostic-nearest")
		scene.foliage21_cards.material_override=original_material
		check(before_sample.get_data()==(await capture("diagnostic-filtered-restored")).get_data(),"sampler diagnostic restores exact original image")
		check(cards_hash_guard(scene)==card_hash and mesh_hash==hash(scene.parametric_wood.mesh.get_faces()),"sampler diagnostic preserves geometry/UV/normals")
		print("TREE_FOLIAGE21_MINIMAL ","PASS" if errors.is_empty() else errors)
		quit(0 if errors.is_empty() else 1);return
	if OS.get_cmdline_user_args().has("--minimal-leaves"):
		await capture_minimal_leaves(camera,camera_start,fov_start,source_hash,mesh_hash,card_hash,floor_hash,grass_hash,terrain)
		return
	if OS.get_cmdline_user_args().has("--materials-timing"):
		scene.set_lighting_preset(1);scene.set_sun_pose(0);scene.set_network_view(1)
		var samples: Array=[]
		for revision in [0,2,1,0]:
			scene.set_material_revision(revision);await frames(30)
			var timings: Array[float]=[]
			for i in 60:
				await process_frame
				timings.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
			timings.sort();samples.append({"revision":revision,"median_ms":timings[30],"p95_ms":timings[57]})
		var timing_file:=FileAccess.open(output.path_join("material-timing.json"),FileAccess.WRITE)
		timing_file.store_string(JSON.stringify({"scope":"same complete LAB, current shared GPU load; comparison only, not forest budget","samples":samples},"\t"));timing_file.close()
		print("TREE_FOLIAGE21_NATIVE PASS");quit();return
	if OS.get_cmdline_user_args().has("--materials-close"):
		scene.set_lighting_preset(1);scene.set_sun_pose(0)
		var bark_center: Vector3=scene.smooth_tree.global_position+Vector3(0,1.1,0)
		camera.fov=40;camera.global_position=bark_center+Vector3(1.2,0.4,2.7);camera.look_at(bark_center)
		for revision in 3:
			scene.set_material_revision(revision);await capture("bark-material-%d"%revision)
		check(mesh_hash==hash(scene.parametric_wood.mesh.get_faces()) and card_hash==hash(scene.foliage21_cards.mesh.surface_get_arrays(0)),"bark inspection preserves geometry/UV/normals")
		check(source_hash==scene.parametric_inputs.source.voxels.hex_encode().sha256_text(),"bark inspection preserves Source")
		print("TREE_FOLIAGE21_NATIVE ","PASS" if errors.is_empty() else errors)
		quit(0 if errors.is_empty() else 1);return
	scene.set_leaf_cards_mode(1); var game := await capture("game-new")
	scene.set_leaf_cards_mode(0); await capture("game-previous")
	scene.set_leaf_cards_mode(1)
	check(game.get_data()==(await capture("game-return")).get_data(),"return comparison exact")
	var tree_root: Vector3=scene.smooth_tree.global_position
	var center := tree_root+Vector3(0,3.5,0)
	scene.set_lighting_preset(1); scene.set_sun_pose(0)
	var offsets: Array[Vector3] = [Vector3(2,-0.4,13),Vector3(-13,-0.4,2),Vector3(-2,-0.4,-13),Vector3(6,3.6,11)]
	for pose in offsets.size():
		camera.fov=40; camera.global_position=center+offsets[pose]; camera.look_at(center)
		for mode in 3:
			scene.set_leaf_cards_mode(mode); await capture("view-%d-%d"%[pose,mode])
		for revision in 3:
			scene.set_material_revision(revision);await capture("view-%d-material-%d"%[pose,revision])
			check(mesh_hash==hash(scene.parametric_wood.mesh.get_faces()) and card_hash==hash(scene.foliage21_cards.mesh.surface_get_arrays(0)),"material comparison preserves wood/cards/UV/normals")
	if not OS.get_cmdline_user_args().has("--quick"):
		scene.set_leaf_cards_mode(2)
		for preset in 3:
			for light in 2:
				scene.set_lighting_preset(preset); scene.set_sun_pose(light)
				for revision in 3:
					scene.set_material_revision(revision)
					camera.fov=40;camera.global_position=center+offsets[0];camera.look_at(center)
					await capture("light-%d-%d-material-%d"%[preset,light,revision])
					camera.global_transform=camera_start;camera.fov=fov_start
					await capture("game-light-%d-%d-material-%d"%[preset,light,revision])
					if revision==2:
						await capture("game-light-%d-%d"%[preset,light])
						camera.fov=40;camera.global_position=center+offsets[0];camera.look_at(center)
						await capture("light-%d-%d"%[preset,light])
		scene.set_lighting_preset(1);scene.set_sun_pose(0)
		for i in 8:
			var angle := i*TAU/8
			camera.global_position=center+Vector3(cos(angle)*13,0.5,sin(angle)*13);camera.look_at(center)
			await capture("orbit-%d"%i)
		for name in ["fork","near","far"]:
			var target:=tree_root+Vector3(0,2.9,0) if name=="fork" else center
			camera.global_position=target+(Vector3(1,0.1,3.1) if name=="fork" else offsets[0]*(0.72 if name=="near" else 1.7));camera.look_at(target)
			await capture(name)
			for revision in 3:
				scene.set_material_revision(revision);await capture(name+"-material-%d"%revision)
		scene.set_material_revision(0);scene.set_network_view(1)
		var old_art:=await capture("old-art-return")
		scene.set_material_revision(2);await frames();scene.set_material_revision(0)
		check(old_art.get_data()==(await capture("old-art-return-repeat")).get_data(),"old artwork returns exactly after swapping both materials")
		scene.set_material_revision(2)
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
	check(source_hash==scene.parametric_inputs.source.voxels.hex_encode().sha256_text() and mesh_hash==hash(scene.parametric_wood.mesh.get_faces()),"Source and mesh unchanged by view/light")
	check(not scene.branching_cards.visible and not scene.card_visual.visible,"legacy cards stay hidden")
	check(card_hash==hash(scene.foliage21_cards.mesh.surface_get_arrays(0)),"fixed cards, UVs and macro normals do not follow camera/light")
	for key in ["low","cool","warm","tint_strength","shadow_color","shadow_fill"]:
		check(scene.foliage21_quiet.get_shader_parameter("painterly_grass_"+key)==scene.foliage21_painted.get_shader_parameter("painterly_grass_"+key),"quiet artwork retains leaf light "+key)
	for key in ["painted_bark_supports","painted_bark_period_m","painted_bark_strength","painted_bark_tint"]:
		check(scene.foliage21_soft_bark.get_shader_parameter(key)==scene.parametric_painted.get_shader_parameter(key),"soft artwork retains bark projection "+key)
	if not OS.get_cmdline_user_args().has("--quick"):
		scene.set_leaf_cards_mode(2);scene.set_network_view(1)
		scene.get_node("Instructions").show();await capture("controls")
	var presets: Array=[]
	if not OS.get_cmdline_user_args().has("--quick"):
		scene.get_node("Instructions").hide();scene.set_leaf_cards_mode(2)
		for preset in 3:
			scene.apply_branch_preset(preset);await frames()
			check(scene.parameter_panel.creation!=null,"existing panel preset preview")
			presets.append({"preset":preset,"parameters":scene.parameter_panel.creation.recipe.parameters,"branches":scene.parametric_inputs.layout.size(),"supports":scene.parametric_inputs.structure.lines.size()})
			for pose in 3:
				camera.global_position=center+offsets[pose];camera.look_at(center)
				await capture("preset-%d-view-%d"%[preset,pose])
		check(presets[0].branches<presets[1].branches and presets[1].branches<presets[2].branches,"presets visibly grow branching")
		scene.parameter_panel.undo_parameters();scene.parameter_panel.prepare()
		check(scene.parametric_inputs.source.voxels.hex_encode().sha256_text()==source_hash,"one Undo returns normal preset exactly")
		scene.parameter_panel.redo_parameters();scene.parameter_panel.prepare()
		check(scene.parametric_inputs.layout.size()==presets[2].branches,"Redo restores dense preset")
		scene.parameter_panel.discard()
		check(scene.parameter_panel.creation==null and scene.parametric_inputs.source.voxels.hex_encode().sha256_text()==source_hash,"discard restores original visual and recipe")
		scene.set_network_view(1);scene.get_node("Instructions").show();await capture("controls")
	var gpu: Array[float]=[]
	if not OS.get_cmdline_user_args().has("--quick"):
		scene.get_node("Instructions").hide();await frames(12)
		for i in 30:
			await process_frame;gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()))
		gpu.sort()
	var metrics := {"source_sha256":source_hash,"supports":scene.parametric_inputs.structure.lines.size(),"branches":scene.parametric_inputs.layout.size(),"wood_triangles":scene.parametric_wood.mesh.get_faces().size()/3,"build_ms":scene.parametric_build_ms,"grass_tufts":scene.tuft_visual.multimesh.instance_count,"pass":errors.is_empty(),"art_acceptance":"OPEN","presets":presets,"cards":scene.foliage21_inputs.cards,"card_triangles":scene.foliage21_inputs.triangles,"gpu_median_ms":gpu[15] if gpu.size()==30 else 0,"gpu_p95_ms":gpu[28] if gpu.size()==30 else 0}
	var file := FileAccess.open(output.path_join("native.json"),FileAccess.WRITE);file.store_string(JSON.stringify(metrics,"\t"));file.close()
	print("TREE_FOLIAGE21_NATIVE ","PASS" if errors.is_empty() else errors)
	quit(0 if errors.is_empty() else 1)

func capture_minimal_leaves(camera: Camera3D,game_transform: Transform3D,game_fov: float,source_hash: String,wood_hash: int,cards_hash: int,floor_hash: int,grass_hash: int,terrain: Resource) -> void:
	var tree_root: Vector3=scene.smooth_tree.global_position
	var center:=tree_root+Vector3(0,3.5,0)
	var offsets: Array[Vector3]=[Vector3(2,-0.4,13),Vector3(-13,-0.4,2),Vector3(-2,-0.4,-13)]
	for revision in [2,3,4]:
		scene.set_material_revision(revision);scene.set_lighting_preset(1);scene.set_sun_pose(0)
		for pose in 3:
			camera.fov=40;camera.global_position=center+offsets[pose];camera.look_at(center)
			await capture("minimal-view-%d-material-%d"%[pose,revision])
		for name in ["near","far","leaf"]:
			camera.global_position=center+offsets[0]*(0.47 if name=="leaf" else (0.72 if name=="near" else 1.7));camera.look_at(center)
			await capture("minimal-%s-material-%d"%[name,revision])
		for preset in 3:
			for light in 2:
				scene.set_lighting_preset(preset);scene.set_sun_pose(light)
				camera.fov=40;camera.global_position=center+offsets[0];camera.look_at(center)
				await capture("minimal-light-%d-%d-material-%d"%[preset,light,revision])
				camera.global_transform=game_transform;camera.fov=game_fov
				await capture("minimal-game-%d-%d-material-%d"%[preset,light,revision])
		scene.set_lighting_preset(1);scene.set_sun_pose(0);scene.set_network_view(1)
		for key in ["low","cool","warm","tint_strength","shadow_color","shadow_fill"]:
			check(scene.foliage21_cards.material_override.get_shader_parameter("painterly_grass_"+key)==scene.foliage21_painted.get_shader_parameter("painterly_grass_"+key),"minimal artwork preserves shared light "+key)
		check(scene.parametric_wood.material_override==scene.foliage21_soft_bark,"bark remains the same in all minimal comparisons")
		check(wood_hash==hash(scene.parametric_wood.mesh.get_faces()) and cards_hash==hash(scene.foliage21_cards.mesh.surface_get_arrays(0)),"minimal texture switching preserves wood/cards/UV/macro normals")
	# Isolate texture contrast from actual cast-shadow fragmentation. This is only
	# a temporary capture diagnostic, never a scene setting or accepted light change.
	scene.set_material_revision(3);scene.set_network_view(1)
	var original_shadow: int=scene.foliage21_cards.cast_shadow
	var normal_view:=await capture("minimal-before-diagnostic")
	var original_plain: Color=scene.foliage21_plain.get_shader_parameter("painted_leaf_card_plain")
	scene.foliage21_plain.set_shader_parameter("painted_leaf_card_plain",Color("748568"))
	scene.set_leaf_cards_mode(1);await capture("diagnostic-flat-lit")
	scene.foliage21_cards.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	await capture("diagnostic-flat-no-cast")
	scene.foliage21_cards.cast_shadow=original_shadow
	scene.foliage21_plain.set_shader_parameter("painted_leaf_card_plain",original_plain)
	scene.set_material_revision(3)
	check(normal_view.get_data()==(await capture("minimal-after-diagnostic")).get_data(),"diagnostic restores exact normal shaded view")
	check(source_hash==scene.parametric_inputs.source.voxels.hex_encode().sha256_text(),"minimal study preserves Source21")
	check(scene._projection.document.same_terrain_data(terrain) and floor_hash==floor_geometry() and grass_hash==hash(scene.tuft_visual.multimesh.buffer),"minimal study preserves paint/ground/collision/grass")
	check(scene.depth_material.get_shader_parameter("material_depth_amplitude_m")==0.04,"minimal study retains POM")
	scene.get_node("Instructions").show();await capture("minimal-controls")
	var report:={"pass":errors.is_empty(),"source_sha256":source_hash,"cards":scene.foliage21_inputs.cards,"card_triangles":scene.foliage21_inputs.triangles,"geometry_uv_normals_preserved":true,"cast_shadow_restored":scene.foliage21_cards.cast_shadow==original_shadow,"art_acceptance":"OPEN"}
	var file:=FileAccess.open(output.path_join("minimal.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("TREE_FOLIAGE21_MINIMAL ","PASS" if errors.is_empty() else errors)
	quit(0 if errors.is_empty() else 1)

func cards_hash_guard(study: Node) -> int:
	return hash(study.foliage21_cards.mesh.surface_get_arrays(0))
