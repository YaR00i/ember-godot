extends CharacterBody3D
## Field movement and first contact only; the encounter owns actual combat.
@export var home := Vector3(-248,12,312)
@export var combat_unit_id := "shore_boar"
var _phase := 0.0
var _target := Vector3.ZERO
var _engaging := false
var _facing := Vector3.FORWARD

func _ready() -> void:
	visible = false
	collision_layer = 0
	collision_mask = 1
	_target = home
	add_to_group("ember_field_enemies")

func _world() -> Node:
	return get_tree().current_scene

func _available() -> bool:
	var state := get_node("/root/EmberExploreProgress") as EmberExploreState
	return bool(state.flags.get("shore_shells_delivered",false)) and not bool(state.flags.get("shore_boar_defeated",false))

func _physics_process(dt: float) -> void:
	var world := _world()
	if world == null or world.get("_player") == null: return
	if world.has_method("_startup_status") and not world.get("_startup_complete"): return
	var state := get_node("/root/EmberExploreProgress") as EmberExploreState
	if _engaging and not state.combat_party_locked and get_parent().battle == null:
		_engaging = false
	visible = _available() and not _engaging
	if not visible or _engaging: return
	var player := world.get("_player") as EmberPlayer
	if state.combat_party_locked or player._ui_blocks_movement(): return
	_phase += dt
	var delta := player.global_position - global_position
	delta.y = 0
	var sees := delta.length() < 64 and _facing.dot(delta.normalized()) > 0.35
	if sees:
		var ray := PhysicsRayQueryParameters3D.create(global_position+Vector3.UP*8,player.global_position+Vector3.UP*8,1)
		sees = get_world_3d().direct_space_state.intersect_ray(ray).is_empty()
	_target = player.global_position if sees else home + Vector3(sin(_phase*0.4)*16,0,cos(_phase*0.4)*16)
	var corner: Vector3 = get_parent().field_corner
	_target.x = clampf(_target.x, corner.x+12, corner.x+68)
	_target.z = clampf(_target.z, corner.z+12, corner.z+68)
	var direction := _target-global_position
	direction.y = 0
	if direction.length() > 2:
		_facing = direction.normalized()
		$Visual.rotation.y = atan2(-_facing.x,-_facing.z)
	velocity.x = _facing.x * (24 if sees else 7)
	velocity.z = _facing.z * (24 if sees else 7)
	velocity.y -= 150*dt
	move_and_slide()
	for leg in ["LegFL","LegFR","LegBL","LegBR"]:
		var node := $Visual.get_node_or_null(leg)
		if node != null: node.rotation.x = sin(_phase*(12 if sees else 5) + (0 if leg in ["LegFL","LegBR"] else PI))*0.25
	$Prompt.text = "Кабан · ЛКМ — ударить\nСо спины преимущество сильнее" if delta.length() < 48 else "Кабан"
	if sees and delta.length() < 17:
		_engaging = true
		_enter_battle.call_deferred("enemy")

func strike() -> Error:
	var player := _world().get("_player") as EmberPlayer
	if not visible or player == null or player.global_position.distance_to(global_position) > 32: return ERR_UNAVAILABLE
	var ray := PhysicsRayQueryParameters3D.create(player.global_position+Vector3.UP*8,global_position+Vector3.UP*8,1)
	if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): return ERR_UNAVAILABLE
	var direction := player.global_position-global_position
	direction.y = 0
	return start_battle("rear" if _facing.dot(direction.normalized()) < -0.5 else "player")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var player := _world().get("_player") as EmberPlayer
		if player != null and not player._ui_blocks_movement() and strike() == OK:
			get_viewport().set_input_as_handled()

func start_battle(advantage: String) -> Error:
	if _engaging or not _available(): return ERR_UNAVAILABLE
	_engaging = true
	return _enter_battle(advantage)

func _enter_battle(advantage: String) -> Error:
	var host := get_parent()
	var error: Error = host.engage(advantage)
	if error != OK:
		_engaging = false
		_world().get("_hud").text = host.last_error
	return error
