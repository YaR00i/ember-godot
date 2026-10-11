extends "res://scripts/ember_explore_scene.gd"
## Isolated, non-story authoring scene. Continue the existing play controller.
## No duplicate floor: finish native ground/water preparation before play.
const STORAGE_ROOT := "user://ember-world-canvas-v1"
@export var sandbox_storage_root := STORAGE_ROOT

var _startup_complete := false
var _startup_layer: CanvasLayer
var _startup_title: Label
var _startup_status_label: Label
var _startup_participants: Array[Node] = []
var _startup_canvas_visible := true

func _ready() -> void:
	if Engine.is_editor_hint(): return
	_begin_startup_screen()
	for child in get_children():
		if child.has_method("startup_preparation_status"):
			_startup_participants.append(child)
	var progress := _progress()
	if progress != null:
		var isolated_root := str(progress.get_meta("world_canvas_storage_root", sandbox_storage_root))
		if progress.storage_root != isolated_root:
			progress.storage_root = isolated_root
			progress.legacy_storage_root = isolated_root.path_join("legacy-unused")
			progress.combat_party_locked = false
			progress.set_world_context(map_id, null, 16.0)
			progress.reset_new_game()
			progress.load_latest_available()
		progress.set_active_hero_ids(["protagonist", "mira"], false)
	while is_inside_tree():
		var status := _startup_status()
		_set_startup_text(status.text)
		if status.ready: break
		await get_tree().process_frame
	if not is_inside_tree(): return
	# Let newly attached physics shapes reach the physics server before spawning.
	await get_tree().physics_frame
	super._ready()
	if not is_instance_valid(_player): return
	var held: Array[Dictionary] = []
	for node in [_player, _party_followers, _interaction_ui, _inventory_ui, _quest_journal_ui, _pause_ui]:
		if is_instance_valid(node):
			held.append({"node": node, "mode": node.process_mode})
			node.process_mode = Node.PROCESS_MODE_DISABLED
	_set_startup_text("Настраиваем камеру")
	for participant in _startup_participants:
		if is_instance_valid(participant) and participant.has_method("initialize_startup_camera"):
			participant.initialize_startup_camera()
	_player.camera_rig._process(0.0)
	# Keep the cover while camera/reflection transforms reach a rendered frame.
	# process_frame works in native play and headless fixtures alike.
	for frame in 2: await get_tree().process_frame
	if not is_inside_tree(): return
	for entry in held:
		if is_instance_valid(entry.node): entry.node.process_mode = entry.mode
	_startup_complete = true
	$CanvasLayer.visible = _startup_canvas_visible
	_startup_layer.queue_free()
	_startup_layer = null
	_startup_participants.clear()


func _startup_status() -> Dictionary:
	var projection = _map._visual_surface_projection
	if is_instance_valid(projection):
		var pending: int = projection.pending_tile_count() if projection.has_method("pending_tile_count") else projection.pending_chunk_count()
		if pending > 0 or projection.pending_physics_chunk_count() > 0:
			return {"ready": false, "text": "Подготавливаем землю"}
		if projection.has_method("pending_runtime_lod_count") and projection.pending_runtime_lod_count() > 0:
			return {"ready": false, "text": "Подготавливаем дальний вид земли и воды"}
	elif _map.compact_terrain != null:
		return {"ready": false, "text": "Не удалось подготовить землю. Проверьте карту в редакторе."}
	for participant in _startup_participants:
		if not is_instance_valid(participant): continue
		var status: Dictionary = participant.startup_preparation_status()
		if not status.ready: return status
	return {"ready": true, "text": "Подготавливаем сцену"}


func _begin_startup_screen() -> void:
	_startup_canvas_visible = $CanvasLayer.visible
	$CanvasLayer.visible = false
	_startup_layer = CanvasLayer.new()
	_startup_layer.name = "WorldLoadingScreen"
	_startup_layer.layer = 1000
	add_child(_startup_layer)
	var background := ColorRect.new()
	background.color = Color(0.055, 0.085, 0.11, 1.0)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_startup_layer.add_child(background)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_startup_layer.add_child(center)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 18)
	center.add_child(rows)
	_startup_title = Label.new()
	_startup_title.text = "Подготовка мира…"
	_startup_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_startup_title.add_theme_font_size_override("font_size", 26)
	rows.add_child(_startup_title)
	_startup_status_label = Label.new()
	_startup_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_startup_status_label.add_theme_font_size_override("font_size", 18)
	_startup_status_label.modulate = Color(0.75, 0.84, 0.88)
	rows.add_child(_startup_status_label)
	var hint := Label.new()
	hint.text = "Esc — закрыть"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 14)
	hint.modulate = Color(0.5, 0.6, 0.65)
	rows.add_child(hint)


func _set_startup_text(text: String) -> void:
	_startup_status_label.text = text
	_startup_title.text = "Подготовка мира" + ".".repeat(1 + (Time.get_ticks_msec() / 450) % 3)


func _input(event: InputEvent) -> void:
	if not _startup_complete:
		if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE:
			get_tree().quit()
		get_viewport().set_input_as_handled()
		return
	super._input(event)


func _physics_process(delta: float) -> void:
	if _startup_complete: super._physics_process(delta)

func _play_text() -> String:
	return "ХОЛСТ МИРА · берег и вода\nWASD — идти · Tab — герой · I — сумка · Esc — меню · RMB — камера"
