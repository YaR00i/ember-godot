extends SceneTree
const Materials=preload("res://scripts/ember_voxel_surface_materials.gd")
const Editor=preload("res://addons/ember_import/ember_compact_material_pattern_dialog.gd")
const Road=preload("res://scripts/prototypes/ember_sand_road_recipe.gd")
var errors: Array[String]=[]
func _initialize() -> void:run.call_deferred()
func check(ok: bool,label: String) -> void:
	if not ok:errors.append(label);push_error(label)
func run() -> void:
	var out:=OS.get_cmdline_user_args()[0].replace("\\","/")
	var old=load(out.path_join("before/content/terrain_materials/cartoon_sand.tres"))
	var road:=Materials.load_compact_terrain_variant("cartoon_sand")
	var soil:=Materials.load_compact_terrain_variant("soil_grain")
	check(road.validation_errors().is_empty(),"road validates")
	check(road.base_color.is_equal_approx(Road.PAINTED_BASE_COLOR) and is_equal_approx(road.pattern_size_m,1.5),"accepted road tint and span")
	check(road.albedo_texture==soil.albedo_texture,"shared accepted artwork, one source")
	check(not road.albedo_relief_enabled and road.albedo_periodic and road.pixel_relief==0,"new road colour never adds height")
	for key in Editor.EDIT_FIELDS:
		if key not in ["base_color","albedo_texture","albedo_periodic","albedo_relief_enabled"]:check(road.get(key)==old.get(key),"original authored channel retained "+key)
	var image:=road.albedo_texture.get_image().duplicate() as Image
	if image.is_compressed():image.decompress()
	image.convert(Image.FORMAT_RGBA8);image.clear_mipmaps()
	var expected:=Road.painted_image();expected.clear_mipmaps()
	check(image.get_data()==expected.get_data() and image.get_size()==Vector2i(256,256),"exact accepted painted road artwork")
	var path:="user://road-editor-transfer.tres"
	check(ResourceSaver.save(road.duplicate(true),path)==OK,"fixture material saved")
	var panel:=Editor.new();root.add_child(panel);root.add_child(panel.parameters_panel);panel.pattern_path_override=path
	check(panel.open_variant("cartoon_sand","sand"),"ordinary material editor opens road")
	panel._tones[0].color_changed.emit(Color("a08060"))
	check(panel.is_dirty() and panel._draft.base_color.is_equal_approx(Color("a08060")),"manual road tint edits draft")
	panel.undo_edit();check(panel._draft.base_color.is_equal_approx(Road.PAINTED_BASE_COLOR),"manual tint Undo")
	panel.redo_edit();check(panel._draft.base_color.is_equal_approx(Color("a08060")),"manual tint Redo")
	panel.undo_edit()
	panel._texture_options.albedo_relief_enabled.button_pressed=true;panel.undo_edit()
	check(not panel._draft.albedo_relief_enabled,"PNG relief Undo")
	check(panel._save(),"normal save")
	var saved=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	check(saved.base_color.is_equal_approx(road.base_color) and saved.albedo_texture.resource_path==road.albedo_texture.resource_path and saved.albedo_periodic and not saved.albedo_relief_enabled,"saved road tint/artwork/flags reopen")
	check(panel.open_variant("cartoon_sand","sand"),"reopen material editor")
	panel._finish_sliders.pattern_size_m.value=2.0;panel.cancel_edit()
	check(is_equal_approx(ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP).pattern_size_m,1.5),"discard preserves saved road scale")
	var roles:=PackedStringArray(["","stone","sand","grass","soil"])
	var ids:=PackedStringArray(["","cartoon_stone","cartoon_sand","cartoon_grass","soil_grain"])
	var before:=Materials.compact_terrain_material();var after:=Materials.compact_terrain_material()
	Materials.set_compact_terrain_roles(before,roles,ids,PackedColorArray(),{"cartoon_sand":old})
	Materials.set_compact_terrain_roles(after,roles,ids)
	check(road.albedo_texture.get_image().get_size()==Vector2i(256,256),"bank never resizes the shared source image")
	var lookup: Image=after.get_shader_parameter("png_lookup").get_image();var entry:=lookup.get_pixel(2,0)
	check(entry.b==-3 and entry.a==1 and is_equal_approx(entry.g,1.5),"normal runtime binding stores road role/scale/colour-only")
	check(entry.r==lookup.get_pixel(4,0).r,"road and soil share one runtime PNG layer")
	for key in ["finish_lookup","detail_lookup","surface_lookup","roughness_atlas","side_roughness_atlas","style_rim_lookup","grass_light_lookup"]:
		check(before.get_shader_parameter(key).get_image().get_data()==after.get_shader_parameter(key).get_image().get_data(),"all height/finish/light bytes retained "+key)
	for key in ["png_lookup","png_mean_lookup","png_tint_lookup"]:
		var a: Image=before.get_shader_parameter(key).get_image();var b: Image=after.get_shader_parameter(key).get_image()
		for i in 256:
			if i==2:continue
			var x:=a.get_pixel(i,0);var y:=b.get_pixel(i,0)
			# Layer indices are derived and may reorder when a shared PNG is first
			# encountered in an earlier slot. Every other material input stays exact.
			if key=="png_lookup":x.r=0;y.r=0
			check(x==y,"non-road sampling/mean/tint retained "+key+"/"+str(i))
	panel.free();print("ROAD_EDITOR_TRANSFER ","PASS" if errors.is_empty() else errors);quit(0 if errors.is_empty() else 1)
