class_name EmberPlayer
extends CharacterBody3D
## Exploration controller: collision-checked smooth stepping over low obstacles.
## WASD is projected through the follow-camera yaw, matching JOI explore play.

const STEP_VOXELS := 4.0
const SPEED_BLOCKS := 3.0
const STEP_SECONDS := 0.16
const ACTION_MESSAGE_MS := 1400
const ICE_SURFACE_GROUP := &"ember_ice_surface"
const FREE_ICE_GROUP := &"ember_free_ice"
const ICE_MAX_SPEED := 74.0
const ICE_STEER_SPEED := 18.0
const ICE_DRY_BRAKE := 110.0
const VINE_JUMP_TIME := 0.4
const WaterContact := preload("res://scripts/ember_water_contact_3d.gd")
const PartyState := preload("res://scripts/ember_party_state.gd")
const HeroScale := preload("res://scripts/ember_exploration_hero_scale.gd")
const HoshiVisual := preload("res://scripts/ember_hoshi_visual.gd")
const MiraMotionControls := preload("res://scripts/ember_mira_motion_controls.gd")
const WingFlightMotion := preload("res://scripts/ember_wing_flight_motion.gd")
const WingFlapMotion := preload("res://scripts/ember_wing_flap_motion.gd")
const GroundLeafSteps := preload("res://scripts/ember_ground_leaf_steps.gd")

signal respawn_requested
signal flight_collision

@export var tile_size := 16.0
@export var debug_damage_amount := 0.0

var _prompt := ""
var _ground_leaf_steps := GroundLeafSteps.new()
var _magic_push_body: WeakRef
var _reaching_door: EmberInteract
var _door_reach_elapsed := 0.0
var _magic_push_normal := Vector3.ZERO
var _magic_push_retreat := 0.0
var _magic_push_left := 0.0
var _heavy_push_id := 0
var _heavy_push_time := 0.0
var _heavy_push_gap := 0.0
var _interaction_forward := Vector3.FORWARD
var _action_message := ""
var _action_message_until_ms := 0
var _next_world_strike_ms := 0
const StaffProjectile = preload("res://scripts/ember_staff_projectile.gd")
const STAFF_AIM_HALF_ANGLE := 27.5
const STAFF_RANGE_M := StaffProjectile.RANGE_M
var _staff_shot_pending := false
var _staff_target: WeakRef
var _staff_target_marker: Label3D
var _mira_ground_wish := Vector3.ZERO
var _mira_gait_speed := 0.0
var _mira_stop_deceleration := 0.0
var _mira_stop_contact_wait := 0.0
var _mira_stop_goal := Vector3.ZERO
var _mira_stop_direction := Vector3.ZERO
var _trial_swimming := false
var _trial_swim_swell := 0.0
var interact_hud: Label
var camera_rig: EmberFollowCamera
var interaction_ui: EmberInteractionUi
var inventory_ui: EmberInventoryUi
var quest_journal_ui: EmberQuestJournalUi
var quest_tracker_ui: Control
var pause_ui: EmberExplorePauseMenu
var party_followers
var progress_state: EmberExploreState
var controlled_hero_id := PartyState.LEADER_ID
var _defeated := false
var _respawn_grace_frames := 0
var _visual_material: StandardMaterial3D
var _facing_material: StandardMaterial3D
var _status_label: Label3D
var _body_radius := 0.0
var _applied_hero_scale := ""
var _step_active := false
var _step_top := 0.0
var _step_direction := Vector3.ZERO
var _step_elapsed := 0.0
var _mantle_start := Vector3.ZERO
var _mantle_landing := Vector3.ZERO
var _mantle_time := 0.0
var _mantle_duration := 0.0
var _mantle_hands_first := false
var _mantle_jumps := false
var _hoshi_visual: Node3D
var flight_motion: RefCounted
var zipline: Node3D
var _zipline_elapsed := 0.0
var _zipline_departure := Vector3.ZERO
var _pipe_visual_rest: Dictionary = {}
var _route_airborne := false
var _route_touchdown := -1.0
var _vine_target: Node3D
var _vine_launch := Vector3.ZERO
var _vine_arrival := 0.0
var _vine_jump_elapsed := 0.0
var _vine_trail: Array[Vector3] = []
var _ice_momentum := Vector3.ZERO
var _sliding_on_ice := false
var ice_sled: Node3D
var _sled_heading := Vector3.ZERO
var _sled_launch_heading := Vector3.ZERO
var _sled_speed := 0.0
var _sled_surface_rise := 0.0
var _sled_elapsed := 0.0
var _sled_visual_rest: Dictionary = {}
## Session controls; QA opts into Ctrl/Shift without changing the final input design.
var walk_modifier_key := KEY_SHIFT
var boost_modifier_key := KEY_NONE
var boost_speed_multiplier := 1.6

const MIRA_VISUAL_PREFS := "user://ember_character_visuals.cfg"
const MIRA_EDITABLE_MOTION := "res://assets/local_characters/hoshi/mira_motion_editable.tres"
const MIRA_BAKED_MOTION := "res://assets/local_characters/hoshi/mira_motion_trial.res"
var _kai_visual: Node3D
var _mira_visual: Node3D
var _mira_model_available := true
var _mira_outfit := true

func install_hoshi_test_visual(hero_id: String = PartyState.LEADER_ID, trial_clips: AnimationLibrary = null) -> bool:
	if hero_id == "mira":
		if not is_instance_valid(_mira_visual):
			_mira_visual = _make_hoshi_visual("MiraVisual", trial_clips, _mira_outfit)
		_refresh_active_visual()
		return is_instance_valid(_mira_visual)
	if not is_instance_valid(_kai_visual):
		_kai_visual = _make_hoshi_visual("Hoshi", trial_clips, false)
	_refresh_active_visual()
	if is_instance_valid(party_followers):
		party_followers.refresh_hero_models()
	return is_instance_valid(_kai_visual)

func has_kai_test_visual() -> bool:
	return is_instance_valid(_kai_visual)

func _make_hoshi_visual(node_name: String, clips: AnimationLibrary, use_mira_outfit: bool) -> Node3D:
	var visual := HoshiVisual.new()
	visual.name = node_name
	add_child(visual)
	if not visual.setup(self, tile_size, clips, use_mira_outfit):
		visual.queue_free()
		return null
	visual.spell_released.connect(_launch_staff_shot.bind(visual))
	return visual

func _ensure_mira_visual() -> void:
	if is_instance_valid(_mira_visual) or not _mira_model_available:
		return
	var path := MIRA_EDITABLE_MOTION if ResourceLoader.exists(MIRA_EDITABLE_MOTION) else MIRA_BAKED_MOTION
	var clips := load(path) as AnimationLibrary if ResourceLoader.exists(path) else null
	_mira_visual = _make_hoshi_visual("MiraVisual", clips, _mira_outfit)
	_mira_model_available = is_instance_valid(_mira_visual)

func mira_outfit_available() -> bool:
	return ResourceLoader.exists(HoshiVisual.MIRA_AVATAR_PATH)

func mira_outfit_selected() -> bool:
	return _mira_outfit

func set_mira_outfit(value: bool) -> void:
	if value == _mira_outfit or (value and not mira_outfit_available()):
		return
	_mira_outfit = value
	var config := ConfigFile.new()
	config.load(MIRA_VISUAL_PREFS)
	config.set_value("mira", "outfit", value)
	config.save(MIRA_VISUAL_PREFS)
	if is_instance_valid(_mira_visual):
		_mira_visual.hide()
		_mira_visual.queue_free()
		_mira_visual = null
	_mira_model_available = true
	_applied_hero_scale = ""
	_refresh_active_visual()
	if is_instance_valid(party_followers):
		party_followers.refresh_hero_models()

func _sync_hoshi_visual() -> void:
	if controlled_hero_id == "mira":
		_ensure_mira_visual()
		_hoshi_visual = _mira_visual
	elif controlled_hero_id == PartyState.LEADER_ID:
		_hoshi_visual = _kai_visual
	else:
		_hoshi_visual = null
	for visual: Node3D in [_kai_visual, _mira_visual]:
		if is_instance_valid(visual):
			visual.visible = visual == _hoshi_visual
	boost_modifier_key = KEY_CTRL if controlled_hero_id == "mira" and is_instance_valid(_hoshi_visual) else KEY_NONE
	var active := is_instance_valid(_hoshi_visual)
	get_node("Viz").visible = not active
	get_node("Facing").visible = not active
	if active:
		var height: float = _hoshi_visual.height_m * tile_size
		get_node("Shape").shape.height = height
		get_node("Shape").position.y = height * 0.5
		if _status_label != null:
			_status_label.position.y = height + 2.3 * tile_size / 16.0


func _ready() -> void:
	var visual_prefs := ConfigFile.new()
	if visual_prefs.load(MIRA_VISUAL_PREFS) == OK:
		_mira_outfit = bool(visual_prefs.get_value("mira", "outfit", true))
	_ensure_actions()
	var vw := tile_size / 16.0
	var radius := HeroScale.collision_radius(tile_size)
	var visual_radius := HeroScale.radius(PartyState.LEADER_ID, tile_size)
	var height := HeroScale.height(PartyState.LEADER_ID, tile_size)
	_body_radius = radius
	_applied_hero_scale = PartyState.LEADER_ID
	collision_layer = 2
	collision_mask = 1 | 4
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
	vis.radius = visual_radius
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
	marker.radius = visual_radius * 0.21
	marker.height = visual_radius * 0.42
	facing.mesh = marker
	facing.position = Vector3(0.0, cap.height * 0.66, visual_radius * 0.93)
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


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if _ui_blocks_movement() or flight_motion != null: return
		world_strike()
		get_viewport().set_input_as_handled()

func world_strike() -> bool:
	var state := _progress()
	if _mantle_duration > 0.0 or is_instance_valid(_reaching_door) or _ui_blocks_movement() or flight_motion != null or _trial_swimming or (state != null and state.combat_party_locked): return false
	if has_meta("ember_carried_item") or Time.get_ticks_msec() < _next_world_strike_ms: return false
	var direction := interaction_forward()
	if uses_trial_staff():
		if _hoshi_visual.staff_action_active(): return false
		var enemy := _visible_field_strike_target()
		if enemy != null:
			var toward := enemy.global_position - global_position
			toward.y = 0.0
			if not toward.is_zero_approx():
				direction = toward.normalized()
		var strike: bool = not _hoshi_visual.staff_needs_draw() or enemy != null
		if _hoshi_visual.begin_staff_action(direction, strike, _hoshi_visual == _mira_visual):
			_staff_shot_pending = strike
			_staff_target = weakref(enemy) if enemy != null else null
			_hoshi_visual.spell_aim_point = enemy.field_spell_aim_point() if enemy != null else global_position + Vector3.UP * tile_size * 0.65 + direction * tile_size * STAFF_RANGE_M
			_next_world_strike_ms = Time.get_ticks_msec() + 350
			return true
	_next_world_strike_ms = Time.get_ticks_msec() + 350
	_show_world_strike()
	return _resolve_world_strike(direction)

func uses_trial_staff() -> bool:
	return is_instance_valid(_hoshi_visual) and _hoshi_visual.has_trial_staff()


func _visible_field_strike_target() -> Node3D:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return null
	var closest: Node3D
	var nearest := pow(tile_size * STAFF_RANGE_M, 2)
	var forward := interaction_forward()
	for candidate in get_tree().get_nodes_in_group("ember_field_enemies"):
		var enemy := candidate as Node3D
		if enemy == null or not enemy.is_visible_in_tree() or not enemy.has_method("field_spell_aim_point") or not enemy.has_method("receive_field_spell"):
			continue
		var aim: Vector3 = enemy.field_spell_aim_point()
		var delta := aim - global_position
		delta.y = 0.0
		var distance := delta.length_squared()
		if distance >= nearest or forward.dot(delta.normalized()) < cos(deg_to_rad(STAFF_AIM_HALF_ANGLE)):
			continue
		if not _staff_aim_visible(camera, aim):
			continue
		closest = enemy
		nearest = distance
	return closest


func _staff_aim_visible(camera: Camera3D, aim: Vector3) -> bool:
	if camera == null or not camera.is_position_in_frustum(aim):
		return false
	var ray := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * tile_size * 0.65, aim, 1 | 4, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()


func _update_staff_aim() -> void:
	var state := _progress()
	if (
		not uses_trial_staff() or _ui_blocks_movement() or _defeated or flight_motion != null or _mantle_duration > 0.0
		or _trial_swimming or has_meta("ember_carried_item") or (state != null and state.combat_party_locked)
	):
		_staff_shot_pending = false
		_staff_target = null
		if is_instance_valid(_staff_target_marker):
			_staff_target_marker.hide()
		return
	var enemy: Node3D
	if _staff_shot_pending and _staff_target != null:
		enemy = _staff_target.get_ref() as Node3D
		if is_instance_valid(enemy) and enemy.is_visible_in_tree():
			var aim: Vector3 = enemy.field_spell_aim_point()
			if _staff_aim_visible(get_viewport().get_camera_3d(), aim):
				_hoshi_visual.spell_aim_point = aim
			else:
				enemy = null
				_staff_target = null
	elif not _hoshi_visual.staff_action_active():
		enemy = _visible_field_strike_target()
	if not is_instance_valid(enemy) or not enemy.is_visible_in_tree():
		if is_instance_valid(_staff_target_marker):
			_staff_target_marker.hide()
		return
	if not is_instance_valid(_staff_target_marker):
		_staff_target_marker = Label3D.new()
		_staff_target_marker.text = "◆"
		_staff_target_marker.modulate = Color(0.93, 0.68, 1.0)
		_staff_target_marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_staff_target_marker.no_depth_test = true
		_staff_target_marker.font_size = 28
		_staff_target_marker.pixel_size = tile_size * 0.0035
		add_child(_staff_target_marker)
	_staff_target_marker.global_position = enemy.field_spell_aim_point() + Vector3.UP * tile_size * 0.70
	_staff_target_marker.show()


func _launch_staff_shot(origin: Vector3, direction: Vector3, visual: Node) -> void:
	if not _staff_shot_pending or visual != _hoshi_visual or not is_inside_tree():
		return
	_staff_shot_pending = false
	var enemy := _staff_target.get_ref() as Node3D if _staff_target != null else null
	_staff_target = null
	var world := get_tree().current_scene
	if world == null:
		return
	var bolt := StaffProjectile.new()
	bolt.launch(tile_size, get_rid(), direction, enemy, _staff_projectile_hit)
	world.add_child(bolt)
	bolt.global_position = origin


func _staff_projectile_hit(body: Node3D, direction: Vector3) -> void:
	if body.has_method("receive_field_spell"):
		body.receive_field_spell(self)
	elif body.has_method("receive_world_hit") and not body.is_queued_for_deletion():
		_apply_world_strike_hit(body, direction)


func _apply_world_strike_hit(body: Node3D, direction: Vector3) -> bool:
	var destroyed: bool = body.receive_world_hit(self, direction)
	_action_message = str(body.world_hit_feedback()) if destroyed and body.has_method("world_hit_feedback") else "Удар: ящик разбит" if destroyed else "Удар: предмет цел"
	_action_message_until_ms = Time.get_ticks_msec() + ACTION_MESSAGE_MS
	return destroyed


func _resolve_world_strike(direction: Vector3) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = SphereShape3D.new(); query.shape.radius = tile_size * 0.5
	query.transform.origin = global_position + Vector3.UP * tile_size * 0.5 + direction * tile_size
	query.collision_mask = 4; query.collide_with_areas = true; query.exclude = [get_rid()]
	var space := get_world_3d().direct_space_state
	var targets := space.intersect_shape(query, 16)
	targets.sort_custom(func(a, b): return global_position.distance_squared_to(a.collider.global_position) < global_position.distance_squared_to(b.collider.global_position))
	for result in targets:
		var body: Node3D = result.collider
		if not body.has_method("receive_world_hit") or body.is_queued_for_deletion(): continue
		var shape := body.get_node_or_null("BodyShape") as CollisionShape3D
		var target := body.to_global(shape.position) if shape != null else body.global_position
		var ray := PhysicsRayQueryParameters3D.create(global_position + Vector3.UP * tile_size * 0.5, target, 1 | 4)
		ray.collide_with_areas = true; ray.exclude = [get_rid()]
		var hit := space.intersect_ray(ray)
		if not hit.is_empty() and hit.collider == body:
			return _apply_world_strike_hit(body, direction)
	return false

func _show_world_strike() -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for index in 13:
		var angle := -1.1 + 2.2 * float(index) / 12.0
		for radius in [tile_size * 0.85, tile_size * 1.1]:
			mesh.surface_set_normal(Vector3.UP)
			mesh.surface_add_vertex(Vector3(sin(angle) * radius, 0, -cos(angle) * radius))
	mesh.surface_end()
	var arc := MeshInstance3D.new(); arc.mesh = mesh
	arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(1, 0.94, 0.7, 0.85); arc.material_override = material
	get_tree().current_scene.add_child(arc)
	arc.add_to_group("ember_world_strike_effects")
	arc.global_transform = Transform3D(Basis.looking_at(interaction_forward()), global_position + Vector3.UP * tile_size * 0.5)
	var tween := arc.create_tween()
	tween.tween_property(material, "albedo_color:a", 0.0, 0.18)
	tween.tween_callback(arc.queue_free)

func _ensure_actions() -> void:
	_bind("move_north", KEY_W)
	_bind("move_south", KEY_S)
	_bind("move_west", KEY_A)
	_bind("move_east", KEY_D)
	_bind("interact", KEY_F)
	_bind("throw_item", KEY_G)
	_bind("inventory", KEY_I)
	_bind("quest_journal", KEY_Q)
	_bind("companion_direction", KEY_J)
	_bind("party_follow_toggle", KEY_T)
	_bind("party_leader_next", KEY_TAB)
	_bind("health_test", KEY_H)
	_bind("respawn", KEY_R)
	_bind("mantle", KEY_SPACE)


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
	_update_staff_aim()
	if is_instance_valid(zipline):
		_tick_zipline(dt)
		return
	if flight_motion != null:
		_tick_flight(dt)
		return
	if _mantle_duration > 0.0:
		_tick_mantle(dt)
		return
	if _defeated:
		_cancel_step()
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
	var crate := carried_crate()
	if Input.is_action_just_pressed("mantle") and crate == null and _try_mantle():
		return
	var handling_crate: bool = crate != null and not crate.crate_action.is_empty()
	var input_axis := Vector2.ZERO
	if not is_instance_valid(_reaching_door) and _magic_push_body == null and not handling_crate and not _ui_blocks_movement() and (not is_instance_valid(_hoshi_visual) or not _hoshi_visual.staff_strike_active()):
		input_axis = Input.get_vector(
			"move_west",
			"move_east",
			"move_north",
			"move_south",
		)
	var camera_yaw := camera_rig.yaw if is_instance_valid(camera_rig) else 0.0
	var wish := EmberCameraMovement.world_direction(input_axis, camera_yaw) * (SPEED_BLOCKS * tile_size)
	var rolling: bool = is_instance_valid(_hoshi_visual) and _hoshi_visual.visible and _hoshi_visual.traversal_roll_active()
	if not wish.is_zero_approx() and not rolling:
		_interaction_forward = wish.normalized()
	if boost_modifier_key != KEY_NONE or (is_instance_valid(_hoshi_visual) and _hoshi_visual.visible):
		if Input.is_physical_key_pressed(walk_modifier_key):
			wish *= 0.4
		elif boost_modifier_key != KEY_NONE and Input.is_physical_key_pressed(boost_modifier_key):
			wish *= boost_speed_multiplier
	if crate != null:
		wish = wish.limit_length(tile_size * 1.2)
	var was_sliding := not _ice_momentum.is_zero_approx()
	var swim_surface := _trial_swim_surface()
	if _trial_swimming:
		_cancel_step()
		_mira_ground_wish = Vector3.ZERO
		_mira_stop_deceleration = 0.0
		_hoshi_visual.clear_gait_tempo()
		_hoshi_visual.wait_for_gait_stop_contact(false)
		_hoshi_visual.set_gait_braking(false)
		wish = wish.limit_length(tile_size * 1.45)
	elif rolling:
		wish = _interaction_forward * tile_size * _hoshi_visual.traversal_roll_speed() if not is_on_wall() else Vector3.ZERO
	else:
		wish = _ground_motion(wish, dt)
		wish = _mira_ground_motion(wish, dt, was_sliding)
	if handling_crate:
		wish = Vector3.ZERO
		_mira_ground_wish = Vector3.ZERO
	elif crate != null:
		wish = wish.limit_length(tile_size * 1.2)
	if _magic_push_body != null:
		wish = _tick_magic_crate_push(dt)
		_mira_ground_wish = Vector3.ZERO
	if is_instance_valid(_reaching_door):
		wish = _door_approach_velocity()
		_mira_ground_wish = Vector3.ZERO
	velocity.x = wish.x
	velocity.z = wish.z
	var motion := Vector3(wish.x, 0.0, wish.z) * dt
	if _step_active and (
		motion.is_zero_approx()
		or motion.normalized().dot(_step_direction) < 0.5
		or _step_elapsed > STEP_SECONDS + 0.3
	):
		_cancel_step()
	if not _trial_swimming and not _step_active and not _sliding_on_ice and not was_sliding and not is_instance_valid(ice_sled) and is_on_floor() and not motion.is_zero_approx():
		_try_start_step(motion)
	if _respawn_grace_frames > 0:
		_respawn_grace_frames -= 1
		velocity.y = 0.0
	elif _trial_swimming:
		var float_error := swim_surface - tile_size * 0.80 - global_position.y
		var float_speed := clampf(float_error * 6.0, -tile_size * 1.4, tile_size * 0.95)
		velocity.y = move_toward(velocity.y, float_speed, tile_size * 4.5 * dt)
	elif _step_active:
		_step_elapsed += dt
		var remaining := maxf(0.0, _step_top - global_position.y)
		velocity.y = minf(STEP_VOXELS * tile_size / 16.0 / STEP_SECONDS, remaining / maxf(dt, 0.00001))
	elif not is_on_floor():
		velocity.y -= 48.0 * dt
	else:
		velocity.y = 0.0
	var sled_on_floor := is_instance_valid(ice_sled) and is_on_floor()
	var descent := maxf(0.0, -velocity.y)
	var previous_y := global_position.y
	var was_grounded := is_on_floor()
	move_and_slide()
	if is_instance_valid(_reaching_door) and _tick_door_reach(dt):
		return
	if is_instance_valid(ice_sled):
		if sled_on_floor and not is_on_floor():
			velocity.y = _sled_surface_rise
		_update_sled_visual()
		return
	if not _ui_blocks_movement():
		_heavy_push_gap += dt
		if _heavy_push_gap > 0.07:
			_heavy_push_time = 0.0
			_heavy_push_id = 0
		var pushed := {}
		for index in get_slide_collision_count():
			var hit := get_slide_collision(index)
			var body := hit.get_collider()
			var normal := hit.get_normal()
			if not body is RigidBody3D or not body.has_method("push_from") or pushed.has(body.get_instance_id()) or absf(normal.y) >= 0.5:
				continue
			pushed[body.get_instance_id()] = true
			if body.is_heavy_crate():
				if not uses_crate_magic() and crate == null and is_on_floor() and not body.freeze and input_axis.length() > 0.25 and not wish.is_zero_approx() and wish.normalized().dot(-normal) >= 0.76:
					_push_heavy_crate(body, normal, dt)
			else:
				body.push_from(wish.normalized(), wish.length())
		if Input.is_action_just_pressed("throw_item") and has_meta("ember_carried_item"):
			var held: WeakRef = get_meta("ember_carried_item")
			if is_instance_valid(held.get_ref()):
				report_crate_action(held.get_ref().request_throw(self))
	if _step_active:
		_finish_step_if_supported()
	_ground_leaf_steps.tick(self, dt, tile_size, not input_axis.is_zero_approx() and not _trial_swimming and not _sliding_on_ice and not rolling)
	if is_instance_valid(_hoshi_visual) and _hoshi_visual.uses_gait_transitions():
		_hoshi_visual.update_traversal_pose(is_on_floor() or _step_active, _trial_swimming, descent, dt, swim_surface + _trial_swim_swell, previous_y, not input_axis.is_zero_approx())
		if not was_grounded and is_on_floor() and _hoshi_visual.moving_landing_speed() < 1.0:
			_mira_ground_wish = Vector3(get_real_velocity().x, 0.0, get_real_velocity().z)
		_hoshi_visual.sample_stance_support(not _trial_swimming and is_on_floor() and input_axis.is_zero_approx() and wish.is_zero_approx() and not _step_active and not _sliding_on_ice)
		var grounded := is_on_floor()
		var terrain_travel := wish if not _trial_swimming and (grounded or _step_active) and not input_axis.is_zero_approx() and not _sliding_on_ice else Vector3.ZERO
		_hoshi_visual.sample_terrain_step(terrain_travel, get_floor_normal() if grounded else Vector3.UP, dt, _step_active)
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
	elif Input.is_action_just_pressed("companion_direction"):
		ask_mira_direction()
	if (
		debug_damage_amount > 0.0
		and not _ui_blocks_movement()
		and Input.is_action_just_pressed("health_test")
	):
		_apply_debug_damage()
	if interact_hud:
		interact_hud.text = _hud_text()


func begin_wing_flight(pose: Transform3D, speed: float = 26.0) -> void:
	_cancel_step()
	flight_motion = WingFlightMotion.new()
	flight_motion.reset(pose.basis.get_rotation_quaternion(), speed)
	global_transform = pose
	velocity = flight_motion.velocity
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	floor_snap_length = 0.0
	get_node("Shape").position = Vector3.ZERO
	get_node("Shape").rotation.x = PI * 0.5
	get_node("Viz").hide()
	get_node("Facing").hide()
	_status_label.hide()
	if is_instance_valid(camera_rig):
		camera_rig.wing_flight_view = true
		camera_rig.reset_follow_height()


func end_wing_flight() -> void:
	flight_motion = null
	global_basis = Basis.IDENTITY
	velocity = Vector3.ZERO
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	floor_snap_length = STEP_VOXELS * tile_size / 16.0
	get_node("Shape").rotation = Vector3.ZERO
	get_node("Shape").position.y = get_node("Shape").shape.height * 0.5
	get_node("Viz").show()
	get_node("Facing").show()
	_status_label.show()
	_refresh_active_visual()
	if is_instance_valid(camera_rig):
		camera_rig.wing_flight_view = false
		camera_rig.reset_follow_height()


func _tick_flight(dt: float) -> void:
	var controls := Vector3(
		float(Input.is_physical_key_pressed(KEY_S)) - float(Input.is_physical_key_pressed(KEY_W)),
		float(Input.is_physical_key_pressed(KEY_Q)) - float(Input.is_physical_key_pressed(KEY_E)),
		float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A)))
	var throttle := float(Input.is_physical_key_pressed(KEY_SPACE))
	if flight_motion is WingFlapMotion:
		throttle = float(Input.is_physical_key_pressed(KEY_CTRL))
		flight_motion.ground_supported = is_on_floor()
		motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED if flight_motion.phase in [WingFlapMotion.Phase.STANDING, WingFlapMotion.Phase.JUMPING] else CharacterBody3D.MOTION_MODE_FLOATING
	var brake := float(Input.is_physical_key_pressed(KEY_SHIFT))
	var pads := Input.get_connected_joypads()
	if not pads.is_empty():
		var pad := pads[0]
		var stick := Vector2(Input.get_joy_axis(pad, JOY_AXIS_LEFT_X), Input.get_joy_axis(pad, JOY_AXIS_LEFT_Y))
		var magnitude := stick.length()
		stick = stick.normalized() * clampf((magnitude - 0.18) / 0.82, 0.0, 1.0)
		controls.x += stick.y
		controls.z += stick.x
		controls.y += float(Input.is_joy_button_pressed(pad, JOY_BUTTON_LEFT_SHOULDER)) - float(Input.is_joy_button_pressed(pad, JOY_BUTTON_RIGHT_SHOULDER))
		throttle = maxf(throttle, Input.get_joy_axis(pad, JOY_AXIS_TRIGGER_RIGHT))
		brake = maxf(brake, Input.get_joy_axis(pad, JOY_AXIS_TRIGGER_LEFT))
	if _ui_blocks_movement():
		return
	flight_motion.step(dt, controls.clamp(Vector3(-1, -1, -1), Vector3.ONE), throttle, brake)
	global_basis = Basis(flight_motion.orientation)
	velocity = flight_motion.velocity
	move_and_slide()
	flight_motion.velocity = velocity
	if flight_motion is WingFlapMotion:
		flight_motion.ground_supported = is_on_floor()
	if get_slide_collision_count() > 0:
		flight_collision.emit()


func _try_mantle() -> bool:
	if not is_on_floor() or _step_active or _trial_swimming or _sliding_on_ice or _ui_blocks_movement() or is_instance_valid(ice_sled) or _magic_push_body != null or is_instance_valid(_reaching_door):
		return false
	if not is_instance_valid(_hoshi_visual):
		return false
	var duration: float = _hoshi_visual.mantle_duration()
	if duration <= 0.0:
		return false
	var space := get_world_3d().direct_space_state
	var forward := interaction_forward().slide(Vector3.UP).normalized()
	var waist := global_position + Vector3.UP * tile_size * 0.25
	var face := space.intersect_ray(PhysicsRayQueryParameters3D.create(waist, waist + forward * (_body_radius + tile_size * 0.24), collision_mask, [get_rid()]))
	if face.is_empty() or not face.collider is StaticBody3D or face.normal.dot(forward) > -0.85:
		return false
	forward = -Vector3(face.normal.x, 0.0, face.normal.z).normalized()
	var across := Vector3.UP.cross(forward)
	var edge: Vector3 = face.position + forward * tile_size * 0.10
	var top_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(
		edge + Vector3.UP * tile_size * 0.91, edge, collision_mask, [get_rid()]))
	if top_hit.is_empty() or top_hit.collider != face.collider or top_hit.normal.y < 0.94:
		return false
	var top: float = top_hit.position.y
	var rise := top - global_position.y
	if rise < tile_size * 0.27 or rise > tile_size * 1.12:
		return false
	var hands_first: bool = rise > _hoshi_visual.mantle_waist_height()
	var jumps: bool = not hands_first and rise > _hoshi_visual.mantle_unassisted_height()
	var palms: Array[Vector3] = []
	if hands_first:
		for side in [-1.0, 1.0]:
			var point: Vector3 = edge + across * side * tile_size * 0.19
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(point + Vector3.UP * tile_size * 0.91, point, collision_mask, [get_rid()]))
			if hit.is_empty() or hit.collider != face.collider or hit.normal.y < 0.94:
				return false
			palms.append(hit.position + Vector3.UP * tile_size * 0.035)
		if absf(palms[0].y - palms[1].y) > tile_size * 0.04:
			return false
	var supports: Array[Vector3] = []
	var landing: Vector3 = face.position + forward * (_body_radius + tile_size * 0.10)
	landing.y = top + safe_margin * 2.0
	var support_center: Vector3 = landing if jumps else top_hit.position + forward * tile_size * 0.06
	for side in ([-1.0, 1.0] if hands_first or jumps else [-1.0]):
		var point: Vector3 = support_center + across * side * tile_size * (0.095 if jumps else 0.13)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(
			point + Vector3.UP * tile_size * 0.08, point - Vector3.UP * tile_size * 0.06, collision_mask, [get_rid()]))
		if hit.is_empty() or hit.collider != face.collider or hit.normal.y < 0.94:
			return false
		supports.append(hit.position)
	var clearance := tile_size * (MiraMotionControls.LEDGE_JUMP_CLEARANCE if jumps else 0.03)
	var up := Vector3.UP * (landing.y - global_position.y + clearance)
	var over := Vector3(landing.x - global_position.x, 0.0, landing.z - global_position.z)
	if test_move(global_transform, up) or test_move(global_transform.translated(up), over):
		return false
	var raised := global_transform.translated(up + over)
	var support := KinematicCollision3D.new()
	if not test_move(raised, Vector3.DOWN * (clearance + tile_size * 0.06), support) or support.get_normal().y < 0.94:
		return false
	_mantle_start = global_position
	_mantle_landing = landing
	_mantle_time = 0.0
	_mantle_duration = duration
	_mantle_hands_first = hands_first
	_mantle_jumps = jumps
	floor_snap_length = 0.0
	velocity = Vector3.ZERO
	_mira_ground_wish = Vector3.ZERO
	_hoshi_visual.begin_mantle(palms, forward, supports, hands_first, jumps)
	return true


func _tick_mantle(dt: float) -> void:
	if _defeated or not is_instance_valid(_hoshi_visual) or not _hoshi_visual.visible:
		_finish_mantle()
		return
	_mantle_time += dt
	var phase := _mantle_time / _mantle_duration
	if _mantle_jumps:
		_hoshi_visual.set_ledge_jump_phase(phase)
		if phase >= MiraMotionControls.LEDGE_JUMP_RECOVERED:
			_finish_mantle()
			return
		# The capsule has arrived. Keep the landing pose active while the
		# knees absorb the impact and straighten over the planted feet.
		if phase > MiraMotionControls.LEDGE_JUMP_LAND + dt / _mantle_duration:
			return
		var apex := _mantle_landing.y + tile_size * MiraMotionControls.LEDGE_JUMP_CLEARANCE
		var ascent := clampf(inverse_lerp(MiraMotionControls.LEDGE_JUMP_TAKEOFF, 0.52, phase), 0.0, 1.0)
		var descent := clampf(inverse_lerp(0.52, MiraMotionControls.LEDGE_JUMP_LAND, phase), 0.0, 1.0)
		var goal := _mantle_start.lerp(_mantle_landing, smoothstep(0.39, 0.76, phase))
		goal.y = lerpf(_mantle_start.y, apex, 1.0 - (1.0 - ascent) ** 2) - (apex - _mantle_landing.y) * descent ** 2
		var hit := move_and_collide(goal - global_position)
		var landed := phase >= 0.76 and global_position.distance_to(_mantle_landing) <= tile_size * 0.03
		if hit != null and not (landed and hit.get_normal().y >= 0.94):
			_finish_mantle()
		return
	var plant := MiraMotionControls.MANTLE_FOOT_PHASE
	var over := smoothstep(0.62, 0.88, phase) if _mantle_hands_first else smoothstep(0.68, 0.92, phase)
	var position_goal := _mantle_start.lerp(_mantle_landing, over)
	var rise := smoothstep(plant + 0.03, 0.68, phase)
	if _mantle_hands_first:
		rise = smoothstep(0.21, 0.65, phase)
	position_goal.y = lerpf(_mantle_start.y, _mantle_landing.y + tile_size * 0.03, rise)
	position_goal.y -= tile_size * 0.03 * smoothstep(0.88, 1.0, phase)
	if move_and_collide(position_goal - global_position) != null or phase >= 1.0:
		_finish_mantle()


func _finish_mantle() -> void:
	_mantle_duration = 0.0
	if is_instance_valid(_hoshi_visual):
		_hoshi_visual.finish_mantle()
	floor_snap_length = STEP_VOXELS * tile_size / 16.0
	apply_floor_snap()


func _try_start_step(motion: Vector3) -> void:
	# Probe the entire capsule up, forward and down before beginning an ascent.
	# Queries use the same world collision mask as ordinary movement, including
	# authored props; there is no second heightfield or navigation owner.
	var blocked := KinematicCollision3D.new()
	if not test_move(global_transform, motion, blocked):
		return
	if blocked.get_normal().dot(Vector3.UP) >= cos(floor_max_angle):
		return
	var height := STEP_VOXELS * tile_size / 16.0
	var clearance := maxf(safe_margin * 2.0, tile_size * 0.0001)
	var up := Vector3.UP * (height + clearance)
	if test_move(global_transform, up):
		return
	var raised := global_transform
	raised.origin += up
	var radius := _body_radius
	var forward := motion.normalized() * maxf(motion.length(), radius + clearance * 2.0)
	if test_move(raised, forward):
		return
	raised.origin += forward
	var landing := KinematicCollision3D.new()
	if not test_move(raised, -Vector3.UP * (height + clearance * 2.0), landing):
		return
	if landing.get_normal().dot(Vector3.UP) < cos(floor_max_angle):
		return
	var top := maxf(raised.origin.y + landing.get_travel().y, landing.get_position().y + safe_margin)
	var rise := top - global_position.y
	if rise <= clearance or rise > height + clearance:
		return
	_step_active = true
	_step_top = top
	_step_direction = motion.normalized()
	_step_elapsed = 0.0
	# Downward snapping during the ascent would undo the lift at the old floor.
	floor_snap_length = 0.0


func _finish_step_if_supported() -> void:
	var clearance := maxf(safe_margin * 3.0, tile_size * 0.0002)
	if global_position.y < _step_top - clearance:
		if is_on_ceiling():
			_cancel_step()
		return
	# Capsule recovery at a corner may leave a tiny gap above the tread. Probe
	# only near the planned top, never snap back down to the previous floor.
	var support_distance := maxf(clearance, STEP_VOXELS * tile_size / 16.0 * 0.08)
	var floor_hit := KinematicCollision3D.new()
	if test_move(global_transform, Vector3.DOWN * support_distance, floor_hit):
		if floor_hit.get_normal().dot(Vector3.UP) >= cos(floor_max_angle):
			var supported_height := global_position.y + floor_hit.get_travel().y
			if supported_height >= _step_top - support_distance:
				_cancel_step()
				apply_floor_snap()


func _cancel_step() -> void:
	if _step_active and velocity.y > 0.0:
		velocity.y = 0.0
	_step_active = false
	_step_elapsed = 0.0
	floor_snap_length = STEP_VOXELS * tile_size / 16.0


func _ice_contact() -> Dictionary:
	if not is_on_floor():
		return {}
	var query := PhysicsRayQueryParameters3D.create(
		global_position + Vector3.UP, global_position - Vector3.UP * 2.0,
		collision_mask, [get_rid()]
	)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit.normal.y >= cos(floor_max_angle) and hit.collider is Node and hit.collider.is_in_group(ICE_SURFACE_GROUP):
		return hit
	return {}


func _trial_swim_surface() -> float:
	var already_swimming := _trial_swimming
	_trial_swimming = false
	_trial_swim_swell = 0.0
	if not is_instance_valid(_hoshi_visual) or not _hoshi_visual.can_swim_in_trial() or is_instance_valid(ice_sled):
		return 0.0
	var contact := get_node_or_null("WaterContact") as EmberWaterContact3D
	if contact == null: return 0.0
	var sample := contact.swimming_surface_sample()
	if not sample.get("wet", false): return 0.0
	var surface: float = sample.position.y
	var head_depth: float = _hoshi_visual.swim_entry_depth()
	if not already_swimming:
		_trial_swimming = surface - global_position.y >= head_depth
	else:
		var waterline := Vector3(global_position.x, surface + tile_size * 0.1, global_position.z)
		var shallow := PhysicsRayQueryParameters3D.create(waterline, waterline - Vector3.UP * (head_depth - tile_size * 0.04), 1, [get_rid()])
		_trial_swimming = get_world_3d().direct_space_state.intersect_ray(shallow).is_empty()
	if _trial_swimming:
		var water_settings := get_tree().current_scene.get_node_or_null("PlanarReflection")
		if water_settings != null and water_settings.has_method("swimmer_swell_offset"):
			_trial_swim_swell = water_settings.swimmer_swell_offset(global_position, sample)
	return surface


func _mira_ground_motion(wish: Vector3, dt: float, was_sliding: bool) -> Vector3:
	if not is_instance_valid(_hoshi_visual) or not _hoshi_visual.uses_gait_transitions():
		_mira_ground_wish = Vector3.ZERO
		_mira_stop_deceleration = 0.0
		_mira_stop_contact_wait = 0.0
		return wish
	if not is_on_floor() or was_sliding or _sliding_on_ice or _ui_blocks_movement() or _hoshi_visual.staff_strike_active():
		_hoshi_visual.set_jog_turn_input(Vector3.ZERO)
		_mira_ground_wish = Vector3.ZERO
		_mira_stop_deceleration = 0.0
		_mira_stop_contact_wait = 0.0
		_hoshi_visual.wait_for_gait_stop_contact(false)
		_hoshi_visual.clear_gait_tempo()
		_hoshi_visual.set_gait_braking(false)
		return wish
	_hoshi_visual.set_jog_turn_input(wish)
	var moving := not wish.is_zero_approx()
	if moving:
		_mira_gait_speed = _hoshi_visual.gait_speed_for_input(wish.length(), _mira_gait_speed, dt)
		var stride: float = _hoshi_visual.terrain_stride_for(wish, get_floor_normal())
		wish = wish.normalized() * _mira_gait_speed * stride * _hoshi_visual.moving_landing_speed()
		_mira_stop_deceleration = 0.0
		_mira_stop_contact_wait = 0.0
		_hoshi_visual.wait_for_gait_stop_contact(false)
	else:
		_hoshi_visual.clear_gait_tempo()
	var speed := _mira_ground_wish.length()
	var finishing := not moving and speed <= 1.25 * tile_size
	var waiting_for_contact := false
	if finishing and speed > 0.0 and _mira_stop_deceleration == 0.0 and not is_on_wall():
		var distance: float = _hoshi_visual.try_commit_gait_stop(_mira_ground_wish)
		if distance > 0.0:
			_mira_stop_direction = _mira_ground_wish.normalized()
			_mira_stop_goal = global_position + _mira_stop_direction * distance
			_mira_stop_deceleration = _mira_ground_wish.length_squared() / (2.0 * distance)
		elif _mira_stop_contact_wait < 0.30:
			waiting_for_contact = _hoshi_visual.wait_for_gait_stop_contact(true)
			_mira_stop_contact_wait += dt
	if not waiting_for_contact:
		_hoshi_visual.wait_for_gait_stop_contact(false)
	if _mira_stop_deceleration > 0.0:
		var remaining := (_mira_stop_goal - global_position).dot(_mira_stop_direction)
		if remaining <= tile_size * 0.003 or is_on_wall():
			_mira_stop_deceleration = 0.0
			_mira_ground_wish = Vector3.ZERO
			if is_on_wall():
				_hoshi_visual.set_gait_braking(false)
				_hoshi_visual.set_gait_braking(true)
			return Vector3.ZERO
		var speed_limit := sqrt(2.0 * _mira_stop_deceleration * remaining)
		var tick_speed := minf(remaining / dt, maxf(0.0, speed_limit - _mira_stop_deceleration * dt * 0.5))
		# The last sub-step reaches the anchor without overshooting it.
		if speed_limit <= _mira_stop_deceleration * dt:
			tick_speed = remaining / dt
		_mira_ground_wish = _mira_stop_direction * tick_speed
		return _mira_ground_wish
	var pace := _mira_gait_speed / tile_size
	var stop_seconds := lerpf(0.30, 0.58, smoothstep(1.2, 3.0, pace))
	stop_seconds += 0.14 * smoothstep(3.0, 4.8, pace)
	# Brake through the regular gait first. Plant the final step once the
	# remaining travel fits a short step underneath the body.
	var remaining_seconds := stop_seconds * speed / maxf(_mira_gait_speed, 0.001)
	var finish_travel := _mira_ground_wish * maxf(0.0, remaining_seconds - dt) * 0.5
	_hoshi_visual.set_gait_braking(finishing and not waiting_for_contact, finish_travel, maxf(remaining_seconds, 0.20))
	var ramp_seconds := 0.22 if moving else stop_seconds
	if waiting_for_contact:
		wish = _mira_ground_wish.limit_length(tile_size * 0.45)
	_mira_ground_wish = _mira_ground_wish.move_toward(wish, _mira_gait_speed / ramp_seconds * dt)
	return _mira_ground_wish


func _ground_motion(wish: Vector3, dt: float) -> Vector3:
	var was_ice_last_frame := _sliding_on_ice
	_sliding_on_ice = false
	if is_instance_valid(ice_sled):
		return _sled_motion(dt)
	if is_on_floor() and get_tree().has_group(ICE_SURFACE_GROUP) and (
		get_floor_normal().y < 0.999 or get_tree().has_group(FREE_ICE_GROUP)
	):
		var hit := _ice_contact()
		if not hit.is_empty():
			var normal: Vector3 = hit.normal
			var slope := Vector3(normal.x, 0.0, normal.z)
			if hit.collider.is_in_group(FREE_ICE_GROUP):
				_cancel_step()
				if not was_ice_last_frame:
					_ice_momentum = Vector3(velocity.x, 0.0, velocity.z)
				_ice_momentum = _ice_momentum.move_toward(wish * 1.35, (8.0 if wish.is_zero_approx() else 29.0) * dt)
				_ice_momentum = (_ice_momentum + slope * 76.0 * dt).limit_length(84.0)
				_sliding_on_ice = true
				return _ice_momentum
			if slope.length_squared() > 0.001:
				_cancel_step()
				var downhill := slope.normalized()
				var across := downhill.cross(Vector3.UP)
				var input := wish.limit_length(SPEED_BLOCKS * tile_size) / (SPEED_BLOCKS * tile_size)
				var forward_speed := maxf(10.0, _ice_momentum.dot(downhill))
				forward_speed = minf(ICE_MAX_SPEED, forward_speed + 115.0 * slope.length() * dt)
				var lateral := move_toward(_ice_momentum.dot(across), input.dot(across) * ICE_STEER_SPEED, 48.0 * dt)
				_ice_momentum = downhill * forward_speed + across * lateral
				_sliding_on_ice = true
				_interaction_forward = _ice_momentum.normalized()
				return _ice_momentum
	if not _ice_momentum.is_zero_approx():
		if not is_on_floor():
			return _ice_momentum
		_ice_momentum = _ice_momentum.move_toward(wish, ICE_DRY_BRAKE * dt)
		if _ice_momentum.is_equal_approx(wish):
			_ice_momentum = Vector3.ZERO
			return wish
		return _ice_momentum
	return wish


func begin_ice_sled(sled: Node3D) -> bool:
	var progress := _progress()
	if _ui_blocks_movement() or flight_motion != null or has_meta("ember_carried_item"):
		return false
	if progress == null or progress.combat_party_locked or global_position.distance_to(sled.global_position) > 8.0:
		return false
	var launch: Marker3D = sled.launch
	var heading := launch.global_basis.z
	_sled_launch_heading = Vector3(heading.x, 0.0, heading.z).normalized()
	var lift := Vector3.UP * (3.0 + maxf(0.0, launch.global_position.y - global_position.y))
	var raised := global_transform.translated(lift)
	var above_launch := Vector3(launch.global_position.x, raised.origin.y, launch.global_position.z)
	if _sled_launch_heading.is_zero_approx() or test_move(global_transform, lift):
		return false
	if test_move(raised, above_launch - raised.origin) or test_move(
		Transform3D(global_basis, above_launch), launch.global_position - above_launch
	):
		return false
	_cancel_step()
	ice_sled = sled
	_sled_heading = _sled_launch_heading
	_sled_speed = 6.0
	_sled_surface_rise = 0.0
	_sled_elapsed = 0.0
	_ice_momentum = Vector3.ZERO
	velocity = Vector3.ZERO
	global_position = launch.global_position
	for child in [get_node("Viz"), get_node("Facing")]:
		_sled_visual_rest[child] = child.transform
		child.position.y = child.position.y * 0.58 + 3.0
		child.scale.y *= 0.58
	return true


func _sled_motion(dt: float) -> Vector3:
	_sled_elapsed += dt
	var hit := _ice_contact()
	if not hit.is_empty():
		var turn := Input.get_axis("move_west", "move_east") * 0.85 * dt
		var angle := _sled_launch_heading.signed_angle_to(_sled_heading, Vector3.UP)
		_sled_heading = _sled_launch_heading.rotated(Vector3.UP, clampf(angle - turn, -0.48, 0.48))
		var normal: Vector3 = hit.normal
		var downhill := Vector3(normal.x, 0.0, normal.z)
		var drag := 13.0 if downhill.length_squared() < 0.001 else 4.0
		_sled_speed = clampf(_sled_speed + (downhill.dot(_sled_heading) * 145.0 - drag) * dt, 0.0, 84.0)
		_sled_surface_rise = -downhill.dot(_sled_heading * _sled_speed) / maxf(normal.y, 0.1)
		_sliding_on_ice = true
	elif is_on_floor() and _sled_elapsed > 0.2 and get_floor_normal().y >= 0.999:
		_sled_speed = move_toward(_sled_speed, 0.0, 98.0 * dt)
		_sled_surface_rise = 0.0
	return _sled_heading * _sled_speed


func _update_sled_visual() -> void:
	if is_on_floor() and _sled_elapsed > 0.5 and (_sled_speed < 0.5 or is_on_wall()):
		_end_ice_sled()
		return
	ice_sled.update_rider(global_position, _sled_heading, get_floor_normal() if is_on_floor() else Vector3.UP)
	if interact_hud:
		interact_hud.text = "%s\nСани · A / D — рулить" % _health_text()


func _end_ice_sled() -> void:
	if is_instance_valid(ice_sled):
		ice_sled.park()
	ice_sled = null
	for child in _sled_visual_rest:
		child.transform = _sled_visual_rest[child]
	_sled_visual_rest.clear()
	_sliding_on_ice = false
	velocity = Vector3.ZERO


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
		if is_instance_valid(_hoshi_visual) and _hoshi_visual.visible:controls=controls.replace("WASD ходить","WASD бег · Shift шаг")
		if boost_modifier_key != KEY_NONE:
			controls=controls.replace("WASD бег · Shift шаг","WASD ходить").replace("WASD ходить","WASD ход · %s шаг · %s ускорение" % [OS.get_keycode_string(walk_modifier_key),OS.get_keycode_string(boost_modifier_key)])
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
	if _mantle_duration > 0.0:
		_finish_mantle()
	controlled_hero_id = hero_id if hero_id in PartyState.HERO_IDS else PartyState.LEADER_ID
	_refresh_active_visual()


func _apply_hero_scale() -> void:
	if _applied_hero_scale == controlled_hero_id:
		return
	var height := HeroScale.height(controlled_hero_id, tile_size)
	var radius := HeroScale.collision_radius(tile_size)
	var visual_radius := HeroScale.radius(controlled_hero_id, tile_size)
	var shape_node := get_node_or_null("Shape") as CollisionShape3D
	var visual := get_node_or_null("Viz") as MeshInstance3D
	var facing := get_node_or_null("Facing") as MeshInstance3D
	if shape_node == null or visual == null or facing == null:
		return
	var capsule := shape_node.shape as CapsuleShape3D
	var mesh := visual.mesh as CapsuleMesh
	var marker := facing.mesh as SphereMesh
	if capsule == null or mesh == null or marker == null:
		return
	capsule.radius = radius
	capsule.height = height
	shape_node.position.y = height * 0.5
	mesh.radius = visual_radius
	mesh.height = height
	visual.position.y = height * 0.5
	marker.radius = visual_radius * 0.21
	marker.height = visual_radius * 0.42
	facing.position = Vector3(0.0, height * 0.66, visual_radius * 0.93)
	if _status_label != null:
		_status_label.position.y = height + 2.3 * tile_size / 16.0
	_body_radius = radius
	_applied_hero_scale = controlled_hero_id


func _refresh_active_visual() -> void:
	_apply_hero_scale()
	_sync_hoshi_visual()
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
	_end_ice_sled()
	if _mantle_duration > 0.0:
		_finish_mantle()
	_ice_momentum = Vector3.ZERO
	_sliding_on_ice = false
	_cancel_step()
	if is_instance_valid(camera_rig):
		camera_rig.reset_follow_height()
	_defeated = false
	velocity = Vector3.ZERO
	_respawn_grace_frames = 1
	_action_message = "Возвращение к точке входа"
	_action_message_until_ms = Time.get_ticks_msec() + ACTION_MESSAGE_MS


func _enter_defeat() -> void:
	_end_ice_sled()
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
	var carried_pickup: Node3D
	if has_meta("ember_carried_item"):
		var held: WeakRef = get_meta("ember_carried_item")
		var body := held.get_ref() as Node3D
		if is_instance_valid(body) and body.has_node("Pickup"):
			carried_pickup = body.get_node("Pickup")
	var origin := global_position
	var best: Node3D = null
	var best_d := 12.0
	for node in get_tree().get_nodes_in_group("ember_interact"):
		var area := node as Node3D
		if area == null or (not area is EmberInteract and not area is EmberRegion):
			continue
		if carried_pickup != null:
			if not area is EmberInteract or area.kind != "door" or not ResourceLoader.exists(EmberMapTransition.scene_path(area.target_map_id)): continue
		if not area.is_visible_in_tree() or area.is_queued_for_deletion(): continue
		var d := (
			(area as EmberInteract).distance_to_world(origin)
			if area is EmberInteract
			else origin.distance_to(area.global_position)
		)
		if d < best_d:
			# Story routing can touch quest/legacy content. Only a reachable
			# candidate that could beat the current target needs that work.
			if area is EmberInteract:
				var progress := _progress()
				if carried_pickup != null and not area.runtime_route(progress.flags if progress != null else {}).get("primary", false): continue
				if not area.runtime_available(progress.flags if progress != null else {}): continue
			best_d = d
			best = area
	return best if best != null else carried_pickup


func _nearest_prompt() -> String:
	var area := _nearest()
	if area == null:
		return ""
	if area is EmberInteract:
		var target := area.get_parent()
		if uses_crate_magic() and target.has_method("is_heavy_crate") and target.is_heavy_crate():
			return "F — толкнуть посохом"
		return (area as EmberInteract).prompt()
	return (area as EmberRegion).prompt()

func begin_magic_crate_push(body: RigidBody3D) -> String:
	if _magic_push_body != null:
		return ""
	if not is_on_floor() or _trial_swimming or carried_crate() != null or _hoshi_visual.staff_strike_active() or body.freeze:
		return "Сейчас нельзя толкнуть ящик"
	var normal: Vector3 = body.heavy_crate_face(global_position)
	if normal.is_zero_approx():
		return "Встань перед гранью ящика"
	var box: CollisionShape3D = body.crate_box()
	var half: Vector3 = box.shape.size * 0.5
	var start := global_position + Vector3.UP * tile_size
	var face_point := box.to_global(box.to_local(start).clamp(-half, half))
	var ray := PhysicsRayQueryParameters3D.create(start, face_point, 1, [get_rid(), body.get_rid()])
	if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
		return "Ящик закрыт препятствием"
	_magic_push_body = weakref(body)
	_magic_push_normal = normal
	_magic_push_retreat = 0.18
	_magic_push_left = crate_motion_duration("push", 0.95)
	_interaction_forward = -normal
	_hoshi_visual.face_crate(-normal)
	return ""

func magic_push_active() -> bool:
	return _magic_push_body != null

func _tick_magic_crate_push(dt: float) -> Vector3:
	var body := _magic_push_body.get_ref() as RigidBody3D
	if not is_instance_valid(body) or body.is_queued_for_deletion() or body.freeze or not body.is_item_available() or not uses_crate_magic() or _ui_blocks_movement() or not is_on_floor():
		_magic_push_body = null
		return Vector3.ZERO
	if _magic_push_retreat > 0.0:
		_magic_push_retreat -= dt
		return _magic_push_normal * tile_size * 1.35
	var direction := -_magic_push_normal
	_hoshi_visual.face_crate(direction)
	if not prepare_crate_magic(direction):
		return Vector3.ZERO
	_hoshi_visual.note_crate_push(body, _magic_push_normal)
	_magic_push_left -= dt
	if _magic_push_left <= 0.0:
		_magic_push_body = null
		return Vector3.ZERO
	var phase := 1.0 - _magic_push_left / maxf(0.01, crate_motion_duration("push", 0.95))
	var pressure := crate_motion_weight("push", phase, smoothstep(0.18, 0.24, phase))
	if pressure > 0.0:
		body.push_from(direction, tile_size * 0.85 * pressure)
		return direction * maxf(0.0, body.linear_velocity.dot(direction))
	return Vector3.ZERO

func _push_heavy_crate(body: RigidBody3D, normal: Vector3, dt: float) -> void:
	var id := body.get_instance_id()
	if _heavy_push_id != id:
		_heavy_push_id = id
		_heavy_push_time = 0.0
	_heavy_push_gap = 0.0
	_heavy_push_time += dt
	if is_instance_valid(_hoshi_visual) and _hoshi_visual.visible:
		_hoshi_visual.note_crate_push(body, normal)
	if _heavy_push_time >= 0.14:
		body.push_from(-normal, tile_size * 0.85)

func carried_crate() -> Node3D:
	var held := get_meta("ember_carried_item", null) as WeakRef if has_meta("ember_carried_item") else null
	var body := held.get_ref() as Node3D if held != null else null
	return body if is_instance_valid(body) and body.get("item_id") == "quest_crate" else null

func uses_crate_animation() -> bool:
	return is_instance_valid(_hoshi_visual) and _hoshi_visual.visible and _hoshi_visual.supports_crate_pose()

func uses_crate_magic() -> bool:
	return controlled_hero_id == "mira" and uses_crate_animation() and _hoshi_visual.has_trial_staff()

func prepare_crate_magic(direction: Vector3) -> bool:
	return _hoshi_visual.prepare_crate_magic(direction)

func crate_motion_duration(action: String, fallback: float) -> float:
	return _hoshi_visual.crate_motion_duration(action, fallback) if uses_crate_magic() else fallback

func crate_motion_weight(action: String, phase: float, fallback: float) -> float:
	return _hoshi_visual.crate_motion_weight(action, &"crate_travel", phase, fallback) if uses_crate_magic() else fallback

func report_crate_action(message: String) -> void:
	if message.is_empty():
		return
	_action_message = message
	_action_message_until_ms = Time.get_ticks_msec() + ACTION_MESSAGE_MS

func interaction_forward() -> Vector3:
	return _interaction_forward


func _try_interact() -> void:
	if _magic_push_body != null or is_instance_valid(_reaching_door):
		return
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


func begin_zipline(route: Node3D) -> bool:
	var progress := _progress()
	if _ui_blocks_movement() or flight_motion != null or has_meta("ember_carried_item"):
		return false
	if progress == null or progress.combat_party_locked or not route.can_mount(self):
		return false
	if route.is_cable() and is_instance_valid(_hoshi_visual) and _hoshi_visual.visible and not _hoshi_visual.prepare_cable_grip():
		return false
	_cancel_step()
	zipline = route
	_zipline_elapsed = 0.0
	_ice_momentum = Vector3.ZERO
	_sliding_on_ice = false
	_zipline_departure = global_position
	route.start_ride(global_position)
	_vine_trail.clear()
	if route.is_pipe():
		for child in [get_node("Viz"), get_node("Facing"), _status_label, _hoshi_visual]:
			if is_instance_valid(child):
				_pipe_visual_rest[child] = child.transform
		if is_instance_valid(camera_rig):
			camera_rig.set_pipe_view(route, get_node("Viz") as Node3D)
	velocity = Vector3.ZERO
	_prompt = ""
	if interact_hud:
		interact_hud.text = "%s\n%s" % [_health_text(), route.ride_hint()]
	if is_instance_valid(party_followers):
		party_followers.release_hold()
	return true


func _tick_zipline(dt: float) -> void:
	var route := zipline
	if _route_airborne:
		_tick_route_air(dt)
		return
	_zipline_elapsed += dt
	route.advance_rope_load(_zipline_elapsed, dt)
	route.steer_ride(_zipline_elapsed, dt, Input.get_axis("move_west", "move_east"))
	var next: Vector3 = route.rider_position(_zipline_elapsed)
	if route.supports_transfers():
		next = _vine_ride_position(route, next, dt)
	if test_move(global_transform, next - global_position):
		global_position = _zipline_departure
		_end_zipline()
		_action_message = "Путь перекрыт. Попробуй ещё раз."
		_action_message_until_ms = Time.get_ticks_msec() + ACTION_MESSAGE_MS
		return
	global_position = next
	if route.supports_transfers():
		_vine_trail.append(next)
		if is_instance_valid(_vine_target):
			if _vine_jump_elapsed >= VINE_JUMP_TIME:
				route.release_rope_load()
				zipline = _vine_target
				_zipline_elapsed = _vine_arrival
				_vine_target = null
			_update_route_followers(zipline)
			return
	_update_route_pose(route)
	var duration: float = route.duration()
	if route.is_pipe() and route.cross_section == 1 and _zipline_elapsed >= duration:
		var lip: Vector3 = route.rider_position(duration)
		var last: Vector3 = route.rider_position(maxf(0.0, duration - dt))
		if lip.y > route.route_point(1.0).y + 2.0:
			_zipline_elapsed = duration
			velocity = (lip - last) / dt
			_route_airborne = true
			route.begin_air_exit(dt, lip)
			if is_instance_valid(camera_rig):
				camera_rig.clear_pipe_approach(route)
				camera_rig.set_pipe_view(null)
			return
	var follower_count := _update_route_followers(route)
	if _zipline_elapsed >= duration + follower_count * route.FOLLOW_DELAY:
		_end_zipline()


func _tick_route_air(dt: float) -> void:
	var route := zipline
	_zipline_elapsed += dt
	if _route_touchdown < 0.0:
		velocity.y -= 86.0 * dt
		move_and_slide()
		if is_on_floor() and velocity.y <= 0.0:
			velocity = Vector3.ZERO
			_route_touchdown = _zipline_elapsed
		elif _zipline_elapsed - route.duration() > 4.0:
			global_position = _zipline_departure
			_end_zipline()
			return
	route.record_air_exit(global_position)
	_update_route_pose(route)
	var follower_count := _update_route_followers(route)
	if _route_touchdown >= 0.0 and _zipline_elapsed >= _route_touchdown + follower_count * route.FOLLOW_DELAY:
		_end_zipline()


func _update_route_pose(route: Node3D) -> void:
	if not _pipe_visual_rest.is_empty():
		var pose: Basis = global_basis.inverse() * route.rider_basis(_zipline_elapsed)
		for child in _pipe_visual_rest:
			child.transform = Transform3D(pose, Vector3.ZERO) * _pipe_visual_rest[child]
		if is_instance_valid(camera_rig):
			camera_rig._pipe_elapsed = _zipline_elapsed


func _update_route_followers(route: Node3D) -> int:
	if is_instance_valid(party_followers):
		if route.supports_transfers():
			return party_followers.ride_vine_trail(_vine_trail, float(route.FOLLOW_DELAY))
		return party_followers.ride_zipline(route, _zipline_elapsed)
	return 0

func cable_hand_targets() -> Dictionary:
	if not is_instance_valid(zipline) or is_instance_valid(_vine_target) or _route_airborne:
		return {}
	return zipline.cable_grip_at(_zipline_elapsed, tile_size * 0.105)


func _vine_ride_position(route: Node3D, along_route: Vector3, dt: float) -> Vector3:
	if not is_instance_valid(_vine_target):
		var direction := int(Input.is_action_just_pressed("move_east")) - int(Input.is_action_just_pressed("move_west"))
		if direction != 0:
			var target: Node3D = route.vine_transfer_target(_zipline_elapsed, direction)
			if target != null:
				var arrival: float = target.vine_arrival_time(global_position, VINE_JUMP_TIME)
				if arrival > 0.0 and global_position.distance_to(target.rider_position(arrival)) <= 48.0:
					_vine_target = target
					_vine_arrival = arrival
					_vine_launch = global_position
					_vine_jump_elapsed = 0.0
	if not is_instance_valid(_vine_target):
		if interact_hud:
			interact_hud.text = "%s\n%s" % [_health_text(), route.vine_hint(_zipline_elapsed)]
		return along_route
	_vine_jump_elapsed = minf(VINE_JUMP_TIME, _vine_jump_elapsed + dt)
	var t := _vine_jump_elapsed / VINE_JUMP_TIME
	var destination: Vector3 = _vine_target.rider_position(_vine_arrival)
	if interact_hud:
		interact_hud.text = "%s\nПрыжок на соседнюю ветку" % _health_text()
	return _vine_launch.lerp(destination, t) + Vector3.UP * (24.0 * t * (1.0 - t))


func _end_zipline() -> void:
	if is_instance_valid(zipline):
		zipline.release_rope_load()
	zipline = null
	_vine_target = null
	_vine_trail.clear()
	_route_airborne = false
	_route_touchdown = -1.0
	velocity = Vector3.ZERO
	if not _pipe_visual_rest.is_empty():
		for child in _pipe_visual_rest:
			child.transform = _pipe_visual_rest[child]
		_pipe_visual_rest.clear()
		if is_instance_valid(camera_rig):
			camera_rig.clear_pipe_approach(camera_rig._pipe_route)
			camera_rig.set_pipe_view(null)
	if is_instance_valid(party_followers):
		party_followers.reset_to_leader()


func activate_interact(interact: EmberInteract, allow_door_reach := true) -> bool:
	if interact == null or _ui_blocks_movement():
		return false
	var progress := _progress()
	var flags := progress.flags if progress != null else {}
	if not interact.runtime_available(flags):
		return false
	var routed_script := interact.routed_script_id(flags)
	var leaf := interact.swing_leaf()
	if interact.kind == "door" and routed_script.is_empty() and leaf != null:
		if is_zero_approx(leaf.rotation.y) and allow_door_reach and _begin_door_reach(interact):
			return true
		leaf.rotation.y = deg_to_rad(90.0)
		interact.refresh_runtime_binding()
		return true
	if (
		allow_door_reach and interact.kind == "door" and routed_script.is_empty()
		and not interact.target_map_id.is_empty()
		and ResourceLoader.exists(EmberMapTransition.scene_path(interact.target_map_id))
		and _begin_door_reach(interact)
	):
		return true
	var message := ""
	if is_instance_valid(interaction_ui) and (
		interact.kind == "talk"
		or interact.kind == "shop"
		or not routed_script.is_empty()
	):
		message = interaction_ui.activate(interact)
	else:
		message = interact.activate_from(self)
	if not message.is_empty():
		_action_message = message
		_action_message_until_ms = Time.get_ticks_msec() + ACTION_MESSAGE_MS
	return true

func _begin_door_reach(interact: EmberInteract) -> bool:
	if is_instance_valid(_reaching_door):
		return true
	var leaf := interact.swing_leaf()
	var contact := (leaf if leaf != null else interact).get_node_or_null("HandContact") as Marker3D
	if (
		contact == null or not uses_crate_animation() or not _hoshi_visual.can_reach_door()
		or has_meta("ember_carried_item") or not is_on_floor()
	):
		return false
	var offset := contact.global_position - global_position
	offset.y = 0.0
	var normal := interact.global_basis.z if leaf != null else contact.global_basis.z
	if offset.length() > tile_size * 0.70 or offset.dot(normal) >= 0.0:
		return false
	_reaching_door = interact
	_door_reach_elapsed = 0.0
	return true

func door_hand_contact() -> Marker3D:
	if not is_instance_valid(_reaching_door):
		return null
	var leaf := _reaching_door.swing_leaf()
	return (leaf if leaf != null else _reaching_door).get_node_or_null("HandContact") as Marker3D

func door_is_swinging() -> bool:
	return is_instance_valid(_reaching_door) and _reaching_door.swing_leaf() != null

func door_reach_phase() -> float:
	var duration: float = 1.05 if door_is_swinging() else _hoshi_visual.door_reach_duration()
	return clampf(_door_reach_elapsed / duration, 0.0, 1.0)

func _door_approach_velocity() -> Vector3:
	var contact := door_hand_contact()
	if contact == null or _ui_blocks_movement():
		return Vector3.ZERO
	var normal := (_reaching_door.global_basis.z if door_is_swinging() else contact.global_basis.z).normalized()
	_hoshi_visual.face_crate(-normal)
	if door_is_swinging():
		var phase := door_reach_phase()
		var gap := (global_position - _reaching_door.global_position).dot(normal)
		var target_gap := lerpf(tile_size * 0.23, -tile_size * 0.38, smoothstep(0.30, 0.84, phase))
		return -normal * clampf((gap - target_gap) * 15.0, 0.0, tile_size * 1.8)
	var gap := (global_position - contact.global_position).dot(normal)
	var speed := clampf((gap - tile_size * 0.25) * 10.0, 0.0, tile_size * 1.2)
	return -normal * speed if door_reach_phase() < 0.65 else Vector3.ZERO

func _tick_door_reach(dt: float) -> bool:
	if _ui_blocks_movement() or not is_instance_valid(door_hand_contact()) or not is_instance_valid(_hoshi_visual) or not _hoshi_visual.can_reach_door():
		if door_is_swinging() and not is_zero_approx(_reaching_door.swing_leaf().rotation.y):
			_reaching_door.swing_leaf().rotation.y = deg_to_rad(90.0)
			_reaching_door.refresh_runtime_binding()
		_reaching_door = null
		return false
	_door_reach_elapsed += dt
	if door_is_swinging():
		var leaf := _reaching_door.swing_leaf()
		var phase := door_reach_phase()
		var push_angle := 22.0 * smoothstep(0.36, 0.57, phase)
		var follow_through := 68.0 * smoothstep(0.57, 0.84, phase)
		leaf.rotation.y = deg_to_rad(push_angle + follow_through)
	if door_reach_phase() >= 1.0:
		var door := _reaching_door
		_reaching_door = null
		return activate_interact(door, false)
	return false


func ask_mira_direction() -> bool:
	var progress := _progress()
	if _ui_blocks_movement() or progress == null or progress.combat_party_locked or flight_motion != null:
		return false
	if "mira" not in progress.active_hero_ids or controlled_hero_id == "mira":
		return false
	if not is_instance_valid(quest_tracker_ui) or not is_instance_valid(interaction_ui):
		return false
	var direction: String = quest_tracker_ui.current_direction()
	return interaction_ui.show_companion_direction("Мира", direction)


func _ui_blocks_movement() -> bool:
	return (
		_defeated
		or is_instance_valid(zipline)
		or is_instance_valid(ice_sled)
		or (is_instance_valid(interaction_ui) and interaction_ui.blocks_movement())
		or (is_instance_valid(inventory_ui) and inventory_ui.blocks_movement())
		or (is_instance_valid(quest_journal_ui) and quest_journal_ui.blocks_movement())
		or (is_instance_valid(pause_ui) and pause_ui.blocks_movement())
	)


func _progress() -> EmberExploreState:
	if is_instance_valid(progress_state):
		return progress_state
	return get_node_or_null("/root/EmberExploreProgress") as EmberExploreState
