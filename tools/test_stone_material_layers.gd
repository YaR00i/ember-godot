extends SceneTree
## Focused material editor checks. Only user:// copies are written.
const Pattern=preload("res://scripts/ember_compact_terrain_pattern.gd")
const Materials=preload("res://scripts/ember_voxel_surface_materials.gd")
const Layers=preload("res://scripts/ember_solid_material_layers.gd")
const Dialog=preload("res://addons/ember_import/ember_compact_material_pattern_dialog.gd")
const DIR="user://ember-tests/stone-layer-editor"
var errors:Array[String]=[]
var prop:EmberVoxelProp
var panel:Control
var scene:Node3D
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	if not ok:errors.append(label);printerr("LAYERS_FAIL ",label)
func frames(count:int)->void:
	for i in count:await process_frame
func profile()->Image:
	return (prop.get_node("Mesh").material_override as ShaderMaterial).get_meta("solid_layer_profiles").get_image()
func run()->void:
	if DisplayServer.get_name()=="headless":quit(2);return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var legacy:=Pattern.new();legacy.role_id="stone";legacy.pixels.resize(256)
	check(not legacy.stone_edges_enabled and not legacy.stone_faces_enabled and not legacy.stone_weathering_enabled,"legacy opt-out defaults")
	for field in ["stone_edge_width_mm","stone_edge_strength","stone_face_pattern_variation","stone_face_tint_variation"]:
		var invalid:Resource=legacy.duplicate();invalid.set(field,NAN)
		check(not invalid.validation_errors().is_empty(),"reject nonfinite "+field)
	var stone:Resource=Materials.load_compact_terrain_variant("cartoon_stone").duplicate(true)
	stone.stone_edges_enabled=false;stone.stone_faces_enabled=false;stone.stone_weathering_enabled=false
	var path:=DIR.path_join("stone.tres");check(ResourceSaver.save(stone,path)==OK,"save fixture")
	scene=Node3D.new();root.add_child(scene);current_scene=scene
	prop=load("res://prefabs/voxels/vox_painted_rock_group.tscn").instantiate();scene.add_child(prop);prop.set_world_look(0)
	var visual:MeshInstance3D=prop.get_node("Mesh")
	var mesh:ArrayMesh=visual.mesh;var material:ShaderMaterial=visual.material_override
	check(material.get_meta("ember_solid_layers",false),"runtime material layer binding")
	check(not material.shader.get_shader_uniform_list().is_empty(),"layered shader compiles")
	var comparison:ShaderMaterial=Layers.material(material,{"texture":mesh.get_meta("solid_layer_faces")})
	check(not comparison.shader.get_shader_uniform_list().is_empty(),"old A/B/C entry still compiles")
	if not errors.is_empty():print("LAYERS_EARLY ",errors);quit(1);return
	var surface:PackedVector3Array=mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var preparations:=Layers.preparations
	panel=Dialog.new();root.add_child(panel);root.add_child(panel.parameters_panel)
	panel.pattern_path_override=path
	panel.light_profile_previewed.connect(func(pattern,id):prop.preview_solid_material_light(pattern,id))
	check(panel.open_variant("cartoon_stone","stone"),"open original Pattern editor")
	prop.preview_solid_material_light(panel._draft,"cartoon_stone")
	check(panel._stone_groups.size()==2 and panel._stone_groups[0].visible,"two native stone groups")
	panel._stone_switches.stone_edges_enabled.button_pressed=true
	panel._stone_switches.stone_faces_enabled.button_pressed=true
	check(profile().get_pixel(1,0).r==1 and profile().get_pixel(1,0).a==1,"independent switches reach material")
	panel._stone_switches.stone_weathering_enabled.button_pressed=true
	check(profile().get_pixel(1,1).b==1,"weathering switch reaches material")
	panel.undo_edit();check(profile().get_pixel(1,1).b==0,"weathering Undo")
	panel.redo_edit();check(profile().get_pixel(1,1).b==1,"weathering Redo")
	panel._stone_sliders.stone_edge_width_mm.value=35.0
	check(is_equal_approx(profile().get_pixel(1,0).g,0.035),"live width")
	panel.undo_edit();check(is_equal_approx(profile().get_pixel(1,0).g,0.02),"width Undo")
	panel.redo_edit();check(is_equal_approx(profile().get_pixel(1,0).g,0.035),"width Redo")
	panel._stone_sliders.stone_edge_strength.value=0.6
	panel._stone_sliders.stone_face_pattern_variation.value=0.4
	panel._stone_sliders.stone_face_tint_variation.value=0.7
	check(is_equal_approx(profile().get_pixel(1,0).b,0.6) and is_equal_approx(profile().get_pixel(1,1).r,0.4) and is_equal_approx(profile().get_pixel(1,1).g,0.7),"all numeric controls preview")
	check(visual.mesh==mesh and Layers.preparations==preparations,"controls never rebuild prepared geometry")
	check(surface==visual.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX],"positions unchanged")
	check(panel._save(true),"Save material copy")
	var disk:Resource=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE)
	check(disk.stone_edges_enabled and disk.stone_faces_enabled and disk.stone_weathering_enabled and is_equal_approx(disk.stone_edge_width_mm,35.0) and is_equal_approx(disk.stone_face_pattern_variation,0.4),"fresh resource reopen")
	check(disk.pixels==stone.pixels and disk.albedo_texture.resource_path==stone.albedo_texture.resource_path and disk.depth_mm==stone.depth_mm and not disk.style_rim_enabled,"artwork/depth/rim preserved")
	panel._stone_switches.stone_weathering_enabled.button_pressed=false
	check(profile().get_pixel(1,1).b==0,"weathering off preview")
	panel.cancel_edit();check(profile().get_pixel(1,1).b==1,"weathering discard")
	check(panel.open_variant("cartoon_stone","stone"),"reopen weathered Pattern")
	panel._stone_switches.stone_faces_enabled.button_pressed=false
	check(profile().get_pixel(1,0).a==0 and profile().get_pixel(1,0).r==1,"face switch independent")
	panel.cancel_edit();check(profile().get_pixel(1,0).a==1,"discard restores saved material")
	check(panel.open_variant("cartoon_stone","stone"),"reopen editor")
	check(panel._draft.stone_faces_enabled and panel._stone_sliders.stone_edge_width_mm.value==35.0,"native controls reopen")
	# The existing form-pull control still works at zero, retaining layer support.
	panel._depth_sliders.form_pull_mm.value=0.0
	check(prop.get_node("Mesh").mesh.has_meta("solid_layer_faces"),"flat form retains layer mapping")
	panel.cancel_edit()
	for look in [1,2,0]:
		prop.set_world_look(look)
		check(bool(prop.get_node("Mesh").material_override.get_meta("ember_solid_layers",false))==(look==0),"detailed-only layer binding "+str(look))
	check(prop.get_node("Mesh").mesh==mesh,"world look returns cached display mesh")
	panel.queue_free();scene.queue_free();await frames(3)
	print("LAYERS_EDITOR ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"preparations":Layers.preparations,"prepare_ms":Layers.preparation_usec/1000.0}))
	quit(0 if errors.is_empty() else 1)
