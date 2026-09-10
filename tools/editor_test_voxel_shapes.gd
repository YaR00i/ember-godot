@tool
extends EditorPlugin
## Enable only in a disposable ember-canvas-smoke-* project.
const Dialog = preload("res://addons/ember_import/ember_voxel_shape_dialog.gd")
const Session = preload("res://addons/ember_import/ember_voxel_object_session.gd")
var errors: Array[String] = []

func _enter_tree() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	if not value:
		errors.append(message)

func frames(count: int) -> void:
	for frame in count:
		await get_tree().process_frame

func capture(label: String, viewport: Viewport = null) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await frames(15)
	# Hidden/background Windows editors may not schedule a presentation frame.
	RenderingServer.force_draw(false)
	var path := "user://voxel-shapes-%s-%d.png" % [label, OS.get_process_id()]
	var target := viewport if viewport != null else EditorInterface.get_base_control().get_viewport()
	target.get_texture().get_image().save_png(path)
	print("VOXEL_SHAPES_CAPTURE ", ProjectSettings.globalize_path(path))

func settle_filesystem() -> void:
	await frames(10)
	for attempt in 200:
		if not EditorInterface.get_resource_filesystem().is_scanning():
			return
		await frames(5)

func save_scene_when_ready() -> int:
	await settle_filesystem()
	return EditorInterface.save_scene()

func _run() -> void:
	if not ProjectSettings.globalize_path("res://").contains("ember-canvas-smoke-"):
		push_error("Only disposable ember-canvas-smoke project is allowed")
		return
	await frames(60)
	var scene: Node3D
	for attempt in 10:
		EditorInterface.open_scene_from_path("res://scenes/test_pier.tscn")
		await frames(30)
		scene = EditorInterface.get_edited_scene_root() as Node3D
		if scene != null and scene.scene_file_path == "res://scenes/test_pier.tscn":
			break
	if scene == null or scene.scene_file_path != "res://scenes/test_pier.tscn":
		push_error("Cannot activate test_pier")
		get_tree().quit(1)
		return
	print("SHAPES_EDITOR ready, hint=", Engine.is_editor_hint())
	var parent := scene.get_node("Map/Props") as Node3D
	var dialog := Dialog.new()
	EditorInterface.get_base_control().add_child(dialog)
	dialog.open_for(scene,parent,get_undo_redo(),Vector3(192,0,164))
	dialog._prepare()
	var result := {"prop": null}
	dialog.created.connect(func(prop: EmberVoxelProp): result.prop = prop)
	dialog._commit()
	var prop: EmberVoxelProp = result.prop
	check(prop != null, "editor empty creation")
	if prop == null:
		get_tree().quit(1)
		return
	var rebuilt := EmberVoxelPrefab.ensure_saved(prop.model_id,16.0,{},true)
	check(rebuilt != null and EmberVoxelPrefab.validate_packed(prop.model_id,rebuilt).ok, "canonical empty rebuild")
	var edit := Session.new()
	check(edit.open(prop,scene,get_undo_redo()), "empty session " + edit.error)
	var canvas = EditorInterface.get_editor_main_screen().get_node("EmberSurfaceCanvasWorkspace")
	canvas.open_object(edit)
	EditorInterface.set_main_screen_editor("Surface Canvas")
	await frames(20)
	var point: Vector2 = canvas._camera.unproject_position(Vector3(0.25,0,0.25)) * canvas._viewport_container.size / Vector2(canvas._viewport.size)
	check(canvas._pick_at(point).get("empty_floor",false), "editor empty ray target")
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.button_mask = MOUSE_BUTTON_MASK_LEFT
	press.position = point
	press.pressed = true
	canvas._on_viewport_input(press)
	var release := press.duplicate() as InputEventMouseButton
	release.pressed = false
	release.button_mask = 0
	canvas._on_viewport_input(release)
	check(edit.draft.voxels.count(1) > 0, "editor first mouse stroke")
	check(canvas.save_changes(), "editor first Save " + edit.error)
	check(prop.get_node("Collision/Shape").shape != null, "editor first collider")
	check((await save_scene_when_ready()) == OK, "editor scene save")
	var history := get_undo_redo().get_history_undo_redo(get_undo_redo().get_object_history_id(scene))
	history.undo()
	check(prop.get_node("Collision/Shape").shape == null, "editor Save Undo")
	history.redo()
	check(prop.get_node("Collision/Shape").shape != null, "editor Save Redo")
	var reopened := (ResourceLoader.load(scene.scene_file_path,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene).instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
	check(reopened.get_node(NodePath("Map/Props/" + str(prop.name))).get_node("Collision/Shape").shape != null, "editor scene reopen")
	reopened.free()
	dialog._kind.select(1)
	dialog._kind_changed()
	dialog._sizes[0].value = 16
	dialog._sizes[1].value = 2
	dialog._sizes[2].value = 32
	dialog.open_for(scene,parent,get_undo_redo(),Vector3(192,0,200))
	dialog._prepare()
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(Vector2i(1600,900))
	await capture("dialog-board",dialog)
	check(dialog.size.x <= 900 and dialog.size.y <= 850, "dialog exceeds bounded native layout: " + str(dialog.size))
	print("SHAPES_DIALOG_SIZE ",dialog.size)
	dialog._commit()
	var board: EmberVoxelProp = result.prop
	var board_edit := Session.new()
	check(board_edit.open(board,scene,get_undo_redo()), "board session")
	canvas.open_object(board_edit)
	EditorInterface.edit_node(board)
	await capture("created-board")
	dialog.queue_free()
	# Regression: publish/instance while switching between two authored maps.
	for scene_path in ["res://scenes/agent_sandbox.tscn", "res://scenes/test_pier.tscn"]:
		EditorInterface.set_main_screen_editor("3D")
		EditorInterface.open_scene_from_path(scene_path)
		await frames(40)
		var current := EditorInterface.get_edited_scene_root() as Node3D
		check(current.scene_file_path == scene_path, "cross-map current root")
		var creation := preload("res://addons/ember_import/ember_voxel_shape_creation.gd").new()
		creation.prepare("block",Vector3i(16,16,16),16,Color.RED,"CrossMap")
		var created := creation.commit(current,current,get_undo_redo(),Vector3(100,0,100))
		EditorInterface.edit_node(created)
		await frames(15)
		await capture("object-toolbar")
		check((await save_scene_when_ready()) == OK, "cross-map save")
		var growth_session := Session.new()
		check(growth_session.open(created,current,get_undo_redo()), "cross-map session")
		canvas.open_object(growth_session)
		EditorInterface.set_main_screen_editor("Surface Canvas")
		canvas._show_canvas_growth()
		for child in canvas.get_children():
			if child is ConfirmationDialog and child.title == "Расширить холст объекта":
				await capture("growth-dialog", child)
				child.queue_free()
		canvas._actions.grow_canvas(growth_session.draft,Vector3i(32,32,32))
		check(canvas.save_changes(), "editor growth save: " + growth_session.error)
		check((await save_scene_when_ready()) == OK, "editor grown scene save")
		await frames(15)
		var saved_scene := ResourceLoader.load(scene_path,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		var saved_instance := saved_scene.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
		check(saved_instance.get_node(NodePath(str(created.name))).model_id == created.model_id, "cross-map reopen")
		saved_instance.free()
	check(canvas.create_object_callback.is_valid(), "Canvas create callback missing")
	canvas.create_object_callback.call()
	await frames(10)
	var creation_opened := false
	for child in EditorInterface.get_base_control().get_children():
		if child is Dialog and child.visible:
			creation_opened = true
			child.hide()
			child.canceled.emit()
	check(creation_opened, "Canvas create callback did not open dialog")
	await frames(10)
	await capture("grown-object")
	await settle_filesystem()
	print("SHAPES_EDITOR functional: ", "PASS" if errors.is_empty() else "FAIL", " errors=",errors)
	get_tree().quit(0 if errors.is_empty() else 1)
