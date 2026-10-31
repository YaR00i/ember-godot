extends "res://scripts/ember_world_break_effect.gd"
## Short airborne blade wisps; shares the existing cosmetic effect budget.
var _wind := Vector3.ZERO

func _play_leaves(_size: float, direction: Vector3) -> void:
	_wind = global_basis.inverse() * (direction * 18.0 + Vector3.RIGHT * 6.0)
	for child in get_children():
		if child is MultiMeshInstance3D:
			child.multimesh = child.multimesh.duplicate()
			_leaf_batches.append(child)
	for index in leaf_transforms.size():
		var pose := leaf_transforms[index]
		var outward := Vector3(pose.origin.x,0,pose.origin.z).normalized()
		var velocity := _wind * 0.6 + outward * 0.45 + global_basis.inverse() * Vector3.UP * (9.0 + index % 7)
		_leaf_parts.append({"pose":pose,"velocity":velocity})
		_leaf_batches[index % 4].multimesh.set_instance_transform(index / 4,pose)

func _update_leaves(delta: float) -> void:
	var fade := clampf((lifetime-_elapsed)/0.24,0.0,1.0)
	var down := global_basis.inverse() * Vector3.DOWN * gravity
	for index in _leaf_parts.size():
		var part: Dictionary = _leaf_parts[index]
		part.velocity = part.velocity.lerp(_wind,minf(1.0,delta*2.0)) + down*delta
		var pose: Transform3D = part.pose
		pose.origin += part.velocity*delta + Vector3.UP*sin(_elapsed*24.0+index)*delta*0.08
		pose.basis = Basis(Vector3(0.3,0.8,0.2).normalized(),delta*(4.0+index%5)) * pose.basis
		part.pose = pose
		pose.basis = pose.basis.scaled(Vector3.ONE*fade)
		_leaf_batches[index%4].multimesh.set_instance_transform(index/4,pose)
