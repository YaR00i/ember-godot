extends SceneTree
## Working terrain must never silently re-enable preset POM on refresh/reopen.
const Materials=preload("res://scripts/ember_voxel_surface_materials.gd")
const TerrainProjection=preload("res://scripts/prototypes/ember_terrain_pilot_projection.gd")
const Fixture=preload("res://tools/fixtures/ember_smooth_tools_fixture.gd")
const Dialog=preload("res://addons/ember_import/ember_compact_material_pattern_dialog.gd")
var failures:Array[String]=[]
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	if not ok:failures.append(label);push_error(label)
func names(shader:Shader)->Dictionary:
	var result:Dictionary={}
	for item in shader.get_shader_uniform_list():result[item.name]=true
	return result
func run()->void:
	var host:=Node3D.new();root.add_child(host)
	var projection:=TerrainProjection.new();host.add_child(projection)
	projection.document=Fixture.base();projection.ground_style=1
	for look in [-1,0,1,2]:
		projection.world_look=look
		projection._refresh_look_materials();projection._refresh_material_atlas()
		var material:ShaderMaterial=projection._ground_material
		check(material.shader.get_meta("ember_terrain_cheap",false),"working ground cheap for look %d"%look)
		check(not names(material.shader).has("material_depth_enabled"),"no compiled POM uniforms for look %d"%look)
		check(not material.has_meta("ember_depth_keys"),"working ground builds no optical height bank")
	var preset=Materials.load_compact_terrain_variant("cartoon_grass")
	var previous_depth:float=preset.depth_mm
	var draft=preset.duplicate(true);draft.pattern_size_m=8.0;draft.depth_mm=12.0
	projection.preview_shared_material_light(draft,"cartoon_grass")
	check(not names(projection._ground_material.shader).has("material_depth_enabled"),"preset preview cannot enable ground POM")
	check(preset.depth_mm==previous_depth,"shared preset remains unchanged")
	var special:=ShaderMaterial.new();special.shader=Materials.compact_terrain_bank_depth_shader()
	Materials.set_terrain_depth_profiles(special,PackedStringArray(["grass"]),PackedStringArray(["cartoon_grass"]))
	check(names(special.shader).has("material_depth_enabled") and special.has_meta("ember_depth_keys"),"explicit special-material depth path preserved")
	for material in [Materials.compact_grass_material(),Materials.compact_flower_material()]:
		check(not names(material.shader).has("material_depth_enabled"),"cover compiles without POM")
	var dialog:=Dialog.new();dialog.cheap_ground_profile=true;root.add_child(dialog)
	root.add_child(dialog.parameters_panel)
	var folder:="user://ember-tests/cheap-ground-profile";DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	dialog.pattern_path_override=folder.path_join("grass.tres")
	check(ResourceSaver.save(preset.duplicate(true),dialog.pattern_path_override)==OK,"fixture save")
	check(dialog.open_role("grass"),"ground material editor opens existing preset")
	check(dialog._ground_profile_notice.visible,"ground profile explained")
	check(not dialog._depth_sliders.depth_mm.editable and dialog._depth_texture_buttons[0].disabled,"ground depth controls disabled")
	check(not dialog._finish_sliders.pixel_relief.editable and not dialog._finish_sliders.micro_relief.editable,"ground optical relief controls disabled")
	check(dialog._finish_sliders.pattern_size_m.editable,"working colour size stays editable")
	dialog._finish_sliders.pattern_size_m.value=8.0
	dialog.undo_edit();check(dialog._draft.pattern_size_m==preset.pattern_size_m,"size Undo")
	dialog.redo_edit();check(dialog._draft.pattern_size_m==8.0,"size Redo")
	check(dialog._save(),"existing material Save")
	var saved=ResourceLoader.load(dialog.pattern_path_override,"",ResourceLoader.CACHE_MODE_IGNORE)
	check(saved.depth_mm==previous_depth and saved.pattern_size_m==8.0 and saved.validation_errors().is_empty(),"fresh reopen preserves disabled preset and saves colour size")
	dialog.open_role("grass");dialog._finish_sliders.pattern_size_m.value=12.0;dialog.cancel_edit()
	check(ResourceLoader.load(dialog.pattern_path_override,"",ResourceLoader.CACHE_MODE_IGNORE).pattern_size_m==8.0,"discard does not write draft")
	dialog.cheap_ground_profile=false;dialog.open_role("grass")
	check(dialog._depth_sliders.depth_mm.editable and not dialog._depth_texture_buttons[0].disabled,"special-object preset editor remains available")
	dialog.free();host.free()
	print("TERRAIN_CHEAP_PROFILE ",JSON.stringify({"pass":failures.is_empty(),"failures":failures}))
	quit(0 if failures.is_empty() else 1)
