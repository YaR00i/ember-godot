@tool
extends RefCounted
## Pure transform math for exact scene placement. Voxel sources are never changed.


static func safe_steps(value: Vector3) -> Vector3:
	return Vector3(maxf(value.x,0.000001),maxf(value.y,0.000001),maxf(value.z,0.000001))


static func stroke_samples(first: Vector3, last: Vector3, spacing: float, remaining: float) -> Dictionary:
	# Carry distance across input events; results do not depend on mouse frequency.
	var length := first.distance_to(last)
	var step := maxf(spacing, 0.001)
	var distance := maxf(remaining, 0.001)
	var points: Array[Vector3] = []
	while distance <= length and points.size() < 256:
		points.append(first.lerp(last, distance / length))
		distance += step
	return {"points": points, "remaining": maxf(0.001, distance - length)}


static func world_to_vox(point: Vector3,steps: Vector3) -> Vector3:
	var value := safe_steps(steps)
	return Vector3(point.x/value.x,point.y/value.y,point.z/value.z)


static func vox_to_world(coordinates: Vector3,steps: Vector3) -> Vector3:
	return coordinates*safe_steps(steps)


static func snap_vox(coordinates: Vector3,step_vox: float) -> Vector3:
	var step := maxf(step_vox,0.000001)
	return Vector3(
		roundf(coordinates.x/step)*step,
		roundf(coordinates.y/step)*step,
		roundf(coordinates.z/step)*step,
	)


static func rotation_delta(degrees: Vector3) -> Basis:
	# Explicit order: local value X is applied first, then world Y, then world Z.
	return (
		Basis(Vector3.BACK,deg_to_rad(degrees.z))
		* Basis(Vector3.UP,deg_to_rad(degrees.y))
		* Basis(Vector3.RIGHT,deg_to_rad(degrees.x))
	)


static func place_world(
	initial_world: Transform3D,
	pivot_local: Vector3,
	desired_world_pivot: Vector3,
	rotation_degrees: Vector3,
) -> Transform3D:
	# Left multiplication rotates the complete authored basis. This preserves
	# non-uniform scale and shear instead of decomposing/rebuilding the transform.
	var basis := rotation_delta(rotation_degrees)*initial_world.basis
	return Transform3D(basis,desired_world_pivot-basis*pivot_local)
