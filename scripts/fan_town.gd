extends Node3D
## Authored fan_town. Reimport is destructive; play walks the saved scene.

const PartyFollowers := preload("res://scripts/ember_party_followers.gd")

@export var map_id := "fan_town"
@export var player_debug_damage := 0.0

@onready var _hud: Label = $CanvasLayer/Gate
@onready var _map: EmberMapLoader = $Map

var _player: EmberPlayer
var _interaction_ui: EmberInteractionUi
var _inventory_ui: EmberInventoryUi
var _quest_journal_ui: EmberQuestJournalUi
var _pause_ui: EmberExplorePauseMenu
var _party_followers
var _party_mode_button: Button
var _shadow_acc := 0.0
var _last_shadow_at := Vector3(INF, INF, INF)
var _arrival_guard_region := ""


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	var progress := _progress()
	if progress:
		var restore_scene := progress.start_scene_path_for(scene_file_path)
		if not restore_scene.is_empty():
			if get_tree().change_scene_to_file(restore_scene) == OK:
				return
	var ts := _map.imported_tile_size if _map.imported_tile_size > 0.0 else 16.0
	if not _map.has_authored_content():
		_map.load_map(map_id)
		ts = _map.imported_tile_size
	_map.hydrate_region_runtime()
	_add_interaction_ui()
	_add_inventory_ui()
	_add_quest_journal_ui()
	_add_pause_ui()
	_spawn_player(ts)
	_add_party_followers(ts)
	_resume_combat_return_action()
	_map.hydrate_native_cutaway()
	_add_benchmark_overlay()
	_hud.text = _play_text()
	# Scene setup may include chunk hydration and party presentation. Start the
	# short anti-bounce window from the usable arrival frame, not from the first
	# spawn lookup before that work.
	if not _arrival_guard_region.is_empty():
		EmberMapTransition.guard_arrival(_arrival_guard_region)


func _physics_process(dt: float) -> void:
	if _player == null:
		return
	_shadow_acc += dt
	if _shadow_acc < 0.35:
		return
	_shadow_acc = 0.0
	var pos := _player.global_position
	if pos.distance_squared_to(_last_shadow_at) < 256.0:
		return
	_last_shadow_at = pos
	_map.refresh_omni_shadow_focus(pos)


func _input(event: InputEvent) -> void:
	# World party control belongs to the scene, not to a particular hero model.
	# Handling physical Tab here also makes it independent of focused HUD nodes.
	if not event is InputEventKey or not is_instance_valid(_player):
		return
	var key := event as InputEventKey
	if (
		key.pressed
		and not key.echo
		and key.physical_keycode == KEY_TAB
		and not _player._ui_blocks_movement()
	):
		_player.cycle_controlled_hero()
		get_viewport().set_input_as_handled()


func _spawn_player(ts: float) -> void:
	var progress := _progress()
	var player := EmberPlayer.new()
	player.name = "Player"
	player.tile_size = ts
	player.interact_hud = _hud
	player.interaction_ui = _interaction_ui
	player.inventory_ui = _inventory_ui
	player.quest_journal_ui = _quest_journal_ui
	player.pause_ui = _pause_ui
	player.progress_state = progress
	player.debug_damage_amount = maxf(0.0, player_debug_damage)
	player.respawn_requested.connect(_respawn_player)
	var target_region := EmberMapTransition.consume_spawn_region(map_id)
	var saved_spawn: Variant = (
		progress.consume_saved_spawn(map_id, ts)
		if progress and target_region.is_empty()
		else null
	)
	if not target_region.is_empty():
		player.position = _map.region_world(target_region) + Vector3(0.0, 6.0, 0.0)
		_arrival_guard_region = target_region
	elif saved_spawn is Vector3:
		player.position = saved_spawn
		var occupied := _map.occupying_region_id(player.position, ["trigger", "teleport"])
		if not occupied.is_empty():
			EmberMapTransition.guard_arrival(occupied)
			_arrival_guard_region = occupied
	else:
		player.position = _map.spawn_world() + Vector3(0.0, 6.0, 0.0)
	add_child(player)
	_player = player
	if progress:
		progress.set_world_context(map_id, player, ts)
	_map.refresh_omni_shadow_focus(player.global_position)
	_last_shadow_at = player.global_position
	var cam := EmberFollowCamera.new()
	cam.name = "FollowCamera"
	cam.target = player
	cam.fov = _map.camera_fov
	cam.follow_distance = _map.camera_distance
	cam.polar_angle = _map.camera_polar
	cam.yaw = _map.camera_yaw
	cam.look_height = _map.camera_look_height
	cam.cam_near = _map.camera_near
	cam.cam_far = _map.play_camera_far()
	add_child(cam)
	player.camera_rig = cam


func _respawn_player() -> void:
	if not is_instance_valid(_player) or not _player.is_defeated():
		return
	if is_instance_valid(_interaction_ui):
		_interaction_ui.close()
	if is_instance_valid(_inventory_ui):
		_inventory_ui.close()
	if is_instance_valid(_quest_journal_ui):
		_quest_journal_ui.close()
	_player.global_position = _map.spawn_world() + Vector3(0.0, 6.0, 0.0)
	_player.velocity = Vector3.ZERO
	var occupied := _map.occupying_region_id(_player.global_position, ["trigger", "teleport"])
	if not occupied.is_empty():
		EmberMapTransition.guard_arrival(occupied)
	var progress := _progress()
	if progress:
		progress.set_world_context(map_id, _player, _player.tile_size)
		progress.respawn_member(_player.controlled_hero_id)
	_player.complete_respawn()
	if is_instance_valid(_party_followers):
		_party_followers.reset_to_leader()
	_map.refresh_omni_shadow_focus(_player.global_position)
	_last_shadow_at = _player.global_position


func _add_interaction_ui() -> void:
	var ui := EmberInteractionUi.new()
	ui.name = "InteractionUI"
	$CanvasLayer.add_child(ui)
	_interaction_ui = ui


func _resume_combat_return_action() -> void:
	var action_id := EmberCombatTransition.consume_return_action()
	var loot_steps := EmberCombatTransition.consume_return_steps()
	if _interaction_ui != null and (not action_id.is_empty() or not loot_steps.is_empty()):
		_interaction_ui.call_deferred("activate_script_with_steps", action_id, loot_steps)


func _add_inventory_ui() -> void:
	var ui := EmberInventoryUi.new()
	ui.name = "InventoryUI"
	$CanvasLayer.add_child(ui)
	_inventory_ui = ui


func _add_quest_journal_ui() -> void:
	var ui := EmberQuestJournalUi.new()
	ui.name = "QuestJournalUI"
	ui.progress_state = _progress()
	$CanvasLayer.add_child(ui)
	_quest_journal_ui = ui


func _add_pause_ui() -> void:
	var ui := EmberExplorePauseMenu.new()
	ui.name = "ExplorePauseUI"
	ui.progress_state = _progress()
	ui.map_display_name = map_id
	ui.blockers = [_interaction_ui, _inventory_ui, _quest_journal_ui]
	$CanvasLayer.add_child(ui)
	_pause_ui = ui


func _add_party_followers(ts: float) -> void:
	var followers := PartyFollowers.new()
	followers.name = "PartyFollowers"
	followers.leader = _player
	followers.progress_state = _progress()
	followers.tile_size = ts
	followers.mode_changed.connect(_on_party_follow_mode_changed)
	add_child(followers)
	_party_followers = followers
	_player.party_followers = followers

	var button := Button.new()
	button.name = "PartyFollowModeButton"
	button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	button.offset_left = -274
	button.offset_top = 70
	button.offset_right = -18
	button.offset_bottom = 112
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.tooltip_text = "T: формация с живым перестроением / точный след паровозиком"
	button.pressed.connect(followers.toggle_mode)
	$CanvasLayer.add_child(button)
	_party_mode_button = button
	_on_party_follow_mode_changed(followers.mode, followers.mode_label())


func _on_party_follow_mode_changed(_mode: String, label: String) -> void:
	if _party_mode_button != null:
		_party_mode_button.text = "Отряд: %s · T" % label


func _add_benchmark_overlay() -> void:
	var overlay := EmberBenchmarkOverlay.new()
	overlay.name = "LightingBenchmark"
	overlay.map = _map
	$CanvasLayer.add_child(overlay)


func _play_text() -> String:
	return "\n".join([
		"Ember Godot — %s" % map_id,
		"Пропы в сцене. Reimport из пака затирает сдвиги.",
		"WASD ходить · Tab герой · F действие · I сумка · Q задания · T строй отряда · Esc меню · RMB yaw камеры · F3/F4 тест света",
	])


func _exit_tree() -> void:
	if Engine.is_editor_hint() or _player == null:
		return
	var progress := _progress()
	if progress:
		progress.save_autosave()


func _progress() -> EmberExploreState:
	return get_node_or_null("/root/EmberExploreProgress") as EmberExploreState
