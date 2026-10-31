extends SceneTree
## Local pattern size: scene ownership, unchanged geometry, and the actual
## four-metre grass/light frequency compared with the terrain projection.
const Solid=preload("res://scripts/ember_voxel_solid_surface.gd")
var errors:Array[String]=[]
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	if not ok:errors.append(label);printerr("PATTERN_SCALE_FAIL ",label)
func fixture()->EmberVoxelModelResource:
	var source:=EmberVoxelModelResource.new();source.model_id="pattern_scale_fixture";source.display_name="Pattern size fixture"
	source.size_blocks=Vector3i(4,1,4);source.height_voxels=4
	source.palette=PackedColorArray([Color.TRANSPARENT,Color("738f48")])
	source.voxels.resize(64*4*64);source.voxels.fill(1)
	source.voxel_part_ids.resize(source.voxels.size());source.voxel_part_ids.fill(1);source.merge_parts=PackedStringArray(["body"])
	source.solid_surface={"version":1,"parts":[PackedVector3Array([Vector3.UP,Vector3.DOWN,Vector3.LEFT,Vector3.RIGHT,Vector3.FORWARD,Vector3.BACK])],"occupancy":Solid.occupancy_hash(source.voxels),"roles":PackedStringArray(["","grass"]),"material_ids":PackedStringArray(["","cartoon_grass"])}
	return source
func make_prop(source:EmberVoxelModelResource,parent:Node)->EmberVoxelProp:
	var prop:EmberVoxelProp=EmberVoxelPrefab.prepare_resource(source).instantiate();prop.authoring_source=source
	parent.add_child(prop);prop.owner=parent;prop.set_world_look(1);return prop
func frames(count:int)->void:
	for i in count:await process_frame
func image_for(visual:MeshInstance3D,material:Material)->Image:
	visual.material_override=material;await frames(4);await RenderingServer.frame_post_draw
	return root.get_texture().get_image()
func difference(a:Image,b:Image)->float:
	var total:=0.0;var count:=0
	for y in range(a.get_height()*3/10,a.get_height()*7/10,2):
		for x in range(a.get_width()*3/10,a.get_width()*7/10,2):
			var d:=a.get_pixel(x,y)-b.get_pixel(x,y)
			total+=absf(d.r)+absf(d.g)+absf(d.b);count+=3
	return total/count
func run()->void:
	if DisplayServer.get_name()=="headless":printerr("Forward+ required");quit(2);return
	Engine.max_fps=30;root.content_scale_size=Vector2i(512,512);root.size=Vector2i(512,512);DisplayServer.window_set_size(root.size)
	var stage:=Node3D.new();stage.name="PatternScaleFixture";root.add_child(stage);current_scene=stage
	var source:=fixture();var original:=source.to_definition().duplicate(true)
	var prop:=make_prop(source,stage);prop.name="Edited"
	var other:=make_prop(source,stage);other.name="Other";other.position.x=200
	var visual:MeshInstance3D=prop.get_node("Mesh")
	var mesh_id:=visual.mesh.get_instance_id();var collision:Shape3D=prop.get_node("Collision/Shape").shape
	var history:=UndoRedo.new();history.create_action("Local pattern size")
	history.add_do_property(prop,"material_pattern_scale",2.0);history.add_undo_property(prop,"material_pattern_scale",1.0);history.commit_action()
	check(prop.material_pattern_scale==2.0 and other.material_pattern_scale==1.0,"instance-only data")
	check(visual.mesh.get_instance_id()==mesh_id and prop.get_node("Collision/Shape").shape==collision,"no geometry or collision rebuild")
	check(source.to_definition()==original and load("res://content/terrain_materials/cartoon_grass.tres").pattern_size_m==4.0,"Source and shared Pattern unchanged")
	history.undo();check(prop.material_pattern_scale==1.0,"Undo")
	history.redo();check(prop.material_pattern_scale==2.0,"Redo")
	for look in 3:
		prop.set_world_look(look)
		var mat:ShaderMaterial=visual.get_active_material(0)
		check(mat.get_shader_parameter("solid_pattern_scale")==2.0 and mat.get_shader_parameter("ember_texture_world_unit")==32.0,"scale survives look %d"%look)
		if look==0:
			var amplitude:Variant=mat.get_shader_parameter("material_depth_amplitude_m")
			prop.material_pattern_scale=3.0
			check(mat.get_shader_parameter("material_depth_amplitude_m")==amplitude,"texture size leaves optical depth amplitude unchanged")
			prop.material_pattern_scale=2.0
	prop.scale=Vector3(2,1,0.5);await frames(2)
	check((visual.get_active_material(0) as ShaderMaterial).get_shader_parameter("solid_texture_unit_m").is_equal_approx(Vector3(2,1,0.5)),"node scaling keeps physical texture units")
	prop.scale=Vector3.ONE;prop.material_pattern_scale=2.0
	var saved:="user://ember-tests/object-pattern-scale.tscn";var packed:=PackedScene.new();check(packed.pack(stage)==OK,"pack fixture")
	check(ResourceSaver.save(packed,saved)==OK,"save scene")
	var reopened:Node=ResourceLoader.load(saved,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP).instantiate()
	check(reopened.get_node("Edited").material_pattern_scale==2.0 and reopened.get_node("Other").material_pattern_scale==1.0,"fresh reopen preserves independent scales")
	prop.material_pattern_scale=3.0
	check(reopened.get_node("Edited").material_pattern_scale==2.0,"discard unsaved scale")
	reopened.free();history.clear_history();history.free()
	prop.material_pattern_scale=1.0;prop.set_world_look(1)
	var actual:ShaderMaterial=visual.get_active_material(0)
	var terrain:ShaderMaterial=actual.duplicate();terrain.set_shader_parameter("solid_projection_mode",0)
	var old:ShaderMaterial=actual.duplicate();old.set_shader_parameter("ember_texture_world_unit",1.0)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-48,-32,0);stage.add_child(light)
	var camera:=Camera3D.new();stage.add_child(camera);camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=80
	var center:Vector3=visual.global_transform*visual.mesh.get_aabb().get_center()
	camera.look_at_from_position(center+Vector3(0,200,0),center,Vector3.FORWARD);camera.make_current()
	var a:Image=await image_for(visual,actual);var b:Image=await image_for(visual,terrain);var c:Image=await image_for(visual,old)
	var matched:=difference(a,b);var old_error:=difference(c,b)
	check(matched<0.008,"object and terrain rendered pattern frequency agree")
	check(old_error>matched+0.01,"old world-unit path is a visible negative control")
	visual.material_override=actual
	var host:=EmberMapLoader.new();stage.add_child(host);prop.reparent(host,true)
	var sphere=load("res://scripts/ember_world_anomaly_3d.gd").new();sphere.enabled=false;host.add_child(sphere);sphere.set_process(false)
	var copied:ShaderMaterial=actual.duplicate()
	var overlay:=MeshInstance3D.new();overlay.visible=false;visual.add_child(overlay)
	sphere._bindings.append({"source":visual,"visual":overlay,"originals":[terrain],"materials":[copied],"alternate":true})
	sphere.refresh_material_bindings();prop.material_pattern_scale=2.0
	check(copied.get_shader_parameter("solid_pattern_scale")==2.0 and copied.get_shader_parameter("ember_texture_world_unit")==32.0,"existing sphere refresh keeps local size on alternate materials")
	check(sphere.preparations==0,"size update does not prepare sphere geometry")
	sphere._bindings.clear()
	print("OBJECT_PATTERN_SCALE ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"matched_mean_rgb":matched,"old_mean_rgb":old_error}))
	stage.queue_free();await process_frame;quit(0 if errors.is_empty() else 1)
