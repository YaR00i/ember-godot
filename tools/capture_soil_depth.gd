extends "res://tools/capture_soil_derived_looks.gd"
## Accepted v4 colour at three optical strengths. One existing terrain renderer.
const SoilDepth=preload("res://scripts/prototypes/ember_soil_depth_recipe.gd")
const AMOUNTS=[0.0,0.008,0.016]
var depth_prepared:=false
var optical_heights: Array[Image]=[]
var zero_materials: Array[ShaderMaterial]=[]

func prepare_materials() -> void:
	super.prepare_materials()
	if depth_prepared:return
	depth_prepared=true
	var flat: Array=soil_materials[1].duplicate()
	optical_heights=SoilDepth.heights(SoilRecipe.colour_image())
	var source=scene._projection.document
	var mask:=SoilDepth.coverage(source,4)
	var cache: Dictionary={}
	for z in mask.get_height():
		for x in mask.get_width():
			if mask.get_pixel(x,z).r<=0.0:continue
			var weights:=SoilDepth.Smooth.material_weights(source,Vector2i(x,z),cache)
			for slot in weights:
				check(slot in [3,4] or weights[slot]<=0.00001,"soil optical mask only blends accepted soil and grass")
	var coverage:=ImageTexture.create_from_image(mask)
	var textures: Array[Texture2D]=[ImageTexture.create_from_image(optical_heights[0]),null,ImageTexture.create_from_image(optical_heights[2])]
	textures[1]=textures[0]
	var variants: Array=[flat,[],[]]
	for look in 3:
		optical_heights[look].save_png(output.path_join("soil-height-%d.png"%look))
		for revision in [1,2]:
			var base: ShaderMaterial=flat[look]
			var material:=base.duplicate() as ShaderMaterial
			material.shader=Materials.compact_terrain_secondary_depth_shader(base.shader)
			check(material.shader!=null,"one existing POM renderer has optional secondary input")
			check(Materials.bind_compact_terrain_secondary_depth(material,textures[look],coverage,Vector2i(4,3),AMOUNTS[revision],scene.get_node("Map/Look/Sun").global_basis.z),"soil depth binding")
			for key in ["png_albedo_bank","png_lookup","png_mean_lookup","png_tint_lookup","material_depth_height","material_depth_coverage","material_depth_slots","material_depth_amplitude_m","material_depth_sun_direction","material_depth_steps","material_depth_fade_near_m","material_depth_fade_far_m","finish_lookup","roughness_atlas","side_roughness_atlas","grass_light_lookup","style_rim_lookup"]:
				check(material.get_shader_parameter(key)==base.get_shader_parameter(key),"original colour/primary depth/finish/light retained "+key)
			variants[revision].append(material)
		var zero:=variants[1][look].duplicate() as ShaderMaterial
		zero.set_shader_parameter("material_depth_secondary_enabled",false)
		zero.set_shader_parameter("material_depth_secondary_amplitude_m",0.0)
		zero_materials.append(zero)
	soil_materials=variants
	mask.save_png(output.path_join("soil-depth-mask.png"))
	soil_stats["control"]="accepted v4 without added depth"
	soil_stats["amounts_m"]=AMOUNTS
	soil_stats["height_source"]="LAB heuristic: broad pigment luminance, 64px smoothing, percentile8/92, bounded0.28..0.72; independent height image"
	soil_stats["height_texture_builds"]=2
	soil_stats["coverage_builds"]=1
	soil_stats["shared_steps"]=32

func apply_look(nodes: Array[MeshInstance3D],look: int) -> void:
	super.apply_look(nodes,look)
	if depth_prepared and soil_revision>0:
		soil_materials[soil_revision][look].set_shader_parameter("material_depth_secondary_sun_direction",scene.get_node("Map/Look/Sun").global_basis.z)

func capture_looks(source,clouds: Array[PackedVector3Array],nodes: Array[MeshInstance3D]) -> Dictionary:
	var result:=await super.capture_looks(source,clouds,nodes)
	var camera: Camera3D=scene.follow_camera._cam
	var game:=camera.global_transform;var fov:=camera.fov
	for look in 3:
		select_materials(0,look,nodes)
		var off:=await capture("zero-original-%d"%look)
		for tile in scene._projection._tiles.values():tile.get_node("Ground").material_override=zero_materials[look]
		check(off.get_data()==(await capture("zero-compiled-%d"%look)).get_data(),"secondary zero equals the accepted flat renderer")
	for view in 3:
		for preset in 3:
			for light in 2:
				for look in 3:
					camera.global_transform=game;camera.fov=fov
					if view==2:
						camera.global_position+=game.basis.z*4.0+Vector3.UP*1.5
						camera.look_at(game.origin-game.basis.z*5.0)
					scene.set_lighting_preset(preset);scene.set_sun_pose(light)
					select_materials(2,look,nodes)
					await capture("view-%d-preset-%d-light-%d-look-%d-rev-2"%[view,preset,light,look])
	for preset in 3:
		scene.set_lighting_preset(preset);scene.set_sun_pose(0)
		for look in 3:
			select_materials(2,look,nodes)
			for frame in 10:
				camera.global_transform=game;camera.fov=fov
				await capture("motion-%d-%d-2-%02d"%[preset,look,frame])
	camera.global_transform=game;camera.fov=fov
	scene.set_lighting_preset(1);scene.set_sun_pose(1);select_materials(1,0,nodes)
	var before:=await capture("strength-return-start")
	select_materials(2,2,nodes);await frames();select_materials(0,0,nodes);await frames();select_materials(1,0,nodes)
	check(before.get_data()==(await capture("strength-return-end")).get_data(),"strength/look switching returns exactly")
	result["soil_depth"]={"strengths_m":AMOUNTS,"cases":54,"stills":162,"motion_frames":270,"zero_exact":true,"height_texture_builds":2,"coverage_builds":1,"author_acceptance":"OPEN; v4 pigment accepted, new depth trial only"}
	return result
