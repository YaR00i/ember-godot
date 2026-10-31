extends SceneTree
## Shared library -> real dialog -> ground and layered prop; only user:// fixtures are saved.
const Materials=preload("res://scripts/ember_voxel_surface_materials.gd")
const Dialog=preload("res://addons/ember_import/ember_compact_material_pattern_dialog.gd")
var errors:Array[String]=[]
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	if not ok:errors.append(label);printerr("LIBRARY_DEPTH_FAIL ",label)
func frames(n:int)->void:
	for i in n:await process_frame
func depth(material:ShaderMaterial,slot:int)->float:
	return material.get_meta("ember_depth_profiles").get_pixel(slot,0).g
func run()->void:
	if DisplayServer.get_name()=="headless":quit(2);return
	Engine.max_fps=30
	var scene:=Node3D.new();root.add_child(scene);current_scene=scene
	var prop:EmberVoxelProp=load("res://prefabs/voxels/vox_natural_earth_outcrop.tscn").instantiate();scene.add_child(prop);prop.set_world_look(0)
	var visual:MeshInstance3D=prop.get_node("Mesh");var mesh:=visual.mesh
	var collider:Shape3D=prop.get_node("Collision/Shape").shape
	var mat:ShaderMaterial=visual.get_active_material(0)
	var ids:PackedStringArray=mesh.get_meta("solid_surface_material_ids")
	var roles:PackedStringArray=mesh.get_meta("solid_surface_roles")
	var ground:=Materials.compact_terrain_material();ground.shader=Materials.compact_terrain_bank_depth_shader()
	Materials.set_compact_terrain_roles(ground,roles,ids,mesh.get_meta("solid_surface_palette"))
	Materials.set_terrain_depth_profiles(ground,roles,ids)
	check(mat.get_shader_parameter("material_depth_bank_enabled"),"solid uses common library bank")
	for slot in range(1,ids.size()):
		var p=Materials.load_compact_terrain_variant(ids[slot])
		check(is_equal_approx(depth(mat,slot),p.depth_mm*0.001) and is_equal_approx(depth(ground,slot),depth(mat,slot)),"ground/object own profile "+ids[slot])
	check(mat.get_shader_parameter("terrain_depth_world_unit")==16.0,"metres converted only at shading")
	var sibling:ShaderMaterial=preload("res://scripts/ember_voxel_solid_surface.gd").material_for(mesh,true)
	check(sibling.get_shader_parameter("terrain_depth_bank")==mat.get_shader_parameter("terrain_depth_bank"),"same recipes share GPU height bank")
	var normal_only:=OS.get_cmdline_user_args().has("--normal-only")
	if not normal_only:await editor_cycle(prop,visual,mesh,collider,mat,ground,roles,ids)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-40,-25,0);scene.add_child(light)
	var camera:=Camera3D.new();scene.add_child(camera)
	var center:Vector3=visual.global_transform*visual.mesh.get_aabb().get_center()
	camera.look_at_from_position(center+Vector3(90,70,110),center);camera.make_current()
	await frames(5);await RenderingServer.frame_post_draw
	check(not mat.shader.get_shader_uniform_list().is_empty() and not ground.shader.get_shader_uniform_list().is_empty(),"both shaders compile")
	await normal_cycle(visual)
	scene.queue_free();await frames(3);quit(0 if errors.is_empty() else 1)

func editor_cycle(prop:EmberVoxelProp,visual:MeshInstance3D,mesh:ArrayMesh,collider:Shape3D,mat:ShaderMaterial,ground:ShaderMaterial,roles:PackedStringArray,ids:PackedStringArray)->void:
	var old_stone:=depth(mat,1);var old_grass:=depth(mat,3)
	var soil=Materials.load_compact_terrain_variant("soil_grain")
	var path:="user://ember-tests/library-depth/soil.tres";DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	check(ResourceSaver.save(soil,path)==OK,"save initial material fixture")
	var dialog:=Dialog.new();root.add_child(dialog);root.add_child(dialog.parameters_panel);dialog.pattern_path_override=path
	dialog.light_profile_previewed.connect(func(draft,id):
		prop.preview_solid_material_light(draft,id)
		Materials.set_terrain_depth_profiles(ground,roles,ids,{id:draft}))
	check(dialog.open_variant("soil_grain","soil"),"open library soil in existing editor")
	var bank:Texture2DArray=mat.get_shader_parameter("terrain_depth_bank")
	dialog._depth_sliders.depth_mm.value=12.0
	check(is_equal_approx(depth(mat,2),0.012) and is_equal_approx(depth(ground,2),0.012),"one control reaches ground and object")
	check(depth(mat,1)==old_stone and depth(mat,3)==old_grass,"soil edit keeps other profiles")
	check(mat.get_shader_parameter("terrain_depth_bank")==bank,"amplitude does not upload height bank")
	dialog.undo_edit();check(is_equal_approx(depth(mat,2),0.003) and is_equal_approx(depth(ground,2),0.003),"Undo both consumers")
	dialog.redo_edit();check(is_equal_approx(depth(mat,2),0.012),"Redo object")
	check(dialog._save(true),"save edited recipe")
	var disk=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
	check(disk.validation_errors().is_empty() and disk.depth_mm==12.0,"fresh recipe reopen validates")
	dialog._depth_sliders.depth_mm.value=0.0
	check(depth(mat,2)==0.0 and depth(mat,1)==old_stone,"disable only soil")
	dialog.cancel_edit();check(is_equal_approx(depth(mat,2),0.012),"discard returns saved value")
	check(visual.mesh==mesh and prop.get_node("Collision/Shape").shape==collider,"no geometry/collision rebuild")
	# Restore the working-copy draft before switching looks; no author material was written.
	prop.preview_solid_material_light(soil,"soil_grain")
	for look in [1,2,0]:
		prop.set_world_look(look)
		if look==0:check(is_equal_approx(depth(visual.get_active_material(0),2),0.003),"detailed return restores library")
	dialog.queue_free()

func normal_cycle(visual:MeshInstance3D)->void:
	# A flat height field must retain the same smooth object shading. This catches
	# POM replacing the authored normal with each tiny triangle's plane normal.
	var mat:ShaderMaterial=visual.get_active_material(0)
	var blank:=Image.create(16,16,true,Image.FORMAT_R8);blank.fill(Color(0.5,0,0))
	var blank_bank:=Texture2DArray.new();blank_bank.create_from_images([blank,blank,blank])
	mat.set_shader_parameter("terrain_depth_bank",blank_bank)
	var neutral:=Image.create(16,16,true,Image.FORMAT_RGB8);neutral.fill(Color(0.5,0.5,0.5))
	var neutral_bank:=Texture2DArray.new();neutral_bank.create_from_images([neutral,neutral,neutral])
	mat.set_shader_parameter("png_albedo_bank",neutral_bank)
	mat.set_shader_parameter("material_depth_enabled",false);await frames(3);await RenderingServer.frame_post_draw
	var flat:Image=root.get_texture().get_image()
	mat.set_shader_parameter("material_depth_enabled",true);await frames(3);await RenderingServer.frame_post_draw
	var relief:Image=root.get_texture().get_image();var total:=0.0;var count:=0
	for y in range(flat.get_height()/4,flat.get_height()*3/4,2):
		for x in range(flat.get_width()/4,flat.get_width()*3/4,2):
			var d:=flat.get_pixel(x,y)-relief.get_pixel(x,y);total+=absf(d.r)+absf(d.g)+absf(d.b);count+=3
	var normal_error:=total/count
	check(normal_error<0.0005,"neutral relief keeps smooth shading")
	var original_shader:=mat.shader;var old_shader:=Shader.new()
	old_shader.code=original_shader.code.replace("relief_normal=normalize(terrain_world_normal);","relief_normal=n;")
	mat.shader=old_shader;await frames(3);await RenderingServer.frame_post_draw
	var old:Image=root.get_texture().get_image();total=0.0;count=0
	for y in range(flat.get_height()/4,flat.get_height()*3/4,2):
		for x in range(flat.get_width()/4,flat.get_width()*3/4,2):
			var d:=flat.get_pixel(x,y)-old.get_pixel(x,y);total+=absf(d.r)+absf(d.g)+absf(d.b);count+=3
	var old_error:=total/count;mat.shader=original_shader
	check(old_error>normal_error+0.0005,"previous plane-normal path exposes tessellation")
	print("MATERIAL_LIBRARY_DEPTH ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"neutral_height_mean_rgb":normal_error,"old_normal_mean_rgb":old_error}))
