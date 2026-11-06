extends "res://scripts/ember_explore_scene.gd"
## Isolated, non-story authoring scene. Continue the existing play controller.
## No duplicate floor: finish native ground/water preparation before play.
const STORAGE_ROOT := "user://ember-world-canvas-v1"
const StartupDiagnostics=preload("res://scripts/ember_startup_diagnostics.gd")
@export var sandbox_storage_root := STORAGE_ROOT
@export var hoshi_test_character := false

var _startup_complete := false
var _startup_layer: CanvasLayer
var _startup_title: Label
var _startup_status_label: Label
var _startup_participants: Array[Node] = []
var _startup_canvas_visible := true

func _enter_tree()->void:
	if not Engine.is_editor_hint():StartupDiagnostics.start()

func _ready() -> void:
	if Engine.is_editor_hint(): return
	if StartupDiagnostics.enabled():
		var diagnostics:=StartupDiagnostics.new()
		diagnostics.name="StartupDiagnostics"
		add_child(diagnostics)
	_begin_startup_screen()
	for child in get_children():
		if child.has_method("startup_preparation_status"):
			_startup_participants.append(child)
	var progress := _progress()
	var mira_trial := hoshi_test_character and "--mira-motion-trial" in OS.get_cmdline_user_args()
	if progress != null and not EmberMapTransition.test_mode(progress):
		var isolated_root := str(progress.get_meta("world_canvas_storage_root", sandbox_storage_root))
		if mira_trial:
			isolated_root = isolated_root.path_join("mira-motion-trial")
		if progress.storage_root != isolated_root:
			progress.storage_root = isolated_root
			progress.legacy_storage_root = isolated_root.path_join("legacy-unused")
			progress.combat_party_locked = false
			progress.set_world_context(map_id, null, 16.0)
			progress.reset_new_game()
			progress.load_latest_available()
		progress.set_active_hero_ids(["protagonist", "mira"], false)
		if mira_trial:
			progress.set_exploration_leader("mira")
	# Bounded preparation needs a focus before the normal controller creates
	# Player/FollowCamera. Keep saved/transition spawn consumption in its owner.
	var projection = _map._visual_surface_projection
	if is_instance_valid(projection) and projection.has_method("set_runtime_start_anchor"):
		projection.set_runtime_start_anchor(_map.spawn_world())
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
	if mira_trial:
		_install_mira_trial_visual()
	if hoshi_test_character:
		_player.install_hoshi_test_visual()
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
	# Saved/transition entry can differ. Hold actors until its real support is ready.
	if is_instance_valid(projection) and projection.has_method("set_runtime_start_anchor"):
		projection.set_runtime_start_anchor(_player.global_position)
		while is_inside_tree():
			var status := _startup_status()
			if status.ready:break
			_set_startup_text(status.text)
			await get_tree().process_frame
		if not is_inside_tree():return
		await get_tree().physics_frame
	if _map.world_look in [-1, 0] and get_tree().has_group(&"ember_solid_surface"):
		_set_startup_text("Подготавливаем материалы скал")
		preload("res://scripts/ember_solid_material_layers.gd").prepare_runtime_depth_programs()
	# Keep the cover while camera/reflection transforms reach a rendered frame.
	# process_frame works in native play and headless fixtures alike.
	for frame in 2: await get_tree().process_frame
	if not is_inside_tree(): return
	for entry in held:
		if is_instance_valid(entry.node): entry.node.process_mode = entry.mode
	_startup_complete = true
	StartupDiagnostics.stage("world_revealed")
	$CanvasLayer.visible = _startup_canvas_visible
	_startup_layer.queue_free()
	_startup_layer = null
	_startup_participants.clear()


func is_world_preparation_complete()->bool:
	return _startup_complete


func _startup_status() -> Dictionary:
	var projection = _map._visual_surface_projection
	if is_instance_valid(projection):
		var pending: int = projection.pending_tile_count() if projection.has_method("pending_tile_count") else projection.pending_chunk_count()
		if pending > 0 or projection.pending_physics_chunk_count() > 0:
			return {"ready": false, "text": "Подготавливаем землю"}
		if projection.has_method("pending_runtime_lod_count") and projection.pending_runtime_lod_count() > 0:
			return {"ready": false, "text": "Подготавливаем дальний вид земли и воды"}
		if projection is EmberTerrainPilotProjection and not projection._look_pending.is_empty():
			return {"ready": false, "text": "Подготавливаем облики земли"}
	elif _map.compact_terrain != null:
		return {"ready": false, "text": "Не удалось подготовить землю. Проверьте карту в редакторе."}
	for patch in get_tree().get_nodes_in_group(&"ember_grass_patches"):
		if _map.is_ancestor_of(patch) and patch.detail_preparation_pending():
			return {"ready": false, "text": "Подготавливаем растительность"}
	var anomaly := _map.get_node_or_null("WorldAnomaly")
	if anomaly != null and anomaly.enabled and _map.world_look == 0 and _map.compact_ground_style == 1 and not anomaly._prepared:
		return {"ready": false, "text": "Подготавливаем аномалию: " + anomaly.preparation_state}
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
	var label:="anomaly" if text.begins_with("Подготавливаем аномалию") else text
	if _startup_status_label.text!=text:
		if not (label=="anomaly" and _startup_status_label.text.begins_with("Подготавливаем аномалию")):
			StartupDiagnostics.stage(label)
		var diagnostics=get_node_or_null("StartupDiagnostics")
		if diagnostics!=null:diagnostics._phase=label
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
