extends "res://tools/capture_sand_road_looks.gd"
## Existing grass, fixed scatter and one accepted source. A is the earlier
## derived LAB; B changes only derived pigment and flat-clump representation.
const GrassRecipe=preload("res://scripts/prototypes/ember_grass_look_recipe.gd")
var grass_revision:=1
var grass_meshes: Array=[]
var grass_ground: Array=[]
var grass_cards: Array=[]
var grass_stats: Dictionary={}

func prepare_materials() -> void:
	super.prepare_materials()
	if not grass_meshes.is_empty():return
	var master: Image=scene._grass.albedo_texture.get_image()
	var input_hash:=hash(master.get_data())
	var original_mesh: ArrayMesh=scene.grass_variants[0]
	var old_meshes: Array[ArrayMesh]=[original_mesh,scene.grass_variants[1],scene.grass_variants[2]]
	var new_meshes:=GrassRecipe.meshes(original_mesh,Fixture.grass_tuft_outline())
	grass_meshes=[old_meshes,new_meshes]
	var old_colours: Array[Image]=[master,scene.study_images[1].grass,TerrainLook.pixel_image(master,32)]
	var new_colours:=GrassRecipe.colours(master)
	var original_cards: ShaderMaterial=scene.tuft_visual.material_override
	var options:={"slot":3,"material_id":"cartoon_grass","pattern":scene._grass,"span_m":scene._grass.pattern_size_m}
	for revision in 2:
		var ground: Array[ShaderMaterial]=[];var cards: Array[ShaderMaterial]=[]
		var images: Array=old_colours if revision==0 else new_colours
		for look in 3:
			images[look].save_png(output.path_join("grass-colour-%d-%d.png"%[revision,look]))
			ground.append(road_materials[1][look] if look==0 else road_material(road_materials[1][look],images[look],options))
			cards.append(original_cards if look==0 else road_material(original_cards,images[look],options))
		grass_ground.append(ground);grass_cards.append(cards)
	check(input_hash==hash(master.get_data()),"accepted grass pigment unchanged")
	check(new_meshes[0]==original_mesh,"ordinary clump is exact accepted mesh")
	var horizontal_min:=INF;var horizontal_max:=0.0;var vertical_min:=INF;var vertical_max:=0.0
	for index in scene.tuft_visual.multimesh.instance_count:
		var basis: Basis=scene.tuft_visual.global_basis*scene.tuft_visual.multimesh.get_instance_transform(index).basis
		var horizontal:=basis.x.length()*GrassRecipe.VOXEL_STEP_M
		var vertical:=basis.y.length()*GrassRecipe.VOXEL_STEP_M
		horizontal_min=minf(horizontal_min,horizontal);horizontal_max=maxf(horizontal_max,horizontal)
		vertical_min=minf(vertical_min,vertical);vertical_max=maxf(vertical_max,vertical)
	var mesh_info: Array=[]
	for revision in 2:
		for look in 3:
			var mesh: ArrayMesh=grass_meshes[revision][look]
			mesh_info.append({"revision":revision,"look":look,"triangles_per_clump":mesh.get_faces().size()/3,"local_height_m":mesh.get_aabb().size.y,"local_width_m":mesh.get_aabb().size.x})
	grass_stats={"instance_count":scene.tuft_visual.multimesh.instance_count,"mesh_info":mesh_info,"pixel_local_m":GrassRecipe.VOXEL_STEP_M,"pixel_world_horizontal_m":[horizontal_min,horizontal_max],"pixel_world_vertical_m":[vertical_min,vertical_max],"grass_pattern_span_m":scene._grass.pattern_size_m,"ordinary_input_hash":input_hash,"scope":"existing flat crossed clumps; local silhouette grid, not solid voxel cubes or a globally aligned lattice"}

func apply_look(nodes: Array[MeshInstance3D],look: int) -> void:
	super.apply_look(nodes,look)
	if grass_meshes.is_empty():return
	for tile in scene._projection._tiles.values():tile.get_node("Ground").material_override=grass_ground[grass_revision][look]
	scene.tuft_visual.multimesh.mesh=grass_meshes[grass_revision][look]
	scene.tuft_visual.material_override=grass_cards[grass_revision][look]

func select_materials(revision: int,look: int,nodes: Array[MeshInstance3D]) -> void:
	grass_revision=revision
	# Road B is an unaccepted, fixed control in both halves. No new road decision.
	super.select_materials(1,look,nodes)

func capture(name: String) -> Image:
	if name.begins_with("view-1-"):
		var camera: Camera3D=scene.follow_camera._cam
		var target:=Vector3(2.95,0.55,5.1)
		camera.fov=40;camera.global_position=target+Vector3(0.25,0.95,1.85);camera.look_at(target)
	await frames()
	var image:=root.get_texture().get_image()
	check(image.save_png(output.path_join(name+".png"))==OK,"capture "+name)
	return image

func capture_looks(source,clouds: Array[PackedVector3Array],nodes: Array[MeshInstance3D]) -> Dictionary:
	var scatter_hash: int=hash(scene.tuft_visual.multimesh.buffer)
	var result:=await super.capture_looks(source,clouds,nodes)
	var camera: Camera3D=scene.follow_camera._cam
	var game:=camera.global_transform;var fov:=camera.fov
	for preset in 3:
		for light in 2:
			scene.set_lighting_preset(preset);scene.set_sun_pose(light)
			for look in 3:
				for revision in 2:
					camera.global_transform=game;camera.fov=fov
					camera.global_position+=game.basis.z*4.0+Vector3.UP*1.5
					camera.look_at(game.origin-game.basis.z*5.0)
					select_materials(revision,look,nodes)
					await capture("view-2-preset-%d-light-%d-look-%d-rev-%d"%[preset,light,look,revision])
	camera.global_transform=game;camera.fov=fov
	scene.set_lighting_preset(1);scene.set_sun_pose(1);select_materials(1,0,nodes)
	check(scatter_hash==hash(scene.tuft_visual.multimesh.buffer),"all instance transforms and count unchanged")
	result["grass"]=grass_stats
	result["grass"]["matrix_pairs"]=54
	result["grass"]["acceptance"]="OPEN; road candidate remains unaccepted"
	return result
