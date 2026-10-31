extends SceneTree
const Preparation=preload("res://scripts/ember_detail_preparation.gd")
const Materials=preload("res://scripts/ember_voxel_surface_materials.gd")
var errors:Array[String]=[]
func _initialize():run.call_deferred()
func check(ok:bool,label:String):
	if not ok:errors.append(label);printerr("DETAIL_SHADER_FAIL ",label)
func run():
	check(not await Preparation.prepare_shader(true,root,func():return true),"cancelled consumer cannot publish")
	for flower in [true,false]:
		check(await Preparation.prepare_shader(flower,root,func():return false),"background shader becomes ready")
		var began:=Time.get_ticks_usec()
		var material:=Materials.compact_flower_material() if flower else Materials.compact_grass_material()
		var elapsed:=Time.get_ticks_usec()-began
		check(elapsed<20000,"ready factory does not recompile the shader")
		var names:Array=[]
		for uniform in material.shader.get_shader_uniform_list():names.append(uniform.name)
		check(&"role_lookup" in names and &"painterly_blades" in names,"shared terrain/painterly bindings compile")
		check((&"flower_atlas" in names)==flower,"correct two-sided card variant")
		var second:=Materials.compact_flower_material() if flower else Materials.compact_grass_material()
		check(second!=material and second.shader==material.shader,"private materials share only the ready shader")
		print("DETAIL_SHADER_FACTORY ",flower," ",elapsed)
	var map:=EmberMapLoader.new();root.add_child(map)
	var visual:=MeshInstance3D.new();visual.mesh=PlaneMesh.new();visual.material_override=Materials.compact_flower_material();map.add_child(visual)
	map.compact_style_rim_enabled=false;map._apply_style_rim_instance(visual)
	check(visual.get_instance_shader_parameter("ember_style_rim_master")==false,"shared shader body obeys the map rim switch")
	map.compact_style_rim_enabled=true;map._apply_style_rim_instance(visual)
	check(visual.get_instance_shader_parameter("ember_style_rim_master")==true,"map rim switch restores the same detail material")
	map.free();await process_frame
	Preparation._detail_shaders.clear()
	Materials._flower_shader=null;Materials._grass_shader=null
	print("DETAIL_SHADER ",JSON.stringify({"pass":errors.is_empty(),"errors":errors}));quit(0 if errors.is_empty() else 1)
