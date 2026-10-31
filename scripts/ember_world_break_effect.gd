extends Node3D
## Baked voxel fragments are cosmetic; they never become saved/pickable bodies.
const MAX_EFFECTS := 4
const LIFETIME := 1.1
@export_range(0.3, 3.0, 0.1) var lifetime := LIFETIME
@export_range(0.0, 200.0, 1.0) var gravity := 80.0
@export_range(0.1, 2.0, 0.1) var launch_strength := 1.0
@export_range(0.01, 0.5, 0.01) var ground_radius_ratio := 0.22
## Leaf cards keep their baked poses and share four rendering batches.
@export var leaf_transforms: Array[Transform3D] = []
var _parts: Array[Dictionary] = []
var _leaf_parts: Array[Dictionary] = []
var _leaf_batches: Array[MultiMeshInstance3D] = []
var _leaf_floor := PackedFloat32Array()
var _elapsed := 0.0

func play(pose: Transform3D, size: float, direction: Vector3) -> void:
	var active := get_tree().get_nodes_in_group("ember_world_break_effects")
	while active.size() >= MAX_EFFECTS:
		var oldest: Node = active.pop_front()
		oldest.remove_from_group("ember_world_break_effects")
		oldest.queue_free()
	add_to_group("ember_world_break_effects")
	global_transform = pose.scaled_local(Vector3.ONE * size)
	if not leaf_transforms.is_empty():
		_play_leaves(size, direction)
		return
	var meshes := get_children()
	for index in meshes.size():
		var mesh := meshes[index] as MeshInstance3D
		if mesh == null or mesh.mesh == null: continue
		var center := mesh.global_transform * mesh.mesh.get_aabb().get_center()
		var pivot := Node3D.new(); add_child(pivot); pivot.global_position = center
		mesh.reparent(pivot, true)
		var outward := (center - pose.origin - Vector3.UP * size * 0.5).normalized()
		_parts.append({"pivot": pivot, "velocity": (outward * 14.0 + direction * 10.0 + Vector3.UP * (18.0 + index % 3 * 3.0)) * launch_strength, "landed": false, "radius": size * ground_radius_ratio})

func _physics_process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= lifetime: queue_free(); return
	if not _leaf_parts.is_empty():
		_update_leaves(delta)
		return
	for part in _parts:
		var pivot: Node3D = part.pivot
		if not part.landed:
			part.velocity += Vector3.DOWN * gravity * delta
			var next: Vector3 = pivot.global_position + part.velocity * delta
			var ray := PhysicsRayQueryParameters3D.create(pivot.global_position, next + Vector3.DOWN * part.radius, 1)
			var hit := get_world_3d().direct_space_state.intersect_ray(ray)
			if not hit.is_empty():
				next = hit.position + hit.normal * part.radius
				part.landed = true
			pivot.global_position = next
			pivot.rotate_x(delta * 3.0); pivot.rotate_z(delta * 2.0)
		if _elapsed > lifetime - 0.3: pivot.scale *= maxf(0.0, (lifetime - _elapsed) / (lifetime - _elapsed + delta))

func _play_leaves(size: float, direction: Vector3) -> void:
	# Cosmetic landing samples the terrain once, never adds saved physics bodies.
	for z in 3:
		for x in 3:
			var point := Vector3((x - 1) * 2.5, 0, (z - 1) * 2.5)
			var start := global_transform * (point + Vector3.UP * 2.0)
			var finish := global_transform * (point + Vector3.DOWN * 4.0)
			var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(start, finish, 1))
			_leaf_floor.append(to_local(hit.position).y if not hit.is_empty() else -4.0)
	for child in get_children():
		if child is MultiMeshInstance3D:
			# Packed scenes share Resources. Each flight owns its instance buffer.
			child.multimesh = child.multimesh.duplicate()
			_leaf_batches.append(child)
	for index in leaf_transforms.size():
		var pose := leaf_transforms[index]
		_leaf_batches[index % 4].multimesh.set_instance_transform(index / 4, pose)
		var outward := Vector3(pose.origin.x, 0, pose.origin.z).normalized()
		var velocity := (outward * (12.0 + index % 5) + direction * 6.0 + Vector3.UP * (16.0 + index % 7)) * launch_strength / size
		_leaf_parts.append({"pose": pose, "velocity": velocity, "landed": false})

func _update_leaves(delta: float) -> void:
	var fade := clampf((lifetime - _elapsed) / 0.5, 0.0, 1.0)
	for index in _leaf_parts.size():
		var part: Dictionary = _leaf_parts[index]
		var pose: Transform3D = part.pose
		if not part.landed:
			part.velocity += Vector3.DOWN * gravity * delta / global_basis.get_scale().x
			var next: Vector3 = pose.origin + part.velocity * delta
			var ground := _floor_height(next) + 0.015
			if part.velocity.y < 0.0 and next.y <= ground:
				next.y = ground
				part.landed = true
				pose.basis = Basis(Vector3.UP, index * 2.39996).scaled(leaf_transforms[index].basis.get_scale())
			pose.origin = next
			if not part.landed:
				pose.basis = Basis(Vector3.RIGHT, delta * (1.1 + index % 3 * 0.2)) * pose.basis
			part.pose = pose
		# All cards retain full size until the final half second.
		pose.basis = pose.basis.scaled(Vector3.ONE * fade)
		_leaf_batches[index % 4].multimesh.set_instance_transform(index / 4, pose)

func _floor_height(point: Vector3) -> float:
	var grid := (Vector2(point.x, point.z) / 2.5 + Vector2.ONE).clamp(Vector2.ZERO, Vector2.ONE * 2.0)
	var x := mini(1, floori(grid.x)); var z := mini(1, floori(grid.y))
	return lerpf(lerpf(_leaf_floor[z * 3 + x], _leaf_floor[z * 3 + x + 1], grid.x - x), lerpf(_leaf_floor[(z + 1) * 3 + x], _leaf_floor[(z + 1) * 3 + x + 1], grid.x - x), grid.y - z)
