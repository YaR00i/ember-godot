extends SceneTree
const Visual=preload("res://scripts/ember_hoshi_visual.gd")
const Lod=preload("res://tools/fixtures/hoshi_native_lods.gd")
var errors:Array[String]=[]
var out:="user://ember-tests/hoshi-native-lods"
var rows:Array=[]
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	if not ok:errors.append(label);printerr("HOSHI_LOD_FAIL ",label)
func base_only(mesh:ArrayMesh)->ArrayMesh:
	if mesh.get_blend_shape_count()>0:return mesh
	var surfaces:Array=mesh.get("_surfaces").duplicate(true)
	for surface:Dictionary in surfaces:surface.erase("lods")
	var base:=ArrayMesh.new();base.set("_surfaces",surfaces);base.custom_aabb=mesh.custom_aabb
	return base
func capture()->Dictionary:
	for i in 8:await process_frame
	await RenderingServer.frame_post_draw
	return {"image":root.get_texture().get_image(),"visible":root.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME),"shadow":root.get_render_info(Viewport.RENDER_INFO_TYPE_SHADOW,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)}
func run()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("output="):out=arg.trim_prefix("output=")
	if RenderingServer.get_current_rendering_method()!="forward_plus" or not ResourceLoader.exists(Visual.AVATAR_PATH):
		printerr("Native Forward+ and staged private Hoshi are required");quit(2);return
	DirAccess.make_dir_recursive_absolute(out)
	root.size=Vector2i(1280,720);root.use_taa=false;root.mesh_lod_threshold=1.0
	var world:=Node3D.new();root.add_child(world);current_scene=world
	var environment:=WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR
	environment.environment.background_color=Color("344558")
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=0.5;world.add_child(environment)
	var sun:=DirectionalLight3D.new();sun.rotation_degrees=Vector3(-55,-25,0);sun.shadow_enabled=true;sun.directional_shadow_max_distance=1800;world.add_child(sun)
	var floor:=MeshInstance3D.new();var plane:=PlaneMesh.new();plane.size=Vector2(500,500);floor.mesh=plane;world.add_child(floor)
	var actor:=CharacterBody3D.new();world.add_child(actor)
	var visual:=Visual.new();actor.add_child(visual);check(visual.setup(actor,16.0),"native Hoshi setup")
	visual.set_process(false);visual.skeleton.modifier_callback_mode_process=Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
	var meshes:Array=visual.avatar.find_children("*","MeshInstance3D",true,false)
	var originals:Array[ArrayMesh]=[];var candidates:Array[ArrayMesh]=[];var skins:Array=[];var changed:=0
	for node:MeshInstance3D in meshes:
		var source:ArrayMesh=base_only(node.mesh);var candidate:=Lod.prepare(source)
		originals.append(source);candidates.append(candidate);skins.append(node.skin)
		if candidate!=source:changed+=1
		for surface in source.get_surface_count():
			check(source.surface_get_arrays(surface)==candidate.surface_get_arrays(surface),"exact full arrays including bones/weights/normals "+str(node.name))
			check(source.surface_get_material(surface)==candidate.surface_get_material(surface),"same source material")
		if source.get_blend_shape_count()>0:check(candidate==source,"morph mesh is retained exactly")
	check(changed==2,"body and hair have native LOD; face retained")
	var camera:=Camera3D.new();camera.far=2000;world.add_child(camera);camera.make_current()
	var reduced:=0
	for clip:String in ["idle","walk","run"]:
		visual.motion.play(clip);visual.motion.advance(0.37)
		for pose:Dictionary in [{"name":"near","distance":70.0,"fov":40.0},{"name":"far","distance":600.0,"fov":70.0}]:
			camera.fov=pose.fov;camera.look_at_from_position(Vector3(pose.distance*0.16,18,pose.distance),Vector3(0,12,0))
			for i in meshes.size():meshes[i].mesh=originals[i];meshes[i].lod_bias=100000.0
			var full:=await capture()
			for i in meshes.size():meshes[i].mesh=candidates[i]
			var base:=await capture()
			check(full.image.get_data()==base.image.get_data(),"forced-base animated pixels exact "+clip+str(pose.name))
			for node:MeshInstance3D in meshes:node.lod_bias=1.0
			var native:=await capture()
			check(native.visible>1000,"nonempty native character render")
			if pose.name=="far" and native.visible<full.visible:reduced+=1
			for i in meshes.size():check(meshes[i].skin==skins[i],"same Skin binding after mesh swap")
			full.image.save_png(out.path_join(clip+"-"+str(pose.name)+"-full.png"))
			native.image.save_png(out.path_join(clip+"-"+str(pose.name)+"-lod.png"))
			rows.append({"clip":clip,"pose":pose.name,"full_visible":full.visible,"lod_visible":native.visible,"full_shadow":full.shadow,"lod_shadow":native.shadow})
	check(reduced==3,"native far LOD reduces all three animated poses")
	FileAccess.open(out.path_join("result.json"),FileAccess.WRITE).store_string(JSON.stringify({"pass":errors.is_empty(),"errors":errors,"rows":rows}))
	print("HOSHI_NATIVE_LOD ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"rows":rows}))
	world.queue_free();await process_frame;quit(0 if errors.is_empty() else 1)
