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
	source.model_id = "coastal_workflow_fixture"
	source.display_name = "Пологий берег · песок · открытая вода"
	source.voxels_per_block = 16
	source.size_blocks = Vector3i(8,4,8)
	source.height_voxels = 64
	source.palette = PackedColorArray([Color.TRANSPARENT,Color("427637"),Color("846c4d"),Color("635239"),Color("378caf")])
	var grid := source.grid_size()
	source.voxels.resize(grid.x*grid.y*grid.z)
	for z in grid.z:
		for x in grid.x:
			for y in 41: source.voxels[Model.index_of(Vector3i(x,y,z),grid)] = 1
	return source

func screen_for(workspace: Control, cell: Vector3i) -> Vector2:
	return workspace._camera.unproject_position((Vector3(cell)+Vector3(.5,1,.5))/16)*workspace._viewport_container.size/Vector2(workspace._viewport.size)

func _run() -> void:
	var source := fixture()
	var baseline := source.voxels.duplicate()
	var foundation := Model.column_heights(baseline,source.grid_size())
	var a := Vector3i(8,40,64)
	var b := Vector3i(104,40,64)
	var settings := {"origin":Vector2(8,64),"height":40,"direction":0,"width":96,"roughness":0,"foundation":foundation}
	var delta := Model.generative_relief_segment_changes(source,baseline,a,b,1,32,12,24,0,7,0,"shore",false,{}, {},foundation,{},settings)
	source.voxels = Model.values_with_changes(baseline,delta,true)
	var once := source.voxels.duplicate()
	var edited_heights := Model.column_heights(once,source.grid_size())
	check(edited_heights[8+64*128] == 40 and edited_heights[104+64*128] == 28,"gentle endpoints")
	for x in range(8,104):
		check(edited_heights[x+64*128]-edited_heights[x+1+64*128] in [0,1],"gentle single-column cliff")
	var repeat := Model.generative_relief_segment_changes(source,once,a,b,1,32,12,24,0,7,0,"shore",false,{}, {},edited_heights,{},settings)
	check(repeat.is_empty(),"new gesture deepened the same shore/rim")
	var side := Model.generative_relief_segment_changes(source,once,Vector3i(8,40,88),Vector3i(104,40,88),1,32,12,24,0,7,0,"shore",false,{}, {},edited_heights,{},settings)
	source.voxels = Model.values_with_changes(once,side,true)
	check(Model.column_heights(source.voxels,source.grid_size())[64+88*128] == edited_heights[64+64*128],"adjacent gesture changed shore profile")
	# Compare both modes at the same plane41. Auto may legitimately find a
	# smaller closed pocket below a softly rounded brush end.
	var basin := Model.surface_fill_selection(source,Vector3i(104,28,64),12,Rect2i(),Model.column_heights(source.voxels,source.grid_size()))
	check(bool(basin.open) or (basin.columns as PackedInt32Array).is_empty(),"open coast at level41 unexpectedly accepted as basin")
	var open_fill := Model.open_surface_fill_selection(source,Vector3i(104,28,64),41,Rect2i(2,2,6,6))
	check(not open_fill.open and not open_fill.columns.is_empty(),"open water refused coast")
	for column in open_fill.columns:
		check(column%128 >= 32 and column/128 >= 32,"open fill escaped region")
	check(Model.open_surface_fill_selection(source,Vector3i(104,28,64),41,Rect2i(),PackedInt32Array(),8).truncated,"open water count limit")
	var edge_delta := Model.surface_pattern_segment_changes(source,Vector3i(104,28,64),Vector3i(127,28,64),2,3,32,24,0)
	check(not edge_delta.is_empty(),"step paint inert")
	var wall_count := 0
	var current_heights := Model.column_heights(source.voxels,source.grid_size())
	for index in edge_delta:
		var y := int(index)/(128*128)
		if y < current_heights[int(index)%(128*128)]: wall_count += 1
	check(wall_count > 0,"vertical walls omitted")
	check(not edge_delta.has(Model.index_of(Vector3i(64,1,64),source.grid_size())),"buried terrain painted")
	check(Profiles.normalize_profile({}).shore_slope == 0,"default shore not gentle")
	check(Profiles.normalize_profile({"shore_width":24}).shore_slope == 3,"legacy width silently changed")
	root.size = Vector2i(1440,900)
	var undo := UndoRedo.new()
	var workspace := Workspace.new()
	workspace.setup(null,undo)
	root.add_child(workspace)
	workspace.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var editable := fixture()
	var path := "user://coastal-workflow-%d.tres"%Time.get_ticks_usec()
	workspace.open_surface(editable,path,Rect2i(0,0,8,8))
	for frame in 8: await process_frame
	workspace._activate_tool_id(Model.TOOL_RAISE)
	workspace._select_option_metadata(workspace._relief_mode,Profiles.RELIEF_GENERATOR)
	workspace._select_option_metadata(workspace._relief_generator_style,Profiles.RELIEF_SHORE)
	workspace._select_option_metadata(workspace._radius,32)
	workspace._select_option_metadata(workspace._height_limit,12)
	workspace._shore_slope.select(0)
	workspace._shore_roughness.value = 0
	workspace._on_brush_setting_changed()
	check(workspace._shore_width.value == 96 and workspace._shore_reset.visible,"gentle preset UI")
	for preset in [1,2,0]:
		workspace._shore_slope.select(preset)
		workspace._shore_slope.item_selected.emit(preset)
		check(workspace._shore_width.value == 12*int([8,4,2][preset]),"slope preset inert")
	workspace._shore_width.value = 128
	check(workspace._shore_slope.selected == 3,"manual length not custom")
	workspace._shore_slope.select(0)
	workspace._on_brush_setting_changed()
	workspace._begin_stroke(screen_for(workspace,a))
	check(workspace._stroke_active,"shore picker")
	workspace._apply_generative_relief_segment(a,b)
	workspace._finish_stroke()
	var first := editable.voxels.duplicate()
	var anchor: Vector3i = workspace._shore_anchor
	check(anchor != Model.INVALID_CELL,"shore anchor missing")
	var h := Model.column_heights(first,editable.grid_size())
	workspace._begin_stroke(screen_for(workspace,Vector3i(40,h[40+64*128],64)))
	workspace._apply_generative_relief_segment(Vector3i(40,h[40+64*128],64),Vector3i(100,h[100+64*128],64))
	workspace._finish_stroke()
	check(workspace._shore_anchor == anchor and editable.voxels == first,"second gesture changed origin/profile")
	undo.undo()
	check(editable.voxels == baseline,"shore one Undo")
	undo.redo()
	check(editable.voxels == first,"shore Redo")
	workspace._shore_paint_button.pressed.emit()
	check(workspace._radius.get_selected_metadata() == 32,"shore paint shortcut lost radius")
	workspace._select_palette_color(2)
	workspace._select_option_metadata(workspace._sand_palette,3)
	workspace._sand_seed = 7
	workspace._on_brush_setting_changed()
	workspace._begin_stroke(screen_for(workspace,Vector3i(8,40,64)))
	workspace._apply_sand_segment(a,b)
	workspace._finish_stroke()
	var painted := editable.voxels.duplicate()
	check(painted != first and Model.column_heights(painted,editable.grid_size()) == h,"sand changed shore shape")
	for x in range(8,105):
		var painted_top := int(painted[Model.index_of(Vector3i(x,h[x+64*128],64),editable.grid_size())])
		check(painted_top == 2 or painted_top == 3,"sand skipped flat terrace at %d"%x)
	undo.undo()
	check(editable.voxels == first,"sand Undo")
	undo.redo()
	check(editable.voxels == painted,"sand Redo")
	workspace._activate_tool_id(Model.TOOL_SURFACE_FILL)
	workspace._select_option_metadata(workspace._surface_fill_mode,"open")
	workspace._surface_fill_mode.item_selected.emit(1)
	check(workspace._open_water_level.value == anchor.y+1 and workspace._open_water_level.visible and not workspace._surface_fill_level.visible,"open water UI/shore height")
	workspace._select_option_metadata(workspace._surface_fill_tint,4)
	workspace._apply_surface_fill_click(screen_for(workspace,Vector3i(104,h[104+64*128],64)))
	check(editable.surface_fill_materials.count(1) > 0 and editable.voxels == painted,"actual UI open water failed or changed floor")
	var high_levels := editable.surface_fill_levels.duplicate()
	var high_mask := editable.surface_fill_materials.duplicate()
	undo.undo()
	check(editable.surface_fill_materials.is_empty() and editable.voxels == painted,"water Undo")
	undo.redo()
	check(editable.surface_fill_levels == high_levels,"water Redo")
	workspace._open_water_level.value = 34
	workspace._apply_surface_fill_click(screen_for(workspace,Vector3i(104,h[104+64*128],64)))
	check(editable.surface_fill_levels != high_levels and editable.surface_fill_materials.count(1) < high_mask.count(1),"lowering open water left fringe")
	undo.undo()
	check(editable.surface_fill_levels == high_levels,"lowering Undo")
	workspace._edit_region_blocks = Rect2i(4,3,4,5)
	workspace._open_water_level.value = 38
	workspace._apply_surface_fill_click(screen_for(workspace,Vector3i(104,h[104+64*128],64)))
	check(editable.surface_fill_levels != high_levels,"bounded replacement refused existing water crossing scope")
	for column in high_levels.size():
		if column%128 < 64 or column/128 < 48:
			check(editable.surface_fill_levels[column] == high_levels[column],"replacement changed water outside area")
	undo.undo()
	workspace._edit_region_blocks = Rect2i(0,0,8,8)
	workspace._open_water_level.value = 41
	check(workspace._save() and editable.validation_errors().is_empty(),"coast save/validation")
	var loaded := ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as EmberVoxelModelResource
	check(loaded != null and loaded.voxels == painted and loaded.surface_fill_levels == high_levels,"coast reopen")
	var store := ViewStore.new()
	store.import_data(workspace.export_editor_view_data())
	var profiles := store.recall_brush_profiles()
	check(profiles[Model.TOOL_SURFACE_FILL].fill_mode == "open" and profiles[Model.TOOL_SURFACE_FILL].open_water_level == 41,"water settings serialization")
	check(profiles[Model.TOOL_RAISE].shore_slope == 0 and profiles[Model.TOOL_RAISE].shore_width == 96 and profiles[Model.TOOL_RAISE].height_limit == 12,"shore preset/depth serialization")
	workspace._activate_tool_id(Model.TOOL_RAISE)
	check(workspace._shore_anchor == anchor,"tool switch lost anchor")
	workspace._shore_reset.pressed.emit()
	check(workspace._shore_anchor == Model.INVALID_CELL and editable.voxels == painted,"reset altered source")
	workspace.discard_changes()
	check(editable.voxels == painted and editable.surface_fill_levels == high_levels,"coast discard")
	if DisplayServer.get_name() != "headless":
		workspace._activate_tool_id(Model.TOOL_SURFACE_FILL)
		workspace._show_grid = false
		workspace._show_region = false
		workspace._grid.visible = false
		workspace._rebuild_region_overlay()
		workspace._ortho_size = 10.5
		workspace._update_camera()
		workspace._rebuild_visual()
		for frame in 50: await process_frame
		RenderingServer.force_draw(false)
		root.get_texture().get_image().save_png("user://coastal_workflow_native.png")
		print("COAST_NATIVE_CAPTURE ",ProjectSettings.globalize_path("user://coastal_workflow_native.png"))
	workspace.free()
	undo.clear_history()
	undo.free()
	for message in errors: push_error(message)
	print("test_voxel_coastal_workflow: ","PASS" if errors.is_empty() else "FAIL"," · ",errors.size())
	quit(0 if errors.is_empty() else 1)
