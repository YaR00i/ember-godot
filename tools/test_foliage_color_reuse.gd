extends SceneTree
## Native pixel comparison with the existing weighted fallback. No authored data.
const Materials=preload("res://scripts/ember_voxel_surface_materials.gd")
const Cover=preload("res://scripts/ember_flowered_grass.gd")
const FAST_CONDITION="else if(painterly_blades && slots.x==slots.y && slots.y==slots.z)"
var failures:Array[String]=[]
var output:="user://ember-tests/foliage-color-reuse"
var measurements:Array=[]

func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
	if not value:failures.append(label);printerr("FOLIAGE_COLOR_FAIL ",label)
func frames(count:int)->void:
	for i in count:await process_frame
func capture()->Image:
	await frames(5);await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func material(kind:String)->ShaderMaterial:
	var result:ShaderMaterial
	if kind=="flower":result=Materials.compact_flower_material()
	elif kind=="grass":result=Materials.compact_grass_material()
	else:
		result=Materials.compact_terrain_material()
		if kind=="stone":result.shader=Materials.compact_terrain_bank_depth_shader()
	Materials.set_compact_terrain_roles(result,PackedStringArray(["","stone","soil","grass"]),PackedStringArray(["","cartoon_stone","cartoon_soil","cartoon_grass"]))
	result.set_shader_parameter("ember_texture_world_unit",1.0)
	if kind=="flower":Cover.bind(result,load(Cover.PATTERN_PATH),3)
	return result

func reference(original:ShaderMaterial)->ShaderMaterial:
	var result:ShaderMaterial=original.duplicate()
	var shader:=Shader.new()
	var body:=FileAccess.get_file_as_string("res://shaders/ember_compact_terrain_body.gdshaderinc")
	body=body.replace(FAST_CONDITION,"else if(false && painterly_blades && slots.x==slots.y && slots.y==slots.z)")
	shader.code=original.shader.code.replace("#define EMBER_GRASS_COVER\n","").replace('#include "res://shaders/ember_compact_terrain_body.gdshaderinc"',body)
	for key in original.shader.get_meta_list():shader.set_meta(key,original.shader.get_meta(key))
	result.shader=shader
	for property in original.shader.get_shader_uniform_list():result.set_shader_parameter(property.name,original.get_shader_parameter(property.name))
	return result

func quad(slots:Vector3,mixed:bool,flower:bool)->ArrayMesh:
	var points:=[Vector3(-2,0,-2),Vector3(2,0,-2),Vector3(2,0,2),Vector3(-2,0,2)]
	var weights:=[Color(0.7,0.2,0.1),Color(0.2,0.5,0.3),Color(0.3,0.2,0.5),Color(0.1,0.2,0.7)]
	var uv:=[Vector2.ZERO,Vector2(1,0),Vector2.ONE,Vector2(0,1)]
	var builder:=SurfaceTool.new();builder.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in [0,1,2,0,2,3]:
		builder.set_normal(Vector3.UP)
		var color:Color=weights[i] if mixed else Color(1,0,0)
		color.a=slots.x/255.0;builder.set_color(color)
		builder.set_uv(uv[i] if flower else Vector2(slots.x,slots.y)/255.0)
		builder.set_uv2(Vector2(slots.z/255.0,0));builder.add_vertex(points[i])
	return builder.commit()

func run()->void:
	if DisplayServer.get_name()=="headless":printerr("Native Forward+ required");quit(2);return
	check(RenderingServer.get_current_rendering_method()=="forward_plus","Forward+ renderer")
	var args:=OS.get_cmdline_user_args()
	if not args.is_empty():output=args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var code:=FileAccess.get_file_as_string("res://shaders/ember_compact_terrain_body.gdshaderinc")
	check(code.contains(FAST_CONDITION),"fast path available for comparison")
	if not failures.is_empty():quit(1);return
	DisplayServer.window_set_size(Vector2i(384,320));root.size=Vector2i(384,320);Engine.max_fps=60
	var scene:=Node3D.new();root.add_child(scene);current_scene=scene
	var visual:=MeshInstance3D.new();scene.add_child(visual)
	var camera:=Camera3D.new();scene.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=5.8;camera.look_at_from_position(Vector3(1.7,5,4),Vector3.ZERO);camera.make_current()
	var sun:=DirectionalLight3D.new();scene.add_child(sun);sun.rotation_degrees=Vector3(-40,-25,0)
	var world:=WorldEnvironment.new();world.environment=Environment.new();world.environment.background_mode=Environment.BG_COLOR;world.environment.background_color=Color(0.12,0.15,0.18);world.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;world.environment.ambient_light_color=Color.WHITE;world.environment.ambient_light_energy=0.3;scene.add_child(world)
	var cases:=[
		["single",Vector3(3,3,3),false,0,false,true,true],
		["mixed_same",Vector3(3,3,3),true,1,false,true,true],
		["mixed_distinct",Vector3(3,2,1),true,2,false,true,true],
		["gray",Vector3(3,3,3),true,0,true,true,true],
		["blade_off",Vector3(3,3,3),true,1,false,false,true],
		["legacy",Vector3(3,3,3),false,2,false,true,false]]
	for kind in ["grass","flower","ground","stone"]:
		var optimized:=material(kind)
		var fallback:=reference(optimized)
		for values in cases:
			visual.mesh=quad(values[1],values[2],kind=="flower")
			for current in [optimized,fallback]:
				current.set_shader_parameter("material_light_mode",values[3])
				current.set_shader_parameter("material_gray_preview",values[4])
				current.set_shader_parameter("painterly_blades",values[5] and kind in ["grass","flower"])
				current.set_shader_parameter("smooth_surface_enabled",values[6])
			visual.material_override=fallback;var before:=await capture()
			visual.material_override=optimized;var after:=await capture()
			var maximum:=0.0;var changed:=0;var coverage:=0;var background:=before.get_pixel(0,0)
			for y in after.get_height():
				for x in after.get_width():
					var a:=before.get_pixel(x,y);var b:=after.get_pixel(x,y)
					var difference:=maxf(absf(a.r-b.r),maxf(absf(a.g-b.g),absf(a.b-b.b)))
					maximum=maxf(maximum,difference)
					if difference>0.0:changed+=1
					if maxf(absf(a.r-background.r),maxf(absf(a.g-background.g),absf(a.b-background.b)))>0.01:coverage+=1
			var label:String=kind+"_"+values[0]
			check(coverage>500,label+" visible fixture")
			check(changed==0,label+" RGB exact")
			measurements.append({"case":label,"changed":changed,"max":maximum,"coverage":coverage})
			if values[0]=="mixed_same":after.save_png(output.path_join(label+".png"))
	var report:={"pass":failures.is_empty(),"failures":failures,"cases":measurements}
	FileAccess.open(output.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("FOLIAGE_COLOR_REUSE ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)
