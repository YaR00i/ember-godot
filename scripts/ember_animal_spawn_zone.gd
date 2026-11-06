extends Area3D
## One animal per profile entry, spawned as the player approaches.

const Profile = preload("res://scripts/ember_animal_profile.gd")
const Animal = preload("res://prefabs/items/field_animal.tscn")

@export var profiles: Array[Profile] = []

var _slot := 0
var _attempt := 0
var _spots: Array[Vector3] = []
@onready var _shape: CollisionShape3D = $Shape

func _physics_process(_dt: float) -> void:
	if _slot >= profiles.size():
		set_physics_process(false)
		return
	if not _shape.shape is BoxShape3D:
		push_warning("Animal spawn zone %s requires BoxShape3D" % name)
		set_physics_process(false)
		return
	var world := get_tree().current_scene
	if world == null or (world.has_method("is_world_preparation_complete") and not world.is_world_preparation_complete()):
		return
	var player := world.get_node_or_null("Player") as Node3D
	if player == null or player.global_position.distance_to(global_position) > 160.0:
		return
	var profile := profiles[_slot]
	if profile == null or profile.model == null or profile.reaction == Profile.Reaction.ENCOUNTER:
		if profile != null and profile.reaction == Profile.Reaction.ENCOUNTER:
			push_warning("Animal profile %s requires a field encounter" % profile.display_name)
		_slot += 1
		return
	var size: Vector3 = _shape.shape.size
	var angle := float(_slot * 5 + _attempt) * 2.399963
	var ratio := 0.30 if _attempt % 2 == 0 else 0.14
	var point := _shape.to_global(Vector3(cos(angle) * size.x * ratio, 0, sin(angle) * size.z * ratio))
	var map := world.get_node_or_null("Map")
	if map != null and map.has_method("prepare_physics_destination") and not map.prepare_physics_destination(point):
		return
	var space := get_world_3d().direct_space_state
	var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * size.y * 0.5, point - Vector3.UP * size.y * 0.5, 1)
	var hit := space.intersect_ray(ray)
	if not hit.is_empty() and hit.normal.y > 0.85 and _spot_clear(hit.position):
		var animal := Animal.instantiate() as CharacterBody3D
		animal.profile = profile
		animal.roam_shape = _shape
		animal.position = to_local(hit.position + Vector3.UP * 0.10)
		add_child(animal)
		_spots.append(hit.position)
		_slot += 1
		_attempt = 0
	else:
		_attempt += 1
		if _attempt >= 12:
			push_warning("Animal spawn zone %s: no ground for slot %d" % [name, _slot + 1])
			_slot += 1
			_attempt = 0

func _spot_clear(point: Vector3) -> bool:
	for previous in _spots:
		if previous.distance_squared_to(point) < 36.0:
			return false
	return true
