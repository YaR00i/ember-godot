@tool
extends Node
## One authored scene component; transforms/items remain owned by the bound object.
@export var component_id := ""
@export var label := "Компонент"
@export_enum("plate", "lever", "all", "any", "not", "door", "lamp", "hold", "latch") var kind := "all"
@export_range(0.05, 120.0, 0.05) var hold_seconds := 3.0
@export_node_path("Node3D") var target_path := NodePath("")
@export_node_path("RigidBody3D") var crate_path := NodePath("")
@export_node_path("Area3D") var clearance_path := NodePath("")
@export var open_offset := Vector3(0, 40, 0)
@export_range(0.1, 3.0, 0.05) var move_seconds := 0.6
@export_range(0.0, 3.0, 0.05) var settle_seconds := 0.35
## Zero preserves legacy any-body plates. Character contribution is explicit.
@export_range(0.0, 1000.0, 0.25) var required_weight := 0.0
@export_range(0.0, 1000.0, 0.25) var character_weight := 1.0
## Optional momentary lever operated by a follower instead of a saved toggle.
@export var companion_hero_id := ""
@export var companion_completion_flag := ""
var sensed_weight := 0.0
var value := false
var blocked := false
var openness := 1.0
var _settled := 0.0
var _closed := Vector3.ZERO
var _target: Node3D
var _adapter: Area3D
var _material: StandardMaterial3D
var _original_material: Material
var _original_visible := true
const Rules = preload("res://scripts/ember_object_zone_rules.gd")
const Geometry = preload("res://scripts/ember_mechanism_role_geometry.gd")
var _clearance_transform := Transform3D.IDENTITY
var _auto_clearance: Area3D
var _disabled_shapes: Array[Dictionary] = []
var authored_helper: Node3D
var authored_parent: Node3D
func binding(path: NodePath) -> Node:
	return get_node_or_null(path) if not path.is_empty() else null
func prepare() -> void:
	_target = binding(target_path) as Node3D
	if _target == null: return
	_original_visible = _target.visible
	var helper := Geometry.helper_for(_target, component_id)
	if helper != null:
		var object := Geometry.object_for(_target)
		var previous_shapes := _disabled_shapes.duplicate()
		_disabled_shapes.clear()
		for node in object.find_children("*", "CollisionShape3D", true, false):
			if helper.is_ancestor_of(node) or not node.get_parent() is StaticBody3D: continue
			var original_disabled: bool = node.disabled
			for previous in previous_shapes:
				if is_instance_valid(previous.node) and previous.node == node: original_disabled = previous.disabled; break
			_disabled_shapes.append({"node": node, "disabled": original_disabled}); node.set_deferred("disabled", true)
	if kind == "door":
		if helper != null:
			_auto_clearance = binding(clearance_path) as Area3D
			if _auto_clearance:
				_clearance_transform = _auto_clearance.transform
				var world := _auto_clearance.global_transform
				_auto_clearance.top_level = true; _auto_clearance.global_transform = world
		_closed = _target.position
		_target.position = _closed + open_offset
	elif kind == "lever":
		_adapter = preload("res://scripts/ember_mechanism_lever_interact.gd").new()
		_adapter.name = "MechanismLeverInput"
		_adapter.component = self
		_adapter.kind = "custom"
		var shape := CollisionShape3D.new()
		shape.name = "Shape"
		shape.shape = SphereShape3D.new()
		shape.shape.radius = 8.0
		shape.position.y = 8.0
		_adapter.add_child(shape)
		_target.add_child(_adapter)
	if _target is MeshInstance3D:
		_original_material = _target.material_override
		if kind != "door":
			_material = _original_material.duplicate() as StandardMaterial3D if _original_material is StandardMaterial3D else StandardMaterial3D.new()
			_target.material_override = _material
	elif kind in ["plate", "lever"]:
		var visual := _target.get_node_or_null("Visual") as MeshInstance3D
		if visual:
			_original_material = visual.material_override
			_material = _original_material.duplicate() as StandardMaterial3D if _original_material is StandardMaterial3D else StandardMaterial3D.new()
			visual.material_override = _material
func release() -> void:
	for entry in _disabled_shapes:
		if is_instance_valid(entry.node): entry.node.set_deferred("disabled", entry.disabled)
	if is_instance_valid(_auto_clearance):
		_auto_clearance.top_level = false; _auto_clearance.transform = _clearance_transform
	_auto_clearance = null
	if is_instance_valid(_adapter):
		_adapter.get_parent().remove_child(_adapter)
		_adapter.free()
	_adapter = null
	if not is_instance_valid(_target): return
	if kind == "door": _target.position = _closed
	if _target is MeshInstance3D: _target.material_override = _original_material
	elif kind in ["plate", "lever"]:
		var visual := _target.get_node_or_null("Visual") as MeshInstance3D
		if visual: visual.material_override = _original_material
	if _target is Light3D: _target.visible = _original_visible
func sense(delta: float, state: EmberExploreState, circuit_id: String) -> bool:
	if kind == "lever":
		if not companion_hero_id.is_empty():
			return is_instance_valid(_adapter) and _adapter.call("companion_holding")
		return bool(state.flags.get("mechanism_%s_%s" % [circuit_id, component_id], false)) if state != null else false
	if kind != "plate" or not is_instance_valid(_target) or not _target is Area3D: return false
	var valid := false
	sensed_weight = 0.0
	if crate_path.is_empty():
		for body in _target.get_overlapping_bodies():
			if body is CharacterBody3D: sensed_weight += character_weight; valid = true
			if body is RigidBody3D and body.linear_velocity.length() <= 1.0 and body.angular_velocity.length() <= 0.15:
				if not body.has_method("is_carried") or not body.is_carried(): sensed_weight += body.mass; valid = true
	var crate := binding(crate_path) as RigidBody3D
	if crate != null:
		for body in _target.get_overlapping_bodies():
			if body == crate and Rules.accepts_body(_target, body, str(crate.get("pickup_id"))): sensed_weight = body.mass; valid = true; break
	if required_weight > 0.0: valid = valid and sensed_weight + 0.0001 >= required_weight
	_settled = _settled + delta if valid else 0.0
	return valid and _settled >= settle_seconds
func apply(next_value: bool, delta: float) -> void:
	value = next_value
	if not is_instance_valid(_target): return
	if kind == "door":
		var clearance := binding(clearance_path) as Area3D
		blocked = clearance == null
		if clearance:
			for body in clearance.get_overlapping_bodies():
				if body != _target and not _target.is_ancestor_of(body): blocked = true; break
		openness = move_toward(openness, 1.0 if value or blocked else 0.0, delta / maxf(0.1, move_seconds))
		_target.position = _closed + open_offset * openness
	elif kind == "lamp" and _target is Light3D: _target.visible = value
	if _material:
		_material.albedo_color = Color("67d6bd") if value else Color("c79746") if kind == "plate" else Color("46515f")
		_material.emission_enabled = kind == "lamp" and value
		_material.emission = Color("67d6bd") if value else Color.BLACK
