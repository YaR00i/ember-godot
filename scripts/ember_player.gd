class_name EmberPlayer
extends CharacterBody3D
## Explore walk. Radius / height / step match JOI `DEFAULT_WORLD_BODY`.
## WASD is projected through the follow-camera yaw, matching JOI explore play.

const RADIUS_VOXELS := 2.5
const HEIGHT_VOXELS := 12.0
const STEP_VOXELS := 4.0
const SPEED := 28.0
const ACTION_MESSAGE_MS := 1400
const WaterContact := preload("res://scripts/ember_water_contact_3d.gd")
const PartyState := preload("res://scripts/ember_party_state.gd")

signal respawn_requested

@export var tile_size := 16.0
@export var debug_damage_amount := 0.0

var _prompt := ""
var _action_message := ""
var _action_message_until_ms := 0
var interact_hud: Label
var camera_rig: EmberFollowCamera
var interaction_ui: EmberInteractionUi
var inventory_ui: EmberInventoryUi
var quest_journal_ui: EmberQuestJournalUi
var pause_ui: EmberExplorePauseMenu
var party_followers
var progress_state: EmberExploreState
var controlled_hero_id := PartyState.LEADER_ID
var _defeated := false
var _respawn_grace_frames := 0
var _visual_material: StandardMaterial3D
var _facing_material: StandardMaterial3D
var _status_label: Label3D


func _ready() -> void:
	_ensure_actions()
	var vw := tile_size / 16.0
	var radius := RADIUS_VOXELS * vw
	var height := HEIGHT_VOXELS * vw
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = STEP_VOXELS * vw
	var col := CollisionShape3D.new()
	col.name = "Shape"
	var cap := CapsuleShape3D.new()
	cap.radius = radius
	cap.height = maxf(height, radius * 2.0 + 0.01)
	col.shape = cap
	col.position.y = cap.height * 0.5
	add_child(col)
	var mesh := MeshInstance3D.new()
	mesh.name = "Viz"
	var vis := CapsuleMesh.new()
	vis.radius = radius
	vis.height = cap.height
	mesh.mesh = vis
	mesh.position.y = cap.height * 0.5
	var mat := StandardMaterial3D.new()
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mesh)
	_visual_material = mat
	var facing := MeshInstance3D.new()
	facing.name = "Facing"
	var marker := SphereMesh.new()
	marker.radius = 0.52 * vw
	marker.height = 1.04 * vw
	facing.mesh = marker
	facing.position = Vector3(0.0, cap.height * 0.66, radius * 0.93)
	_facing_material = StandardMaterial3D.new()
	_facing_material.albedo_color = Color("fff2d8")
	_facing_material.emission_enabled = true
	facing.material_override = _facing_material
	add_child(facing)
	_status_label = Label3D.new()
	_status_label.name = "Status"
	_status_label.position.y = cap.height + 2.3 * vw
	_status_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_status_label.no_depth_test = true
	_status_label.font_size = 28
	_status_label.outline_size = 7
	_status_label.pixel_size = 0.028 * vw
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_status_label)
	var water_contact: Node3D = WaterContact.new()
	water_contact.name = "WaterContact"
	water_contact.set("radius_blocks", 0.25)
	add_child(water_contact)
	var state := _progress()
	if state != null:
		controlled_hero_id = state.exploration_leader_id
		if not state.exploration_leader_changed.is_connected(_on_exploration_leader_changed):
			state.exploration_leader_changed.connect(_on_exploration_leader_changed)
		if not state.progress_changed.is_connected(_refresh_active_visual):
			state.progress_changed.connect(_refresh_active_visual)
	_refresh_active_visual()
	var active := state.party_member_view(controlled_hero_id) if state != null else {}
	_defeated = state != null and int(active.get("hp", 0)) <= 0


func _exit_tree() -> void:
	var state := _progress()
	if state != null:
		if state.exploration_leader_changed.is_connected(_on_exploration_leader_changed):
			state.exploration_leader_changed.disconnect(_on_exploration_leader_changed)
		if state.progress_changed.is_connected(_refresh_active_visual):
			state.progress_changed.disconnect(_refresh_active_visual)


func _ensure_actions() -> void:
	_bind("move_north", KEY_W)
	_bind("move_south", KEY_S)
	_bind("move_west", KEY_A)
	_bind("move_east", KEY_D)
	_bind("interact", KEY_F)
	_bind("inventory", KEY_I)
	_bind("quest_journal", KEY_Q)
	_bind("party_follow_toggle", KEY_T)
	_bind("party_leader_next", KEY_TAB)
	_bind("health_test", KEY_H)
	_bind("respawn", KEY_R)


func _bind(action: String, key: Key) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for existing in InputMap.action_get_events(action):
		if existing is InputEventKey and existing.physical_keycode == key:
			return
	var ev := InputEventKey.new()
	ev.physical_keycode = key
	InputMap.action_add_event(action, ev)


func _physics_process(dt: float) -> void:
	if _defeated:
		velocity.x = 0.0
		velocity.z = 0.0
		if not is_on_floor():
			velocity.y -= 48.0 * dt
		else:
			velocity.y = 0.0
		move_and_slide()
		if Input.is_action_just_pressed("respawn"):
			request_respawn()
		if interact_hud:
			interact_hud.text = _hud_text()
		return
	var input_axis := Vector2.ZERO
	if not _ui_blocks_movement():
		input_axis = Input.get_vector(
			"move_west",
			"move_east",
			"move_north",
			"move_south",
		)
	var camera_yaw := camera_rig.yaw if is_instance_valid(camera_rig) else 0.0
	var wish := EmberCameraMovement.world_direction(input_axis, camera_yaw) * SPEED
	velocity.x = wish.x
	velocity.z = wish.z
	if _respawn_grace_frames > 0:
		_respawn_grace_frames -= 1
		velocity.y = 0.0
	elif not is_on_floor():
		velocity.y -= 48.0 * dt
	else:
		velocity.y = 0.0
	move_and_slide()
	_prompt = "" if _ui_blocks_movement() else _nearest_prompt()
	if Input.is_action_just_pressed("inventory"):
		if (
			is_instance_valid(inventory_ui)
			and not (is_instance_valid(interaction_ui) and interaction_ui.is_open())
			and not (is_instance_valid(quest_journal_ui) and quest_journal_ui.is_open())
		):
			inventory_ui.toggle()
	if Input.is_action_just_pressed("party_follow_toggle"):
		if not _ui_blocks_movement() and is_instance_valid(party_followers):
			party_followers.toggle_mode()
	if Input.is_action_just_pressed("quest_journal"):
		if (
			is_instance_valid(quest_journal_ui)
			and not (is_instance_valid(interaction_ui) and interaction_ui.is_open())
			and not (is_instance_valid(inventory_ui) and inventory_ui.is_open())
		):
			quest_journal_ui.toggle()
	if Input.is_action_just_pressed("interact"):
		if is_instance_valid(interaction_ui) and interaction_ui.is_open():
			interaction_ui.advance()
		elif is_instance_valid(inventory_ui) and inventory_ui.is_open():
			inventory_ui.confirm()
		elif is_instance_valid(quest_journal_ui) and quest_journal_ui.is_open():
			pass
		else:
			_try_interact()
	if (
		debug_damage_amount > 0.0
		and not _ui_blocks_movement()
		and Input.is_action_just_pressed("health_test")
	):
		_apply_debug_damage()
	if interact_hud:
		interact_hud.text = _hud_text()


func _hud_text() -> String:
	var health := _health_text()
	if _defeated:
		return "%s\nПОРАЖЕНИЕ · R вернуться к точке входа" % health
	if _ui_blocks_movement():
		return ""
	if Time.get_ticks_msec() < _action_message_until_ms:
		return "%s\n%s" % [health, _action_message]
	if _prompt.is_empty():
		var controls := "WASD ходить · Tab герой · F действие · I сумка · Q задания · T строй отряда · Esc меню · RMB камера"
		if debug_damage_amount > 0.0:
			controls += " · H тест урона"
		return "%s\n%s" % [health, controls]
	return "%s\nF: %s" % [health, _prompt]


func _health_text() -> String:
	var state := _progress()
	if state == null:
		return "HP —"
	var active := state.party_member_view(controlled_hero_id)
	return "%s · HP %d/%d" % [
		str(active.get("nameRu", controlled_hero_id)),
		int(active.get("hp", 0)),
		int(active.get("maxHp", 0)),
	]


func _apply_debug_damage() -> void:
	if debug_damage_amount <= 0.0:
		return
	var result := apply_damage(debug_damage_amount)
	if not bool(result.get("ok", false)):
		return
	_action_message = "-%d HP (тест)" % roundi(float(result.get("damage", 0.0)))
	_action_message_until_ms = Time.get_ticks_msec() + ACTION_MESSAGE_MS


func apply_damage(raw_damage: float) -> Dictionary:
	var state := _progress()
	if state == null or _defeated:
		return {"ok": false, "reason": "defeated" if _defeated else "missing_state"}
	var result := state.apply_damage_to_member(controlled_hero_id, raw_damage)
	if bool(result.get("dead", false)):
		_enter_defeat()
	return result


func is_defeated() -> bool:
	return _defeated


func cycle_controlled_hero() -> String:
	var state := _progress()
	if state == null:
		return controlled_hero_id
	return state.next_exploration_leader()


func _on_exploration_leader_changed(hero_id: String) -> void:
	controlled_hero_id = hero_id if hero_id in PartyState.HERO_IDS else PartyState.LEADER_ID
	_refresh_active_visual()


func _refresh_active_visual() -> void:
	var state := _progress()
	var view := state.party_member_view(controlled_hero_id) if state != null else {}
	var definition := PartyState.unit_definition(controlled_hero_id)
	var color: Color = definition.get("battleColor", Color("ffac5a"))
	if _visual_material != null:
		_visual_material.albedo_color = color
	if _facing_material != null:
		_facing_material.emission = color * 0.28
	if _status_label != null:
		var hp := int(view.get("hp", 0))
		_status_label.text = "%s\nHP %d/%d" % [
			str(view.get("nameRu", controlled_hero_id)),
			hp,
			int(view.get("maxHp", 0)),
		]
		_status_label.modulate = Color("f0a0a0") if hp <= 0 else Color("fff1c9")


func request_respawn() -> void:
	if _defeated:
		respawn_requested.emit()


func complete_respawn() -> void:
	_defeated = false
	velocity = Vector3.ZERO
	_respawn_grace_frames = 1
	_action_message = "Возвращение к точке входа"
	_action_message_until_ms = Time.get_ticks_msec() + ACTION_MESSAGE_MS


func _enter_defeat() -> void:
	_defeated = true
	velocity = Vector3.ZERO
	_prompt = ""
	if is_instance_valid(interaction_ui):
		interaction_ui.close()
	if is_instance_valid(inventory_ui):
		inventory_ui.close()
	if is_instance_valid(quest_journal_ui):
		quest_journal_ui.close()


func _nearest() -> Node3D:
	var best: Node3D = null
	var best_d := 12.0
	for node in get_tree().get_nodes_in_group("ember_interact"):
		var area := node as Node3D
		if area == null or (not area is EmberInteract and not area is EmberRegion):
			continue
		var d := (
			(area as EmberInteract).distance_to_world(global_position)
			if area is EmberInteract
			else global_position.distance_to(area.global_position)
		)
		if d < best_d:
			best_d = d
			best = area
	return best


func _nearest_prompt() -> String:
	var area := _nearest()
	if area == null:
		return ""
	if area is EmberInteract:
		return (area as EmberInteract).prompt()
	return (area as EmberRegion).prompt()


func _try_interact() -> void:
	var area := _nearest()
	if area == null:
		return
	if area is EmberInteract:
		activate_interact(area as EmberInteract)
		return
	var message := ""
	var region := area as EmberRegion
	if is_instance_valid(interaction_ui) and not region.script_id.is_empty():
		message = interaction_ui.activate_script(region.script_id)
	else:
		message = region.activate()
	if not message.is_empty():
		_action_message = message
		_action_message_until_ms = Time.get_ticks_msec() + ACTION_MESSAGE_MS


func activate_interact(interact: EmberInteract) -> bool:
	if interact == null or _ui_blocks_movement():
		return false
	var progress := _progress()
	var flags := progress.flags if progress != null else {}
	if not interact.runtime_available(flags):
		return false
	var routed_script := interact.routed_script_id(flags)
	var message := ""
	if is_instance_valid(interaction_ui) and (
		interact.kind == "talk"
		or interact.kind == "shop"
		or not routed_script.is_empty()
	):
		message = interaction_ui.activate(interact)
	else:
		message = interact.activate()
	if not message.is_empty():
		_action_message = message
		_action_message_until_ms = Time.get_ticks_msec() + ACTION_MESSAGE_MS
	return true


func _ui_blocks_movement() -> bool:
	return (
		_defeated
		or (is_instance_valid(interaction_ui) and interaction_ui.blocks_movement())
		or (is_instance_valid(inventory_ui) and inventory_ui.blocks_movement())
		or (is_instance_valid(quest_journal_ui) and quest_journal_ui.blocks_movement())
		or (is_instance_valid(pause_ui) and pause_ui.blocks_movement())
	)


func _progress() -> EmberExploreState:
	if is_instance_valid(progress_state):
		return progress_state
	return get_node_or_null("/root/EmberExploreProgress") as EmberExploreState
