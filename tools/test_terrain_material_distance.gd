extends SceneTree
const Policy=preload("res://scripts/prototypes/ember_world_detail_policy.gd")
const Materials=preload("res://scripts/ember_voxel_surface_materials.gd")
const TerrainProjection=preload("res://scripts/prototypes/ember_terrain_pilot_projection.gd")
const Fixture=preload("res://tools/fixtures/ember_smooth_tools_fixture.gd")
var errors:Array[String]=[]
func check(ok:bool,why:String)->void:
	if not ok:errors.append(why);push_error(why)
func _initialize()->void:run.call_deferred()
func run()->void:
	var policy:=Policy.new()
	for distance in [0.0,5.0,13.9,14.0,14.4]:
		check(policy.material_depth_required(distance,14.0,true),"full depth returns before the visible fade boundary")
	check(policy.material_depth_required(14.8,14.0,false) and not policy.material_depth_required(14.8,14.0,true),"material hysteresis beyond flat endpoint")
	check(not policy.material_depth_required(16.0,14.0,false),"far surface uses cheap path")
	check(policy.material_depth_required(16.0,20.0,true),"changing the existing fade distance restores depth")
	policy.material_lod_enabled=false
	check(policy.material_depth_required(1000.0,14.0,true),"comparison switch restores original path")
	var base:=Materials.compact_terrain_material()
	base.shader=Materials.compact_terrain_bank_depth_shader()
	base.set_shader_parameter("material_gray_preview",true)
	base.set_shader_parameter("material_light_mode",2)
	base.set_shader_parameter("terrain_world_look",2)
	base.set_shader_parameter("material_depth_enabled",true)
	var image:=Image.create(16,16,false,Image.FORMAT_RGBA8);image.fill(Color(0.2,0.6,0.1))
	var texture:=ImageTexture.create_from_image(image)
	base.set_shader_parameter("pattern_atlas",texture)
	var far:=Materials.compact_terrain_far_material(base)
	var original:Dictionary={}
	for item in base.shader.get_shader_uniform_list():original[item.name]=base.get_shader_parameter(item.name)
	for item in far.shader.get_shader_uniform_list():
		if original.has(item.name):check(far.get_shader_parameter(item.name)==original[item.name],"common parameter retained: "+item.name)
	check(far.get_shader_parameter("pattern_atlas")==texture,"artwork texture shared without re-upload")
	far.set_shader_parameter("material_gray_preview",false)
	check(base.get_shader_parameter("material_gray_preview")==true and base.get_shader_parameter("material_depth_enabled")==true,"private far settings do not flatten or recolour the original")
	var names:Dictionary={}
	for item in far.shader.get_shader_uniform_list():names[item.name]=true
	check(not names.has("material_depth_enabled"),"parallax feature is compiled out of far shader")
	# Exercise the existing material-preview command, not just a copied setter.
	var host:=Node3D.new();root.add_child(host)
	var projection:=TerrainProjection.new();host.add_child(projection)
	projection.ground_style=1;projection.world_look=0;projection.document=Fixture.base()
	projection._refresh_material_atlas()
	var tile:=Node3D.new();projection.add_child(tile)
	var visual:=MeshInstance3D.new();visual.name="Ground";visual.mesh=BoxMesh.new();tile.add_child(visual)
	projection._tiles[Vector2i.ZERO]=tile
	var camera:=Camera3D.new();host.add_child(camera);camera.position=Vector3.ONE*10000
	projection._apply_ground_distance_material(Vector2i.ZERO,camera,true)
	check(not visual.get_meta("ember_far_ground_material",false) and projection._ground_material.shader.get_meta("ember_terrain_cheap",false),"working ground already uses the same cheap profile at every distance")
	var pattern=Materials.load_compact_terrain_variant("cartoon_grass").duplicate()
	pattern.grass_light_enabled=not bool(projection._ground_material.get_shader_parameter("grass_light_profiles_enabled"))
	projection.preview_shared_material_light(pattern,"cartoon_grass")
	projection._apply_ground_distance_material(Vector2i.ZERO,camera,true)
	check(projection._ground_material.get_shader_parameter("grass_light_profiles_enabled")==pattern.grass_light_enabled,"existing preview updates the shared near and distant working profile")
	host.free()
	print("TERRAIN_MATERIAL_DISTANCE ",JSON.stringify({"pass":errors.is_empty(),"errors":errors}))
	quit(0 if errors.is_empty() else 1)
