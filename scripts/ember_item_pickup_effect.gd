extends Node3D
## Presentation only. Inventory has already committed before this node exists.
const Arc = preload("res://scripts/ember_arc_motion.gd")
var actor: Node3D
var _pivot: Node3D
var _start := Vector3.ZERO
var _height := 8.0
var _collapsing := false

func play(visual: Node3D, collector: Node3D) -> void:
	actor = collector
	add_to_group("ember_item_pickup_effects")
	var bounds := AABB(visual.global_position,Vector3.ZERO)
	var first := true
	var meshes: Array[Node] = visual.find_children("*","MeshInstance3D",true,false)
	if visual is MeshInstance3D: meshes.append(visual)
	for node in meshes:
		var mesh := node as MeshInstance3D
		if mesh.mesh == null: continue
		var box: AABB = mesh.global_transform * mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	_pivot = Node3D.new()
	_pivot.name = "FlyingItem"
	add_child(_pivot)
	_pivot.global_position = bounds.get_center()
	visual.reparent(_pivot,true)
	_start = _pivot.global_position
	_height = maxf(8.0,absf(_destination().y-_start.y)*0.5+4.0)
	var tween := create_tween()
	tween.tween_method(_fly,0.0,1.0,0.44)
	tween.tween_callback(func():_collapsing=true)
	tween.tween_interval(0.07)
	tween.tween_property(_pivot,"scale",Vector3.ZERO,0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(queue_free)

func _destination() -> Vector3:
	var label := actor.get_node_or_null("Status") as Node3D
	return (label.global_position if label != null else actor.global_position+Vector3.UP*28.0) + Vector3.UP*3.0

func _fly(weight: float) -> void:
	if not is_instance_valid(actor) or actor.is_queued_for_deletion(): queue_free();return
	_pivot.global_position = Arc.position_at(_start,_destination(),weight,_height)
	_pivot.rotation.y = weight*0.65

func _process(_dt: float) -> void:
	if not is_instance_valid(actor) or actor.is_queued_for_deletion(): queue_free();return
	if _collapsing: _pivot.global_position = _destination()
