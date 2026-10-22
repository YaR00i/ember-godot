extends "res://tools/capture_rock_painted_refinement.gd"
var flat_stone: Array[ShaderMaterial]=[]
var relief_stone: Array[ShaderMaterial]=[]
var relief_bake_count:=0

func review_depth_amplitude_m() -> float:
	return Recipe.PAINT_RELIEF_RANGE_M

func prepare_materials() -> void:
	super.prepare_materials()
	if not relief_stone.is_empty():return
	var master:=Recipe.painted_image();var guide:=Recipe.painted_structure(master)
	relief_bake_count=Recipe.structure_bake_count
	var colours: Array[Image]=[master,Bake.calm_variant(master,256,0.65),TerrainLook.pixel_image(master,16)]
	var heights: Array[Image]=[guide,guide,TerrainLook.pixel_image(guide,16)]
	var pattern=scene._stone.duplicate(true);pattern.base_color=Color("90938f")
	for look in 3:
		colours[look].save_png(output.path_join("paint-%d.png"%look));heights[look].save_png(output.path_join("height-paint-%d.png"%look))
		var material:=road_material(painted_stone[look],colours[look],{"slot":1,"material_id":"cartoon_stone","pattern":pattern,"span_m":Recipe.SPAN_M})
		material.set_shader_parameter("material_depth_height",ImageTexture.create_from_image(heights[look]))
		material.set_shader_parameter("colour_probe_shared_height",true)
		material.set_shader_parameter("material_depth_amplitude_m",Recipe.PAINT_RELIEF_RANGE_M)
		material.set_shader_parameter("material_depth_enabled",true);relief_stone.append(material)
		var flat:=material.duplicate() as ShaderMaterial
		flat.set_shader_parameter("material_depth_enabled",false);flat.set_shader_parameter("material_depth_amplitude_m",0.0)
		flat_stone.append(flat)
		for key in ["png_albedo_bank","png_lookup","png_mean_lookup","png_tint_lookup"]:
			check(flat.get_shader_parameter(key)==material.get_shader_parameter(key),"flat/relief pigment identical "+key)
		for key in ["material_depth_coverage","finish_lookup","surface_lookup","detail_lookup","roughness_atlas","style_rim_lookup"]:
			check(material.get_shader_parameter(key)==painted_stone[look].get_shader_parameter(key),"other finish/light binding unchanged "+key)

func apply_look(nodes: Array[MeshInstance3D],look: int) -> void:
	super.apply_look(nodes,look)
	if not relief_stone.is_empty():bind_stone(relief_stone,look)

func capture(name: String) -> Image:
	var paired:=name.begins_with("view-") or name.begins_with("motion-") or name.begins_with("return-")
	if paired and not relief_stone.is_empty():
		var look: int=scene.material_style
		for revision in 2:
			bind_stone(painted_stone if revision==0 else flat_stone,look)
			var image:=await take(name+"-rev-%d"%revision)
			if name.begins_with("return-"):
				var parts:=name.split("-")
				var first:=Image.load_from_file(output.path_join("view-%s-preset-%s-light-%s-look-0-rev-%d.png"%[parts[1],parts[2],parts[3],revision]))
				check(image.get_data()==first.get_data(),"control variant returns exactly")
		bind_stone(relief_stone,look)
	return await take(name)

func capture_looks(source,clouds: Array[PackedVector3Array],nodes: Array[MeshInstance3D]) -> Dictionary:
	var result:=await super.capture_looks(source,clouds,nodes)
	var original_grass: Material=scene.tuft_visual.material_override
	var original_mesh: ArrayMesh=scene.tuft_visual.multimesh.mesh
	var camera: Camera3D=scene.follow_camera._cam;var pose:=camera.global_transform;var fov:=camera.fov
	var variants: Array=[painted_stone,flat_stone,relief_stone]
	# A zero-amplitude shared-height path must reproduce the flat control.
	for look in 3:
		select_materials(1,look,nodes);camera_view(3);bind_stone(flat_stone,look)
		var flat:=await take("flat-zero-reference-%d"%look)
		bind_stone(relief_stone,look);relief_stone[look].set_shader_parameter("material_depth_amplitude_m",0.0)
		check(flat.get_data()==(await take("shared-zero-%d"%look)).get_data(),"zero height/POM exactly flat")
		relief_stone[look].set_shader_parameter("material_depth_amplitude_m",Recipe.PAINT_RELIEF_RANGE_M)
	scene.set_lighting_preset(1)
	var sun: DirectionalLight3D=scene.get_node("Map/Look/Sun")
	scene.set_sun_pose(0);var start:=sun.global_basis
	scene.set_sun_pose(1);var end:=sun.global_basis
	for look in 3:
		select_materials(1,look,nodes);camera_view(3)
		for frame in 12:
			sun.global_basis=start.slerp(end,frame/11.0)
			for revision in 3:
				bind_stone(variants[revision],look)
				await take("sun-%d-%d-%02d"%[look,revision,frame])
	check(Recipe.structure_bake_count==relief_bake_count,"no structural processing during camera/light/variant switches")
	camera.global_transform=pose;camera.fov=fov
	scene.set_lighting_preset(1);scene.set_sun_pose(1);select_materials(1,0,nodes)
	scene.tuft_visual.multimesh.mesh=original_mesh;scene.tuft_visual.material_override=original_grass
	result.erase("rock_pigment")
	result["paint_relief"]={"guide":"periodically smoothed 32-cell warm/cool mineral-region heuristic; not brightness-to-physical-shape recovery","trace_range_m":Recipe.PAINT_RELIEF_RANGE_M,"actual_height_span_m":0.003,"matrix_cases":review_records.size(),"stills":162,"motion_frames":540,"sun_motion_frames":108,"exact_returns":54,"zero_cases":3,"bakes":relief_bake_count,"shared_height":true,"macro_geometry":"unchanged","scope":"A previous pigment/lines/depth; B same raw paint without old lines, flat; C same B pigment plus shallow shared structural height"}
	result["scope"]="existing stone geometry; three material variants; accepted road/soil/grass/tree/light retained"
	result["manual_acceptance"]="OPEN; structural guide and 3mm depth are candidates"
	return result
