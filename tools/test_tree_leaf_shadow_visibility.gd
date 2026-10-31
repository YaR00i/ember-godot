extends SceneTree
var errors:Array[String]=[]
var out:="user://tree-leaf-shadow-visibility"
func _init()->void:run.call_deferred()
func check(value:bool,message:String)->void:
	if not value:errors.append(message)
func shot(label:String)->Image:
	for frame in 8:await process_frame
	await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image();image.save_png(out.path_join(label+".png"));return image
func changed(a:Image,b:Image)->int:
	var count:=0
	for y in a.get_height():
		for x in a.get_width():
			var p:=a.get_pixel(x,y);var q:=b.get_pixel(x,y)
			if absf(p.r-q.r)+absf(p.g-q.g)+absf(p.b-q.b)>0.01:count+=1
	return count
func run()->void:
	if DisplayServer.get_name()=="headless":printerr("Native Forward+ required");quit(2);return
	Engine.max_fps=30;DirAccess.make_dir_recursive_absolute(out)
	var world:=Node3D.new();root.add_child(world);current_scene=world
	var env:=WorldEnvironment.new();env.environment=Environment.new();world.add_child(env)
	env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color.BLACK
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color=Color.WHITE;env.environment.ambient_light_energy=0.1
	var sun:=DirectionalLight3D.new();sun.rotation_degrees.x=-30;sun.light_energy=0.4
	sun.shadow_enabled=true;sun.directional_shadow_mode=0;sun.directional_shadow_max_distance=20;world.add_child(sun)
	var arrays:=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3(-1,-1,0),Vector3(1,-1,0),Vector3(1,1,0),Vector3(-1,1,0)])
	arrays[Mesh.ARRAY_NORMAL]=PackedVector3Array([Vector3.BACK,Vector3.BACK,Vector3.BACK,Vector3.BACK])
	arrays[Mesh.ARRAY_COLOR]=PackedColorArray([Color.WHITE,Color.WHITE,Color.WHITE,Color.WHITE])
	arrays[Mesh.ARRAY_TEX_UV]=PackedVector2Array([Vector2(0,1),Vector2(1,1),Vector2(1,0),Vector2(0,0)])
	arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,2,0,2,3])
	arrays[Mesh.ARRAY_CUSTOM1]=PackedFloat32Array([0,0,1,0,0,0,1,0,0,0,1,0,0,0,1,0])
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays,[],{},Mesh.ARRAY_FORMAT_CUSTOM1|(Mesh.ARRAY_CUSTOM_RGBA_FLOAT<<Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT))
	if mesh.get_surface_count()!=1:printerr("Invalid leaf fixture");quit(2);return
	var leaf:=MeshInstance3D.new();leaf.mesh=mesh;leaf.position.y=1;leaf.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;world.add_child(leaf)
	var material:=ShaderMaterial.new();material.shader=load("res://shaders/ember_tree_leaf_cards.gdshader")
	var white:=Image.create(2,2,false,Image.FORMAT_RGBA8);white.fill(Color.WHITE)
	material.set_shader_parameter("painted_leaf_card_albedo",ImageTexture.create_from_image(white))
	material.set_shader_parameter("painted_foliage_paint_reference",Vector3.ONE)
	material.set_shader_parameter("painted_leaf_shadow_strength",0.4)
	material.set_shader_parameter("painted_leaf_rim_weight",1.0)
	material.set_shader_parameter("painterly_rim_strength",0.7)
	leaf.material_override=material
	var blocker:=MeshInstance3D.new();var box:=BoxMesh.new();box.size=Vector3(8,8,0.1);blocker.mesh=box
	blocker.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	world.add_child(blocker);blocker.global_transform=Transform3D(sun.global_basis,leaf.position+sun.global_basis.z*3)
	var camera:=Camera3D.new();camera.near=0.1;camera.far=50;camera.fov=32;world.add_child(camera)
	camera.look_at_from_position(Vector3(5,1,1),leaf.position);camera.make_current()
	var blocked_on:=await shot("blocked-rim-on")
	material.set_shader_parameter("painted_leaf_rim_weight",0.0);var blocked_off:=await shot("blocked-rim-off")
	var blocked_delta:=changed(blocked_on,blocked_off)
	check(blocked_delta==0,"Fully occluded leaf must not gain view-dependent rim light")
	blocker.hide();var clear_off:=await shot("clear-rim-off")
	check(changed(clear_off,blocked_off)>100,"Blocker casts a real shadow across the leaf")
	material.set_shader_parameter("painted_leaf_rim_weight",1.0);var clear_on:=await shot("clear-rim-on")
	var clear_delta:=changed(clear_on,clear_off)
	check(clear_delta>100,"Lit leaf must retain its authored rim")
	check(material.get_shader_parameter("painted_leaf_shadow_strength")==0.4,"Diffuse shadow softening stays authored")
	var report:={"pass":errors.is_empty(),"errors":errors,"occluded_changed_pixels":blocked_delta,"lit_changed_pixels":clear_delta}
	var file:=FileAccess.open(out.path_join("result.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"  "));file.close()
	print("TREE_LEAF_SHADOW_VISIBILITY ",JSON.stringify(report));quit(0 if errors.is_empty() else 1)
