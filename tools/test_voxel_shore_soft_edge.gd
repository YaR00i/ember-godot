extends SceneTree

const Model = preload("res://addons/ember_import/ember_voxel_sculpt_model.gd")
const Workspace = preload("res://addons/ember_import/ember_voxel_sculpt_workspace.gd")
const Profiles = preload("res://addons/ember_import/ember_voxel_brush_profiles.gd")
var errors: Array[String] = []

func check(condition: bool, message: String) -> void:
	if not condition: errors.append(message)

func _init() -> void:
	_run.call_deferred()

func fixture() -> EmberVoxelModelResource:
	var source := EmberVoxelModelResource.new()
	source.model_id = "shore_soft_edge_fixture"
	source.display_name = "Мягкий край берега · радиус16 · глубина4 · длина60"
	source.voxels_per_block = 16
	source.size_blocks = Vector3i(8,4,8)
	source.height_voxels = 64
	source.palette = PackedColorArray([Color.TRANSPARENT,Color("427637"),Color("d1a55f")])
	var grid := source.grid_size()
	source.voxels.resize(grid.x*grid.y*grid.z)
	for z in grid.z:
		for x in grid.x:
			for y in 41:
				source.voxels[Model.index_of(Vector3i(x,y,z),grid)] = 2 if y == 40 else 1
	return source

func screen_for(workspace: Control, cell: Vector3i) -> Vector2:
	return workspace._camera.unproject_position((Vector3(cell)+Vector3(.5,1,.5))/16)*workspace._viewport_container.size/Vector2(workspace._viewport.size)

func capture(workspace: Control, name: String) -> void:
	if DisplayServer.get_name() == "headless": return
	workspace._rebuild_visual()
	for frame in 20: await process_frame
	RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png("user://"+name+".png")
	print("SHORE_SOFT_CAPTURE ",ProjectSettings.globalize_path("user://"+name+".png"))

func _run() -> void:
	var source := fixture()
	var baseline := source.voxels.duplicate()
	var foundation := Model.column_heights(baseline,source.grid_size())
	var a := Vector3i(20,40,24)
	var b := Vector3i(20,40,104)
	var settings := {"origin":Vector2(80,24),"height":40,"direction":1,"width":60,"roughness":0,"foundation":foundation}
	var cache := {}
	var delta := Model.generative_relief_segment_changes(source,baseline,a,b,2,16,4,16,0,7,0,"shore",false,{},cache,foundation,{},settings)
	source.voxels = Model.values_with_changes(baseline,delta,true)
	var result := source.voxels.duplicate()
	var heights := Model.column_heights(result,source.grid_size())
	check(heights[20+64*128] == 36,"center lost depth4")
	check(heights[28+64*128] >= 38,"half-radius remained a flat cut")
	check(heights[32+64*128] >= 39,"outer shore rim too steep")
	for x in range(4,37):
		check(absi(heights[x+64*128]-heights[x+1+64*128]) <= 1,"parallel-stroke rim cliff at %d"%x)
	for index in delta:
		check(delta[index].after == 0,"shore repainted or added voxels")
	var repeated := Model.generative_relief_segment_changes(source,result,a,b,2,16,4,16,0,7,0,"shore",false,{}, {},heights,{},settings)
	check(repeated.is_empty(),"separate gesture deepened soft rim")
	var split := fixture()
	var split_cache := {}
	for z in range(24,104,4):
		var segment := Model.generative_relief_segment_changes(split,baseline,Vector3i(20,40,z),Vector3i(20,40,z+4),2,16,4,16,0,7,0,"shore",false,{},split_cache,foundation,{},settings)
		split.voxels = Model.values_with_changes(split.voxels,segment,true)
	check(split.voxels == result,"soft rim depends on event density")
	root.size = Vector2i(1440,900)
	var undo := UndoRedo.new()
	var workspace := Workspace.new()
	workspace.setup(null,undo)
	root.add_child(workspace)
	workspace.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var editable := fixture()
	var path := "user://shore-soft-edge-%d.tres"%Time.get_ticks_usec()
	workspace.open_surface(editable,path,Rect2i(0,0,8,8))
	for frame in 8: await process_frame
	workspace._activate_tool_id(Model.TOOL_RAISE)
	workspace._select_option_metadata(workspace._relief_mode,Profiles.RELIEF_GENERATOR)
	workspace._select_option_metadata(workspace._relief_generator_style,Profiles.RELIEF_SHORE)
	workspace._select_option_metadata(workspace._radius,16)
	workspace._select_option_metadata(workspace._height_limit,4)
	workspace._select_option_metadata(workspace._relief_generator_scale,16)
	workspace._shore_width.value = 60
	workspace._shore_roughness.value = 15
	workspace._shore_direction.select(1)
	workspace._select_palette_color(2)
	workspace._relief_seed_value = 7
	workspace._on_brush_setting_changed()
	workspace._show_grid = false
	workspace._show_region = false
	workspace._grid.visible = false
	workspace._rebuild_region_overlay()
	workspace._ortho_size = 10.5
	workspace._update_camera()
	await capture(workspace,"shore_soft_edge_before")
	workspace._begin_stroke(screen_for(workspace,Vector3i(80,40,24)))
	workspace._finish_stroke()
	check(workspace._shore_anchor == Vector3i(80,40,24),"initial shore anchor pick failed")
	workspace._begin_stroke(screen_for(workspace,a))
	check(workspace._stroke_active,"parallel shore pick failed")
	workspace._apply_generative_relief_segment(a,b)
	workspace._finish_stroke()
	var edited := editable.voxels.duplicate()
	check(edited != baseline,"parallel UI stroke inert")
	check(editable.validation_errors().is_empty(),"invalid edited source")
	for index in edited.size():
		check(edited[index] == 0 or edited[index] == baseline[index],"parallel UI stroke changed surviving colors")
	check(editable.surface_fill_levels.is_empty() and editable.surface_fill_materials.is_empty(),"parallel stroke created water")
	undo.undo()
	check(editable.voxels == baseline,"parallel stroke one Undo")
	undo.redo()
	check(editable.voxels == edited,"parallel stroke one Redo")
	workspace._begin_stroke(screen_for(workspace,Vector3i(20,36,64)))
	workspace._apply_generative_relief_segment(a,b)
	workspace._finish_stroke()
	check(editable.voxels == edited,"parallel UI repeat accumulated")
	check(workspace._save(),"parallel shore save failed")
	var loaded := ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as EmberVoxelModelResource
	check(loaded != null and loaded.voxels == edited,"parallel shore reopen failed")
	workspace.discard_changes()
	check(editable.voxels == edited,"parallel shore discard failed")
	await capture(workspace,"shore_soft_edge_after")
	workspace.free()
	undo.clear_history()
	undo.free()
	for message in errors: push_error(message)
	print("test_voxel_shore_soft_edge: ","PASS" if errors.is_empty() else "FAIL"," · ",errors.size())
	quit(0 if errors.is_empty() else 1)
