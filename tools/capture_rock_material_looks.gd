extends "res://tools/capture_rock_surface_detail.gd"
## Material-only comparison over the accepted Source-first geometry probe.
const Bake=preload("res://scripts/ember_material_look_bake.gd")
const Materials=preload("res://scripts/ember_voxel_surface_materials.gd")
const TerrainLook=preload("res://scripts/prototypes/ember_terrain_look_bake.gd")
var study_materials: Array[ShaderMaterial]=[]
var material_checks: Dictionary={}

func prepare_materials() -> void:
	var master_colour: Image=scene.rock_maps.colour
	var master_height: Image=scene.rock_maps.height
	var colour_hash:=hash(master_colour.get_data());var height_hash:=hash(master_height.get_data())
	var coverage:=Image.create(1,1,false,Image.FORMAT_R8);coverage.fill(Color.WHITE)
	master_colour.save_png(output.path_join("master-colour.png"));master_height.save_png(output.path_join("master-height.png"))
	for look in 3:
		var material: ShaderMaterial=scene.rock_materials[look].duplicate()
		var colour: Image=master_colour;var relief: Image=master_height
		if look==1:colour=Bake.calm_variant(master_colour)
		if look==2:
			colour=TerrainLook.pixel_image(master_colour,16)
			relief=TerrainLook.pixel_image(master_height,16)
		colour.save_png(output.path_join("colour-%d.png"%look));relief.save_png(output.path_join("height-%d.png"%look))
		var stone=scene._stone.duplicate()
		stone.albedo_texture=ImageTexture.create_from_image(colour)
		stone.base_color=Color("90938f");stone.pattern_size_m=scene.RockRecipe.SPAN_M
		Materials.set_compact_terrain_roles(material,scene._projection.document.palette_surface_roles,scene._projection.document.palette_material_ids,scene._projection.document.palette,
			{"cartoon_stone":stone,"cartoon_sand":scene._depth_sand,"cartoon_grass":scene._grass},PackedStringArray(["cartoon_stone"]))
		# These are independent rock objects: terrain coverage must not paint road
		# or grass onto their sides. Same POM solver, entirely stone coverage.
		material.set_shader_parameter("material_depth_coverage",ImageTexture.create_from_image(coverage))
		material.set_shader_parameter("material_depth_height",ImageTexture.create_from_image(relief))
		material.set_shader_parameter("material_depth_enabled",true)
		material.set_shader_parameter("smooth_surface_enabled",true)
		material.set_shader_parameter("material_shape_mode",0)
		material.set_shader_parameter("material_depth_sun_direction",scene.get_node("Map/Look/Sun").global_basis.z)
		check(is_equal_approx(material.get_shader_parameter("material_depth_amplitude_m"),0.04),"4cm shared depth")
		check(int(material.get_shader_parameter("material_depth_steps"))==32,"same 32-step POM solver")
		study_materials.append(material)
	check(hash(master_colour.get_data())==colour_hash and hash(master_height.get_data())==height_hash,"master colour and height unchanged")
	material_checks={"master_colour_hash":colour_hash,"master_height_hash":height_hash,"pixel_m":scene.RockRecipe.SPAN_M/16.0,"depth_m":0.04,"steps":32,"scope":"same material pair; calm low-poly colour, paired voxel sampling; rock objects only"}

func look_material(look: int) -> Material:
	return study_materials[look]

func apply_look(nodes: Array[MeshInstance3D],look: int) -> void:
	study_materials[look].set_shader_parameter("material_depth_sun_direction",scene.get_node("Map/Look/Sun").global_basis.z)
	for id in nodes.size():
		nodes[id].mesh=captured_look_meshes[id][look];nodes[id].material_override=study_materials[look]

func capture_looks(source,clouds: Array[PackedVector3Array],nodes: Array[MeshInstance3D]) -> Dictionary:
	prepare_materials()
	var result:=await super.capture_looks(source,clouds,nodes)
	for preset in [0,2]:
		scene.set_lighting_preset(preset)
		for look in 3:
			apply_look(nodes,look);await capture("preset-%d-look-%d"%[preset,look])
	scene.set_lighting_preset(0);scene.set_sun_pose(0)
	for look in 3:
		apply_look(nodes,look);await capture("back-look-%d"%look)
	scene.set_sun_pose(1)
	scene.set_lighting_preset(1)
	for look in 3:
		apply_look(nodes,look)
		var enabled:=await capture("depth-on-%d"%look)
		study_materials[look].set_shader_parameter("material_depth_enabled",false)
		var disabled:=await capture("depth-off-%d"%look)
		check(enabled.get_data()!=disabled.get_data(),"depth visibly contributes in look %d"%look)
		study_materials[look].set_shader_parameter("material_depth_enabled",true)
		check(enabled.get_data()==(await capture("depth-return-%d"%look)).get_data(),"depth returns exactly")
	apply_look(nodes,0)
	result["materials"]=material_checks
	return result
