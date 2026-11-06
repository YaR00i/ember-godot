extends SceneTree
## Real material dialog and terrain brush, isolated user:// documents only.
const Materials = preload("res://scripts/ember_voxel_surface_materials.gd")
const Dialog = preload("res://addons/ember_import/ember_compact_material_pattern_dialog.gd")
const Brush = preload("res://addons/ember_import/ember_compact_terrain_brush.gd")
var errors: Array[String] = []
func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	if not value: errors.append(message); printerr("FAIL ", message)

func run() -> void:
	# A bounded dense fixture, rather than assuming the author map still stores dense arrays.
	var source = load("res://content/world_terrains/landscape_compact.res").dense_window(Rect2i(0,192,64,32))
	var slot: int = source.palette_material_ids.find("paving")
	check(slot > 0 and source.validation_errors().is_empty(), "map has valid paintable paving")
	var material := Materials.compact_terrain_material()
	material.shader = Materials.compact_terrain_bank_depth_shader()
	Materials.set_compact_terrain_roles(material, source.palette_surface_roles, source.palette_material_ids, source.palette)
	Materials.set_terrain_depth_profiles(material, source.palette_surface_roles, source.palette_material_ids)
	check(is_equal_approx(material.get_meta("ember_depth_profiles").get_pixel(slot,0).g,0.03), "paving profile has authored depth")
	var grass: int = source.palette_surface_roles.find("grass")
	check(is_equal_approx(material.get_meta("ember_depth_profiles").get_pixel(grass,0).g,Materials.load_compact_terrain_variant(source.palette_material_ids[grass]).depth_mm*0.001), "grass uses its own library depth")
	var path := "user://paving-authoring-check.tres"
	var pattern = Materials.load_compact_terrain_variant("paving")
	check(pattern != null and pattern.validation_errors().is_empty(), "paving validates")
	var object_material := ShaderMaterial.new()
	var solid = preload("res://scripts/ember_voxel_solid_surface.gd")
	object_material.shader = solid.solid_depth_shader()
	object_material.set_meta("ember_detailed_depth",true)
	Materials.set_terrain_depth_profiles(object_material,PackedStringArray(["","stone"]),PackedStringArray(["","paving"]))
	check(object_material.get_meta("ember_depth_source_textures")[0] == pattern.depth_texture, "solid material uses the same authored height")
	check(ResourceSaver.save(pattern,path) == OK, "save isolated material fixture")
	var dialog := Dialog.new()
	root.add_child(dialog)
	root.add_child(dialog.parameters_panel)
	dialog.hide();dialog.parameters_panel.hide()
	dialog.pattern_path_override = path
	dialog.light_profile_previewed.connect(func(draft, id): Materials.set_terrain_depth_profiles(material, source.palette_surface_roles, source.palette_material_ids, {id:draft}))
	dialog.pattern_scale_previewed.connect(func(draft, _id): Materials.update_terrain_pattern_scale(material, slot, draft))
	check(dialog.open_variant("paving","stone"), "editor opens paving")
	dialog._finish_sliders.pattern_size_m.value = 2.0
	check(is_equal_approx(material.get_meta("ember_png_lookup_image").get_pixel(slot,0).g,2.0), "paving image size previews live")
	check(is_equal_approx(material.get_meta("ember_surface_lookup_image").get_pixel(slot,0).r,2.0), "paving pattern size previews live")
	dialog.undo_edit()
	check(is_equal_approx(material.get_meta("ember_png_lookup_image").get_pixel(slot,0).g,pattern.pattern_size_m), "paving size Undo")
	dialog.redo_edit()
	dialog._change_depth({"depth_mm":12.0})
	check(is_equal_approx(material.get_meta("ember_depth_profiles").get_pixel(slot,0).g,0.012), "editor depth previews on shared material")
	dialog.undo_edit()
	check(is_equal_approx(dialog._draft.depth_mm,30.0), "depth Undo")
	dialog.redo_edit()
	check(is_equal_approx(dialog._draft.depth_mm,12.0), "depth Redo")
	var height: Texture2D = dialog._draft.depth_texture
	dialog._change_texture(null,"depth_texture")
	check(dialog._draft.depth_texture == null, "editor switches height source")
	dialog.undo_edit()
	check(dialog._draft.depth_texture == height, "height source Undo")
	check(dialog._save(true), "material editor saves")
	dialog._finish_sliders.pattern_size_m.value = 3.0
	dialog._change_depth({"depth_mm":2.0})
	dialog.cancel_edit()
	check(is_equal_approx(material.get_meta("ember_png_lookup_image").get_pixel(slot,0).g,2.0), "discard restores saved paving size")
	check(is_equal_approx(material.get_meta("ember_depth_profiles").get_pixel(slot,0).g,0.012), "discard restores material preview")
	check(dialog.open_variant("paving","stone") and is_equal_approx(dialog._draft.depth_mm,12.0), "fresh material reopen preserves depth")
	check(is_equal_approx(dialog._draft.pattern_size_m,2.0), "fresh material reopen preserves size")
	check(dialog._draft.depth_texture.resource_path == height.resource_path, "height texture survives save/reopen")
	dialog.cancel_edit()
	var node := Node3D.new();root.add_child(node)
	var history := UndoRedo.new()
	var brush := Brush.new();brush.configure({"target":weakref(node),"resource":source},history,node)
	var before: PackedByteArray = source.top_materials.duplicate()
	var heights: PackedInt32Array = source.heights.duplicate()
	check(brush.begin("paint",0.5,1,slot,0,16,0,7,0,-99999,"detail"), "ordinary terrain brush accepts paving")
	var paint_point:=Vector2i(16,16)
	for i in source.top_materials.size():
		if source.top_materials[i]!=slot and source.heights[i]>0:
			paint_point=Vector2i(i%source.width,i/source.width);break
	brush.stamp(paint_point);brush.end()
	var painted: PackedByteArray = source.top_materials.duplicate()
	check(painted != before and source.heights == heights, "paving paint changes material only")
	history.undo();check(source.top_materials == before, "paving brush Undo")
	history.redo();check(source.top_materials == painted, "paving brush Redo")
	var terrain_path := "user://paving-map-authoring-check.res"
	check(ResourceSaver.save(source,terrain_path) == OK, "save painted fixture")
	var reopened = ResourceLoader.load(terrain_path,"",ResourceLoader.CACHE_MODE_IGNORE)
	check(reopened.top_materials == painted and reopened.palette_material_ids[slot] == "paving", "paint survives fresh reopen")
	history.clear_history();history.free();node.free()
	dialog.free()
	# The author-facing World Look panel edits real scene parameters through
	# the same history; the fixture stays outside the tree to avoid generation.
	var ui_scene := Node3D.new()
	var map := EmberMapLoader.new();map.name="Map";ui_scene.add_child(map);map.owner=ui_scene
	map.compact_terrain=source
	var props := Node3D.new();props.name="Props";map.add_child(props);props.owner=ui_scene
	var patch := Node3D.new();patch.name="GrassPatch";patch.set_script(load("res://scripts/ember_grass_patch.gd"));props.add_child(patch);patch.owner=ui_scene
	var panel = load("res://addons/ember_import/ember_world_look_panel.gd").new()
	root.add_child(panel);panel.hide()
	var ui_history := UndoRedo.new();panel.set_target(ui_scene,map,ui_history)
	check(panel._grass_paths.size() == 1, "editor discovers the grass patch")
	panel._commit("compact_depth_fade_near_m",6.0,16.0,false)
	panel._commit("compact_depth_fade_far_m",14.0,28.0,false)
	check(map.compact_depth_fade_near_m == 16.0 and map.compact_depth_fade_far_m == 28.0, "editor changes depth visibility distance")
	ui_history.undo();check(map.compact_depth_fade_far_m == 14.0, "depth distance Undo")
	ui_history.redo();check(map.compact_depth_fade_far_m == 28.0, "depth distance Redo")
	panel._commit("grass_density",100.0,75.0,false)
	check(patch.tufts_per_block == 75, "editor changes grass density")
	ui_history.undo();check(patch.tufts_per_block == 100, "grass density Undo")
	ui_history.redo();check(patch.tufts_per_block == 75, "grass density Redo")
	panel._commit("grass_width",5.0,12.0,false)
	check(patch.size_blocks == Vector2(12,4), "editor width preserves length")
	panel._commit("grass_seed",7,99.0,false)
	check(patch.scatter_seed == 99, "editor changes scatter variant")
	panel._commit("grass_x",0.0,4.0,false)
	check(patch.position.x == 64.0, "editor moves patch in metres")
	var packed := PackedScene.new();check(packed.pack(ui_scene) == OK, "pack editable grass scene")
	var scene_path := "user://grass-authoring-check.tscn"
	check(ResourceSaver.save(packed,scene_path) == OK, "save grass fixture")
	var fresh: Node = (ResourceLoader.load(scene_path,"",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate()
	var saved_patch: Node = fresh.get_node("Map/Props/GrassPatch")
	var saved_map: Node = fresh.get_node("Map")
	check(saved_map.compact_depth_fade_near_m == 16.0 and saved_map.compact_depth_fade_far_m == 28.0, "depth visibility distance survives fresh reopen")
	map.compact_depth_fade_far_m=40.0
	check(saved_map.compact_depth_fade_far_m==28.0, "discard keeps saved depth distance")
	check(saved_patch.tufts_per_block == 75 and saved_patch.size_blocks == Vector2(12,4) and saved_patch.scatter_seed == 99 and saved_patch.position.x == 64.0, "grass parameters survive fresh reopen")
	patch.tufts_per_block=10
	check(saved_patch.tufts_per_block==75, "discard keeps saved grass parameters")
	fresh.free();ui_history.clear_history();ui_history.free();panel.free();ui_scene.free()
	print("LANDSCAPE_MATERIAL_AUTHORING ",JSON.stringify({"pass":errors.is_empty(),"errors":errors,"fixtures":"user://", "manual":"mouse and visual acceptance open"}))
	quit(0 if errors.is_empty() else 1)
