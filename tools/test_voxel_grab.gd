extends SceneTree
const Fragment = preload("res://addons/ember_import/ember_voxel_fragment.gd")
const Shapes = preload("res://addons/ember_import/ember_voxel_shapes.gd")
const Model = preload("res://addons/ember_import/ember_voxel_sculpt_model.gd")
const Selection = preload("res://addons/ember_import/ember_voxel_selection.gd")
const Workspace = preload("res://addons/ember_import/ember_voxel_sculpt_workspace.gd")
var errors := 0

func check(value: bool, message: String) -> void:
	if not value:
		errors += 1
		push_error(message)

func complete(job: RefCounted) -> Dictionary:
	var iterations := 0
	while not job.done and iterations < 10000:
		job.step(1024,4000)
		iterations += 1
	check(job.done,"job completes")
	return job.result

func _init() -> void:
	_run.call_deferred()

func _run() -> void:
	var source: EmberVoxelModelResource = Shapes.build("empty",Vector3i(64,32,32),16,Color.SADDLE_BROWN,"grab_fixture","Доска · Grab").source
	source.palette.append(Color("e9ae72"))
	for channel in Fragment.CHANNELS:
		var data := PackedByteArray()
		data.resize(source.voxels.size())
		source.set(channel,data)
	source.voxel_part_ids.resize(source.voxels.size())
	source.merge_parts = PackedStringArray(["board"])
	var members := PackedInt32Array()
	for y in range(8,10):
		for z in range(12,20):
			for x in range(8,56):
				var index := Model.index_of(Vector3i(x,y,z),source.grid_size())
				source.voxels[index] = 2 if z % 3 == 0 else 1
				source.collision_voxels[index] = 1
				source.voxel_part_ids[index] = 1
				source.shine[index] = 20 + z
				source.transparency[index] = 0
				source.transmittance[index] = 0
				source.emissive[index] = 0
				members.append(index)
	members.sort()
	source.voxel_groups = [{"id":"grain","name":"Grain","indices":members,"locked":false}]
	var initial := source.to_definition().duplicate(true)
	var center := Vector3(32.5,9.5,16.5)
	var job := Fragment.start_grab(source,center,12,Vector3(0,6,0),75)
	check(not job.done,"incremental plan")
	job.step(1,4000)
	check(not job.done,"one cell does not process whole volume")
	var plan := complete(job)
	print("Grab fixture kernel ms: ",job.elapsed_usec / 1000.0)
	check(not plan.has("error"),"grab plan: " + str(plan.get("error","")))
	check(source.to_definition() == initial,"preview pure")
	if plan.has("error"):
		quit(1)
		return
	for destination in job.mapping:
		var original: int = job.mapping[destination]
		for channel in Fragment.CHANNELS:
			check(plan.properties[channel][destination] == source.get(channel)[original],"preserve " + channel)
		check(plan.properties.voxel_part_ids[destination] == 1,"part IDs follow volume")
	check(job.warp(center).is_equal_approx(center + Vector3(0,6,0)),"capture follows cursor exactly")
	check(job.warp(Vector3(8.5,9.5,16.5)).is_equal_approx(Vector3(8.5,9.5,16.5)),"outside radius stays fixed")
	var undo := UndoRedo.new()
	var actions := EmberVoxelSculptActions.new()
	actions.configure(undo)
	check(actions.apply_fragment(source,plan),"commit")
	check(source.validation_errors().is_empty(),"validation after resampling")
	_check_connected(source)
	var bent := source.to_definition().duplicate(true)
	undo.undo()
	check(source.to_definition() == initial and not undo.has_undo(),"one undo restores all data")
	undo.redo()
	check(source.to_definition() == bent,"redo exact")
	check(not actions.apply_fragment(source,plan),"stale rejected")
	var path := "user://ember-tests/grab-%d.tres" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://ember-tests"))
	check(ResourceSaver.save(source,path) == OK,"save")
	var reopened := ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as EmberVoxelModelResource
	var definition := reopened.to_definition()
	definition.erase("_resourcePath")
	var expected := bent.duplicate(true)
	expected.erase("_resourcePath")
	check(definition == expected,"reopen data")
	undo.undo()
	check(complete(Fragment.start_grab(source,center,12,Vector3.ZERO)).has("error"),"zero no-op")
	check(complete(Fragment.start_grab(source,center,12,Vector3(0,40,0))).has("error"),"bounds no crop")
	check(complete(Fragment.start_grab(source,center,12,Vector3(0,6,0),75,Rect2i(),10)).has("error"),"slice bound")
	check(complete(Fragment.start_grab(source,center,12,Vector3(0,6,0),75,Rect2i(0,0,1,1))).has("error"),"working region bound")
	source.voxel_groups[0].locked = true
	check(complete(Fragment.start_grab(source,center,12,Vector3(0,6,0))).has("error"),"locked volume")
	source.voxel_groups[0].locked = false
	source.emissive_lights = [{"id":"fixture"}]
	check(complete(Fragment.start_grab(source,center,12,Vector3(0,6,0))).has("error"),"authored lights protected")
	source.emissive_lights.clear()
	var columns := source.grid_size().x * source.grid_size().z
	source.surface_fill_levels.resize(columns)
	source.surface_fill_materials.resize(columns)
	source.surface_fill_palette.resize(columns)
	check(complete(Fragment.start_grab(source,center,12,Vector3(0,6,0))).has("error"),"water fill protected")
	source.surface_fill_levels.clear()
	source.surface_fill_materials.clear()
	source.surface_fill_palette.clear()
	check(complete(Fragment.start_grab(source,center,12,Vector3(0,-5,0))).has("properties"),"opposite drag direction")
	var hard := Fragment.start_grab(source,center,12,Vector3(0,6,0),25)
	var soft := Fragment.start_grab(source,center,12,Vector3(0,6,0),100)
	var neighbor := center + Vector3(6,0,0)
	check(hard.warp(neighbor).distance_to(neighbor) > soft.warp(neighbor).distance_to(neighbor),"softness changes neighboring influence")
	var thin := source.duplicate(true) as EmberVoxelModelResource
	var thin_members := PackedInt32Array()
	for index in members:
		if Selection.cell_of(index,source.grid_size()).y == 8:
			for channel in Fragment.CHANNELS:
				var data: PackedByteArray = thin.get(channel)
				data[index] = 0
				thin.set(channel,data)
			thin.voxel_part_ids[index] = 0
		else:
			thin_members.append(index)
	thin.voxel_groups[0].indices = thin_members
	var thin_plan := complete(Fragment.start_grab(thin,center,12,Vector3(4,6,-3)))
	check(not thin_plan.has("error"),"one-voxel board warp")
	if not thin_plan.has("error"):
		for key in thin_plan.properties:
			thin.set(key,thin_plan.properties[key])
		_check_connected(thin)
	await _workspace_checks(source,undo)
	var large: EmberVoxelModelResource = Shapes.build("empty",Vector3i(128,32,128),16,Color.BROWN,"grab_large","Large").source
	for y in range(10,12):
		for z in range(8,120):
			for x in range(8,120):
				large.voxels[Model.index_of(Vector3i(x,y,z),large.grid_size())] = 1
	var large_job := Fragment.start_grab(large,Vector3(64.5,11.5,64.5),32,Vector3(8,8,4))
	var large_plan := complete(large_job)
	check(not large_plan.has("error"),"representative524288-cell board")
	print("Grab radius32 / 524288 cells kernel ms: ",large_job.elapsed_usec / 1000.0)
	undo.clear_history()
	undo.free()
	print("test_voxel_grab: ","PASS" if errors == 0 else "FAIL"," · ",errors)
	quit(errors)

func _check_connected(source: EmberVoxelModelResource) -> void:
	var occupied := {}
	for index in source.voxels.size():
		if source.voxels[index] != 0:
			occupied[index] = true
	var seen := {}
	var queue: Array[int] = [int(occupied.keys()[0])]
	seen[queue[0]] = true
	var cursor := 0
	while cursor < queue.size():
		var cell := Selection.cell_of(queue[cursor],source.grid_size())
		cursor += 1
		for direction in Model.SURFACE_FACE_DIRECTIONS:
			var neighbor: Vector3i = cell + direction
			if not Model.contains(neighbor,source.grid_size()):
				continue
			var index := Model.index_of(neighbor,source.grid_size())
			if occupied.has(index) and not seen.has(index):
				seen[index] = true
				queue.append(index)
	check(seen.size() == occupied.size(),"thin board remains face-connected")

func _screen(workspace: Control, point: Vector3) -> Vector2:
	return workspace._camera.unproject_position(point) * workspace._viewport_container.size / Vector2(workspace._viewport.size)

func _button(position: Vector2, pressed: bool) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.position = position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	return event

func _workspace_checks(source: EmberVoxelModelResource,undo: UndoRedo) -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280,720)
	var workspace := Workspace.new()
	workspace.setup(null,undo)
	root.add_child(workspace)
	workspace.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	workspace.open_surface(source,"user://ember-tests/grab-workspace.tres")
	for frame in 12:
		await process_frame
	workspace._activate_tool_id(Model.TOOL_GRAB)
	workspace._select_option_metadata(workspace._radius,12)
	workspace._on_brush_setting_changed()
	check(workspace._grab_softness.visible and not workspace._depth.visible and not workspace._application_mode.visible,"only grab settings")
	var initial := source.to_definition().duplicate(true)
	var start := _screen(workspace,Vector3(32.5,10,16.5) / 16.0)
	check(workspace._pick_at(start).has("hit"),"visible board pick")
	workspace._on_viewport_input(_button(start,true))
	check(workspace._grab_interaction.active,"LMB capture")
	var target := start + Vector2(0,-45)
	var motion := InputEventMouseMotion.new()
	motion.position = target
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	workspace._on_viewport_input(motion)
	for frame in 300:
		await process_frame
		if not workspace._grab_interaction.plan.is_empty() and workspace._grab_interaction.job == null:
			break
	check(source.to_definition() == initial,"drag preview does not mutate canonical resource")
	print("WORKSPACE GRAB ",workspace._grab_interaction.planned_displacement," ",workspace._grab_interaction.plan.get("error","ready"))
	check(workspace._grab_preview_resource != null,"preview in existing chunk renderer")
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		for frame in 12:
			await process_frame
		RenderingServer.force_draw(false)
		var path := "user://grab-canvas-preview.png"
		check(root.get_texture().get_image().save_png(path) == OK,"native canvas capture")
		print("CAPTURE ",ProjectSettings.globalize_path(path))
	check(not workspace.save_changes(),"save cannot publish unfinished drag")
	var save_key := InputEventKey.new()
	save_key.pressed = true
	save_key.keycode = KEY_S
	save_key.ctrl_pressed = true
	workspace._input(save_key)
	check(workspace._grab_interaction.active and source.to_definition() == initial,"Ctrl+S blocks saving without discarding gesture")
	var draft_definition: Dictionary = workspace._grab_preview_resource.to_definition() if workspace._grab_preview_resource != null else {}
	workspace._on_viewport_input(_button(target,false))
	for frame in 300:
		await process_frame
		if not workspace._grab_interaction.active:
			break
	check(not workspace._grab_interaction.active and source.to_definition() == draft_definition,"release commits exact preview")
	undo.undo()
	check(source.to_definition() == initial,"pointer-up one undo")
	undo.redo()
	check(source.to_definition() == draft_definition,"pointer-up redo")
	undo.undo()
	workspace._on_viewport_input(_button(start,true))
	workspace._on_viewport_input(motion)
	for frame in 6:
		await process_frame
	var escape := InputEventKey.new()
	escape.pressed = true
	escape.keycode = KEY_ESCAPE
	workspace._input(escape)
	check(not workspace._grab_interaction.active and workspace._grab_preview_resource == null and source.to_definition() == initial,"Esc discards all preview work")
	workspace._on_viewport_input(_button(start,true))
	workspace._on_viewport_input(motion)
	workspace._activate_tool_id(Model.TOOL_PAINT)
	check(not workspace._grab_interaction.active and source.to_definition() == initial,"switching tools discards unfinished grab")
	workspace._clip_bounds_control.button_pressed = true
	workspace._on_height_slice_changed(true,12)
	workspace._slice_control.restore_view(12)
	check(not workspace._tool.is_item_disabled(workspace._find_tool_item(Model.TOOL_GRAB)),"Grab available at editable slice")
	workspace._activate_tool_id(Model.TOOL_GRAB)
	start = _screen(workspace,Vector3(32.5,10,16.5) / 16.0)
	target = start + Vector2(0,-45)
	motion.position = target
	workspace._on_viewport_input(_button(start,true))
	workspace._on_viewport_input(motion)
	for frame in 300:
		await process_frame
		if not workspace._grab_interaction.plan.is_empty() and workspace._grab_interaction.job == null:
			break
	check(workspace._grab_preview_resource != null and int(workspace._grab_interaction.plan.get("clipped_voxels",0)) > 0,"global toggle clips Grab at slice with live preview")
	check(source.to_definition() == initial,"cropped preview remains transient")
	draft_definition = workspace._grab_preview_resource.to_definition() if workspace._grab_preview_resource != null else {}
	if "--capture" in OS.get_cmdline_user_args() and DisplayServer.get_name() != "headless":
		workspace._sidebar_tabs.current_tab = 0
		workspace._parts_sections.current_tab = 2
		for frame in 16:
			await process_frame
		RenderingServer.force_draw(false)
		check(root.get_texture().get_image().save_png("user://grab-boundary-clip-preview.png") == OK,"native clipped Grab capture")
		print("CLIP CAPTURE ",ProjectSettings.globalize_path("user://grab-boundary-clip-preview.png"))
	workspace._on_viewport_input(_button(target,false))
	for frame in 300:
		await process_frame
		if not workspace._grab_interaction.active:
			break
	check(source.to_definition() == draft_definition,"clipped pointer-up equals preview")
	undo.undo()
	check(source.to_definition() == initial,"Grab Undo restores cropped voxels")
	undo.redo()
	check(source.to_definition() == draft_definition,"Grab cropped Redo exact")
	undo.undo()
	workspace._on_viewport_input(_button(start,true))
	workspace._on_viewport_input(motion)
	for frame in 6:
		await process_frame
	workspace._clip_bounds_control.button_pressed = false
	check(not workspace._grab_interaction.active and workspace._grab_preview_resource == null and source.to_definition() == initial,"changing global boundary mode discards unfinished Grab")
	workspace.free()
