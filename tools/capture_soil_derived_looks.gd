extends "res://tools/capture_grass_derived_looks.gd"
## One existing soil patch; accepted grass B/rock B and fixed road candidate.
const SoilRecipe=preload("res://scripts/prototypes/ember_soil_look_recipe.gd")
var soil_revision:=1
var soil_materials: Array=[]
var soil_stats: Dictionary={}

func prepare_materials() -> void:
	super.prepare_materials()
	if not soil_materials.is_empty():return
	var soil=load("res://content/terrain_materials/soil_grain.tres")
	check(scene._projection.document.palette_material_ids[4]=="soil_grain","existing soil slot and Source")
	var colours:=SoilRecipe.colours(SoilRecipe.colour_image())
	var previous:=SoilRecipe.colours(SoilRecipe.colour_image(256,2))
	var a: Array[ShaderMaterial]=[];var b: Array[ShaderMaterial]=[]
	for look in 3:
		colours[look].save_png(output.path_join("soil-top-%d.png"%look))
		colours[look].save_png(output.path_join("soil-side-%d.png"%look))
		previous[look].save_png(output.path_join("soil-previous-%d.png"%look))
		var base: ShaderMaterial=grass_ground[1][look]
		a.append(painted_soil_material(base,previous[look],soil));b.append(painted_soil_material(base,colours[look],soil))
	soil_materials=[a,b]
	soil_stats={"material_id":"soil_grain","master_asset":SoilRecipe.MASTER_PATH,"control":"rejected camouflage v3","slot":4,"span_m":SoilRecipe.SPAN_M,"master_cells":256,"faceted_contrast":0.65,"faceted_resampling":false,"voxel_cells":8,"voxel_colour_cell_m":SoilRecipe.SPAN_M/8.0,"pixel_relief":soil.pixel_relief,"micro_relief":soil.micro_relief,"micro_size_m":soil.micro_size_m,"micro_roughness":soil.micro_roughness,"roughness_variation":soil.roughness_variation,"scope":"reference-guided connected painted earth for isometric camera; colour only; stronger depth deferred"}

func painted_soil_material(base: ShaderMaterial,colour: Image,soil) -> ShaderMaterial:
	check(base.get_shader_parameter("png_lookup").get_image().get_pixel(4,0).r<0.5,"old smooth soil has no PNG optical height")
	var result:=road_material(base,colour,{"slot":4,"material_id":"soil_grain","pattern":soil,"span_m":SoilRecipe.SPAN_M})
	var shader:=Shader.new()
	shader.code="#define EMBER_MATERIAL_COLOUR_PROBE\n"+base.shader.code
	shader.set_meta("ember_compact_terrain_shader",true)
	result.shader=shader;result.set_shader_parameter("colour_probe_slot",4)
	for key in ["pattern_atlas","side_pattern_atlas","roughness_atlas","side_roughness_atlas","finish_lookup","detail_lookup","surface_lookup","material_depth_height","material_depth_coverage","style_rim_lookup","grass_light_lookup"]:
		check(result.get_shader_parameter(key)==base.get_shader_parameter(key),"existing optical/artwork/light reference retained "+key)
	return result

func soil_material(base: ShaderMaterial,top: Image,side: Image) -> ShaderMaterial:
	var result:=base.duplicate() as ShaderMaterial
	for pair in [["pattern_atlas",top],["side_pattern_atlas",side]]:
		var old: Image=base.get_shader_parameter(pair[0]).get_image()
		var image:=SoilRecipe.colour_row(old,pair[1],4)
		var before:=old.get_data();var after:=image.get_data()
		var begin:=4*16*16*4;var end:=begin+16*16*4
		check(before.slice(0,begin)==after.slice(0,begin) and before.slice(end)==after.slice(end),"all non-soil atlas rows unchanged")
		for y in 16:
			for x in 16:check(image.get_pixel(x,64+y).a==old.get_pixel(x,64+y).a,"soil optical-height alpha unchanged")
		result.set_shader_parameter(pair[0],ImageTexture.create_from_image(image))
	for key in ["finish_lookup","detail_lookup","surface_lookup","roughness_atlas","side_roughness_atlas","png_lookup","png_albedo_bank","material_depth_height","material_depth_coverage","style_rim_lookup","grass_light_lookup"]:
		check(result.get_shader_parameter(key)==base.get_shader_parameter(key),"shared finish/relief/roughness/light retained "+key)
	return result

func apply_look(nodes: Array[MeshInstance3D],look: int) -> void:
	super.apply_look(nodes,look)
	if not soil_materials.is_empty():
		for tile in scene._projection._tiles.values():tile.get_node("Ground").material_override=soil_materials[soil_revision][look]

func select_materials(revision: int,look: int,nodes: Array[MeshInstance3D]) -> void:
	soil_revision=revision;super.select_materials(1,look,nodes)

func capture(name: String) -> Image:
	if name.begins_with("view-1-") or name.begins_with("motion-"):
		var camera: Camera3D=scene.follow_camera._cam
		var target:=Vector3(6.62,0.20,6.75)
		camera.fov=40;camera.global_position=target+Vector3(0.30,1.25,1.55);camera.look_at(target)
		if name.begins_with("motion-"):
			var frame:=int(name.get_slice("-",4))
			camera.global_position+=camera.global_basis.x*((frame/9.0-0.5)*0.25)
	await frames()
	var image:=root.get_texture().get_image()
	check(image.save_png(output.path_join(name+".png"))==OK,"capture "+name)
	return image

func capture_looks(source,clouds: Array[PackedVector3Array],nodes: Array[MeshInstance3D]) -> Dictionary:
	var result:=await super.capture_looks(source,clouds,nodes)
	result["soil"]=soil_stats
	result["soil"]["matrix_pairs"]=54
	result["soil"]["motion"]="close camera, same 25cm traverse,3 presets and3 looks"
	result["soil"]["acceptance"]="OPEN; grass B accepted; road candidate still OPEN"
	return result
