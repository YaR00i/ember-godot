class_name EmberPartyFollowers
extends Node3D
## Lightweight exploration-only projection of the persistent party.
## The leader remains the sole CharacterBody/controller. Companions replay the
## leader's valid trail and may add a bounded lateral formation offset.

signal mode_changed(mode: String, label: String)

const PartyState := preload("res://scripts/ember_party_state.gd")

const MODE_TRAIN := "train"
const MODE_FORMATION := "formation"
const MODES: Array[String] = [MODE_FORMATION, MODE_TRAIN]
const HERO_COLORS := {
	"protagonist": Color("ffac5a"),
	"mira": Color("65cfe1"),
	"orik": Color("7ad9b0"),
	"sena": Color("c9a4ff"),
}

var leader: Node3D
var progress_state: EmberExploreState
var tile_size := 16.0
var mode := MODE_FORMATION
var active_hero_id := PartyState.LEADER_ID

var _followers: Array[Node3D] = []
var _visuals: Dictionary = {}
var _trail: Array[Vector3] = []
var _last_leader_position := Vector3.ZERO
var _last_sample_position := Vector3.ZERO
var _last_forward := Vector3(0.0, 0.0, -1.0)
var _elapsed := 0.0


func _ready() -> void:
	if progress_state == null:
		progress_state = get_node_or_null("/root/EmberExploreProgress") as EmberExploreState
	if progress_state != null:
		mode = normalized_mode(progress_state.party_follow_mode)
		active_hero_id = _normalized_hero_id(progress_state.exploration_leader_id)
		if not progress_state.progress_changed.is_connected(_refresh_labels):
			progress_state.progress_changed.connect(_refresh_labels)
		if not progress_state.exploration_leader_changed.is_connected(_on_exploration_leader_changed):
			progress_state.exploration_leader_changed.connect(_on_exploration_leader_changed)
	_build_followers()
	reset_to_leader()
	mode_changed.emit(mode, mode_label())


func _exit_tree() -> void:
	if progress_state != null and progress_state.progress_changed.is_connected(_refresh_labels):
		progress_state.progress_changed.disconnect(_refresh_labels)
	if progress_state != null and progress_state.exploration_leader_changed.is_connected(_on_exploration_leader_changed):
		progress_state.exploration_leader_changed.disconnect(_on_exploration_leader_changed)


func _physics_process(delta: float) -> void:
	if not is_instance_valid(leader) or _followers.is_empty():
		return
	_elapsed += maxf(0.0, delta)
	_record_leader_position()
	var leader_moving := _horizontal_distance(leader.global_position, _last_leader_position) > 0.001
	for index in _followers.size():
		var follower := _followers[index]
		var target := target_for(index)
		var distance := follower.global_position.distance_to(target)
		if distance > tile_size * 4.5:
			follower.global_position = target
		else:
			var response := 7.5 + float(index) * 0.65
			follower.global_position = follower.global_position.lerp(
				target,
				1.0 - exp(-response * maxf(0.0, delta)),
			)
		var horizontal_motion := Vector3(target.x - follower.global_position.x, 0.0, target.z - follower.global_position.z)
		if horizontal_motion.length_squared() > 0.0001:
			var desired_yaw := atan2(horizontal_motion.x, horizontal_motion.z)
			follower.rotation.y = lerp_angle(follower.rotation.y, desired_yaw, 1.0 - exp(-9.0 * delta))
		_animate_visual(follower, index, leader_moving, delta)
	_last_leader_position = leader.global_position


func toggle_mode() -> String:
	return set_mode(MODE_TRAIN if mode == MODE_FORMATION else MODE_FORMATION)


func set_mode(value: String) -> String:
	var normalized := normalized_mode(value)
	if normalized == mode:
		return mode
	mode = normalized
	if progress_state != null:
		progress_state.set_party_follow_mode(mode)
	mode_changed.emit(mode, mode_label())
	return mode


func set_active_hero(hero_id: String) -> String:
	var clean_id := _normalized_hero_id(hero_id)
	if clean_id == active_hero_id:
		return active_hero_id
	var previous_id := active_hero_id
	var incoming := _visuals.get(clean_id) as Node3D
	var swap_position := incoming.global_position if is_instance_valid(incoming) else leader.global_position
	active_hero_id = clean_id
	_sync_active_roster()
	var outgoing := _visuals.get(previous_id) as Node3D
	if is_instance_valid(outgoing):
		outgoing.global_position = swap_position
	return active_hero_id


func mode_label() -> String:
	return "Паровозик" if mode == MODE_TRAIN else "Живая формация"


func target_for(index: int) -> Vector3:
	if not is_instance_valid(leader):
		return Vector3.ZERO
	var clean_index := clampi(index, 0, maxi(0, _followers.size() - 1))
	if mode == MODE_TRAIN:
		return _trail_point(tile_size * (0.78 + float(clean_index) * 0.72))
	var behind_distance: float = float([0.68, 0.78, 1.46][clean_index]) * tile_size
	var anchor := _trail_point(behind_distance)
	var right := Vector3(-_last_forward.z, 0.0, _last_forward.x)
	var lateral: float = float([0.52, -0.52, 0.08][clean_index]) * tile_size
	# Small deterministic motion keeps the party from looking bolted to three
	# sockets while stopped. It never exceeds a fraction of one gameplay tile.
	var living_offset := sin(_elapsed * (0.75 + clean_index * 0.11) + clean_index * 1.9)
	lateral += living_offset * tile_size * (0.035 if clean_index < 2 else 0.055)
	var candidate: Vector3 = anchor + right * lateral
	candidate.y = anchor.y
	return candidate if _formation_path_is_clear(anchor, candidate) else anchor


func reset_to_leader() -> void:
	if not is_instance_valid(leader):
		return
	_last_leader_position = leader.global_position
	_last_sample_position = leader.global_position
	_trail.clear()
	for index in 48:
		_trail.append(leader.global_position)
	for index in _followers.size():
		_followers[index].global_position = target_for(index)


func view_state() -> Dictionary:
	var positions: Array[Vector3] = []
	for follower in _followers:
		positions.append(follower.global_position)
	return {
		"mode": mode,
		"modeLabel": mode_label(),
		"activeHeroId": active_hero_id,
		"count": _followers.size(),
		"positions": positions,
		"trailSamples": _trail.size(),
	}


static func normalized_mode(value: String) -> String:
	return value if value in MODES else MODE_FORMATION


func _build_followers() -> void:
	if not _visuals.is_empty():
		return
	var scale_factor := tile_size / 16.0
	for hero_id in PartyState.HERO_IDS:
		var follower := Node3D.new()
		follower.name = "PartyFollower_%s" % hero_id
		follower.set_meta("hero_id", hero_id)
		add_child(follower)

		var mesh := MeshInstance3D.new()
		mesh.name = "Body"
		var capsule := CapsuleMesh.new()
		capsule.radius = 2.15 * scale_factor
		capsule.height = 10.5 * scale_factor
		mesh.mesh = capsule
		mesh.position.y = capsule.height * 0.5
		var material := StandardMaterial3D.new()
		material.albedo_color = _hero_color(hero_id)
		material.roughness = 0.7
		mesh.material_override = material
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		follower.add_child(mesh)

		var facing := MeshInstance3D.new()
		facing.name = "Facing"
		var marker := SphereMesh.new()
		marker.radius = 0.48 * scale_factor
		marker.height = 0.96 * scale_factor
		facing.mesh = marker
		facing.position = Vector3(0.0, capsule.height * 0.66, capsule.radius * 0.93)
		var face_material := StandardMaterial3D.new()
		face_material.albedo_color = Color("fff2d8")
		face_material.emission_enabled = true
		face_material.emission = _hero_color(hero_id) * 0.28
		facing.material_override = face_material
		follower.add_child(facing)

		var label := Label3D.new()
		label.name = "Status"
		label.position.y = capsule.height + 2.3 * scale_factor
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.fixed_size = false
		label.font_size = 28
		label.outline_size = 7
		label.pixel_size = 0.028 * scale_factor
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.modulate = Color("f5f8ff")
		follower.add_child(label)
		_visuals[hero_id] = follower
	_sync_active_roster()
	_refresh_labels()


func _refresh_labels() -> void:
	# Membership can change while the current leader stays the same.
	_sync_active_roster()
	var views_by_id := {}
	if progress_state != null:
		for view in progress_state.party_view():
			views_by_id[str(view.get("heroId", ""))] = view
	for raw_follower in _visuals.values():
		var follower := raw_follower as Node3D
		if follower == null:
			continue
		var hero_id := str(follower.get_meta("hero_id", ""))
		var view: Dictionary = views_by_id.get(hero_id, {})
		var label := follower.get_node_or_null("Status") as Label3D
		if label == null:
			continue
		var hp := int(view.get("hp", 0))
		var max_hp := int(view.get("maxHp", 0))
		label.text = "%s\nHP %d/%d" % [str(view.get("nameRu", hero_id)), hp, max_hp]
		label.modulate = Color("f0a0a0") if hp <= 0 else Color("f5f8ff")


func _on_exploration_leader_changed(hero_id: String) -> void:
	set_active_hero(hero_id)


func _sync_active_roster() -> void:
	_followers.clear()
	for hero_id in PartyState.HERO_IDS:
		var visual := _visuals.get(hero_id) as Node3D
		if visual == null:
			continue
		visual.visible = hero_id != active_hero_id and (progress_state == null or hero_id in progress_state.active_hero_ids)
		if visual.visible:
			_followers.append(visual)


func _normalized_hero_id(hero_id: String) -> String:
	var ids := progress_state.active_hero_ids if progress_state != null else PartyState.HERO_IDS
	return hero_id if hero_id in ids else ids[0]


func _hero_color(hero_id: String) -> Color:
	var definition := PartyState.unit_definition(hero_id)
	return definition.get("battleColor", HERO_COLORS.get(hero_id, Color.WHITE))


func _record_leader_position() -> void:
	var current := leader.global_position
	var delta := Vector3(current.x - _last_sample_position.x, 0.0, current.z - _last_sample_position.z)
	if delta.length() < tile_size * 0.075:
		return
	_last_forward = delta.normalized()
	_trail.push_front(current)
	_last_sample_position = current
	var maximum_samples := 160
	if _trail.size() > maximum_samples:
		_trail.resize(maximum_samples)


func _trail_point(distance: float) -> Vector3:
	if _trail.is_empty():
		return leader.global_position if is_instance_valid(leader) else Vector3.ZERO
	var remaining := maxf(0.0, distance)
	var previous := _trail[0]
	for index in range(1, _trail.size()):
		var current := _trail[index]
		var segment := previous.distance_to(current)
		if segment >= remaining and segment > 0.0001:
			return previous.lerp(current, remaining / segment)
		remaining -= segment
		previous = current
	return _trail[_trail.size() - 1]


func _formation_path_is_clear(anchor: Vector3, candidate: Vector3) -> bool:
	if anchor.distance_squared_to(candidate) < 0.001 or not is_inside_tree():
		return true
	var query := PhysicsRayQueryParameters3D.create(
		anchor + Vector3.UP * tile_size * 0.32,
		candidate + Vector3.UP * tile_size * 0.32,
		1,
	)
	if leader is CollisionObject3D:
		query.exclude = [(leader as CollisionObject3D).get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()


func _animate_visual(follower: Node3D, index: int, moving: bool, delta: float) -> void:
	var body := follower.get_node_or_null("Body") as MeshInstance3D
	if body == null:
		return
	var scale_factor := tile_size / 16.0
	var speed := 7.0 if moving else 1.65
	var amplitude := 0.32 if moving else 0.09
	var wave := sin(_elapsed * speed + float(index) * 1.7)
	var base_height := (body.mesh as CapsuleMesh).height * 0.5
	body.position.y = base_height + wave * amplitude * scale_factor
	body.rotation.z = lerp(body.rotation.z, wave * (0.035 if moving else 0.012), 1.0 - exp(-8.0 * delta))
	body.scale.y = lerpf(body.scale.y, 1.0 + absf(wave) * (0.035 if moving else 0.01), 1.0 - exp(-9.0 * delta))


func _horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
