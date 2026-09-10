extends SceneTree
const Workspace = preload("res://addons/ember_import/ember_voxel_sculpt_workspace.gd")
const Shapes = preload("res://addons/ember_import/ember_voxel_shapes.gd")
const Model = preload("res://addons/ember_import/ember_voxel_sculpt_model.gd")
const Gesture = preload("res://addons/ember_import/ember_voxel_selection_gesture.gd")
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
func _init() -> void:
	_run.call_deferred()
func _run() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280,720)
	var source: EmberVoxelModelResource = Shapes.build("empty",Vector3i(16,8,16),16,Color.BROWN,"selection_ui","Доска").source
	for x in range(2,6):
		for y in 2:
			for z in range(2,6):
				source.voxels[Model.index_of(Vector3i(x,y,z),source.grid_size())] = 1
	var before := source.voxels.duplicate()
	var undo := UndoRedo.new()
	var workspace := Workspace.new()
	workspace.setup(null,undo)
	root.add_child(workspace)
	workspace.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	workspace.open_surface(source,"user://selection_interaction.tres")
	for frame in 5:
		await process_frame
	workspace._toggle_voxel_selection()
	var panel: VBoxContainer = workspace._selection_panel
	var interaction: Control = workspace._selection_interaction
	for operation in 3:
		interaction._operation = operation
		check(interaction.operation_hint() == ["Новое выделение","Добавить к выделению","Убрать из выделения"][operation],"operation hint matches mode")
	var visible := Gesture.new()
	visible.source = source
	visible.camera = workspace._camera
	visible.rectangle = Rect2(Vector2.ZERO,workspace._viewport_container.size)
	visible.viewport_scale = Vector2(workspace._viewport.size)/workspace._viewport_container.size
	while not visible.done:
		visible.step(128)
	check(visible.indices.size() > 0 and visible.indices.size() < 32,"visible surface excludes interior/back")
	panel._through.select(1)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2.ONE
	workspace._on_viewport_input(press)
	var motion := InputEventMouseMotion.new()
	motion.position = workspace._viewport_container.size-Vector2.ONE
	workspace._on_viewport_input(motion)
	for frame in 10:
		await process_frame
	check(panel.selected.is_empty() and source.voxels == before,"live marquee detached")
	check(interaction._ghost.visible,"live candidate ghost")
	press.pressed = false
	press.position = motion.position
	workspace._on_viewport_input(press)
	for frame in 30:
		await process_frame
	check(panel.selected.size() == 32 and not undo.has_undo(),"release selects through, not source")
	var whole: PackedInt32Array = panel.selection_indices()
	panel._mode.select(4)
	panel._mode.item_selected.emit(4)
	panel._depth.value = 1
	press.pressed = true
	press.position = interaction._screen(Vector3(2.5,2,2.5)/16.0)
	workspace._on_viewport_input(press)
	check(interaction._surface_marquee != null and interaction._surface_marquee.axis == 1,"surface gesture starts on top")
	motion.position = interaction._screen(Vector3(5.5,2,5.5)/16.0)
	workspace._on_viewport_input(motion)
	for frame in 10:
		await process_frame
	check(panel.selected.size() == 32 and interaction._ghost.visible,"surface preview leaves previous selection")
	if "--capture" in OS.get_cmdline_user_args():
		var surface_scroll := panel.get_parent().get_parent() as ScrollContainer
		surface_scroll.ensure_control_visible(panel._depth)
		for frame in 5:
			await process_frame
		root.get_texture().get_image().save_png("user://surface_marquee.png")
		print("CAPTURE ",ProjectSettings.globalize_path("user://surface_marquee.png"))
	press.pressed = false
	press.position = motion.position
	workspace._on_viewport_input(press)
	for frame in 15:
		await process_frame
	check(panel.selected.size() == 16 and source.voxels == before,"surface depth 1 selects top layer")
	panel.set_selection(whole)
	for frame in 3:
		await process_frame
	workspace._transform_voxel_selection()
	interaction._numbers[0].value = 4
	await process_frame
	await process_frame
	check(not interaction._apply.disabled and source.voxels == before,"inline preview valid detached")
	var end: Vector2 = interaction._arrow(0)[1]
	press.pressed = true
	press.position = end
	workspace._on_viewport_input(press)
	var unit := Vector3(1.0/16,0,0)
	motion.position = end + (interaction._screen(interaction._center+unit)-interaction._screen(interaction._center))*2
	workspace._on_viewport_input(motion)
	check(interaction._numbers[0].value == 6,"axis drag integer voxels")
	press.pressed = false
	press.position = motion.position
	workspace._on_viewport_input(press)
	for frame in 2:
		await process_frame
	if "--capture" in OS.get_cmdline_user_args():
		var ancestor: Node = interaction._controls.get_parent()
		while ancestor != null and not ancestor is ScrollContainer:
			ancestor = ancestor.get_parent()
		if ancestor is ScrollContainer:
			ancestor.ensure_control_visible(interaction._controls)
		for frame in 6:
			await process_frame
		root.get_texture().get_image().save_png("user://selection_interaction.png")
		print("CAPTURE ",ProjectSettings.globalize_path("user://selection_interaction.png"))
	interaction.commit()
	check(not interaction.transforming and source.voxels != before,"inline commit")
	undo.undo()
	check(source.voxels == before,"one undo")
	undo.redo()
	check(source.voxels != before,"redo")
	panel.set_selection(PackedInt32Array([Model.index_of(Vector3i(8,0,2),source.grid_size())]))
	for frame in 3:
		await process_frame
	workspace._transform_voxel_selection()
	interaction._numbers[0].value = -30
	await process_frame
	check(interaction._apply.disabled,"invalid destination disabled")
	var after := source.voxels.duplicate()
	var escape := InputEventKey.new()
	escape.pressed = true
	escape.keycode = KEY_ESCAPE
	workspace._input(escape)
	check(not interaction.transforming and source.voxels == after,"escape no mutation")
	workspace.free()
	undo.clear_history()
	undo.free()
	print("test_voxel_selection_interaction: ","PASS" if failures == 0 else "FAIL"," · ",failures)
	quit(failures)
