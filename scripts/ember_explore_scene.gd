extends Node3D
## Shared play controller for authored exploration scenes; no scene owns a second runtime.

const PartyFollowers := preload("res://scripts/ember_party_followers.gd")
const WorldItem := preload("res://scripts/ember_world_item_3d.gd")

@export var map_id := EmberMapTransition.DEFAULT_MAP_ID
@export var player_debug_damage := 0.0
@export var recovery_floor_y := -256.0

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
var _world_item_records: Dictionary = {}
var _world_item_placements: Dictionary = {}


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
	_map.refresh_region_runtime()
	_add_interaction_ui()
	_add_inventory_ui()
	_add_quest_journal_ui()
	_add_pause_ui()
	_spawn_player(ts)
	if progress:
		progress.progress_changed.connect(_refresh_world_items)
		_refresh_world_items()
	_add_party_followers(ts)
	var recovery := preload("res://scripts/ember_world_recovery.gd").new()
	recovery.name = "WorldRecovery"
	recovery.floor_y = recovery_floor_y
	recovery.character_return = _recover_fallen_character
	add_child(recovery)
	var focus := preload("res://scripts/ember_interaction_focus.gd").new()
	focus.name = "InteractionFocus"
	focus.player = _player
	add_child(focus)
	var tracker := preload("res://scripts/ember_quest_tracker_ui.gd").new()
	tracker.name = "QuestTrackerUI"
	tracker.progress_state = progress
	$CanvasLayer.add_child(tracker)
	_resume_combat_return_action()
	_map.refresh_cutaway_runtime()
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
	if _progress() != null and _progress().combat_party_locked: return
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
	player.position = _map.safe_spawn_world(player.position)
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

func _recover_fallen_character(body: CharacterBody3D) -> void:
	# Technical recovery is not defeat/respawn: HP, inventory and quest flags stay.
	if body.has_meta("ember_carried_item"):
		var held: WeakRef = body.get_meta("ember_carried_item")
		if is_instance_valid(held.get_ref()): held.get_ref().recover_from_void()
	body.global_position = _map.spawn_world() + Vector3(0, 6, 0)
	body.velocity = Vector3.ZERO
	if body == _player:
		_player._cancel_step()
		if is_instance_valid(_party_followers): _party_followers.reset_to_leader()


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
	ui.script_requested.connect(func(id: String) -> void:
		ui.close()
		_interaction_ui.activate_script(id))
	ui.drop_requested.connect(_drop_inventory_item)


func _drop_inventory_item(item_id: String) -> void:
	if not is_instance_valid(_player): return
	var at := _player.global_position - _player.global_basis.z * 8.0 + Vector3.UP * 8.0
	var query := PhysicsRayQueryParameters3D.create(at+Vector3.UP*8.0,at-Vector3.UP*128.0,1)
	if _player.get_world_3d().direct_space_state.intersect_ray(query).is_empty():
		_inventory_ui.show_item_feedback("Здесь нет поверхности, на которую можно положить предмет")
		return
	var result := _progress().drop_inventory_item(item_id,map_id,at)
	_inventory_ui.show_item_feedback("Предмет выброшен рядом" if result.ok else "Не удалось выбросить предмет")


func _refresh_world_items() -> void:
	if not is_inside_tree(): return
	var progress := _progress()
	if progress == null or not is_inside_tree(): return
	var restored := not is_same(_world_item_records,progress.world_items)
	_world_item_records = progress.world_items
	var existing := {}
	for body in get_tree().get_nodes_in_group("ember_world_item_bodies"):
		if not is_ancestor_of(body) or body.is_queued_for_deletion(): continue
		if body.authored_pickup: _world_item_placements[body.pickup_id] = body.placement_settings()
		body.register_authored_item()
		body.refresh_availability()
		existing[body.pickup_id] = body
		if restored or int(progress.world_items.get(body.pickup_id,{}).get("count",0)) <= 0:
			body.restore_progress()
	for id in _world_item_placements:
		var source: Dictionary = _world_item_placements[id]
		progress.ensure_authored_item(id,str(source.itemId),map_id,source.transform)
	for id in progress.world_items:
		var row: Dictionary = progress.world_items[id]
		if row.mapId != map_id or int(row.count) <= 0 or existing.has(id): continue
		var item := EmberItemCatalog.definition(str(row.itemId))
		if str(item.get("worldScene","")).is_empty(): continue
		var body := WorldItem.new()
		body.name = str(id).validate_node_name()
		body.pickup_id = id
		body.item_id = row.itemId
		body.map_id = map_id
		var placement: Dictionary = _world_item_placements.get(id,{})
		body.authored_pickup = not placement.is_empty()
		body.available_flag_id = str(placement.get("availableFlagId",""))
		body.carryable = bool(placement.get("carryable", item.get("worldCarryable", false)))
		body.start_quest_id = str(placement.get("startQuestId", ""))
		body.pushable = bool(placement.get("pushable", false))
		body.item_mass = float(placement.get("itemMass", 0.25))
		body.visual_size = float(placement.get("visualSize", 16.0))
		body.return_radius = float(placement.get("returnRadius", 0.0))
		body.breakable = bool(placement.get("breakable", false))
		body.break_effect = placement.get("breakEffect") as PackedScene
		body.break_impact_speed = float(placement.get("breakImpactSpeed",36.0))
		body.throw_damage = int(placement.get("throwDamage",8))
		if not placement.is_empty(): body.transform = global_transform.affine_inverse()*placement.transform
		else:
			var origin := WorldItem.Records.vector(row.position)
			if origin.y < recovery_floor_y: origin = _map.spawn_world() + Vector3.UP * 6.0
			body.transform = global_transform.affine_inverse() * Transform3D(Basis.from_euler(WorldItem.Records.vector(row.rotation)), origin)
		body.progress_state = progress
		add_child(body)


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
		"WASD ходить/толкать · Tab герой · F действие · G бросить · I сумка · Q задания · T строй отряда · Esc меню · RMB yaw камеры · F3/F4 тест света",
	])


func _exit_tree() -> void:
	if Engine.is_editor_hint() or _player == null:
		return
	var progress := _progress()
	if progress and not progress.has_pending_spawn_restore():
		progress.save_autosave()


func _progress() -> EmberExploreState:
	return get_node_or_null("/root/EmberExploreProgress") as EmberExploreState
