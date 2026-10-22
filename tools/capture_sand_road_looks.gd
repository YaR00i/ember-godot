extends "res://tools/capture_rock_texture_refinement.gd"
## Reuse the existing A/B matrix. Only the road's PNG slot changes.
const Road=preload("res://scripts/prototypes/ember_sand_road_recipe.gd")
var road_materials: Array=[]
var road_revision:=1
var original_ground: ShaderMaterial

func prepare_materials() -> void:
	# Both halves retain the accepted rock B, including its optical height.
	scene.rock_maps=Recipe.maps()
	super.prepare_materials()
	if road_materials.is_empty():
		original_ground=scene._projection._tiles.values()[0].get_node("Ground").material_override
		var colours:=Road.variants(Road.colour_image())
		road_materials.append([original_ground,original_ground,original_ground])
		var derived: Array[ShaderMaterial]=[]
		for look in 3:
			colours[look].save_png(output.path_join("road-colour-%d.png"%look))
			derived.append(road_material(original_ground,colours[look]))
		road_materials.append(derived)

func road_material(base: ShaderMaterial,colour: Image,options: Dictionary={}) -> ShaderMaterial:
	var target_slot:=int(options.get("slot",2))
	var material_id:=str(options.get("material_id","cartoon_sand"))
	var pattern=options.get("pattern",scene._depth_sand).duplicate(true)
	pattern.albedo_texture=ImageTexture.create_from_image(colour);pattern.pattern_size_m=float(options.get("span_m",Road.SPAN_M))
	check(pattern.validation_errors().is_empty(),"road uses valid existing terrain pattern")
	# Ask the existing owner to format/normalize the new road slot. Retain every
	# original bank layer and every non-road lookup byte in this private LAB clone.
	var temporary: ShaderMaterial=base.duplicate()
	Materials.set_compact_terrain_roles(temporary,scene._projection.document.palette_surface_roles,scene._projection.document.palette_material_ids,scene._projection.document.palette,{material_id:pattern},PackedStringArray([material_id]))
	var result: ShaderMaterial=base.duplicate()
	var original: Texture2DArray=base.get_shader_parameter("png_albedo_bank")
	var built: Texture2DArray=temporary.get_shader_parameter("png_albedo_bank")
	var slot: Color=temporary.get_shader_parameter("png_lookup").get_image().get_pixel(target_slot,0)
	var layers: Array[Image]=[]
	for layer in original.get_layers():layers.append(original.get_layer_data(layer))
	var road:=built.get_layer_data(int(slot.r)-1);road.clear_mipmaps()
	if road.get_size()!=Vector2i(original.get_width(),original.get_height()):road.resize(original.get_width(),original.get_height(),Image.INTERPOLATE_LANCZOS)
	road.generate_mipmaps();layers.append(road)
	var bank:=Texture2DArray.new();check(bank.create_from_images(layers)==OK,"append road to existing texture bank")
	result.set_shader_parameter("png_albedo_bank",bank)
	for key in ["png_lookup","png_mean_lookup","png_tint_lookup"]:
		var original_image: Image=base.get_shader_parameter(key).get_image()
		var image:=original_image.duplicate() as Image
		var value: Color=temporary.get_shader_parameter(key).get_image().get_pixel(target_slot,0)
		if key=="png_lookup":value.r=layers.size()
		image.set_pixel(target_slot,0,value);result.set_shader_parameter(key,ImageTexture.create_from_image(image))
		for index in 256:
			if index!=target_slot:check(image.get_pixel(index,0)==original_image.get_pixel(index,0),"other lookup slots unchanged")
	for layer in original.get_layers():check(bank.get_layer_data(layer).get_data()==original.get_layer_data(layer).get_data(),"non-road texture layers unchanged")
	for key in ["material_depth_height","material_depth_coverage","finish_lookup","surface_lookup","grass_light_lookup","style_rim_lookup"]:
		check(result.get_shader_parameter(key)==base.get_shader_parameter(key),"original depth/light/finish retained "+key)
	return result

func apply_look(nodes: Array[MeshInstance3D],look: int) -> void:
	super.apply_look(nodes,look)
	if not road_materials.is_empty():
		for tile in scene._projection._tiles.values():tile.get_node("Ground").material_override=road_materials[road_revision][look]

func select_materials(revision: int,look: int,nodes: Array[MeshInstance3D]) -> void:
	road_revision=revision;super.select_materials(revision,look,nodes)

func capture(name: String) -> Image:
	if name.begins_with("view-1-"):
		var camera: Camera3D=scene.follow_camera._cam
		var target:=Vector3(3.55,0.45,5.2)
		camera.fov=40;camera.global_position=target+Vector3(0.3,3.4,3.3);camera.look_at(target)
	return await super.capture(name)

func capture_looks(source,clouds: Array[PackedVector3Array],nodes: Array[MeshInstance3D]) -> Dictionary:
	var result:=await super.capture_looks(source,clouds,nodes)
	result["road"]={"span_m":Road.SPAN_M,"pixel_m":Road.SPAN_M/16.0,"scope":"sand pigment only; one master and two derived images; terrain/road contour/grass/tree and accepted rock B preserved","editor_integration":"not implemented by this LAB slice"}
	return result
