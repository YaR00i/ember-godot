extends SceneTree

const Model = preload("res://addons/ember_import/ember_voxel_sculpt_model.gd")
const Workspace = preload("res://addons/ember_import/ember_voxel_sculpt_workspace.gd")
const Profiles = preload("res://addons/ember_import/ember_voxel_brush_profiles.gd")
const ViewStore = preload("res://addons/ember_import/ember_surface_editor_view_store.gd")
var errors: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition: errors.append(message)

func _init() -> void:
	_run.call_deferred()

func fixture() -> EmberVoxelModelResource:
	var source := EmberVoxelModelResource.new()
	source.model_id = "sand_pattern_fixture"
	source.display_name = "Песок · крупные пятна · проба"
	source.voxels_per_block = 16
	source.size_blocks = Vector3i(4,4,4)
	source.height_voxels = 64
	source.palette = PackedColorArray([Color.TRANSPARENT,Color("846c4d"),Color("635239"),Color("378caf")])
	var grid := source.grid_size()
	source.voxels.resize(grid.x*grid.y*grid.z)
	for z in grid.z:
		for x in grid.x:
			var height := 24-roundi(12*smoothstep(0.1,0.85,float(x)/63))
			for y in height+1: source.voxels[Model.index_of(Vector3i(x,y,z),grid)] = 1
	source.surface_fill_levels.resize(grid.x*grid.z)
	source.surface_fill_levels.fill(25)
	source.surface_fill_materials.resize(grid.x*grid.z)
	source.surface_fill_materials.fill(Model.SURFACE_FILL_WATER)
	source.surface_fill_palette.resize(grid.x*grid.z)
	source.surface_fill_palette.fill(3)
	return source

func pattern(source: EmberVoxelModelResource, a: Vector3i, b: Vector3i, scale := 24, amount := 35, seed := 7, coarse := false) -> Dictionary:
	return Model.surface_pattern_segment_changes(source,a,b,1,2,32,scale,amount,seed,coarse)

func screen_for(workspace: Control, cell: Vector3i) -> Vector2:
	return workspace._camera.unproject_position((Vector3(cell)+Vector3(.5,1,.5))/16)*workspace._viewport_container.size/Vector2(workspace._viewport.size)

func _run() -> void:
	var source := fixture()
	var before := source.voxels.duplicate()
	var heights := Model.column_heights(before,source.grid_size())
	var a := Vector3i(0,24,32)
	var b := Vector3i(63,12,32)
	var started := Time.get_ticks_usec()
	var delta := pattern(source,a,b)
	print("SAND_RADIUS32_SEGMENT_MS ",(Time.get_ticks_usec()-started)/1000.0)
	check(not delta.is_empty(),"no sand patches")
	for index in delta:
		var y := int(index)/(64*64)
		var column := int(index)%(64*64)
		var x := column%64
		var z := column/64
		var lowest := int(heights[column])
		for offset in [Vector2i.RIGHT,Vector2i.LEFT,Vector2i.UP,Vector2i.DOWN]:
			var neighbor: Vector2i = Vector2i(x,z)+offset
			lowest = mini(lowest,int(heights[neighbor.x+neighbor.y*64]) if neighbor.x >= 0 and neighbor.y >= 0 and neighbor.x < 64 and neighbor.y < 64 else -1)
		check(y == heights[column] or y > lowest,"painted buried voxel")
		check(delta[index].before != 0 and delta[index].after == 2,"created geometry or unselected color")
	source.voxels = Model.values_with_changes(before,delta,true)
	var result := source.voxels.duplicate()
	check(pattern(source,b,a).is_empty(),"repeat changed pattern")
	check(Model.column_heights(result,source.grid_size()) == heights,"changed terrain heights")
	check(source.validation_errors().is_empty(),"invalid resource")
	for index in before.size(): check((before[index] != 0) == (result[index] != 0),"occupied geometry changed")
	for coarse in [false,true]:
		var whole := fixture()
		whole.voxels = Model.values_with_changes(whole.voxels,pattern(whole,a,b,24,35,7,coarse),true)
		var split := fixture()
		for x in range(0,63,7):
			var d := pattern(split,Vector3i(x,24,32),Vector3i(mini(x+7,63),12,32),24,35,7,coarse)
			split.voxels = Model.values_with_changes(split.voxels,d,true)
		check(split.voxels == whole.voxels,"segment density / coarse="+str(coarse))
	check(pattern(fixture(),a,b,8) != delta,"size inert")
	check(pattern(fixture(),a,b,24,65) != delta,"coverage inert")
	check(pattern(fixture(),a,b,24,35,8) != delta,"seed inert")
	check(pattern(fixture(),a,b,24,0).is_empty(),"coverage0 not base")
	check(pattern(fixture(),a,b,24,100).size() > delta.size(),"coverage100 not all patches")
	var quiet := fixture()
	quiet.voxels = result
	quiet.voxels = Model.values_with_changes(result,pattern(quiet,a,b,24,0),true)
	check(quiet.voxels == before,"base pass did not erase old patches")
	var p := Profiles.normalize_profile({"paint_mode":"sand","sand_scale":999,"sand_coverage":-8,"sand_palette":0,"sand_seed":-3})
	check(p.paint_mode == "sand" and p.sand_scale == 64 and p.sand_coverage == 0 and p.sand_palette == 1 and p.sand_seed == 0,"profile clamps")
	check(Profiles.normalize_profile({}).paint_mode == "plain","legacy paint changed")
	root.size = Vector2i(1440,900)
	var undo := UndoRedo.new()
	var workspace := Workspace.new()
	workspace.setup(null,undo)
	root.add_child(workspace)
	workspace.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var editable := fixture()
	var path := "user://sand-pattern-%d.tres"%Time.get_ticks_usec()
	workspace.open_surface(editable,path,Rect2i(0,0,4,4))
	for frame in 8: await process_frame
	workspace._activate_tool_id(Model.TOOL_RAISE)
	workspace._select_option_metadata(workspace._relief_mode,Profiles.RELIEF_GENERATOR)
	workspace._select_option_metadata(workspace._relief_generator_style,Profiles.RELIEF_SHORE)
	workspace._on_brush_setting_changed()
	check(workspace._shore_paint_button.visible,"shore shortcut missing")
	workspace._shore_paint_button.pressed.emit()
	check(workspace._is_sand_paint() and workspace._sand_scale.visible and not workspace._depth.visible and not workspace._application_mode.visible,"shortcut/paint UI")
	workspace._select_option_metadata(workspace._radius,32)
	workspace._select_palette_color(1)
	workspace._select_option_metadata(workspace._sand_palette,2)
	workspace._sand_scale.value = 24
	workspace._sand_coverage.value = 35
	workspace._sand_seed = 7
	workspace._on_brush_setting_changed()
	check(not workspace.has_unsaved_changes(),"settings dirtied source")
	var store := ViewStore.new()
	store.import_data(workspace.export_editor_view_data())
	var profile: Dictionary = store.recall_brush_profiles()[Model.TOOL_PAINT]
	check(profile.paint_mode == "sand" and profile.sand_palette == 2 and profile.sand_scale == 24 and profile.sand_coverage == 35 and profile.sand_seed == 7,"profile serialization")
	workspace._activate_tool_id(Model.TOOL_ADD)
	workspace._activate_tool_id(Model.TOOL_PAINT)
	check(workspace._is_sand_paint() and workspace._sand_scale.visible,"tool switch lost paint")
	workspace.import_editor_view_data(store.export_data())
	check(workspace._sand_seed == 7 and workspace._sand_palette.get_selected_metadata() == 2,"editor reopen settings")
	var screen := screen_for(workspace,Vector3i(12,heights[12+32*64],32))
	workspace._begin_stroke(screen)
	check(workspace._stroke_active,"real pick under water failed")
	workspace._apply_sand_segment(a,b)
	workspace._finish_stroke()
	var edited := editable.voxels.duplicate()
	check(edited != before,"workspace pattern inert")
	undo.undo()
	check(editable.voxels == before,"one Undo")
	undo.redo()
	check(editable.voxels == edited,"one Redo")
	var original := fixture()
	check(editable.palette == original.palette and editable.surface_fill_levels == original.surface_fill_levels and editable.surface_fill_materials == original.surface_fill_materials and editable.surface_fill_palette == original.surface_fill_palette and editable.transparency.is_empty() and editable.collision_voxels.is_empty(),"palette/water/material/physics channels changed")
	check(workspace._save(),"save")
	var loaded := ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as EmberVoxelModelResource
	check(loaded != null and loaded.voxels == edited and loaded.surface_fill_palette == editable.surface_fill_palette,"save/reopen mismatch")
	var reopened := Workspace.new()
	reopened.setup(null,undo)
	root.add_child(reopened)
	reopened.visible = false
	reopened.open_surface(loaded,path,Rect2i(0,0,4,4))
	reopened.import_editor_view_data(store.export_data())
	reopened._activate_tool_id(Model.TOOL_PAINT)
	check(reopened._is_sand_paint() and reopened._sand_palette.get_selected_metadata() == 2 and reopened._sand_scale.value == 24 and reopened._sand_seed == 7,"fresh workspace reopen settings")
	reopened.free()
	workspace._sand_variant.pressed.emit()
	check(workspace._sand_seed == 8 and editable.voxels == edited,"variant applied without gesture")
	workspace._begin_stroke(screen)
	workspace._apply_sand_segment(a,b)
	check(editable.voxels != edited,"new variant inert")
	workspace._cancel_stroke()
	check(editable.voxels == edited,"cancel")
	workspace._begin_stroke(screen)
	workspace._apply_sand_segment(a,b)
	workspace._finish_stroke()
	workspace.discard_changes()
	check(editable.voxels == edited,"discard")
	workspace._edit_region_blocks = Rect2i(0,0,1,1)
	var inside := screen_for(workspace,Vector3i(8,heights[8+8*64],8))
	workspace._begin_stroke(inside)
	check(workspace._stroke_active,"region pick")
	workspace._apply_sand_segment(Vector3i(8,24,8),Vector3i(30,24,8))
	for index in edited.size():
		if index%64 >= 16 or (index/64)%64 >= 16: check(editable.voxels[index] == edited[index],"escaped region")
	workspace._cancel_stroke()
	workspace._edit_region_blocks = Rect2i(0,0,4,4)
	workspace._slice_height = 16
	workspace._begin_stroke(screen)
	check(not workspace._stroke_active and editable.voxels == edited,"slice painted hidden top")
	workspace._slice_height = -1
	workspace._locked_indices[Model.index_of(Vector3i(12,heights[12+32*64],32),editable.grid_size())] = true
	workspace._begin_stroke(screen)
	workspace._sand_coverage.set_value_no_signal(100)
	workspace._apply_sand_segment(a,b)
	var protected_index := Model.index_of(Vector3i(12,heights[12+32*64],32),editable.grid_size())
	check(editable.voxels[protected_index] == edited[protected_index],"locked voxel changed")
	workspace._cancel_stroke()
	workspace._locked_indices.clear()
	workspace._sand_coverage.set_value_no_signal(35)
	# Colors remain controllable through the canonical palette editor.
	workspace._apply_palette_operation(editable,{"kind":"set","index":2,"color":Color("4d4131")})
	check(editable.palette[2] == Color("4d4131") and editable.voxels == edited,"patch color edit changed pattern")
	undo.undo()
	check(editable.palette == original.palette and editable.voxels == edited,"patch palette Undo")
	workspace._apply_palette_operation(editable,{"kind":"merge","index":2,"target":1})
	check(workspace._sand_palette.get_selected_metadata() == 1,"merged patch color selection not remapped")
	undo.undo()
	workspace._select_option_metadata(workspace._sand_palette,2)
	workspace._select_option_metadata(workspace._sand_palette,3)
	workspace._on_brush_setting_changed()
	workspace._activate_tool_id(Model.TOOL_RAISE)
	workspace._apply_palette_operation(editable,{"kind":"merge","index":2,"target":1})
	check(workspace._tool_profiles[Model.TOOL_PAINT].sand_palette == 2,"inactive paint profile not remapped")
	undo.undo()
	workspace.import_editor_view_data(store.export_data())
	workspace._activate_tool_id(Model.TOOL_PAINT)
	workspace._select_palette_color(1)
	workspace._select_option_metadata(workspace._paint_mode,Profiles.PAINT_PLAIN)
	workspace._on_brush_setting_changed()
	check(workspace._depth.visible and not workspace._sand_scale.visible and workspace._is_oriented_brush_tool(Model.TOOL_PAINT),"plain paint regression")
	workspace._select_option_metadata(workspace._paint_mode,Profiles.PAINT_SAND)
	workspace._on_brush_setting_changed()
	workspace._rebuild_visual()
	if DisplayServer.get_name() != "headless":
		workspace._show_grid = false
		workspace._show_region = false
		workspace._grid.visible = false
		workspace._rebuild_region_overlay()
		workspace._ortho_size = 5.4
		workspace._update_camera()
		workspace._select_option_metadata(workspace._surface_layer_view,"floor")
		workspace._on_surface_layer_view_changed(1)
		for frame in 20: await process_frame
		RenderingServer.force_draw(false)
		root.get_texture().get_image().save_png("user://sand_pattern_floor_native.png")
		workspace._select_option_metadata(workspace._surface_layer_view,"combined")
		workspace._on_surface_layer_view_changed(0)
		for frame in 20: await process_frame
		RenderingServer.force_draw(false)
		root.get_texture().get_image().save_png("user://sand_pattern_water_native.png")
		print("SAND_NATIVE_CAPTURE ",ProjectSettings.globalize_path("user://sand_pattern_floor_native.png"))
	workspace.free()
	undo.clear_history()
	undo.free()
	for message in errors: push_error(message)
	print("test_voxel_surface_pattern: ","PASS" if errors.is_empty() else "FAIL"," · ",errors.size())
	quit(0 if errors.is_empty() else 1)
