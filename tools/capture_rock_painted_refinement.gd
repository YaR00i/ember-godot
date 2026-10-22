extends "res://tools/capture_road_painted_refinement.gd"
## Accepted road B stays fixed. A/B changes rock pigment, retaining all height.
var painted_stone: Array[ShaderMaterial]=[]
var original_stone: Array[ShaderMaterial]=[]
var zero_stone: Array[ShaderMaterial]=[]
var compiled_checked: Dictionary={}
var rock_nodes: Array[MeshInstance3D]=[]

func review_camera_indices() -> Array:
	return [0,1,3]

func prepare_materials() -> void:
	super.prepare_materials()
	if not painted_stone.is_empty():return
	original_stone=study_materials.duplicate()
	var maps:=Recipe.maps(256,2)
	check(maps.height.get_data()==scene.rock_maps.height.get_data(),"every height byte and mip remains accepted B")
	var images: Array[Image]=[maps.colour,Bake.calm_variant(maps.colour,256,0.65),TerrainLook.pixel_image(maps.colour,16)]
	var pattern=scene._stone.duplicate(true);pattern.base_color=Color("90938f")
	for look in 3:
		images[look].save_png(output.path_join("rock-painted-%d.png"%look))
		var base: ShaderMaterial=original_stone[look]
		var material:=road_material(base,images[look],{"slot":1,"material_id":"cartoon_stone","pattern":pattern,"span_m":Recipe.SPAN_M})
		var shader:=Shader.new();shader.code="#define EMBER_MATERIAL_COLOUR_PROBE\n"+base.shader.code
		shader.set_meta("ember_compact_terrain_shader",true);material.shader=shader
		material.set_shader_parameter("colour_probe_height_slot",1)
		material.set_shader_parameter("colour_probe_height_png",base.get_shader_parameter("png_lookup").get_image().get_pixel(1,0))
		var zero:=base.duplicate() as ShaderMaterial;zero.shader=shader
		zero.set_shader_parameter("colour_probe_height_slot",-1);zero_stone.append(zero)
		for key in ["material_depth_height","material_depth_coverage","finish_lookup","surface_lookup","grass_light_lookup","style_rim_lookup","roughness_atlas","side_roughness_atlas","detail_lookup"]:
			check(material.get_shader_parameter(key)==base.get_shader_parameter(key),"original rock optical/light reference retained "+key)
		painted_stone.append(material)

func apply_look(nodes: Array[MeshInstance3D],look: int) -> void:
	super.apply_look(nodes,look)
	rock_nodes=nodes
	if not painted_stone.is_empty():bind_stone(painted_stone,look)

func bind_stone(materials: Array[ShaderMaterial],look: int) -> void:
	var material:=materials[look]
	material.set_shader_parameter("material_depth_sun_direction",scene.get_node("Map/Look/Sun").global_basis.z)
	# Keep the existing toggle/POM preservation gate aimed at the active material.
	study_materials[look]=material
	for node in rock_nodes:node.material_override=material

func take(name: String) -> Image:
	await frames()
	var image:=root.get_texture().get_image()
	check(image.save_png(output.path_join(name+".png"))==OK,"capture "+name)
	return image

func capture(name: String) -> Image:
	# Pair rock only. The inherited road A/B capture is intentionally bypassed;
	# its accepted painted B binding remains unchanged throughout this study.
	var paired:=name.begins_with("view-") or name.begins_with("motion-") or name.begins_with("return-")
	if paired and not painted_stone.is_empty():
		var look: int=scene.material_style
		bind_stone(original_stone,look)
		var old:=await take(name+"-rev-0")
		if name.begins_with("view-"):
			var view:=name.get_slice("-",1);var key:="%s-%d"%[view,look]
			if not compiled_checked.has(key):
				bind_stone(zero_stone,look)
				check(old.get_data()==(await take("compiled-zero-"+key)).get_data(),"optional pigment branch disabled is exact")
				compiled_checked[key]=true
		if name.begins_with("return-"):
			var parts:=name.split("-")
			var baseline:=Image.load_from_file(output.path_join("view-%s-preset-%s-light-%s-look-0-rev-0.png"%[parts[1],parts[2],parts[3]]))
			check(old.get_data()==baseline.get_data(),"original rock returns exactly")
		bind_stone(painted_stone,look)
	return await take(name)

func capture_looks(source,clouds: Array[PackedVector3Array],nodes: Array[MeshInstance3D]) -> Dictionary:
	var result:=await super.capture_looks(source,clouds,nodes)
	result["road"]={"fixed":true,"base_color":Road.PAINTED_BASE_COLOR.to_html(false),"scope":"accepted painted road B fixed in both halves; no road A/B in this study"}
	result["rock_pigment"]={"master":Recipe.PAINTED_MASTER_PATH,"span_m":Recipe.SPAN_M,"matrix_pairs":review_records.size(),"motion_frames":360,"exact_returns":36,"compiled_zero_cases":compiled_checked.size(),"height_unchanged":true,"far_optical_height":"original PNG bank layer retained independently of new pigment","scope":"rock colour only; same Source/geometry/height/POM4cm/32/light"}
	result["scope"]="rock pigment A-B in fixed accepted environment; no form, depth, road or bark changes"
	result["manual_acceptance"]="OPEN; new rock colour not accepted; soil depth deferred"
	return result
