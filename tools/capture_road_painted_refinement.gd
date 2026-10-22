extends "res://tools/capture_environment_material_review.gd"
## A/B road pigment and tint only, in the existing consolidated fixture.
var painted_road: Array[ShaderMaterial]=[]

func review_camera_indices() -> Array:
	return [0,1,2,4]

func add_camera(name: String,target: Vector3,offset: Vector3) -> void:
	if name=="soil":super.add_camera("road",Vector3(3.55,0.45,5.2),Vector3(0.3,3.4,3.3))
	else:super.add_camera(name,target,offset)

func prepare_materials() -> void:
	super.prepare_materials()
	if not painted_road.is_empty():return
	var images:=Road.painted_variants(Road.painted_image())
	var pattern=scene._depth_sand.duplicate(true)
	pattern.base_color=Road.PAINTED_BASE_COLOR
	for look in 3:
		images[look].save_png(output.path_join("road-painted-%d.png"%look))
		var base: ShaderMaterial=soil_materials[1][look]
		check(is_zero_approx(base.get_shader_parameter("finish_lookup").get_image().get_pixel(2,0).b),"existing road has no albedo-derived optical height")
		var material:=road_material(base,images[look],{"pattern":pattern})
		for key in ["pattern_atlas","side_pattern_atlas","roughness_atlas","side_roughness_atlas","finish_lookup","detail_lookup","surface_lookup","material_depth_height","material_depth_coverage","style_rim_lookup","grass_light_lookup"]:
			check(material.get_shader_parameter(key)==base.get_shader_parameter(key),"road colour-only preserves "+key)
		check(material.shader==base.shader,"same shader and soil depth suppression")
		painted_road.append(material)

func apply_look(nodes: Array[MeshInstance3D],look: int) -> void:
	super.apply_look(nodes,look)
	if not painted_road.is_empty():bind_road(true,look)

func bind_road(painted: bool,look: int) -> void:
	var material: ShaderMaterial=painted_road[look] if painted else soil_materials[1][look]
	for tile in scene._projection._tiles.values():tile.get_node("Ground").material_override=material

func capture(name: String) -> Image:
	var paired:=name.begins_with("view-") or name.begins_with("motion-") or name.begins_with("return-")
	if paired and not painted_road.is_empty():
		var look: int=scene.material_style
		bind_road(false,look)
		var old:=await super.capture(name+"-rev-0")
		if name.begins_with("return-"):
			var parts:=name.split("-")
			var baseline:=Image.load_from_file(output.path_join("view-%s-preset-%s-light-%s-look-0-rev-0.png"%[parts[1],parts[2],parts[3]]))
			check(old.get_data()==baseline.get_data(),"original road returns exactly")
		bind_road(true,look)
	return await super.capture(name)

func capture_looks(source,clouds: Array[PackedVector3Array],nodes: Array[MeshInstance3D]) -> Dictionary:
	var result:=await super.capture_looks(source,clouds,nodes)
	result["road"]={"source_master":SoilRecipe.MASTER_PATH,"span_m":Road.SPAN_M,"base_color":Road.PAINTED_BASE_COLOR.to_html(false),"voxel_cells":16,"voxel_colour_cell_m":Road.SPAN_M/16.0,"matrix_pairs":review_records.size(),"motion_frames":360,"exact_returns":48,"scope":"same accepted painted earth artwork used for road pigment; road slot2 and its tint only; no added height or light changes"}
	result["scope"]="existing three-look context; road colour/tint A-B; geometry, source, light and all other material bindings retained"
	result["manual_acceptance"]="OPEN; road painted candidate not accepted; soil depth deferred"
	return result
