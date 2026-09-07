class_name EmberCutawayVolume
extends Area3D
## Godot-native roof reveal: Area3D occupancy + GeometryInstance3D transparency.

signal reveal_changed(revealed: bool)

const FADE_SECONDS := 0.22

var volume_id := ""
var _roof: MeshInstance3D
var _revealed := false
var _fade: Tween


func setup(section: Dictionary, material: Material) -> void:
	volume_id = str(section.get("id", ""))
	name = "Cutaway_%s" % (volume_id if not volume_id.is_empty() else "Interior")
	position = section.get("origin", Vector3.ZERO)
	collision_layer = 0
	collision_mask = 2
	monitoring = true
	monitorable = false
	_roof = MeshInstance3D.new()
	_roof.name = "Roof"
	_roof.mesh = section.get("mesh") as ArrayMesh
	_roof.material_override = material
	_roof.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(_roof)
	var shape_node := CollisionShape3D.new()
	shape_node.name = "InteriorShape"
	var shape := BoxShape3D.new()
	shape.size = section.get("area_size", Vector3.ONE)
	shape_node.shape = shape
	shape_node.position = section.get("area_position", Vector3.ZERO)
	add_child(shape_node)


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func set_revealed(revealed: bool, immediate := false) -> void:
	if _revealed == revealed and not immediate:
		return
	_revealed = revealed
	if is_instance_valid(_fade):
		_fade.kill()
	var target := 1.0 if revealed else 0.0
	if immediate or not is_inside_tree():
		_roof.transparency = target
	else:
		_fade = create_tween()
		_fade.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		_fade.tween_property(_roof, "transparency", target, FADE_SECONDS)
	reveal_changed.emit(revealed)


func is_revealed() -> bool:
	return _revealed


func roof() -> MeshInstance3D:
	return _roof


func _on_body_entered(body: Node3D) -> void:
	if body is EmberPlayer:
		set_revealed(true)


func _on_body_exited(body: Node3D) -> void:
	if body is EmberPlayer:
		set_revealed(false)
