extends SceneTree
const Pattern=preload("res://scripts/ember_compact_terrain_pattern.gd")
const Materials=preload("res://scripts/ember_voxel_surface_materials.gd")
const Editor=preload("res://addons/ember_import/ember_compact_material_pattern_dialog.gd")
const Recipe=preload("res://scripts/prototypes/ember_soil_look_recipe.gd")
var errors: Array[String]=[]
func _initialize() -> void:run.call_deferred()
func check(ok: bool,label: String) -> void:
	if not ok:errors.append(label);push_error(label)
func run() -> void:
	var out:=OS.get_cmdline_user_args()[0].replace("\\","/")
	var old: Pattern=load(out.path_join("before/content/terrain_materials/soil_grain.tres"))
	var soil:=Materials.load_compact_terrain_variant("soil_grain")
	check(soil!=null and soil.validation_errors().is_empty(),"existing soil variant validates")
	check(old.albedo_relief_enabled and not old.albedo_periodic,"legacy settings retain previous defaults")
	check(not soil.albedo_relief_enabled and soil.albedo_periodic,"accepted soil is periodic colour only")
	for field in Editor.EDIT_FIELDS:
		if field not in ["albedo_texture","albedo_relief_enabled","albedo_periodic"]:check(soil.get(field)==old.get(field),"authored legacy channel unchanged "+field)
	var imported:=soil.albedo_texture.get_image()
	if imported.is_compressed():imported.decompress()
	imported.convert(Image.FORMAT_RGBA8);imported.clear_mipmaps()
	var expected:=Recipe.colour_image();expected.clear_mipmaps()
	check(imported.get_size()==Vector2i(256,256) and imported.get_data()==expected.get_data(),"exact accepted 256px artwork, not a new painting")
	var path:="user://soil-v4-material-fixture.tres"
	check(ResourceSaver.save(soil.duplicate(true),path)==OK,"fixture material saved")
	var panel:=Editor.new();root.add_child(panel);root.add_child(panel.parameters_panel);panel.pattern_path_override=path
	check(panel.open_variant("soil_grain","soil"),"existing material editor opens accepted soil")
	panel._texture_options.albedo_relief_enabled.button_pressed=true
	check(panel._draft.albedo_relief_enabled and panel.is_dirty(),"relief toggle edits draft")
	panel.undo_edit();check(not panel._draft.albedo_relief_enabled,"PNG option Undo")
	panel.redo_edit();check(panel._draft.albedo_relief_enabled,"PNG option Redo")
	panel.undo_edit()
	panel._texture_options.albedo_periodic.button_pressed=false
	panel.undo_edit();check(panel._draft.albedo_periodic,"periodic toggle Undo")
	panel._finish_sliders.pattern_size_m.value=0.9
	panel.undo_edit();check(is_equal_approx(panel._draft.pattern_size_m,0.6),"scale Undo")
	panel._grid.size=Vector2(256,256);panel._select_channel(0);panel._begin_stroke();panel._grid.paint_at(Vector2(8,8),2);panel._finish_stroke()
	# The existing fallback canvas remains an authored independent channel.
	panel.undo_edit();check(panel._draft.pixels==soil.pixels,"manual fallback paint Undo")
	check(panel._save(),"normal material save")
	var saved: Pattern=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	check(saved.albedo_texture.resource_path==soil.albedo_texture.resource_path and not saved.albedo_relief_enabled and saved.albedo_periodic,"PNG flags and artwork survive save/reopen")
	check(panel.open_variant("soil_grain","soil"),"editor reopen")
	panel._texture_options.albedo_relief_enabled.button_pressed=true;panel.cancel_edit()
	check(not (ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP) as Pattern).albedo_relief_enabled,"discard never changes saved material")
	var roles:=PackedStringArray(["","stone","sand","grass","soil"])
	var ids:=PackedStringArray(["","cartoon_stone","cartoon_sand","cartoon_grass","soil_grain"])
	var before:=Materials.compact_terrain_material();var after:=Materials.compact_terrain_material()
	Materials.set_compact_terrain_roles(before,roles,ids,PackedColorArray(),{"soil_grain":old})
	Materials.set_compact_terrain_roles(after,roles,ids)
	var metadata: Color=after.get_shader_parameter("png_lookup").get_image().get_pixel(4,0)
	check(metadata.r>0.5 and metadata.b==-1.0 and metadata.a==1.0 and is_equal_approx(metadata.g,0.6),"runtime bank stores soil colour-only flag, scale and seamless sampling")
	for key in ["pattern_atlas","side_pattern_atlas","roughness_atlas","side_roughness_atlas","finish_lookup","detail_lookup","surface_lookup","style_rim_lookup","grass_light_lookup"]:
		check(before.get_shader_parameter(key).get_image().get_data()==after.get_shader_parameter(key).get_image().get_data(),"height/roughness/light channels exact "+key)
	for key in ["png_lookup","png_mean_lookup","png_tint_lookup"]:
		var a: Image=before.get_shader_parameter(key).get_image();var b: Image=after.get_shader_parameter(key).get_image()
		for i in 256:
			if i!=4:check(a.get_pixel(i,0)==b.get_pixel(i,0),"non-soil lookup unchanged "+key+"/"+str(i))
	panel.free()
	print("SOIL_EDITOR_TRANSFER ","PASS" if errors.is_empty() else errors);quit(0 if errors.is_empty() else 1)
