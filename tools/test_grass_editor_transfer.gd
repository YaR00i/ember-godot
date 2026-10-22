extends SceneTree
const Materials=preload("res://scripts/ember_voxel_surface_materials.gd")
const Editor=preload("res://addons/ember_import/ember_compact_material_pattern_dialog.gd")
const TerrainProjection=preload("res://scripts/prototypes/ember_terrain_pilot_projection.gd")
var errors: Array[String]=[]
func _initialize() -> void:run.call_deferred()
func check(ok: bool,label: String) -> void:
	if not ok:errors.append(label);push_error(label)
func run() -> void:
	var out:=OS.get_cmdline_user_args()[0].replace("\\","/")
	var old=load(out.path_join("before/content/terrain_materials/cartoon_grass.tres"))
	var grass:=Materials.load_compact_terrain_variant("cartoon_grass")
	var accepted=load("res://content/terrain_materials/painted_light_grass.tres")
	check(grass.validation_errors().is_empty(),"material validates")
	check(grass.base_color==accepted.base_color and grass.pattern_size_m==accepted.pattern_size_m,"exact accepted base tint and2m scale")
	for field in Editor.EDIT_FIELDS:
		if field.begins_with("grass_light_"):check(grass.get(field)==accepted.get(field),"accepted light profile "+field)
		elif field not in ["base_color","albedo_texture","albedo_periodic","albedo_relief_enabled","pattern_size_m"]:check(grass.get(field)==old.get(field),"other authored channel preserved "+field)
	var actual:=grass.albedo_texture.get_image().duplicate() as Image
	if actual.is_compressed():actual.decompress()
	actual.convert(Image.FORMAT_RGBA8);actual.clear_mipmaps()
	var expected: Image=accepted.albedo_texture.get_image().duplicate();expected.clear_mipmaps();expected.convert(Image.FORMAT_RGBA8)
	check(actual.get_size()==expected.get_size() and actual.get_data()==expected.get_data(),"exact accepted artwork, no repaint or rescale")
	check(grass.albedo_periodic and not grass.albedo_relief_enabled and grass.pixel_relief==old.pixel_relief,"periodic colour adds no new relief")
	var path:="user://grass-editor-transfer.tres"
	check(ResourceSaver.save(grass.duplicate(true),path)==OK,"fixture saved")
	var projection:=TerrainProjection.new();projection.document=load("res://content/world_terrains/material_depth_study.res").working_copy()
	projection.document.palette_surface_roles=PackedStringArray(["","grass"]);projection.document.palette_material_ids=PackedStringArray(["","cartoon_grass"])
	projection._ground_material=Materials.compact_terrain_material()
	Materials.set_compact_terrain_roles(projection._ground_material,projection.document.palette_surface_roles,projection.document.palette_material_ids)
	var panel:=Editor.new();root.add_child(panel);root.add_child(panel.parameters_panel);panel.pattern_path_override=path
	panel.light_profile_previewed.connect(projection.preview_shared_material_light)
	check(panel.open_variant("cartoon_grass","grass"),"existing editor opens material")
	panel._finish_sliders.grass_light_low.value=0.78
	check(is_equal_approx(projection._ground_material.get_meta("ember_grass_light_image").get_pixel(1,0).r,0.78),"live preview reaches existing projection")
	panel.undo_edit();check(is_equal_approx(panel._draft.grass_light_low,grass.grass_light_low),"light Undo")
	panel.redo_edit();check(is_equal_approx(panel._draft.grass_light_low,0.78),"light Redo");panel.undo_edit()
	panel._change_grass_light({"grass_light_warm":Color(0.9,1.0,1.1)})
	panel._tones[0].color_changed.emit(Color("608050"))
	check(panel._draft.grass_light_warm==Color(0.9,1.0,1.1),"manual base colour never overwrites light palette")
	panel.undo_edit();panel.undo_edit()
	panel._texture_options.albedo_relief_enabled.button_pressed=true;panel.undo_edit()
	check(not panel._draft.albedo_relief_enabled,"PNG option Undo")
	panel._grid.size=Vector2(256,256);panel._select_channel(0);panel._begin_stroke();panel._grid.paint_at(Vector2(8,8),2);panel._finish_stroke();panel.undo_edit()
	check(panel._draft.pixels==grass.pixels,"manual fallback paint Undo")
	check(panel._save(),"ordinary Save")
	var reopened=ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	for field in Editor.EDIT_FIELDS:
		if field=="albedo_texture":check(reopened.albedo_texture.resource_path==grass.albedo_texture.resource_path,"PNG path save/reopen")
		else:check(reopened.get(field)==grass.get(field),"save/reopen "+field)
	check(panel.open_variant("cartoon_grass","grass"),"editor Reopen")
	panel._finish_sliders.grass_light_shadow_fill.value=0.12;panel.cancel_edit()
	check(is_equal_approx(ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP).grass_light_shadow_fill,grass.grass_light_shadow_fill),"Discard preserves saved profile")
	var roles:=PackedStringArray(["","stone","sand","grass","soil"])
	var ids:=PackedStringArray(["","cartoon_stone","cartoon_sand","cartoon_grass","soil_grain"])
	var before:=Materials.compact_terrain_material();var after:=Materials.compact_terrain_material()
	Materials.set_compact_terrain_roles(before,roles,ids,PackedColorArray(),{"cartoon_grass":old});Materials.set_compact_terrain_roles(after,roles,ids)
	var metadata: Color=after.get_shader_parameter("png_lookup").get_image().get_pixel(3,0)
	check(metadata.b==-2 and metadata.a==1 and metadata.g==2.0,"ordinary runtime uses grass role/periodic2m colour-only metadata")
	var profile: Image=after.get_shader_parameter("grass_light_lookup").get_image()
	check(profile.get_pixel(3,0).is_equal_approx(Color(grass.grass_light_low,grass.grass_light_tint_strength,grass.grass_light_shadow_fill,1)),"runtime light settings")
	check(profile.get_pixel(3,1).is_equal_approx(grass.grass_light_cool) and profile.get_pixel(3,2).is_equal_approx(grass.grass_light_warm) and profile.get_pixel(3,3).is_equal_approx(grass.grass_light_shadow_color),"runtime warm/cool/shadow palette")
	for key in ["finish_lookup","detail_lookup","roughness_atlas","side_roughness_atlas","style_rim_lookup"]:
		check(before.get_shader_parameter(key).get_image().get_data()==after.get_shader_parameter(key).get_image().get_data(),"height/finish/roughness/rim bytes exact "+key)
	for key in ["surface_lookup","png_lookup","png_mean_lookup","png_tint_lookup","grass_light_lookup"]:
		var a: Image=before.get_shader_parameter(key).get_image();var b: Image=after.get_shader_parameter(key).get_image()
		for y in a.get_height():
			for slot in 256:
				if slot==3:continue
				check(a.get_pixel(slot,y)==b.get_pixel(slot,y),"other material lookup inputs exact "+key+"/"+str(slot))
	print("GRASS_BANK_SIZE before=",before.get_shader_parameter("png_albedo_bank").get_width()," after=",after.get_shader_parameter("png_albedo_bank").get_width())
	panel.free();projection.free();print("GRASS_EDITOR_TRANSFER ","PASS" if errors.is_empty() else errors);quit(0 if errors.is_empty() else 1)
