@tool
extends EditorPlugin
## Run ONLY in a disposable editor checkout. Outputs are a disposable native-bake fixture.
const Probe=preload("res://tools/fixtures/ember_lightmap_probe.gd")
const Surface=preload("res://scripts/prototypes/ember_terrain_smooth_surface.gd")
const Materials=preload("res://scripts/ember_voxel_surface_materials.gd")
const DIR="res://qa_static_shadow"
const OUT="C:/Users/novos/Documents/Codex/2026-11-01/ember-static-shadow-probe"
var errors:Array[String]=[]
var report:Dictionary={"scope":"native stock LightmapGI compatibility; not dense-world acceptance","production_integration":false}
func _enter_tree()->void:
	print("STATIC_BAKE_ENTER")
	run.call_deferred()
func check(ok:bool,label:String)->void:
	if not ok:errors.append(label);printerr("STATIC_BAKE_FAIL ",label)
func frames(n:int)->void:
	for i in n:await get_tree().process_frame
func save_report()->void:
	report.errors=errors
	FileAccess.open(OUT.path_join("editor-result.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
func run()->void:
	check(Engine.is_editor_hint() and DisplayServer.get_name()!="headless","native disposable editor")
	if "bake-existing" in OS.get_cmdline_user_args():
		if FileAccess.file_exists(OUT.path_join("editor-result.json")):report=JSON.parse_string(FileAccess.get_file_as_string(OUT.path_join("editor-result.json")))
		await bake_existing()
		return
	report.phase="setup";save_report();print("STATIC_BAKE_SETUP")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	await frames(12)
	var root:=Node3D.new();root.name="StaticShadowCompatibility"
	get_tree().root.add_child(root)
	var source:Resource=load("res://content/world_terrains/landscape_compact.res")
	var terrain_hash:=FileAccess.get_sha256("res://content/world_terrains/landscape_compact.res")
	var bounds:=Rect2i(Vector2i(source.width/2-64,source.depth/2-64),Vector2i(128,128))
	var field:=Surface.field(source,bounds)
	var data:=Surface.build_arrays(source,bounds,true,true,field,true)
	print("STATIC_BAKE_GROUND_ARRAYS")
	var upload:=Surface.prepare_render_upload(data.arrays,data.render_detail)
	var original:=Surface.publish_render_mesh(upload.arrays,upload.detail)
	var ground:=MeshInstance3D.new();ground.name="Ground";root.add_child(ground);ground.owner=root
	ground.mesh=original
	var mat:=Materials.compact_terrain_material();Materials.set_compact_terrain_roles(mat,source.palette_surface_roles,source.palette_material_ids,source.palette)
	mat.set_shader_parameter("smooth_surface_enabled",true);ground.material_override=mat
	var center:=original.get_aabb().get_center()
	ground.position=-Vector3(center.x,center.y,center.z)
	var rock:EmberVoxelProp=load("res://prefabs/voxels/vox_painted_rock_group.tscn").instantiate()
	root.add_child(rock);rock.set_world_look(0)
	var visual:MeshInstance3D=rock.get_node("Mesh")
	var stone:=MeshInstance3D.new();stone.name="Rock";root.add_child(stone);stone.owner=root
	stone.mesh=visual.mesh;stone.material_override=visual.material_override.duplicate();stone.transform=visual.transform
	stone.scale*=0.35;stone.position=Vector3(0,2,0)
	stone.material_override.set_shader_parameter("solid_depth_world_to_local",Projection(stone.global_transform.affine_inverse()))
	rock.free()
	var light:=DirectionalLight3D.new();light.name="Sun";root.add_child(light);light.owner=root
	light.rotation_degrees=Vector3(-18,-55,0);light.light_energy=1.1;light.shadow_enabled=true;light.directional_shadow_max_distance=1600
	light.light_bake_mode=Light3D.BAKE_DYNAMIC
	var env:=WorldEnvironment.new();env.name="Environment";root.add_child(env);env.owner=root
	env.environment=Environment.new();env.environment.background_mode=Environment.BG_COLOR;env.environment.background_color=Color(0.12,0.15,0.2)
	env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;env.environment.ambient_light_energy=0.0
	var camera:=Camera3D.new();camera.name="Camera";root.add_child(camera);camera.owner=root
	camera.position=Vector3(155,120,155);camera.look_at(Vector3.ZERO);camera.far=4000
	var conversion:Array=[]
	for node:MeshInstance3D in [ground,stone]:
		print("STATIC_BAKE_UNWRAP ",node.name)
		var adapted:=Probe.unwrap(node.mesh,node.transform,0.25)
		check(adapted.error==OK,"stock unwrap "+node.name)
		if adapted.error!=OK:save_report();get_tree().quit(1);return
		check(adapted.triangles_before==adapted.triangles_after,"no triangle loss "+node.name)
		node.mesh=adapted.mesh;node.material_override=Probe.material(node.material_override)
		node.gi_mode=GeometryInstance3D.GI_MODE_STATIC
		adapted.erase("mesh");adapted.name=node.name;conversion.append(adapted)
	report.conversion=conversion;report.source_unchanged=FileAccess.get_sha256("res://content/world_terrains/landscape_compact.res")==terrain_hash
	var gi:=LightmapGI.new();gi.name="LightmapGI";root.add_child(gi);gi.owner=root
	gi.quality=LightmapGI.BAKE_QUALITY_LOW;gi.bounces=0;gi.use_denoiser=false;gi.directional=false;gi.max_texture_size=2048
	gi.environment_mode=LightmapGI.ENVIRONMENT_MODE_DISABLED
	gi.shadowmask_mode=LightmapGIData.SHADOWMASK_MODE_REPLACE
	gi.generate_probes_subdiv=LightmapGI.GENERATE_PROBES_SUBDIV_4
	gi.light_data=LightmapGIData.new();ResourceSaver.save(gi.light_data,DIR.path_join("sun.lmbake"))
	gi.light_data.take_over_path(DIR.path_join("sun.lmbake"))
	# Keep generated arrays in binary resources; the fixture scene stays readable.
	for node:MeshInstance3D in [ground,stone]:
		var mesh_path:=DIR.path_join(node.name.to_lower()+".res")
		check(ResourceSaver.save(node.mesh,mesh_path)==OK,"derived mesh save "+node.name)
		node.mesh.take_over_path(mesh_path)
	var packed:=PackedScene.new();check(packed.pack(root)==OK,"fixture pack")
	check(ResourceSaver.save(packed,DIR.path_join("probe.tscn"))==OK,"disposable fixture save")
	root.free()
	report.phase="prepared";save_report();print("STATIC_BAKE_PREPARED ",JSON.stringify(report))
	get_tree().quit(0 if errors.is_empty() else 1)

func bake_existing()->void:
	var deadline:=Time.get_ticks_msec()+90000
	while Time.get_ticks_msec()<deadline:
		var scene:=get_editor_interface().get_edited_scene_root()
		if scene!=null and scene.scene_file_path==DIR.path_join("probe.tscn"):break
		await frames(1)
	var edited:=get_editor_interface().get_edited_scene_root()
	if edited==null or not edited.has_node("LightmapGI"):check(false,"edited bake fixture available");save_report();get_tree().quit(1);return
	var target:LightmapGI=edited.get_node("LightmapGI")
	if "verify-cleanup" in OS.get_cmdline_user_args():
		report.reopened_shadowmask=not target.light_data.get_shadowmask_textures().is_empty()
		check(report.reopened_shadowmask,"native editor reopens baked data")
		target.light_data=null
		await frames(2)
		report.phase="reopened";save_report();print("STATIC_BAKE_REOPEN ",JSON.stringify(report))
		get_tree().quit(0 if errors.is_empty() else 1)
		return
	get_editor_interface().get_selection().clear()
	get_editor_interface().get_selection().add_node(target)
	get_editor_interface().edit_node(target)
	await frames(15)
	var bake_button:Button
	for button in get_editor_interface().get_base_control().find_children("*","Button",true,false):
		for connection:Dictionary in button.get_signal_connection_list("pressed"):
			var callable:Callable=connection.callable
			if callable.get_method()=="_bake" and callable.get_object()!=null and callable.get_object().get_class()=="LightmapGIEditorPlugin":bake_button=button;break
		if bake_button!=null:break
	check(bake_button!=null and not bake_button.disabled,"stock Bake Lightmaps editor action available")
	if bake_button==null:save_report();get_tree().quit(1);return
	report.phase="baking";save_report();print("STATIC_BAKE_START ",JSON.stringify(report))
	var started:=Time.get_ticks_msec()
	bake_button.emit_signal("pressed")
	await frames(20)
	report.bake_ms=Time.get_ticks_msec()-started
	report.shadowmask=not target.light_data.get_shadowmask_textures().is_empty()
	report.lightmaps=target.light_data.get_lightmap_textures().size()
	check(report.shadowmask,"actual baked shadowmask exists")
	get_editor_interface().save_scene()
	report.phase="complete";save_report();print("STATIC_BAKE_RESULT ",JSON.stringify(report))
	target.light_data=null # Detach users while the edited scene is still inside its tree.
	await frames(2)
	get_tree().quit(0 if errors.is_empty() else 1)
