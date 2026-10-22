extends "res://tools/capture_soil_derived_looks.gd"
## Consolidated review of existing recipes. No new artwork or geometry recipe.
var review_floor: Dictionary={}
var review_scatter: MultiMesh
var review_views: Array=[]
var review_records: Array=[]

func apply_look(nodes: Array[MeshInstance3D],look: int) -> void:
	# Existing scene owner switches the oak, including its retained alpha masks.
	scene.set_material_style(look)
	# This slice keeps the physical/visual floor of the preceding material probes.
	for key in review_floor:scene._projection._tiles[key].get_node("Ground").mesh=review_floor[key]
	scene.tuft_visual.multimesh=review_scatter
	super.apply_look(nodes,look)

func capture(name: String) -> Image:
	# Avoid inherited material-specific camera overrides: all looks share one pose.
	await frames()
	var image:=root.get_texture().get_image()
	check(image.save_png(output.path_join(name+".png"))==OK,"capture "+name)
	return image

func camera_view(index: int) -> void:
	var camera: Camera3D=scene.follow_camera._cam
	camera.global_transform=review_views[index].pose;camera.fov=review_views[index].fov

func add_camera(name: String,target: Vector3,offset: Vector3) -> void:
	var camera: Camera3D=scene.follow_camera._cam
	camera.fov=40;camera.global_position=target+offset;camera.look_at(target)
	review_views.append({"name":name,"pose":camera.global_transform,"fov":camera.fov})

func review_camera_indices() -> Array:
	return range(review_views.size())

func review_depth_amplitude_m() -> float:
	return 0.04

func capture_looks(source,clouds: Array[PackedVector3Array],nodes: Array[MeshInstance3D]) -> Dictionary:
	var camera: Camera3D=scene.follow_camera._cam
	var game_pose:=camera.global_transform;var game_fov:=camera.fov
	var original_grass: Material=scene.tuft_visual.material_override
	review_scatter=scene.tuft_visual.multimesh
	var original_mesh: ArrayMesh=review_scatter.mesh
	for key in scene._projection._tiles:review_floor[key]=scene._projection._tiles[key].get_node("Ground").mesh
	var guard:=protected_scene()
	var tree_source: int=hash(scene.look_source.to_definition())
	var tree_collider: Shape3D=scene.look_prop.get_node("Collision/Shape").shape
	var bake_count: int=scene.bake_count
	prepare_materials();candidate=study_materials.duplicate()
	var model=source_volume(clouds)
	var source_hash: String=model.voxels.hex_encode().sha256_text()
	check(ResourceSaver.save(model,output.path_join("common-rock-source.res"))==OK,"save existing common rock source")
	var reopened=ResourceLoader.load(output.path_join("common-rock-source.res"),"",ResourceLoader.CACHE_MODE_IGNORE)
	check(reopened.voxels==model.voxels and reopened.voxel_part_ids==model.voxel_part_ids,"rock Source save/reopen")
	for id in nodes.size():
		var mass:=mass_data(model,id)
		captured_look_meshes.append([ordinary_look(model,mass,id).mesh,faceted_look(model,mass,id).mesh,voxel_mesh(model,mass.cells)])
		await process_frame
	review_views.append({"name":"game","pose":game_pose,"fov":game_fov})
	add_camera("context",Vector3(3.8,2.4,4.5),Vector3(5.5,5.0,10.5))
	add_camera("soil",Vector3(6.62,0.20,6.75),Vector3(0.30,1.25,1.55))
	add_camera("rock",Vector3(2.0,1.1,2.5),Vector3(1.0,1.6,4.0))
	scene.set_look_view(1)
	review_views.append({"name":"tree","pose":camera.global_transform,"fov":camera.fov})
	scene.set_look_view(3)
	review_views.append({"name":"bark","pose":camera.global_transform,"fov":camera.fov})
	for preset in 3:
		for light in 2:
			scene.set_lighting_preset(preset);scene.set_sun_pose(light)
			for view in review_camera_indices():
				camera_view(view)
				var baseline: Image
				for look in 3:
					select_materials(1,look,nodes)
					check(camera.global_transform==review_views[view].pose,"same camera across looks")
					check(floor_geometry()==guard_floor(),"floor geometry retained across looks")
					var frame:=await capture("view-%d-preset-%d-light-%d-look-%d"%[view,preset,light,look])
					if look==0:baseline=frame
					review_records.append({"view":view,"preset":preset,"light":light,"look":look})
					check([scene.smooth_visual.visible,scene.faceted_visual.visible,scene.voxel_visual.visible]==[look==0,look==1,look==2],"one complete oak look")
				select_materials(1,0,nodes)
				check(baseline.get_data()==(await capture("return-%d-%d-%d"%[view,preset,light])).get_data(),"smooth return exact")
	for preset in 3:
		for light in 2:
			scene.set_lighting_preset(preset);scene.set_sun_pose(light)
			for look in 3:
				select_materials(1,look,nodes)
				for frame in 10:
					camera_view(0)
					camera.global_position+=game_pose.basis.x*((frame/9.0-0.5)*0.65)
					await capture("motion-%d-%d-%d-%02d"%[preset,light,look,frame])
	# Actual POM toggle on the rock; new soil-depth input is never bound.
	scene.set_lighting_preset(1);scene.set_sun_pose(1);camera_view(3)
	for look in 3:
		select_materials(1,look,nodes)
		var on:=await capture("pom-on-%d"%look)
		study_materials[look].set_shader_parameter("material_depth_enabled",false)
		check(on.get_data()!=(await capture("pom-off-%d"%look)).get_data(),"rock POM remains visible")
		study_materials[look].set_shader_parameter("material_depth_enabled",true)
		check(on.get_data()==(await capture("pom-return-%d"%look)).get_data(),"rock POM returns exactly")
		check(is_equal_approx(study_materials[look].get_shader_parameter("material_depth_amplitude_m"),review_depth_amplitude_m()),"declared material depth range")
		check(int(study_materials[look].get_shader_parameter("material_depth_steps"))==32,"existing 32 steps")
		check(not soil_materials[1][look].shader.code.contains("#define EMBER_TERRAIN_SECONDARY_DEPTH"),"new soil depth remains off")
	check(hash(scene.look_source.to_definition())==tree_source,"oak Source retained")
	check(scene.look_prop.get_node("Collision/Shape").shape==tree_collider,"one original oak collider")
	check(scene.bake_count==bake_count,"no oak remesh during switches")
	check(model.voxels.hex_encode().sha256_text()==source_hash,"rock Source retained")
	camera.global_transform=game_pose;camera.fov=game_fov
	scene.set_lighting_preset(1);scene.set_sun_pose(1);select_materials(1,0,nodes)
	check(protected_scene()==guard,"original floor, scatter and oak meshes/pigment retained")
	# Restore the original baseline required by the existing run() preservation gate.
	review_scatter.mesh=original_mesh;scene.tuft_visual.material_override=original_grass
	return {"source_hash":source_hash,"matrix":review_records,"motion_frames":180,"smooth_exact_returns":review_records.size()/3,"views":["game","context","soil","rock","tree","bark"],"soil":soil_stats,"grass":grass_stats,"scope":"existing material families and oak/rock looks together; fixed floor geometry and physics; no new artwork or production world converter","manual_acceptance":"OPEN; road and faceted leaves remain candidates; soil depth deferred"}

func guard_floor() -> int:
	var values: Array=[]
	for key in scene._projection._tiles:
		values.append(hash(review_floor[key].get_faces()))
		values.append(hash(scene._projection._tiles[key].get_node("GroundPhysics/Shape").shape.get_faces()))
	return hash(values)
