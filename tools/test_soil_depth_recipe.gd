extends SceneTree
const Recipe=preload("res://scripts/prototypes/ember_soil_depth_recipe.gd")
const Colour=preload("res://scripts/prototypes/ember_soil_look_recipe.gd")
const Materials=preload("res://scripts/ember_voxel_surface_materials.gd")
const Fixture=preload("res://scripts/prototypes/ember_material_depth_fixture.gd")
var errors: Array[String]=[]
func check(ok: bool,label: String) -> void:
	if not ok:errors.append(label);printerr("FAIL ",label)
func _initialize() -> void:
	var master:=Colour.colour_image();var before:=master.get_data()
	var heights:=Recipe.heights(master)
	check(master.get_data()==before,"accepted pigment immutable")
	check(heights[0].get_data()==heights[1].get_data(),"ordinary/faceted share the same physical-scale optical forms")
	check(heights[0].get_data()==Recipe.heights(master)[0].get_data(),"height deterministic")
	var minimum:=1.0;var maximum:=0.0
	for y in 256:
		for x in 256:
			var v:=heights[0].get_pixel(x,y).r;minimum=minf(minimum,v);maximum=maxf(maximum,v)
			check(heights[2].get_pixel(x,y)==heights[2].get_pixel((x/32)*32,(y/32)*32),"voxel colour/height share eight cells")
	check(minimum>=0.27 and maximum<=0.73 and maximum-minimum>0.4,"bounded gentle optical height")
	var flat:=Image.create(32,32,false,Image.FORMAT_RGBA8);flat.fill(Color(0.6,0.4,0.2))
	var flat_height:=Recipe.height_image(flat)
	check(absf(flat_height.get_pixel(0,0).r-0.5)<0.003,"flat colour has neutral height")
	var source=Fixture.source();var saved:=source.duplicate(true)
	var mask:=Recipe.coverage(source,1);var cache: Dictionary={}
	for z in source.depth+1:
		for x in source.width+1:check(is_equal_approx(mask.get_pixel(x,z).r,Recipe.Smooth.material_weights(source,Vector2i(x,z),cache).get(1,0.0)),"coverage equals physical mesh corner weights")
	check(source.same_terrain_data(saved),"coverage does not modify source")
	var material:=Materials.compact_terrain_material()
	check(Materials.compact_terrain_secondary_depth_shader(material.shader)==null,"secondary input requires existing POM shader")
	material.shader=Materials.compact_terrain_depth_shader()
	var h:=ImageTexture.create_from_image(heights[0]);var c:=ImageTexture.create_from_image(mask)
	check(Materials.bind_compact_terrain_depth(material,h,c,Vector2i(1,2),0.04),"existing primary binding")
	material.shader=Materials.compact_terrain_secondary_depth_shader(material.shader)
	check(Materials.bind_compact_terrain_secondary_depth(material,h,c,Vector2i(4,3),0.008),"secondary binding")
	check(material.get_shader_parameter("material_depth_height")==h and material.get_shader_parameter("material_depth_slots")==Vector2i(1,2) and is_equal_approx(material.get_shader_parameter("material_depth_amplitude_m"),0.04),"primary profile retained")
	for amount in [-0.1,0.09,NAN]:check(not Materials.bind_compact_terrain_secondary_depth(material,h,c,Vector2i(4,3),amount),"reject invalid amplitude")
	check(not Materials.bind_compact_terrain_secondary_depth(material,h,c,Vector2i(0,3),0.008),"reject invalid slots")
	check(is_equal_approx(material.get_shader_parameter("material_depth_secondary_amplitude_m"),0.008),"invalid binding does not mutate valid settings")
	check(Materials.bind_compact_terrain_secondary_depth(material,h,c,Vector2i(4,3),0.0) and not material.get_shader_parameter("material_depth_secondary_enabled"),"zero disables secondary only")
	check(Materials.bind_compact_terrain_secondary_depth(material,h,c,Vector2i(4,3),0.016,Vector3(1,2,3)),"enable stronger depth before saving")
	check(ResourceSaver.save(material,"user://soil-secondary-material.tres")==OK,"material serialization")
	var reopened=ResourceLoader.load("user://soil-secondary-material.tres","",ResourceLoader.CACHE_MODE_IGNORE)
	check(reopened.get_shader_parameter("material_depth_secondary_slots")==Vector2i(4,3) and is_equal_approx(reopened.get_shader_parameter("material_depth_amplitude_m"),0.04) and reopened.get_shader_parameter("material_depth_secondary_enabled") and is_equal_approx(reopened.get_shader_parameter("material_depth_secondary_amplitude_m"),0.016) and reopened.get_shader_parameter("material_depth_secondary_sun_direction")==Vector3(1,2,3),"both profiles, amplitude, toggle and sun reopen")
	print("SOIL_DEPTH_RECIPE ","PASS" if errors.is_empty() else errors);quit(0 if errors.is_empty() else 1)
