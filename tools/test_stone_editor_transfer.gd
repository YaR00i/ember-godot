extends SceneTree
const Materials=preload("res://scripts/ember_voxel_surface_materials.gd")
const Editor=preload("res://addons/ember_import/ember_compact_material_pattern_dialog.gd")
const Recipe=preload("res://scripts/prototypes/ember_natural_rock_recipe.gd")
var errors: Array[String]=[]
func _initialize() -> void:run.call_deferred()
func check(ok: bool,label: String) -> void:
	if not ok:errors.append(label);push_error(label)
func run() -> void:
	var out:=OS.get_cmdline_user_args()[0].replace("\\","/")
	var old=load(out.path_join("before/content/terrain_materials/cartoon_stone.tres"))
	var stone:=Materials.load_compact_terrain_variant("cartoon_stone")
	check(stone.validation_errors().is_empty(),"stone validates")
	check(stone.base_color.is_equal_approx(Color("90938f")) and is_equal_approx(stone.pattern_size_m,2.4),"reviewed pigment tint/scale")
	check(stone.albedo_periodic and not stone.albedo_relief_enabled and stone.pixel_relief==old.pixel_relief,"new artwork cannot add luminance height")
	for key in Editor.EDIT_FIELDS:
		if key not in ["base_color","albedo_texture","albedo_periodic","albedo_relief_enabled","pattern_size_m","style_rim_custom","style_rim_enabled","style_rim_strength","style_rim_width_mm","depth_mm","form_pull_mm"]:check(stone.get(key)==old.get(key),"original authored channel retained "+key)
	var image:=stone.albedo_texture.get_image().duplicate() as Image
	if image.is_compressed():image.decompress()
	image.convert(Image.FORMAT_RGBA8);image.clear_mipmaps()
	var expected:=Recipe.painted_image();expected.clear_mipmaps()
	check(image.get_size()==Vector2i(256,256) and image.get_data()==expected.get_data(),"exact raw B/C paint without added fracture lines or new height")
	var path:="user://stone-editor-transfer.tres"
	check(ResourceSaver.save(stone.duplicate(true),path)==OK,"fixture material saved")
	var panel:=Editor.new();root.add_child(panel);root.add_child(panel.parameters_panel);panel.pattern_path_override=path
	check(panel.open_variant("cartoon_stone","stone"),"ordinary material editor opens stone")
	panel._tones[0].color_changed.emit(Color("809080"));panel.undo_edit()
	check(panel._draft.base_color.is_equal_approx(stone.base_color),"tint Undo")
	panel.redo_edit();check(panel.is_dirty() and panel._draft.base_color.is_equal_approx(Color("809080")),"tint Redo");panel.undo_edit()
	panel._texture_options.albedo_relief_enabled.button_pressed=true
	panel.undo_edit();check(not panel._draft.albedo_relief_enabled,"relief option Undo")
	panel.redo_edit();check(panel._draft.albedo_relief_enabled,"relief option Redo");panel.undo_edit()
	panel._grid.size=Vector2(256,256);panel._select_channel(0);panel._begin_stroke();panel._grid.paint_at(Vector2(8,8),2);panel._finish_stroke()
	panel.undo_edit();check(panel._draft.pixels==stone.pixels,"fallback painting Undo")
	check(panel._save(),"ordinary Save")
	var saved=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	check(saved.albedo_texture.resource_path==stone.albedo_texture.resource_path and saved.base_color.is_equal_approx(stone.base_color) and saved.albedo_periodic and not saved.albedo_relief_enabled and is_equal_approx(saved.pattern_size_m,2.4),"saved material reopens with same artwork/flags/tint/scale")
	check(panel.open_variant("cartoon_stone","stone"),"editor Reopen")
	panel._finish_sliders.pattern_size_m.value=3.0;panel.cancel_edit()
	check(is_equal_approx(ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP).pattern_size_m,2.4),"Discard never changes saved scale")
	var roles:=PackedStringArray(["","stone","sand","grass","soil"])
	var ids:=PackedStringArray(["","cartoon_stone","cartoon_sand","cartoon_grass","soil_grain"])
	var before:=Materials.compact_terrain_material();var after:=Materials.compact_terrain_material()
	Materials.set_compact_terrain_roles(before,roles,ids,PackedColorArray(),{"cartoon_stone":old})
	Materials.set_compact_terrain_roles(after,roles,ids)
	var entry: Color=after.get_shader_parameter("png_lookup").get_image().get_pixel(1,0)
	check(entry.r>0.5 and entry.b==-4.0 and entry.a==1 and is_equal_approx(entry.g,2.4),"normal runtime colour-only stone projection")
	# 20 Oct: stone rim is an explicit material setting (custom, 0.5, frame 10 mm), validated elsewhere.
	check(stone.style_rim_custom and stone.style_rim_enabled and is_equal_approx(stone.style_rim_strength,0.5),"stone keeps the accepted rim setting")
	for key in ["finish_lookup","detail_lookup","roughness_atlas","side_roughness_atlas","grass_light_lookup"]:
		check(before.get_shader_parameter(key).get_image().get_data()==after.get_shader_parameter(key).get_image().get_data(),"height/finish/lighting bytes exact "+key)
	for key in ["png_lookup","png_mean_lookup","png_tint_lookup","surface_lookup"]:
		var a: Image=before.get_shader_parameter(key).get_image();var b: Image=after.get_shader_parameter(key).get_image()
		for slot in 256:
			var x:=a.get_pixel(slot,0);var y:=b.get_pixel(slot,0)
			if slot==1:
				if key=="surface_lookup":x.r=0;y.r=0;check(x==y,"only stone scale changes in surface lookup")
				continue
			check(x==y,"other material lookup exact "+key+"/"+str(slot))
	for key in ["pattern_atlas","side_pattern_atlas"]:
		var a: Image=before.get_shader_parameter(key).get_image();var b: Image=after.get_shader_parameter(key).get_image()
		for y in a.get_height():
			for x in 16:
				if y>=16 and y<32:check(a.get_pixel(x,y).a==b.get_pixel(x,y).a,"stone authored relief exact")
				else:check(a.get_pixel(x,y)==b.get_pixel(x,y),"other fallback artwork exact")
	# The existing POM binding remains optional and its separate height input
	# survives publication of the new colour bank. No automatic POM activation.
	check(after.shader==before.shader and not after.shader.code.contains("#define EMBER_TERRAIN_MATERIAL_DEPTH"),"ordinary material keeps its previous shader/features")
	var height: Texture2D=load("res://content/terrain_materials/textures/material_depth_study/stone_height.png")
	var cover:=Image.create(1,1,false,Image.FORMAT_RF);cover.fill(Color.RED)
	after.shader=Materials.compact_terrain_depth_shader()
	check(Materials.bind_compact_terrain_depth(after,height,ImageTexture.create_from_image(cover),Vector2i(1,2),0.04),"existing optional depth binding works")
	Materials.set_compact_terrain_roles(after,roles,ids)
	check(after.get_shader_parameter("material_depth_height")==height and is_equal_approx(after.get_shader_parameter("material_depth_amplitude_m"),0.04) and after.get_shader_parameter("material_depth_steps")==32,"publication never replaces existing POM height/amount/steps")
	panel.free();print("STONE_EDITOR_TRANSFER ","PASS" if errors.is_empty() else errors);quit(0 if errors.is_empty() else 1)
