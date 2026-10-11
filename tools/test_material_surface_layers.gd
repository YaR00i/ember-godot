extends SceneTree
const Pattern=preload("res://scripts/ember_compact_terrain_pattern.gd")
const Materials=preload("res://scripts/ember_voxel_surface_materials.gd")
const LayerEditor=preload("res://addons/ember_import/ember_compact_material_pattern_dialog.gd")
func _init() -> void: _run.call_deferred()
func _run() -> void:
	var legacy=Materials.load_compact_terrain_variant("grass_surface")
	assert(legacy.surface_pixels("relief")==legacy.pixels)
	assert(legacy.surface_pixels("relief",true)==legacy.side_pixels)
	assert(legacy.surface_pixels("roughness").count(0)==256 and legacy.pattern_size_m==4)
	for id in ["grass_impasto","soil_grain"]:
		var source=Materials.load_compact_terrain_variant(id)
		assert(source.validation_errors().is_empty() and source.relief_pixels.size()==256 and source.roughness_pixels.size()==256)
		for field in ["relief_pixels","side_relief_pixels","roughness_pixels","side_roughness_pixels"]:
			var broken=source.duplicate(true); broken.set(field,PackedByteArray([0])); assert(not broken.validation_errors().is_empty())
			var invalid=source.get(field).duplicate(); invalid[2]=3;broken.set(field,invalid);assert(not broken.validation_errors().is_empty())
		for pair in [["pattern_size_m",0.0],["pattern_size_m",INF],["roughness_variation",NAN],["roughness_variation",0.6]]:
			var broken=source.duplicate(true);broken.set(pair[0],pair[1]);assert(not broken.validation_errors().is_empty())
		var copy=source.duplicate(true);copy.base_color=Color.WHITE;copy.light_color=Color.WHITE;copy.shadow_color=Color.WHITE
		assert(copy.surface_pixels("relief")==source.relief_pixels and copy.surface_pixels("roughness")==source.roughness_pixels)
		var mat=Materials.compact_terrain_material();assert(not mat.get_shader_parameter("independent_surface_enabled"));Materials.set_compact_terrain_roles(mat,PackedStringArray(["",source.role_id]),PackedStringArray(["",id]))
		assert(mat.get_shader_parameter("independent_surface_enabled"))
		var alpha=(mat.get_shader_parameter("pattern_atlas") as Texture2D).get_image().get_pixel(0,16).a
		assert(absf(alpha-float([0.5,1.0,0.0][source.relief_pixels[0]]))<0.005)
		var rough=(mat.get_shader_parameter("roughness_atlas") as Texture2D).get_image().get_pixel(0,16).r
		assert(absf(rough-float([0.5,1.0,0.0][source.roughness_pixels[0]]))<0.005)
		var parameters=(mat.get_shader_parameter("surface_lookup") as Texture2D).get_image().get_pixel(1,0)
		assert(is_equal_approx(parameters.r,source.pattern_size_m) and is_equal_approx(parameters.g,source.roughness_variation))
	var finish=load("res://content/world_terrains/ground_finish_study.res")
	var reference=load("res://content/world_terrains/ground_grass_painted_study.res")
	assert(finish.same_terrain_geometry(reference))
	assert(finish.palette_material_ids[2]=="grass_impasto" and finish.palette_material_ids[4]=="soil_grain")
	var file="user://ember-tests/surface-layer-fixture.tres";DirAccess.make_dir_recursive_absolute(file.get_base_dir()); assert(ResourceSaver.save(legacy.duplicate(true),file)==OK)
	var panel=LayerEditor.new();root.add_child(panel);root.add_child(panel.parameters_panel);panel.pattern_path_override=file;assert(panel.open_role("grass"));
	for i in 3: await process_frame
	panel._grid.size=Vector2(256,256)
	var original=panel._draft.pixels.duplicate();panel._select_channel(1);panel._begin_stroke()
	panel._grid.paint_at(Vector2(8,8),1);panel._finish_stroke()
	assert(panel._draft.pixels==original and panel._draft.relief_pixels.size()==256)
	panel.undo_edit();assert(panel._draft.relief_pixels.is_empty());panel.redo_edit();assert(panel._draft.relief_pixels.size()==256)
	panel._select_channel(2);panel._select_face(1);panel._begin_stroke();panel._grid.paint_at(Vector2(8,8),2);panel._finish_stroke()
	assert(panel._draft.side_roughness_pixels.size()==256 and panel._draft.side_pixels==legacy.side_pixels)
	panel._file_import=false;panel._on_file_selected("user://ember-tests/rough-side.png");var rough_before=panel._draft.side_roughness_pixels.duplicate()
	panel._set_pixels(PackedByteArray(),true,"roughness");panel._file_import=true;panel._on_file_selected("user://ember-tests/rough-side.png")
	assert(panel._draft.side_roughness_pixels==rough_before)
	panel._finish_sliders.pattern_size_m.value=1.6;panel._finish_sliders.roughness_variation.value=0.17;
	for i in 3: await process_frame
	panel._save()
	var saved=ResourceLoader.load(file,"",ResourceLoader.CACHE_MODE_IGNORE) as Pattern
	assert(saved.pixels==original and saved.relief_pixels.size()==256 and saved.side_roughness_pixels==rough_before and is_equal_approx(saved.pattern_size_m,1.6))
	assert(panel.open_role("grass"));panel._select_channel(1);panel._set_pixels(PackedByteArray(),false,"relief");panel.cancel_edit()
	assert((ResourceLoader.load(file,"",ResourceLoader.CACHE_MODE_IGNORE) as Pattern).relief_pixels==saved.relief_pixels)
	panel.free();print("SURFACE_LAYERS PASS independent data/validation/legacy/atlas/per-layer Undo/PNG/Save-Cancel-Reopen");quit()
