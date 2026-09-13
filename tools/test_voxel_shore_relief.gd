extends SceneTree

const Model = preload("res://addons/ember_import/ember_voxel_sculpt_model.gd")
const Workspace = preload("res://addons/ember_import/ember_voxel_sculpt_workspace.gd")
const Profiles = preload("res://addons/ember_import/ember_voxel_brush_profiles.gd")
const ViewStore = preload("res://addons/ember_import/ember_surface_editor_view_store.gd")
const Mesher = preload("res://scripts/ember_voxel_surface_mesher.gd")
var errors: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition: errors.append(message)

func _init() -> void:
	_run.call_deferred()

func fixture() -> EmberVoxelModelResource:
	var source := EmberVoxelModelResource.new()
	source.model_id = "shore_relief_fixture"
	source.display_name = "Отмель и дно · проба"
	source.voxels_per_block = 16
	source.size_blocks = Vector3i(4,4,4)
	source.height_voxels = 64
	source.palette = PackedColorArray([Color.TRANSPARENT, Color("bd9a68"), Color("378caf")])
	var grid := source.grid_size()
	source.voxels.resize(grid.x * grid.y * grid.z)
	for z in grid.z:
		for x in grid.x:
			for y in 25: source.voxels[Model.index_of(Vector3i(x,y,z), grid)] = 1
	source.surface_fill_levels.resize(grid.x * grid.z)
	source.surface_fill_levels.fill(25)
	source.surface_fill_materials.resize(grid.x * grid.z)
	source.surface_fill_materials.fill(Model.SURFACE_FILL_WATER)
	source.surface_fill_palette.resize(grid.x * grid.z)
	source.surface_fill_palette.fill(2)
	return source

func dab(source: EmberVoxelModelResource, baseline: PackedByteArray, a: Vector3i, b: Vector3i, cache: Dictionary, settings: Dictionary, seed := 7, coarse := false) -> Dictionary:
	return Model.generative_relief_segment_changes(source, baseline, a,b,1,32,12,24,0,seed,0,"shore",coarse,{},cache,Model.column_heights(baseline,source.grid_size()),{},settings)

func _run() -> void:
	var source := fixture()
	var baseline := source.voxels.duplicate()
	var a := Vector3i(12,24,32)
	var b := Vector3i(44,24,32)
	var settings := {"origin":Vector2(12,32),"height":24,"direction":0,"width":24,"roughness":0}
	var cache := {}
	var started := Time.get_ticks_usec()
	var changes := dab(source,baseline,a,b,cache,settings)
	print("SHORE_RADIUS32_SEGMENT_MS ", (Time.get_ticks_usec()-started)/1000.0)
	check(not changes.is_empty(), "shore produced no relief")
	for change in changes.values(): check(change.after == 0,"shore raised terrain")
	source.voxels = Model.values_with_changes(baseline,changes,true)
	var result := source.voxels.duplicate()
	check(dab(source,baseline,b,a,cache,settings).is_empty(),"revisit accumulated")
	var heights := Model.column_heights(result,source.grid_size())
	check(heights[12+32*64] == 24 and heights[36+32*64] == 12,"shore endpoints")
	for x in range(12,44): check(heights[x+32*64] >= heights[x+1+32*64],"quiet shoal not monotonic")
	for height in heights: check(height >= 12 and height <= 24,"depth limit")
	check(source.validation_errors().is_empty(),"invalid source")
	var mesh := Mesher.build_region(source,Vector3i.ZERO,source.grid_size(),1.0/16.0)
	var has_water := false
	for surface in mesh.get_surface_count():
		if mesh.surface_get_name(surface) == "water": has_water = true
	check(has_water,"digging did not expose existing water plane")
	var hollow := fixture()
	for y in range(6,25): hollow.voxels[Model.index_of(Vector3i(20,y,32),hollow.grid_size())] = 0
	var hollow_before := hollow.voxels.duplicate()
	hollow.voxels = Model.values_with_changes(hollow_before,dab(hollow,hollow_before,a,b,{},settings),true)
	check(Model.column_heights(hollow.voxels,hollow.grid_size())[20+32*64] == 5,"authored deeper hole was filled")
	for coarse in [false,true]:
		var whole := fixture()
		whole.voxels = Model.values_with_changes(baseline,dab(whole,baseline,a,b,{},settings,7,coarse),true)
		var split := fixture()
		var split_cache := {}
		for x in range(a.x,b.x,4):
			var delta := dab(split,baseline,Vector3i(x,24,32),Vector3i(x+4,24,32),split_cache,settings,7,coarse)
			split.voxels = Model.values_with_changes(split.voxels,delta,true)
		check(split.voxels == whole.voxels,"segment density / coarse="+str(coarse))
	for key in ["direction","width","roughness"]:
		var altered := settings.duplicate()
		altered[key] = {"direction":2,"width":48,"roughness":40}[key]
		check(Model.values_with_changes(baseline,dab(fixture(),baseline,a,b,{},altered),true) != result,"inert control "+key)
	var rough := settings.duplicate()
	rough.roughness = 40
	check(dab(fixture(),baseline,a,b,{},rough,7) != dab(fixture(),baseline,a,b,{},rough,8),"seed inert")
	var edge := dab(fixture(),baseline,Vector3i(0,24,0),Vector3i(63,24,0),{},settings)
	check(not edge.is_empty(),"edge stopped")
	for index in edge: check(index >= 0 and index < baseline.size(),"edge escaped grid")
	var normalized := Profiles.normalize_profile({"relief_style":"shore","shore_direction":9,"shore_width":999,"shore_roughness":-8})
	check(normalized.relief_style == "shore" and normalized.shore_direction == 3 and normalized.shore_width == 256 and normalized.shore_roughness == 0,"profile clamps")
	root.size = Vector2i(1440,900)
	var undo := UndoRedo.new()
	var workspace := Workspace.new()
	workspace.setup(null,undo)
	root.add_child(workspace)
	workspace.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var path := "user://shore-relief-%d.tres" % Time.get_ticks_usec()
	var editable := fixture()
	workspace.open_surface(editable,path,Rect2i(0,0,4,4))
	for frame in 8: await process_frame
	workspace._activate_tool_id(Model.TOOL_RAISE)
	workspace._select_option_metadata(workspace._relief_mode,Profiles.RELIEF_GENERATOR)
	workspace._select_option_metadata(workspace._relief_generator_style,Profiles.RELIEF_SHORE)
	workspace._select_option_metadata(workspace._radius,32)
	workspace._select_option_metadata(workspace._height_limit,12)
	workspace._shore_width.value = 24
	workspace._shore_roughness.value = 15
	workspace._shore_direction.select(0)
	workspace._relief_seed_value = 7
	workspace._on_brush_setting_changed()
	check(workspace._shore_width.visible and not workspace._relief_generator_detail.visible and not workspace._relief_generator_direction.visible,"shore UI")
	var store := ViewStore.new()
	store.import_data(workspace.export_editor_view_data())
	var profile: Dictionary = store.recall_brush_profiles()[Model.TOOL_RAISE]
	check(profile.relief_style == "shore" and profile.shore_width == 24 and profile.shore_roughness == 15,"editor serialization")
	check(not workspace.has_unsaved_changes(),"settings dirtied source")
	workspace._activate_tool_id(Model.TOOL_PAINT)
	var relief_item := workspace._find_tool_item(Model.TOOL_RAISE)
	workspace._tool.deselect_all()
	workspace._tool.select(relief_item)
	workspace._on_tool_selected(relief_item)
	workspace.import_editor_view_data(store.export_data())
	check(workspace._shore_width.visible and workspace._shore_roughness.value == 15,"tool/reopen lost settings")
	var camera: Camera3D = workspace._camera
	var viewport: SubViewport = workspace._viewport
	var container: SubViewportContainer = workspace._viewport_container
	var screen := camera.unproject_position(Vector3(12.5/16.0,25.0/16.0,32.5/16.0))*container.size/Vector2(viewport.size)
	workspace._begin_stroke(screen)
	check(workspace._stroke_active,"surface pick failed")
	var origin: Vector3i = workspace._shore_stroke_origin
	workspace._apply_generative_relief_segment(a,b)
	check(workspace._shore_stroke_origin == origin,"origin moved within stroke")
	workspace._finish_stroke()
	var edited := editable.voxels.duplicate()
	check(edited != baseline,"workspace inert")
	undo.undo()
	check(editable.voxels == baseline,"one Undo")
	undo.redo()
	check(editable.voxels == edited,"one Redo")
	check(editable.surface_fill_levels == source.surface_fill_levels and editable.surface_fill_materials == source.surface_fill_materials and editable.surface_fill_palette == source.surface_fill_palette and editable.transparency.is_empty(),"water/material channels changed")
	check(workspace._save(),"save")
	var loaded := ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as EmberVoxelModelResource
	check(loaded != null and loaded.voxels == edited and loaded.surface_fill_levels == editable.surface_fill_levels,"save/reopen")
	workspace._begin_stroke(screen)
	workspace._apply_generative_relief_segment(a,b)
	workspace._cancel_stroke()
	check(editable.voxels == edited,"cancel")
	workspace.discard_changes()
	check(editable.voxels == edited,"discard")
	workspace._edit_region_blocks = Rect2i(0,0,1,1)
	workspace._begin_stroke(screen)
	check(not workspace._stroke_active,"out-of-region pick accepted")
	var top := Model.column_heights(edited,editable.grid_size())[8+8*64]
	var inside_screen := camera.unproject_position(Vector3(8.5/16.0,float(top+1)/16.0,8.5/16.0))*container.size/Vector2(viewport.size)
	workspace._begin_stroke(inside_screen)
	check(workspace._stroke_active,"region interior pick failed")
	workspace._apply_generative_relief_segment(Vector3i(8,top,8),Vector3i(30,top,8))
	for index in edited.size():
		if index % 64 >= 16 or (index / 64) % 64 >= 16:
			check(editable.voxels[index] == edited[index],"shore escaped edit region")
	workspace._cancel_stroke()
	check(editable.voxels == edited,"region cancel")
	workspace._edit_region_blocks = Rect2i(0,0,4,4)
	workspace._rebuild_visual()
	for frame in 12: await process_frame
	var preview_water := 0
	for visual in workspace._chunk_meshes.values():
		if visual.mesh == null: continue
		for surface in visual.mesh.get_surface_count():
			if visual.mesh.surface_get_name(surface) == "water": preview_water += 1
	check(preview_water > 0,"workspace preview omitted water")
	print("SHORE_PREVIEW_WATER_SURFACES ",preview_water)
	if DisplayServer.get_name() != "headless":
		workspace._show_grid = false
		workspace._show_region = false
		workspace._grid.visible = false
		workspace._rebuild_region_overlay()
		workspace._ortho_size = 5.4
		workspace._update_camera()
		for frame in 20: await process_frame
		RenderingServer.force_draw(false)
		root.get_texture().get_image().save_png("user://shore_relief_native.png")
		print("SHORE_NATIVE_CAPTURE ",ProjectSettings.globalize_path("user://shore_relief_native.png"))
	workspace.free()
	undo.clear_history()
	undo.free()
	for message in errors: push_error(message)
	print("test_voxel_shore_relief: ","PASS" if errors.is_empty() else "FAIL"," · ",errors.size())
	quit(0 if errors.is_empty() else 1)
