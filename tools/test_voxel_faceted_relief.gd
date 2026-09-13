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
	source.model_id = "faceted_relief_fixture"
	source.display_name = "Гранёный рельеф · тест"
	source.voxels_per_block = 16
	source.size_blocks = Vector3i(4,4,4)
	source.height_voxels = 64
	source.palette = PackedColorArray([Color.TRANSPARENT, Color("466678")])
	var grid := source.grid_size()
	source.voxels.resize(grid.x * grid.y * grid.z)
	for z in grid.z:
		for x in grid.x:
			for y in 25: source.voxels[Model.index_of(Vector3i(x,y,z), grid)] = 1
	return source

func dab(source: EmberVoxelModelResource, baseline: PackedByteArray, a: Vector3i, b: Vector3i, cache: Dictionary, settings: Dictionary, seed := 7, direction := 0, coarse := false) -> Dictionary:
	return Model.generative_relief_segment_changes(source, baseline, a,b,1,32,12,16,0,seed,direction,"facets",coarse,{},cache,Model.column_heights(baseline,source.grid_size()),settings)

func _run() -> void:
	var source := fixture()
	var baseline := source.voxels.duplicate()
	var a := Vector3i(20,24,32)
	var b := Vector3i(44,24,32)
	var settings := {"tilt":80,"joint_width":2,"joint_depth":5}
	var cache := {}
	var started := Time.get_ticks_usec()
	var changes := dab(source,baseline,a,b,cache,settings)
	print("FACET_RADIUS32_SEGMENT_MS ", (Time.get_ticks_usec()-started)/1000.0)
	check(not changes.is_empty(), "facets produce no relief")
	source.voxels = Model.values_with_changes(baseline,changes,true)
	var result := source.voxels.duplicate()
	check(dab(source,baseline,b,a,cache,settings).is_empty(), "revisit accumulated")
	check(source.validation_errors().is_empty(), "invalid source")
	for coarse in [false,true]:
		var whole := fixture()
		whole.voxels = Model.values_with_changes(baseline,dab(whole,baseline,a,b,{},settings,7,0,coarse),true)
		var split := fixture()
		var split_cache := {}
		for x in range(a.x,b.x,4):
			var delta := dab(split,baseline,Vector3i(x,24,32),Vector3i(x+4,24,32),split_cache,settings,7,0,coarse)
			split.voxels = Model.values_with_changes(split.voxels,delta,true)
		check(split.voxels == whole.voxels, "segment density changes facets / coarse="+str(coarse))
	for altered in [{"tilt":0,"joint_width":2,"joint_depth":5}, {"tilt":80,"joint_width":0,"joint_depth":5}, {"tilt":80,"joint_width":4,"joint_depth":5}, {"tilt":80,"joint_width":2,"joint_depth":0}]:
		var other := fixture()
		check(Model.values_with_changes(baseline,dab(other,baseline,a,b,{},altered),true) != result, "inert facet setting "+str(altered))
	var other_seed := fixture()
	check(Model.values_with_changes(baseline,dab(other_seed,baseline,a,b,{},settings,8),true) != result, "seed inert")
	var quiet := fixture()
	var width0 := {"tilt":80,"joint_width":0,"joint_depth":0}
	var depth16 := {"tilt":80,"joint_width":0,"joint_depth":16}
	check(dab(quiet,baseline,a,b,{},width0) == dab(quiet,baseline,a,b,{},depth16), "width0 does not disable joints")
	for direction in [-1,1]:
		var directed := fixture()
		for change in dab(directed,baseline,a,b,{},settings,7,direction).values():
			check((change.after == 0) == (direction < 0), "direction violated")
	var sites := {}
	var sample := Model._relief_facet_sample(Vector2(32,32),16,7,sites)
	var anchor: Vector2 = sample.anchor
	var centre := Model._relief_facet_sample(anchor,16,7,sites)
	var left := Model._relief_facet_sample(anchor-Vector2(1,0),16,7,sites)
	var right := Model._relief_facet_sample(anchor+Vector2(1,0),16,7,sites)
	check(left.anchor == centre.anchor and right.anchor == centre.anchor and is_equal_approx(left.slope+right.slope,2*centre.slope), "polygon is not a plane")
	var flat := fixture()
	flat.voxels = Model.values_with_changes(baseline,dab(flat,baseline,a,b,{}, {"tilt":0,"joint_width":0,"joint_depth":0}),true)
	var flat_heights := Model.column_heights(flat.voxels,flat.grid_size())
	var polygon_heights := {}
	for z in range(24,41):
		for x in range(24,41):
			var polygon: Vector2 = Model._relief_facet_sample(Vector2(x,z),16,7,sites).anchor
			var height := flat_heights[x+z*64]
			if polygon_heights.has(polygon): check(polygon_heights[polygon] == height,"brush falloff bends flat facet interior")
			polygon_heights[polygon] = height
	var heights := Model.column_heights(result,source.grid_size())
	for height in heights: check(absi(height-24)<=12,"amplitude exceeded")
	var normalized := Profiles.normalize_profile({"relief_style":"facets","relief_facet_tilt":999,"relief_joint_width":-2,"relief_joint_depth":99})
	check(normalized.relief_style == "facets" and normalized.relief_facet_tilt == 100 and normalized.relief_joint_width == 0 and normalized.relief_joint_depth == 16,"profile clamps")
	var edge := fixture()
	var edge_changes := dab(edge,baseline,Vector3i(0,24,0),Vector3i(0,24,63),{},settings)
	check(not edge_changes.is_empty(),"edge brush stopped")
	for index in edge_changes: check(index >= 0 and index < baseline.size(),"edge out of bounds")
	var larger := fixture()
	larger.voxels_per_block = 32
	var large_grid := larger.grid_size()
	larger.voxels.resize(large_grid.x*large_grid.y*large_grid.z)
	larger.voxels.fill(0)
	for z in large_grid.z:
		for x in large_grid.x:
			for y in 25: larger.voxels[Model.index_of(Vector3i(x,y,z),large_grid)] = 1
	var large_baseline := larger.voxels.duplicate()
	started = Time.get_ticks_usec()
	check(not dab(larger,large_baseline,Vector3i(40,24,64),Vector3i(88,24,64),{},settings).is_empty(),"density32 larger map")
	print("FACET_4X4_DENSITY32_MS ",(Time.get_ticks_usec()-started)/1000.0)
	root.size = Vector2i(1440,900)
	var undo := UndoRedo.new()
	var workspace := Workspace.new()
	workspace.setup(null,undo)
	root.add_child(workspace)
	workspace.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var path := "user://faceted-relief-%d.tres" % Time.get_ticks_usec()
	var editable := fixture()
	workspace.open_surface(editable,path,Rect2i(0,0,4,4))
	for frame in 8: await process_frame
	workspace._activate_tool_id(Model.TOOL_RAISE)
	workspace._select_option_metadata(workspace._relief_mode,Profiles.RELIEF_GENERATOR)
	workspace._select_option_metadata(workspace._relief_generator_style,Profiles.RELIEF_FACETS)
	workspace._select_option_metadata(workspace._radius,32)
	workspace._select_option_metadata(workspace._height_limit,12)
	workspace._select_option_metadata(workspace._relief_generator_scale,16)
	workspace._relief_facet_tilt.value = 80
	workspace._relief_joint_width.value = 2
	workspace._relief_joint_depth.value = 5
	workspace._relief_seed_value = 7
	workspace._on_brush_setting_changed()
	check(workspace._relief_joint_width.visible and not workspace._relief_generator_detail.visible,"facet UI visibility")
	check(workspace._active_tool_label.text.contains("грани"),"facet label")
	var store := ViewStore.new()
	store.import_data(workspace.export_editor_view_data())
	var profile: Dictionary = store.recall_brush_profiles()[Model.TOOL_RAISE]
	check(profile.relief_style == "facets" and profile.relief_facet_tilt == 80 and profile.relief_joint_width == 2 and profile.relief_joint_depth == 5,"editor profile serialization")
	check(not workspace.has_unsaved_changes(),"settings dirtied source")
	workspace._activate_tool_id(Model.TOOL_PAINT)
	var relief_item := workspace._find_tool_item(Model.TOOL_RAISE)
	workspace._tool.deselect_all()
	workspace._tool.select(relief_item)
	workspace._on_tool_selected(relief_item)
	check(workspace._relief_mode_kind() == Profiles.RELIEF_GENERATOR and workspace._relief_joint_width.visible and workspace._relief_facet_tilt.value == 80 and workspace._relief_joint_depth.value == 5,"tool switch lost facet settings")
	workspace.import_editor_view_data(store.export_data())
	check(workspace._relief_generator_style.get_selected_metadata() == "facets" and workspace._relief_joint_depth.value == 5,"editor profile reopen")
	# Start through actual surface picking; the same workspace segment route
	# completes a larger path without relying on fake mouse-button state.
	var camera: Camera3D = workspace._camera
	var viewport: SubViewport = workspace._viewport
	var container: SubViewportContainer = workspace._viewport_container
	var screen := camera.unproject_position(Vector3(20.5/16.0,25.0/16.0,32.5/16.0))*container.size/Vector2(viewport.size)
	workspace._begin_stroke(screen)
	check(workspace._stroke_active,"real surface pick failed")
	workspace._apply_generative_relief_segment(a,b)
	workspace._finish_stroke()
	var edited := editable.voxels.duplicate()
	check(edited != baseline,"workspace facets inert")
	undo.undo()
	check(editable.voxels == baseline,"one Undo")
	undo.redo()
	check(editable.voxels == edited,"one Redo")
	check(workspace._save(),"save")
	var loaded := ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as EmberVoxelModelResource
	check(loaded != null and loaded.voxels == edited,"save/reopen mismatch")
	workspace._begin_stroke(screen)
	workspace._apply_generative_relief_segment(a,b)
	workspace._cancel_stroke()
	check(editable.voxels == edited,"cancel changed saved source")
	workspace.discard_changes()
	check(editable.voxels == edited,"discard did not restore save")
	workspace._edit_region_blocks = Rect2i(0,0,1,1)
	workspace._begin_stroke(screen)
	# The starting pick is outside the region and must not activate a stroke.
	check(not workspace._stroke_active,"out-of-region pick accepted")
	var top := Model.column_heights(editable.voxels,editable.grid_size())[8+8*64]
	var inside_screen := camera.unproject_position(Vector3(8.5/16.0,float(top+1)/16.0,8.5/16.0))*container.size/Vector2(viewport.size)
	workspace._begin_stroke(inside_screen)
	check(workspace._stroke_active,"region interior pick failed")
	workspace._apply_generative_relief_segment(Vector3i(8,top,8),Vector3i(12,top,12))
	for index in edited.size():
		if index % 64 >= 16 or (index / 64) % 64 >= 16:
			check(editable.voxels[index] == edited[index],"facet escaped edit region")
	workspace._cancel_stroke()
	check(editable.voxels == edited,"region cancel")
	workspace._edit_region_blocks = Rect2i(0,0,4,4)
	if DisplayServer.get_name() != "headless":
		workspace._show_grid = false
		workspace._show_region = false
		workspace._grid.visible = false
		workspace._rebuild_region_overlay()
		workspace._ortho_size = 5.4
		workspace._update_camera()
		for frame in 20: await process_frame
		RenderingServer.force_draw(false)
		root.get_texture().get_image().save_png("user://faceted_relief_native.png")
		print("FACET_NATIVE_CAPTURE ",ProjectSettings.globalize_path("user://faceted_relief_native.png"))
	workspace.free()
	undo.clear_history()
	undo.free()
	for message in errors: push_error(message)
	print("test_voxel_faceted_relief: ","PASS" if errors.is_empty() else "FAIL"," · ",errors.size())
	quit(0 if errors.is_empty() else 1)
