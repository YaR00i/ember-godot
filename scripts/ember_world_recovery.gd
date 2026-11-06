extends Area3D
## One scene killbox and missed-crossing guard; bodies retain their own state owners.
const WorldItem=preload("res://scripts/ember_world_item_3d.gd")
@export var floor_y := -256.0
var character_return: Callable
var _origins: Dictionary = {}
var _elapsed := 0.0
var _pending_support:Dictionary={}
var _simulation_characters:Dictionary={}
var _dormant_characters:Dictionary={}

func _ready() -> void:
	process_physics_priority = -200 # Wake support before Map (-100), then controllers.
	collision_layer = 0
	collision_mask = 2 | 4
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(262144, 128, 262144)
	shape.position.y = floor_y - 64.0
	add_child(shape)
	body_entered.connect(func(body): _recover_body_id.call_deferred(body.get_instance_id()))
	for body in get_parent().find_children("*", "PhysicsBody3D", true, false): _register_body(body)
	get_tree().node_added.connect(_node_added)

func _node_added(node: Node) -> void:
	if node is CharacterBody3D or node is RigidBody3D: _register_body_id.call_deferred(node.get_instance_id())

func _register_body_id(id: int) -> void:
	if not is_inside_tree(): return
	var body := instance_from_id(id)
	if is_instance_valid(body) and body is PhysicsBody3D: _register_body(body)

func _recover_body_id(id: int) -> void:
	var body := instance_from_id(id)
	if is_instance_valid(body) and body is Node3D: recover_body(body)

func _register_body(body: PhysicsBody3D) -> void:
	if not is_instance_valid(body) or not (body is CharacterBody3D or body is RigidBody3D) or not get_parent().is_ancestor_of(body): return
	if body.get_world_3d()!=get_world_3d():return
	_origins[body.get_instance_id()] = {"body": weakref(body), "pose": body.global_transform}
	# The controller owns gameplay relevance. Unknown actors always retain their tick.
	if body is CharacterBody3D and body.has_method("runtime_simulation_required"):
		if not _simulation_characters.has(body.get_instance_id()):body.tree_exiting.connect(_simulation_character_exiting.bind(body.get_instance_id()))
		_simulation_characters[body.get_instance_id()]=weakref(body)
		_update_character_simulation(body)
		if _dormant_characters.has(body.get_instance_id()):return
	# Keep recovery registration; a closed harvest flag needs no physical floor yet.
	if _unavailable_world_item(body):return
	# New bodies must not integrate gravity before their streamed floor exists.
	if not prepare_destination(body.global_position) and not body.has_method("recover_from_void"):_hold_for_support(body)

func _unavailable_world_item(body:PhysicsBody3D)->bool:
	return body is WorldItem and not body.available_flag_id.is_empty() and not body.is_item_available()

func prepare_destination(point:Vector3)->bool:
	var map:=get_parent().get_node_or_null("Map") as EmberMapLoader
	return map.prepare_physics_destination(point) if map!=null else true

func _hold_for_support(body:PhysicsBody3D)->void:
	var id:=body.get_instance_id()
	if _pending_support.has(id):return
	if body is RigidBody3D:
		_pending_support[id]={"freeze":body.freeze};body.freeze=true
	elif body is CharacterBody3D:
		_pending_support[id]={"physics":body.is_physics_processing()};body.set_physics_process(false)

func _resume_supported_bodies()->void:
	var map:=get_parent().get_node_or_null("Map") as EmberMapLoader
	for id in _pending_support.keys():
		var body:PhysicsBody3D=_origins[id].body.get_ref() if _origins.has(id) else null
		if not is_instance_valid(body):_pending_support.erase(id);continue
		if not body.is_inside_tree() or body.get_world_3d()!=get_world_3d():continue
		if map!=null and not map.physics_destination_ready(body.global_position):continue
		var state:Dictionary=_pending_support[id]
		if body is RigidBody3D:body.freeze=state.freeze
		elif body is CharacterBody3D:body.set_physics_process(state.physics)
		_pending_support.erase(id)

func _update_character_simulation(body:CharacterBody3D)->void:
	var id:=body.get_instance_id()
	if not body.runtime_simulation_required():
		if _dormant_characters.has(id):return
		# A cancelled wake must preserve the intended tick, not the temporary hold.
		_dormant_characters[id]=_pending_support.get(id,{"physics":body.is_physics_processing()})
		_pending_support.erase(id)
		body.set_physics_process(false)
	elif _dormant_characters.has(id):
		var state:Dictionary=_dormant_characters[id]
		_dormant_characters.erase(id) # Pin the destination throughout preparation.
		if prepare_destination(body.global_position):body.set_physics_process(state.physics)
		else:
			_pending_support[id]=state
			body.set_physics_process(false)

func _release_character_simulation(id:int,body:CharacterBody3D)->void:
	var state:Dictionary=_dormant_characters.get(id,_pending_support.get(id,{}))
	if is_instance_valid(body):
		if not state.is_empty():body.set_physics_process(state.physics)
		var exiting:=_simulation_character_exiting.bind(id)
		if body.tree_exiting.is_connected(exiting):body.tree_exiting.disconnect(exiting)
	_dormant_characters.erase(id);_pending_support.erase(id);_simulation_characters.erase(id)

func _simulation_character_exiting(id:int)->void:
	if not _simulation_characters.has(id):return
	_release_character_simulation(id,(_simulation_characters[id] as WeakRef).get_ref() as CharacterBody3D)
	_origins.erase(id)

func _update_simulation_characters()->void:
	for id in _simulation_characters.keys():
		var body:=(_simulation_characters[id] as WeakRef).get_ref() as CharacterBody3D
		if not is_instance_valid(body) or not body.is_inside_tree() or body.is_queued_for_deletion() or not get_parent().is_ancestor_of(body) or body.get_world_3d()!=get_world_3d():
			_release_character_simulation(id,body);_origins.erase(id)
		elif not body.has_method("runtime_simulation_required"):
			# A new controller inherits the ordinary floor guard before taking over.
			if _dormant_characters.has(id):
				_pending_support[id]=_dormant_characters[id];_dormant_characters.erase(id)
				prepare_destination(body.global_position)
			if _pending_support.has(id):body.set_physics_process(false)
			else:_release_character_simulation(id,body)
		else:_update_character_simulation(body)

func _exit_tree()->void:
	for id in _simulation_characters.keys():
		_release_character_simulation(id,(_simulation_characters[id] as WeakRef).get_ref() as CharacterBody3D)

func physics_activity_anchors(world:World3D)->Array[Vector3]:
	# Rigid bodies retain support; only explicitly dormant characters relinquish it.
	var anchors:Array[Vector3]=[]
	for id in _origins.keys():
		var body:=_origins[id].body.get_ref() as PhysicsBody3D
		if not is_instance_valid(body):_origins.erase(id);continue
		if _unavailable_world_item(body):continue
		if _dormant_characters.has(id):continue
		if body.is_inside_tree() and not body.is_queued_for_deletion() and body.get_world_3d()==world:anchors.append(body.global_position)
	return anchors

func _physics_process(delta: float) -> void:
	_update_simulation_characters()
	if not _pending_support.is_empty():_resume_supported_bodies()
	var scene := get_parent()
	if scene.has_method("_startup_status") and not scene.get("_startup_complete"): return
	_elapsed += delta
	if _elapsed < 0.2: return
	_elapsed = 0.0
	for id in _origins.keys():
		var body := _origins[id].body.get_ref() as Node3D
		if not is_instance_valid(body): _origins.erase(id)
		elif not body.is_inside_tree() or body.get_world_3d()!=get_world_3d(): continue
		elif body.global_position.y < floor_y: recover_body(body)

func recover_body(body: Node3D) -> void:
	if not is_inside_tree() or not is_instance_valid(body) or not body.is_inside_tree() or body.is_queued_for_deletion(): return
	if body.get_world_3d()!=get_world_3d() or body.global_position.y >= floor_y: return
	if body.has_method("recover_from_void"):
		body.recover_from_void()
	elif body is CharacterBody3D:
		if character_return.is_valid(): character_return.call(body)
		elif _origins.has(body.get_instance_id()):
			body.global_transform = _origins[body.get_instance_id()].pose
			body.velocity = Vector3.ZERO
		if is_instance_valid(body) and not prepare_destination(body.global_position):_hold_for_support(body)
	elif body is RigidBody3D and _origins.has(body.get_instance_id()):
		if not prepare_destination(_origins[body.get_instance_id()].pose.origin):_hold_for_support(body)
		body.global_transform = _origins[body.get_instance_id()].pose
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
		body.sleeping = false
