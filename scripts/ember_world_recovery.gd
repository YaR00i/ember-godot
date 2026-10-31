extends Area3D
## One scene killbox and missed-crossing guard; bodies retain their own state owners.
@export var floor_y := -256.0
var character_return: Callable
var _origins: Dictionary = {}
var _elapsed := 0.0

func _ready() -> void:
	collision_layer = 0
	collision_mask = 2 | 4
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(262144, 128, 262144)
	shape.position.y = floor_y - 64.0
	add_child(shape)
	body_entered.connect(func(body): recover_body.call_deferred(body))
	for body in get_parent().find_children("*", "PhysicsBody3D", true, false): _register_body(body)
	get_tree().node_added.connect(_node_added)

func _node_added(node: Node) -> void:
	if node is CharacterBody3D or node is RigidBody3D: _register_body.call_deferred(node)

func _register_body(body: PhysicsBody3D) -> void:
	if not is_instance_valid(body) or not (body is CharacterBody3D or body is RigidBody3D) or not get_parent().is_ancestor_of(body): return
	_origins[body.get_instance_id()] = {"body": weakref(body), "pose": body.global_transform}

func _physics_process(delta: float) -> void:
	var scene := get_parent()
	if scene.has_method("_startup_status") and not scene.get("_startup_complete"): return
	_elapsed += delta
	if _elapsed < 0.2: return
	_elapsed = 0.0
	for id in _origins.keys():
		var body := _origins[id].body.get_ref() as Node3D
		if not is_instance_valid(body): _origins.erase(id)
		elif body.global_position.y < floor_y: recover_body(body)

func recover_body(body: Node3D) -> void:
	if not is_instance_valid(body) or body.is_queued_for_deletion() or body.global_position.y >= floor_y: return
	if body.has_method("recover_from_void"):
		body.recover_from_void()
	elif body is CharacterBody3D:
		if character_return.is_valid(): character_return.call(body)
		elif _origins.has(body.get_instance_id()):
			body.global_transform = _origins[body.get_instance_id()].pose
			body.velocity = Vector3.ZERO
	elif body is RigidBody3D and _origins.has(body.get_instance_id()):
		body.global_transform = _origins[body.get_instance_id()].pose
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
		body.sleeping = false
