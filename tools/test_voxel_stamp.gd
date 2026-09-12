extends SceneTree
const Stamp = preload("res://addons/ember_import/ember_voxel_stamp.gd")
const Shapes = preload("res://addons/ember_import/ember_voxel_shapes.gd")
const Workspace = preload("res://addons/ember_import/ember_voxel_sculpt_workspace.gd")
const Model = preload("res://addons/ember_import/ember_voxel_sculpt_model.gd")
var errors := 0
func check(ok: bool, label: String) -> void:
	if not ok:
		errors += 1
		push_error(label)
func _init() -> void:
	_run.call_deferred()
func _run() -> void:
	var original: EmberVoxelModelResource = Shapes.build("empty",Vector3i(16,8,16),16,Color.CORAL,"stamp_fixture","Stamp").source
	for index in [0,1,16]:
		original.voxels[index] = 1
	original.shine.resize(original.voxels.size())
	original.shine[1] = 70
	var captured := Stamp.capture(original,PackedInt32Array([0,1,16]),"Угол доски")
	check(not captured.has("error"),"capture")
	var preset: Resource = captured.preset
	var geometry_before: Dictionary = preset.geometry.to_definition()
	original.voxels[0] = 0
	check(preset.geometry.to_definition() == geometry_before,"stamp independent from source")
	var directory := "user://stamp_test_%d" % Time.get_ticks_usec()
	var saved := Stamp.save_new(preset,directory.path_join("presets"),directory.path_join("models"))
	check(saved.has("path"),"save library")
	check(Stamp.library(directory.path_join("presets")).size() == 1,"library reopen")
	var reopened := ResourceLoader.load(saved.path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	check(reopened.geometry.voxels == preset.geometry.voxels and reopened.geometry.shine == preset.geometry.shine,"preset external geometry roundtrip")
	var target: EmberVoxelModelResource = Shapes.build("empty",Vector3i(16,8,16),16,Color.BLUE,"target","Объект").source
	target.voxels[0] = 1
	target.voxels[17] = 1 # Empty corner in stamp must remain untouched.
	target.merge_parts = PackedStringArray(["Основа","Деталь"])
	target.voxel_part_ids.resize(target.voxels.size())
	target.voxel_part_ids[0] = 1
	target.voxel_part_ids[17] = 1
	var baseline := target.to_definition()
	var plan := Stamp.plan(target,preset,Vector3i.ZERO,1,0,-1,0,false,2)
	check(not plan.has("error") and target.to_definition() == baseline,"preview detached")
	var undo := UndoRedo.new()
	var actions := EmberVoxelSculptActions.new()
	actions.configure(undo)
	check(actions.apply_fragment(target,plan),"add stamp")
	check(target.palette[target.voxels[0]] == Color.BLUE and target.voxels[17] == 1,"add preserves occupied and empty stamp holes")
	check(target.shine[1] == 70 and target.voxel_part_ids[1] == 2,"channels and part assignment")
	undo.undo()
	check(target.to_definition() == baseline,"one Undo")
	undo.redo()
	check(target.shine[1] == 70,"Redo")
	undo.undo()
	plan = Stamp.plan(target,preset,Vector3i.ZERO,1,0,-1,0,true,2)
	check(actions.apply_fragment(target,plan),"replace stamp")
	check(target.palette[target.voxels[0]] == Color.CORAL and target.voxel_part_ids[0] == 1,"replace color retains old owner")
	check(target.voxels[17] == 1,"replace holes do not erase")
	undo.undo()
	plan = Stamp.plan(target,preset,Vector3i(4,0,4),1,1,0,1,false,0)
	check(not plan.has("error") and plan.selected.size() == 3,"rotate mirror anchor")
	check(Stamp.plan(target,preset,Vector3i(-2,0,0),1,0,-1,0,false,0).has("error"),"out of bounds atomic refusal")
	target.voxel_groups = [{"id":"locked","name":"Locked","indices":PackedInt32Array([1]),"locked":true}]
	check(Stamp.plan(target,preset,Vector3i.ZERO,1,0,-1,0,false,0).has("error"),"locked refusal")
	target.voxel_groups = []
	preset.geometry.voxels_per_block = 32
	check(Stamp.plan(target,preset,Vector3i.ZERO,1,0,-1,0,false,0).has("error"),"density refuses")
	preset.geometry.voxels_per_block = 16
	var crowded := target.duplicate(true) as EmberVoxelModelResource
	crowded.palette.resize(256)
	for i in range(1,256):
		crowded.palette[i] = Color(float(i)/256,0,0)
	check(Stamp.plan(crowded,preset,Vector3i(4,0,4),1,0,-1,0,false,0).has("error"),"palette overflow atomic refusal")
	var line := Stamp.sample_line(Vector3i.ZERO,Vector3i(10,0,0),3)
	check(line == [Vector3i(0,0,0),Vector3i(3,0,0),Vector3i(6,0,0),Vector3i(9,0,0),Vector3i(10,0,0)],"line spacing and exact endpoint")
	var path_knots: Array[Vector3i] = [Vector3i.ZERO,Vector3i(4,0,0),Vector3i(4,0,4)]
	check(Stamp.sample_path(path_knots,3) == [Vector3i(0,0,0),Vector3i(3,0,0),Vector3i(4,0,2)],"path spacing continues across corners")
	var scatter_target: EmberVoxelModelResource = Shapes.build("empty",Vector3i(16,8,16),16,Color.BLUE,"scatter","Scatter").source
	for z in 16:
		for x in 16:
			scatter_target.voxels[Model.index_of(Vector3i(x,0,z),scatter_target.grid_size())] = 1
	var scatter_path: Array[Vector3i] = []
	for x in range(3,14,2):
		scatter_path.append(Vector3i(x,1,8))
	var scatter_a := Stamp.scatter_instances(scatter_target,scatter_path,Vector3i.UP,2,7319,true)
	var scatter_same := Stamp.scatter_instances(scatter_target,scatter_path,Vector3i.UP,2,7319,true)
	var scatter_other := Stamp.scatter_instances(scatter_target,scatter_path,Vector3i.UP,2,9127,true)
	check(not scatter_a.has("error") and scatter_a == scatter_same,"scatter seed is not deterministic")
	check(not scatter_other.has("error") and scatter_other.instances != scatter_a.instances,"new scatter seed did not change the variant")
	var scatter_baseline := scatter_target.to_definition()
	var scatter_plan := Stamp.plan_scatter(scatter_target,preset,scatter_path,Vector3i.UP,2,7319,true,0,-1,1,false,0)
	check(not scatter_plan.has("error") and scatter_plan.scatter_turns.size() == scatter_plan.placements.size(),"scatter plan positions and turns")
	check(scatter_target.to_definition() == scatter_baseline,"scatter preview detached")
	var scatter_undo := UndoRedo.new()
	var scatter_actions := EmberVoxelSculptActions.new()
	scatter_actions.configure(scatter_undo)
	check(scatter_actions.apply_fragment(scatter_target,scatter_plan),"scatter applies atomically")
	scatter_undo.undo()
	check(scatter_target.to_definition() == scatter_baseline,"scatter one Undo")
	scatter_undo.free()
	check(Stamp.scatter_instances(scatter_target,[Vector3i(-1,1,0)],Vector3i.UP,0,1,true).has("error"),"scatter edge refusal")
	var side_target: EmberVoxelModelResource = Shapes.build("empty",Vector3i(16,8,16),16,Color.BLUE,"scatter_sides","Scatter sides").source
	for z in range(6,9):
		for y in range(2,5):
			for x in range(6,9):
				side_target.voxels[Model.index_of(Vector3i(x,y,z),side_target.grid_size())] = 1
	var face_placements := {
		Vector3i.RIGHT:Vector3i(9,3,7), Vector3i.LEFT:Vector3i(5,3,7),
		Vector3i.UP:Vector3i(7,5,7), Vector3i.DOWN:Vector3i(7,1,7),
		Vector3i.BACK:Vector3i(7,3,9), Vector3i.FORWARD:Vector3i(7,3,5),
	}
	for normal in face_placements:
		var side_plan := Stamp.plan_scatter(side_target,preset,[face_placements[normal]],normal,0,42,true,0,-1,1,false,0)
		check(not side_plan.has("error") and side_plan.selected.size() == 3,"scatter orientation on face %s" % normal)
	for normal in [Vector3i.RIGHT,Vector3i.LEFT,Vector3i.UP,Vector3i.DOWN,Vector3i.BACK,Vector3i.FORWARD]:
		var conform_target: EmberVoxelModelResource = Shapes.build("empty",Vector3i(12,12,12),16,Color.BLUE,"conform_%s" % normal,"Conform").source
		conform_target.merge_parts = PackedStringArray(["Основа","Деталь"])
		conform_target.voxel_part_ids.resize(conform_target.voxels.size())
		var base := Vector3i(5,5,5)
		var tangent_a: Vector3i = Model.tangent_axes(normal)[0]
		for z in 12:
			for y in 12:
				for x in 12:
					var cell := Vector3i(x,y,z)
					var raised := 1 if Vector3(cell-base).dot(Vector3(tangent_a)) >= 1.0 else 0
					if Vector3(cell-base).dot(Vector3(normal)) <= float(raised):
						conform_target.voxels[Model.index_of(cell,conform_target.grid_size())] = 1
		var conform_before := conform_target.to_definition()
		var rigid_plan := Stamp.plan_scatter(conform_target,preset,[base+normal],normal,0,42,false,0,-1,0,false,2,Rect2i(),-1,false,2)
		var conform_plan := Stamp.plan_scatter(conform_target,preset,[base+normal],normal,0,42,false,0,-1,0,false,2,Rect2i(),-1,true,2)
		check(not rigid_plan.has("error") and not conform_plan.has("error"),"surface conform plan on face %s" % normal)
		if not rigid_plan.has("error") and not conform_plan.has("error"):
			check(rigid_plan.selected != conform_plan.selected,"surface conform did not deform on face %s" % normal)
			var raised_stamp_cell: Vector3i = base+tangent_a+normal*2
			var raised_stamp_index := Model.index_of(raised_stamp_cell,conform_target.grid_size())
			check(conform_plan.selected.has(raised_stamp_index),"surface conform missed raised column on face %s" % normal)
			check(conform_plan.properties.shine[raised_stamp_index] == 70,"surface conform lost channel mapping on face %s" % normal)
			check(conform_plan.properties.voxel_part_ids[raised_stamp_index] == 2,"surface conform lost part provenance on face %s" % normal)
		check(conform_target.to_definition() == conform_before,"surface conform preview mutated target on face %s" % normal)
	var cliff_target: EmberVoxelModelResource = Shapes.build("empty",Vector3i(12,12,12),16,Color.BLUE,"conform_cliff","Conform cliff").source
	for z in 12:
		for x in 12:
			var top := 4 if x >= 6 else 0
			for y in range(top+1):
				cliff_target.voxels[Model.index_of(Vector3i(x,y,z),cliff_target.grid_size())] = 1
	check(Stamp.plan_scatter(cliff_target,preset,[Vector3i(5,1,5)],Vector3i.UP,0,42,false,0,-1,0,false,0,Rect2i(),-1,true,2).has("error"),"surface conform max bend refusal")
	var indent_geometry: EmberVoxelModelResource = Shapes.build("empty",Vector3i(2,3,2),16,Color.CORAL,"indent_stamp","Indent stamp").source
	for cell in [Vector3i(0,0,0),Vector3i(0,1,0),Vector3i(0,2,0),Vector3i(1,0,0)]:
		indent_geometry.voxels[Model.index_of(cell,indent_geometry.grid_size())] = 1
	var indent_preset := Stamp.Preset.new()
	indent_preset.display_name = "След"
	indent_preset.geometry = indent_geometry
	for normal in [Vector3i.RIGHT,Vector3i.LEFT,Vector3i.UP,Vector3i.DOWN,Vector3i.BACK,Vector3i.FORWARD]:
		var snow: EmberVoxelModelResource = Shapes.build("empty",Vector3i(12,12,12),16,Color.WHITE,"snow_%s" % normal,"Snow").source
		snow.merge_parts = PackedStringArray(["Снег"])
		snow.voxel_part_ids.resize(snow.voxels.size())
		snow.shine.resize(snow.voxels.size())
		var surface := Vector3i(5,5,5)
		for z in 12:
			for y in 12:
				for x in 12:
					var snow_cell := Vector3i(x,y,z)
					if Vector3(snow_cell-surface).dot(Vector3(normal)) <= 0.0:
						var snow_index := Model.index_of(snow_cell,snow.grid_size())
						snow.voxels[snow_index] = 1
						snow.voxel_part_ids[snow_index] = 1
		var deepest: Vector3i = surface-normal*2
		var deepest_index := Model.index_of(deepest,snow.grid_size())
		snow.shine[deepest_index] = 91
		var snow_before := snow.to_definition()
		var indent_plan := Stamp.plan_many(snow,indent_preset,[surface],Model.axis_index(normal),0,-1,0,false,0,Rect2i(),-1,PackedInt32Array(),normal,false,2,true)
		check(not indent_plan.has("error") and indent_plan.get("removes",false),"volume indent plan on face %s" % normal)
		if not indent_plan.has("error"):
			var tangent_a: Vector3i = Model.tangent_axes(normal)[0]
			var expected := PackedInt32Array([
				Model.index_of(surface,snow.grid_size()),
				Model.index_of(surface-normal,snow.grid_size()),
				deepest_index,
				Model.index_of(surface+tangent_a,snow.grid_size()),
			])
			for expected_index in expected:
				check(indent_plan.selected.has(expected_index),"volume indent missed depth on face %s" % normal)
				check(indent_plan.properties.voxels[expected_index] == 0,"volume indent did not clear voxel on face %s" % normal)
				check(indent_plan.properties.voxel_part_ids[expected_index] == 0,"volume indent did not clear owner on face %s" % normal)
			check(indent_plan.properties.shine[deepest_index] == 0,"volume indent did not clear channel on face %s" % normal)
		check(snow.to_definition() == snow_before,"volume indent preview mutated target on face %s" % normal)
		if normal == Vector3i.UP and not indent_plan.has("error"):
			var indent_undo := UndoRedo.new()
			var indent_actions := EmberVoxelSculptActions.new()
			indent_actions.configure(indent_undo)
			check(indent_actions.apply_fragment(snow,indent_plan),"volume indent commit")
			indent_undo.undo()
			check(snow.to_definition() == snow_before,"volume indent one Undo")
			indent_undo.free()
	var locked_snow: EmberVoxelModelResource = Shapes.build("block",Vector3i(8,8,8),16,Color.WHITE,"locked_snow","Locked snow").source
	var locked_surface := Vector3i(3,7,3)
	var locked_indent_index := Model.index_of(locked_surface-Vector3i.UP,locked_snow.grid_size())
	locked_snow.voxel_groups = [{"id":"locked","name":"Locked","indices":PackedInt32Array([locked_indent_index]),"locked":true}]
	check(Stamp.plan_many(locked_snow,indent_preset,[locked_surface],1,0,-1,0,false,0,Rect2i(),-1,PackedInt32Array(),Vector3i.UP,false,2,true).has("error"),"volume indent locked refusal")
	var stepped_snow: EmberVoxelModelResource = Shapes.build("empty",Vector3i(12,8,12),16,Color.WHITE,"stepped_snow","Stepped snow").source
	for z in 12:
		for x in 12:
			var snow_top := 3 if x >= 6 else 2
			for y in range(snow_top+1):
				stepped_snow.voxels[Model.index_of(Vector3i(x,y,z),stepped_snow.grid_size())] = 1
	var rigid_indent := Stamp.plan_scatter(stepped_snow,indent_preset,[Vector3i(5,2,5)],Vector3i.UP,0,42,false,0,-1,0,false,0,Rect2i(),-1,false,2,true)
	var conform_indent := Stamp.plan_scatter(stepped_snow,indent_preset,[Vector3i(5,2,5)],Vector3i.UP,0,42,false,0,-1,0,false,0,Rect2i(),-1,true,2,true)
	check(not rigid_indent.has("error") and not conform_indent.has("error") and rigid_indent.selected != conform_indent.selected,"volume indent surface conform")
	if not conform_indent.has("error"):
		check(conform_indent.selected.has(Model.index_of(Vector3i(6,3,5),stepped_snow.grid_size())),"volume indent did not follow raised snow")
	var application_snow: EmberVoxelModelResource = Shapes.build("empty",Vector3i(16,8,16),16,Color.WHITE,"application_snow","Application snow").source
	for z in 16:
		for x in 16:
			for y in 4:
				application_snow.voxels[Model.index_of(Vector3i(x,y,z),application_snow.grid_size())] = 1
	var indent_path_knots: Array[Vector3i] = [Vector3i(2,3,4),Vector3i(8,3,4),Vector3i(8,3,8)]
	var indent_path_points := Stamp.sample_path(indent_path_knots,2)
	var indent_line_points := Stamp.sample_line(Vector3i(2,3,10),Vector3i(10,3,10),2)
	check(not Stamp.plan_many(application_snow,indent_preset,indent_path_points,1,0,-1,0,false,0,Rect2i(),-1,PackedInt32Array(),Vector3i.UP,false,2,true).has("error"),"volume indent path application")
	check(not Stamp.plan_many(application_snow,indent_preset,indent_line_points,1,0,-1,0,false,0,Rect2i(),-1,PackedInt32Array(),Vector3i.UP,false,2,true).has("error"),"volume indent line application")
	var repeated: EmberVoxelModelResource = Shapes.build("empty",Vector3i(16,8,16),16,Color.BLUE,"repeated","Repeated").source
	repeated.merge_parts = PackedStringArray(["Основа","Деталь"])
	repeated.voxel_part_ids.resize(repeated.voxels.size())
	var repeated_before := repeated.to_definition()
	var repeated_plan := Stamp.plan_many(repeated,preset,[Vector3i.ZERO,Vector3i(1,0,0)],1,0,-1,0,false,2)
	check(not repeated_plan.has("error") and repeated_plan.selected.size() == 5,"overlapping placements are deduplicated")
	check(repeated.to_definition() == repeated_before,"repeated preview detached")
	var repeated_undo := UndoRedo.new()
	var repeated_actions := EmberVoxelSculptActions.new()
	repeated_actions.configure(repeated_undo)
	check(repeated_actions.apply_fragment(repeated,repeated_plan),"repeated stamp applies atomically")
	check(repeated.voxels.count(0) == repeated.voxels.size()-5 and repeated.voxel_part_ids[2] == 2,"repeated colors and part assignment")
	repeated_undo.undo()
	check(repeated.to_definition() == repeated_before,"repeated stamp one Undo")
	repeated_undo.free()
	var source_path: String = reopened.geometry.resource_path
	var edited := ResourceLoader.load(source_path,"",ResourceLoader.CACHE_MODE_IGNORE) as EmberVoxelModelResource
	edited.shine[1] = 90
	check(ResourceSaver.save(edited,source_path) == OK,"edit saved preset geometry")
	var fresh := ResourceLoader.load(saved.path,"",ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	check(fresh.geometry.shine[1] == 90,"preset loads updated dependency rather than stale cache")
	var large: EmberVoxelModelResource = Shapes.build("empty",Vector3i(64,32,64),16,Color.BLUE,"large_target","Large").source
	var large_piece: EmberVoxelModelResource = Shapes.build("block",Vector3i(16,32,32),16,Color.CORAL,"large_stamp","Large stamp").source
	var large_preset := Stamp.Preset.new()
	large_preset.geometry = large_piece
	var start := Time.get_ticks_usec()
	var large_plan := Stamp.plan(large,large_preset,Vector3i.ZERO,1,0,-1,0,false,0)
	print("Stamp 16384 / 131072 cells plan ms: ",(Time.get_ticks_usec()-start)/1000.0)
	check(not large_plan.has("error"),"bounded large stamp")
	var repeated_positions: Array[Vector3i] = []
	for x in range(0,62,2):
		repeated_positions.append(Vector3i(x,0,1))
	start = Time.get_ticks_usec()
	var repeated_large_plan := Stamp.plan_many(large,preset,repeated_positions,1,0,-1,0,false,0)
	print("Stamp path 31 points / 131072 cells plan ms: ",(Time.get_ticks_usec()-start)/1000.0)
	check(not repeated_large_plan.has("error") and repeated_large_plan.selected.size() > repeated_positions.size(),"bounded repeated stamp path")
	var scatter_large: EmberVoxelModelResource = Shapes.build("empty",Vector3i(64,32,64),16,Color.BLUE,"scatter_large","Scatter large").source
	for z in 64:
		for x in 64:
			scatter_large.voxels[Model.index_of(Vector3i(x,0,z),scatter_large.grid_size())] = 1
	var scatter_large_positions: Array[Vector3i] = []
	for x in range(8,58,2):
		scatter_large_positions.append(Vector3i(x,1,32))
	start = Time.get_ticks_usec()
	var scatter_large_plan := Stamp.plan_scatter(scatter_large,preset,scatter_large_positions,Vector3i.UP,4,7319,true,0,-1,1,false,0)
	print("Stamp scatter 25 points / 131072 cells plan ms: ",(Time.get_ticks_usec()-start)/1000.0)
	check(not scatter_large_plan.has("error") and scatter_large_plan.selected.size() > scatter_large_positions.size(),"bounded scatter path")
	var conform_piece: EmberVoxelModelResource = Shapes.build("block",Vector3i(8,4,8),16,Color.CORAL,"conform_piece","Conform piece").source
	var conform_preset := Stamp.Preset.new()
	conform_preset.geometry = conform_piece
	start = Time.get_ticks_usec()
	var conform_large_plan := Stamp.plan_scatter(scatter_large,conform_preset,scatter_large_positions,Vector3i.UP,0,7319,false,0,-1,0,false,0,Rect2i(),-1,true,2)
	print("Stamp conform 25 x 8x4x8 / 131072 cells plan ms: ",(Time.get_ticks_usec()-start)/1000.0)
	check(not conform_large_plan.has("error") and conform_large_plan.selected.size() > scatter_large_positions.size(),"bounded conform scatter path")
	for x in range(3,8):
		for z in range(3,8):
			target.voxels[Model.index_of(Vector3i(x,0,z),target.grid_size())] = 1
	await _ui(target,preset,undo,directory)
	undo.clear_history()
	undo.free()
	print("Voxel stamp: ","PASS" if errors == 0 else "FAIL %d" % errors)
	quit(0 if errors == 0 else 1)

func _ui(target: EmberVoxelModelResource, preset: Resource, undo: UndoRedo, directory: String) -> void:
	root.size = Vector2i(1280,900)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	var workspace := Workspace.new()
	workspace.setup(null,undo)
	root.add_child(workspace)
	workspace.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	workspace.open_surface(target,directory.path_join("target.tres"))
	workspace._stamp_panel.directory = directory.path_join("presets")
	workspace._stamp_panel.sources = directory.path_join("models")
	workspace._stamp_panel.refresh_library()
	for frame in 4:
		await process_frame
	check(not workspace._stamp_panel._create_panel.visible,"new stamp form starts collapsed")
	check(workspace._stamp_panel._library_actions.get_parent() == workspace._stamp_panel,"library actions are pinned outside card scroll")
	check(workspace._stamp_panel._place_button.text == "Выбрать","stamp library still describes a one-shot placement")
	var interaction: Control = workspace._selection_interaction
	var before := target.to_definition()
	workspace._selection_panel.set_selection(PackedInt32Array([0]))
	for frame in 20:
		if not workspace._selection_panel.busy():
			break
		await process_frame
	workspace._selection_panel._mask.button_pressed = true
	workspace._stamp_panel._place()
	for frame in 3:
		await process_frame
	check(interaction.transforming and interaction._apply.disabled,"single stamp waits for an explicit LMB placement")
	check(workspace._canvas_mode == Workspace.CanvasMode.STAMP_DRAFT and workspace._tool.get_selected_items().is_empty(),"stamp draft did not become the sole primary tool")
	check(workspace._selection_panel._mask.button_pressed and workspace._selection_panel._mask_suspended and not workspace._selection_panel.mask_brushes_enabled(),"stamp did not suspend the saved brush mask")
	check(workspace._status.text.begins_with("Маска сохранена · не действует"),"stamp did not expose the suspended mask state in the visible footer")
	var hover_preview := InputEventMouseMotion.new()
	hover_preview.position = interaction._screen(Vector3(7.5,1.01,7.5)/target.normalized_density())
	workspace._on_viewport_input(hover_preview)
	for frame in 3:
		await process_frame
	check(not interaction._stamp_position_picked and interaction._apply.disabled and interaction._ghost.visible,"stamp hover did not keep a detached pre-click preview")
	check(interaction._ghost.multimesh != null and interaction._ghost.multimesh.instance_count == interaction._plan.selected.size(),"stamp hover footprint differs from the planned result")
	interaction._set_stamp_position(Vector3i(8,2,8))
	for frame in 2:
		await process_frame
	check(not interaction._apply.disabled and interaction._ghost.visible,"placed stamp exposes its exact detached preview")
	check(interaction._controls.get_parent() == workspace._operation_panel and interaction._controls.visible,"stamp controls stay visible above the library")
	check(not workspace._radius.visible and not workspace._depth.visible and not workspace._application_mode.visible and not workspace._palette.visible,"volume stamp leaked unrelated sculpt controls")
	check(not interaction._stamp_mode.visible and interaction._stamp_mode_buttons[0].visible,"stamp state dropdown is hidden behind direct mode choices")
	check(interaction._stamp_mode_buttons.size() == 3 and interaction._stamp_application_buttons.size() == 4 and interaction._stamp_spacing.value == 1,"stamp modes, application and spacing controls")
	check(not interaction._stamp_scatter_row.visible and not interaction._stamp_scatter_options.visible and not interaction._stamp_scatter_conform_row.visible,"scatter controls leaked into single stamp mode")
	interaction._select_segment(interaction._stamp_mirror,1)
	await process_frame
	check(interaction._stamp_mirror.selected == 1 and interaction._stamp_mirror_buttons[1].button_pressed,"mirror segment synchronizes stamp plan state")
	check(workspace._sidebar_tabs.current_tab == 1 and workspace._stamp_tool_button.button_pressed,"stamp placement keeps the library context")
	check(workspace._workshop_context_label.text.contains(preset.display_name),"selected stamp is absent from workshop context")
	check(target.to_definition() == before,"UI preview unchanged")
	interaction._numbers[0].value = -100
	for frame in 2:
		await process_frame
	check(interaction._apply.disabled and interaction._hint.modulate.is_equal_approx(Color(1.0,0.45,0.40)),"invalid stamp state is not visibly distinct")
	interaction._numbers[0].value = 8
	for frame in 2:
		await process_frame
	check(not interaction._apply.disabled and not interaction._hint.modulate.is_equal_approx(Color(1.0,0.45,0.40)),"valid stamp state did not recover")
	if "--capture" in OS.get_cmdline_user_args():
		await create_timer(0.3).timeout
		root.get_texture().get_image().save_png("user://voxel_stamp.png")
	interaction.cancel_gesture()
	check(target.to_definition() == before,"UI cancel")
	check(workspace._canvas_mode == Workspace.CanvasMode.STAMP_LIBRARY and not workspace._radius.visible and workspace._tool.get_selected_items().is_empty(),"stamp cancel did not return to a navigation-only library")
	var library_click := InputEventMouseButton.new()
	library_click.button_index = MOUSE_BUTTON_LEFT
	library_click.pressed = true
	library_click.position = workspace._viewport_container.size * 0.5
	workspace._on_viewport_input(library_click)
	library_click.pressed = false
	workspace._on_viewport_input(library_click)
	check(target.to_definition() == before and not workspace._stroke_active,"stamp library leaked LMB into the last brush")
	workspace._stamp_panel._place()
	check(interaction._stamp_mirror.selected == 1,"stamp session did not remember the selected preset settings")
	interaction._set_stamp_position(Vector3i(8,2,8))
	for frame in 2:
		await process_frame
	var escape := InputEventKey.new()
	escape.pressed = true
	escape.keycode = KEY_ESCAPE
	workspace._input(escape)
	for frame in 2:
		await process_frame
	check(interaction.transforming and not interaction._stamp_has_draft() and workspace._canvas_mode == Workspace.CanvasMode.STAMP_DRAFT,"first Esc did not cancel only the current stamp draft")
	check(workspace._status.text.contains("штамп остаётся выбран"),"draft cancel does not explain the armed stamp state")
	workspace._input(escape)
	for frame in 2:
		await process_frame
	check(not interaction.transforming and workspace._canvas_mode == Workspace.CanvasMode.BRUSH,"Esc did not return the stamp draft to the last brush")
	check(workspace._tool.get_selected_items() == PackedInt32Array([0]) and workspace._radius.visible and not workspace._stamp_tool_button.button_pressed,"Esc left conflicting primary-tool highlights")
	check(workspace._selection_panel._mask.button_pressed and not workspace._selection_panel._mask_suspended and workspace._selection_panel.mask_brushes_enabled(),"returning to a compatible brush did not restore the saved mask")
	interaction.begin_stamp(preset)
	workspace._tool.select(1)
	workspace._on_tool_selected(1)
	for frame in 2:
		await process_frame
	check(not interaction.transforming and workspace._canvas_mode == Workspace.CanvasMode.BRUSH and workspace._tool.get_selected_items() == PackedInt32Array([1]),"brush switch during a stamp draft rebounded to the old mode")
	workspace._tool.select(0)
	workspace._on_tool_selected(0)
	interaction.begin_stamp(preset)
	interaction._select_segment(interaction._stamp_mode,2)
	interaction._stamp_normal = Vector3i.UP
	interaction._set_stamp_position(Vector3i(4,0,4))
	for frame in 3:
		await process_frame
	check(interaction._stamp_mode_buttons[2].button_pressed and interaction._plan.get("removes",false) and not interaction._apply.disabled,"UI volume indent preview")
	check(not interaction._axis_buttons[0].get_parent().visible,"surface-oriented indent still exposes an irrelevant axis")
	check(interaction._stamp_anchor_buttons[1].text == "Центр" and not interaction._stamp_anchor_buttons[2].visible,"volume indent exposes duplicate depth anchors")
	if "--capture" in OS.get_cmdline_user_args():
		var indent_ancestor: Node = interaction._controls.get_parent()
		while indent_ancestor != null and not indent_ancestor is ScrollContainer:
			indent_ancestor = indent_ancestor.get_parent()
		if indent_ancestor is ScrollContainer:
			indent_ancestor.ensure_control_visible(interaction._controls)
		for frame in 5:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://voxel_stamp_indent.png")
		print("STAMP_INDENT_CAPTURE ",ProjectSettings.globalize_path("user://voxel_stamp_indent.png"))
	var indent_expected: PackedByteArray = interaction._plan.properties.voxels.duplicate()
	interaction.commit()
	check(target.voxels == indent_expected and target.to_definition() != before,"UI volume indent commit")
	undo.undo()
	check(target.to_definition() == before,"UI volume indent one Undo")
	interaction.begin_stamp(preset)
	interaction._select_segment(interaction._stamp_mode,0)
	interaction._select_segment(interaction._stamp_application,2)
	for frame in 2:
		await process_frame
	check(interaction._apply.disabled and interaction._hint.text.contains("точку A"),"line mode waits for anchor A")
	interaction._stamp_line_start = Vector3i(4,2,4)
	interaction._stamp_line_started = true
	interaction._stamp_spacing.value = 2
	interaction._set_stamp_position(Vector3i(8,2,4))
	interaction._stamp_draft_ready = true
	interaction._stamp_draft_visible_count = interaction._all_stamp_placements().size()
	interaction._pending = true
	for frame in 3:
		await process_frame
	check(not interaction._plan.has("error") and interaction._plan.placements == [Vector3i(4,2,4),Vector3i(6,2,4),Vector3i(8,2,4)],"UI line preview uses exact voxel spacing")
	check(workspace._active_tool_label.text.contains("линия") and workspace._info.text.contains("Первый клик"),"UI line guidance")
	if "--capture" in OS.get_cmdline_user_args():
		var operation_ancestor: Node = interaction._controls.get_parent()
		while operation_ancestor != null and not operation_ancestor is ScrollContainer:
			operation_ancestor = operation_ancestor.get_parent()
		if operation_ancestor is ScrollContainer:
			operation_ancestor.ensure_control_visible(interaction._controls)
		for frame in 5:
			await process_frame
		root.get_texture().get_image().save_png("user://voxel_stamp_line.png")
		print("STAMP_LINE_CAPTURE ",ProjectSettings.globalize_path("user://voxel_stamp_line.png"))
	var line_expected: PackedByteArray = interaction._plan.properties.voxels.duplicate()
	interaction.commit()
	check(target.voxels == line_expected and interaction.transforming and not interaction._stamp_has_draft(),"UI line commit did not rearm the selected stamp")
	undo.undo()
	check(target.to_definition() == before,"UI line one Undo")
	interaction.begin_stamp(preset)
	interaction._select_segment(interaction._stamp_mode,0)
	interaction._select_segment(interaction._stamp_application,1)
	interaction._stamp_spacing.value = 2
	interaction._stamp_knots.assign([Vector3i(4,2,4),Vector3i(8,2,4),Vector3i(8,2,8)])
	interaction._set_stamp_position(Vector3i(8,2,8))
	interaction._stamp_draft_ready = true
	interaction._stamp_draft_visible_count = interaction._all_stamp_placements().size()
	interaction._pending = true
	for frame in 3:
		await process_frame
	check(not interaction._plan.has("error") and interaction._plan.placements.size() == 5,"UI path preview carries spacing around corners")
	var path_expected: PackedByteArray = interaction._plan.properties.voxels.duplicate()
	interaction.commit()
	check(target.voxels == path_expected and interaction.transforming and not interaction._stamp_has_draft(),"UI path commit did not rearm the selected stamp")
	undo.undo()
	check(target.to_definition() == before,"UI path one Undo")
	interaction.begin_stamp(preset)
	interaction._select_segment(interaction._stamp_mode,0)
	interaction._select_segment(interaction._stamp_application,1)
	interaction._stamp_spacing.value = 2
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = interaction._screen(Vector3(3.5,1.01,3.5)/target.normalized_density())
	workspace._on_viewport_input(press)
	var motion := InputEventMouseMotion.new()
	motion.position = interaction._screen(Vector3(7.5,1.01,7.5)/target.normalized_density())
	workspace._on_viewport_input(motion)
	press.pressed = false
	press.position = motion.position
	workspace._on_viewport_input(press)
	for frame in 6:
		await process_frame
	check(interaction.transforming and interaction._stamp_draft_ready and target.to_definition() == before,"pointer path release did not keep a detached draft")
	var path_draft_count: int = interaction._stamp_placements().size()
	var path_undo := InputEventKey.new()
	path_undo.keycode = KEY_Z
	path_undo.pressed = true
	path_undo.ctrl_pressed = true
	check(interaction.handle(path_undo),"path draft Undo was not consumed")
	await process_frame
	check(interaction._stamp_placements().size() == path_draft_count-1 and target.to_definition() == before,"path draft Undo changed the Resource or missed one preview step")
	var path_redo := InputEventKey.new()
	path_redo.keycode = KEY_Z
	path_redo.pressed = true
	path_redo.ctrl_pressed = true
	path_redo.shift_pressed = true
	check(interaction.handle(path_redo),"path draft Redo was not consumed")
	await process_frame
	var apply_draft := InputEventKey.new()
	apply_draft.keycode = KEY_ENTER
	apply_draft.pressed = true
	check(interaction.handle(apply_draft),"path draft Enter was not consumed")
	check(interaction.transforming and not interaction._stamp_has_draft() and target.to_definition() != before,"pointer path did not commit and rearm on Enter")
	undo.undo()
	check(target.to_definition() == before,"pointer path one Undo")
	interaction.begin_stamp(preset)
	interaction._select_segment(interaction._stamp_mode,0)
	interaction._select_segment(interaction._stamp_application,3)
	interaction._stamp_spacing.value = 2
	interaction._stamp_scatter_spread.value = 1
	interaction._stamp_scatter_seed = 7319
	check(interaction._stamp_scatter_row.visible and interaction._stamp_scatter_options.visible and interaction._stamp_scatter_conform_row.visible,"scatter controls are not visible")
	check(not interaction._stamp_scatter_conform.button_pressed and not interaction._stamp_scatter_bend.editable,"surface conform should preserve rigid default")
	interaction._stamp_scatter_conform.button_pressed = true
	check(interaction._stamp_scatter_bend.editable,"surface conform limit did not become editable")
	var scatter_start: Vector2 = interaction._screen(Vector3(4.5,1.01,5.5)/target.normalized_density())
	var scatter_end: Vector2 = interaction._screen(Vector3(6.5,1.01,5.5)/target.normalized_density())
	press.pressed = true
	press.position = scatter_start
	workspace._on_viewport_input(press)
	motion.position = scatter_end
	workspace._on_viewport_input(motion)
	press.pressed = false
	press.position = scatter_end
	workspace._on_viewport_input(press)
	for frame in 6:
		await process_frame
	check(interaction.transforming and not interaction._stamp_drawing and target.to_definition() == before,"scatter release did not keep detached preview")
	check(not interaction._plan.has("error") and interaction._plan.has("scatter_seed") and workspace._active_tool_label.text.contains("россыпь"),"scatter UI did not build a valid preview")
	var draft_count: int = interaction._stamp_placements().size()
	var undo_draft := InputEventKey.new()
	undo_draft.keycode = KEY_Z
	undo_draft.pressed = true
	undo_draft.ctrl_pressed = true
	check(interaction.handle(undo_draft),"scatter draft Undo was not consumed")
	for frame in 3:
		await process_frame
	check(interaction._stamp_placements().size() == draft_count-1 and target.to_definition() == before,"scatter draft Undo did not retract one preview step")
	var redo_draft := InputEventKey.new()
	redo_draft.keycode = KEY_Z
	redo_draft.pressed = true
	redo_draft.ctrl_pressed = true
	redo_draft.shift_pressed = true
	check(interaction.handle(redo_draft),"scatter draft Redo was not consumed")
	for frame in 3:
		await process_frame
	check(interaction._stamp_placements().size() == draft_count and target.to_definition() == before,"scatter draft Redo did not restore one preview step")
	var scatter_knots: Array[Vector3i] = interaction._stamp_knots.duplicate()
	var first_scatter_seed: int = interaction._plan.scatter_seed
	var first_scatter_variant := [interaction._plan.placements.duplicate(),interaction._plan.scatter_turns.duplicate()]
	interaction._new_scatter_variant()
	for frame in 3:
		await process_frame
	check(interaction._stamp_knots == scatter_knots and interaction._plan.scatter_seed == first_scatter_seed+1,"new scatter variant changed the path or not the seed")
	check([interaction._plan.placements,interaction._plan.scatter_turns] != first_scatter_variant,"new scatter variant did not change preview")
	if "--capture" in OS.get_cmdline_user_args():
		var scatter_ancestor: Node = interaction._controls.get_parent()
		while scatter_ancestor != null and not scatter_ancestor is ScrollContainer:
			scatter_ancestor = scatter_ancestor.get_parent()
		if scatter_ancestor is ScrollContainer:
			scatter_ancestor.ensure_control_visible(interaction._stamp_scatter_options)
		for frame in 5:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://voxel_stamp_scatter.png")
		print("STAMP_SCATTER_CAPTURE ",ProjectSettings.globalize_path("user://voxel_stamp_scatter.png"))
	var scatter_expected: PackedByteArray = interaction._plan.properties.voxels.duplicate()
	interaction.commit()
	check(target.voxels == scatter_expected and interaction.transforming and not interaction._stamp_has_draft(),"scatter commit diverged from preview or did not rearm")
	undo.undo()
	check(target.to_definition() == before,"scatter one Undo")
	interaction.begin_stamp(preset)
	check(interaction._stamp_application.selected == 3 and int(interaction._stamp_spacing.value) == 2 and interaction._stamp_scatter_conform.button_pressed,"selected stamp settings were not restored for the Canvas session")
	interaction._select_segment(interaction._stamp_mode,0)
	interaction._select_segment(interaction._stamp_application,2)
	interaction._stamp_spacing.value = 2
	var line_a: Vector2 = interaction._screen(Vector3(3.5,1.01,3.5)/target.normalized_density())
	var line_b: Vector2 = interaction._screen(Vector3(7.5,1.01,3.5)/target.normalized_density())
	press.pressed = true
	press.position = line_a
	workspace._on_viewport_input(press)
	press.pressed = false
	workspace._on_viewport_input(press)
	for frame in 2:
		await process_frame
	check(interaction.transforming and interaction._stamp_line_started and target.to_definition() == before,"pointer line first click only anchors A")
	motion.position = line_b
	workspace._on_viewport_input(motion)
	for frame in 2:
		await process_frame
	check(interaction._plan.get("placements",[]).size() >= 3 and target.to_definition() == before,"pointer line hover preview detached")
	press.pressed = true
	press.position = line_b
	workspace._on_viewport_input(press)
	press.pressed = false
	workspace._on_viewport_input(press)
	for frame in 6:
		await process_frame
	check(interaction.transforming and interaction._stamp_draft_ready and target.to_definition() == before,"pointer line second click did not keep a detached draft")
	var line_draft_count: int = interaction._stamp_placements().size()
	check(interaction.handle(path_undo),"line draft Undo was not consumed")
	await process_frame
	check(interaction._stamp_placements().size() == line_draft_count-1 and target.to_definition() == before,"line draft Undo changed the Resource or missed one preview step")
	check(interaction.handle(path_redo),"line draft Redo was not consumed")
	await process_frame
	check(interaction.handle(apply_draft),"line draft Enter was not consumed")
	check(interaction.transforming and not interaction._stamp_has_draft() and target.to_definition() != before,"pointer line did not commit and rearm on Enter")
	undo.undo()
	check(target.to_definition() == before,"pointer line one Undo")
	interaction.begin_stamp(preset)
	interaction._select_segment(interaction._stamp_mode,0)
	interaction._select_segment(interaction._stamp_application,0)
	interaction._set_stamp_position(Vector3i(8,2,8))
	for frame in 3:
		await process_frame
	var stamp_resource_before_camera := target.to_definition()
	var yaw_before_camera := float(workspace._yaw)
	var camera_target_before := workspace._camera_target
	var rmb := InputEventMouseButton.new()
	rmb.button_index = MOUSE_BUTTON_RIGHT
	rmb.pressed = true
	rmb.position = interaction._screen(Vector3(8.5,2.5,8.5)/target.normalized_density())
	workspace._on_viewport_input(rmb)
	motion.position = rmb.position
	motion.relative = Vector2(32.0, -18.0)
	motion.button_mask = MOUSE_BUTTON_MASK_RIGHT
	workspace._on_viewport_input(motion)
	rmb.pressed = false
	workspace._on_viewport_input(rmb)
	check(not is_equal_approx(float(workspace._yaw),yaw_before_camera),"active stamp swallowed RMB camera orbit")
	check(interaction.transforming and target.to_definition() == stamp_resource_before_camera,"camera orbit cancelled or committed the active stamp")
	var mmb := InputEventMouseButton.new()
	mmb.button_index = MOUSE_BUTTON_MIDDLE
	mmb.pressed = true
	mmb.position = rmb.position
	workspace._on_viewport_input(mmb)
	motion.relative = Vector2(12.0,20.0)
	motion.button_mask = MOUSE_BUTTON_MASK_MIDDLE
	workspace._on_viewport_input(motion)
	mmb.pressed = false
	workspace._on_viewport_input(mmb)
	check(not workspace._camera_target.is_equal_approx(camera_target_before),"active stamp swallowed screen-plane camera pan")
	var zoom_before := float(workspace._ortho_size)
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	wheel.position = Vector2(workspace._viewport_container.size.x * 0.75,workspace._viewport_container.size.y * 0.35)
	workspace._on_viewport_input(wheel)
	check(float(workspace._ortho_size) < zoom_before and interaction.transforming,"active stamp swallowed wheel zoom or lost its draft")
	check(target.to_definition() == stamp_resource_before_camera,"camera navigation mutated the stamp target Resource")
	var expected: PackedByteArray = interaction._plan.properties.voxels.duplicate()
	var persistent_settings_id: String = interaction._stamp_settings_id
	interaction.commit()
	check(target.voxels == expected and interaction.transforming and not interaction._stamp_has_draft(),"UI commit does not keep the chosen stamp armed")
	check(interaction._stamp_settings_id == persistent_settings_id and interaction._stamp_application.selected == 0,"rearmed stamp lost its preset or settings")
	interaction._set_stamp_position(Vector3i(12,2,12))
	for frame in 3:
		await process_frame
	var expected_second: PackedByteArray = interaction._plan.properties.voxels.duplicate()
	interaction.commit()
	check(target.voxels == expected_second and interaction.transforming,"second placement required choosing the library card again")
	undo.undo()
	check(target.voxels == expected and interaction.transforming,"one Undo did not remove only the second persistent placement or dropped the selected stamp")
	undo.undo()
	check(target.to_definition().model == before.model and interaction.transforming,"second Undo did not remove the first persistent placement or dropped the selected stamp")
	undo.redo()
	undo.redo()
	check(target.voxels == expected_second,"persistent placements did not retain separate Redo steps")
	check(workspace._save(),"target save")
	var reopened := ResourceLoader.load(directory.path_join("target.tres"),"",ResourceLoader.CACHE_MODE_IGNORE)
	check(reopened.voxels == expected_second,"target reopen")
	undo.undo()
	check(target.voxels == expected,"UI Undo")
	undo.redo()
	check(target.voxels == expected_second,"UI Redo")
	interaction.cancel_gesture()
	workspace._selection_panel.set_selection(PackedInt32Array([0,17]))
	for frame in 3:
		await process_frame
	workspace._stamp_panel._title.text = "Мой второй штамп"
	workspace._stamp_panel._save()
	check(workspace._stamp_panel._entries.size() == 2,"UI library save")
	check(workspace._stamp_panel._card_buttons.size() == 2,"UI library card grid")
	check(workspace._stamp_panel._card_buttons[0].icon != null,"UI library derived thumbnail")
	workspace._stamp_panel._edit()
	check(workspace._resource.tags.has("stamp"),"edit preset in same Canvas")
	var saved_voxels: PackedByteArray = workspace._resource.voxels.duplicate()
	workspace._resource.voxels.fill(0)
	workspace.discard_changes()
	check(workspace._resource.voxels == saved_voxels,"preset discard")
	workspace.free()
