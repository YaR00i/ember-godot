@tool
extends RefCounted
## Fixed voxel face plane, integer tangential bounds, inward depth.
var anchor := Vector3i.ZERO
var axis := 1
var outward := 1
var density := 16.0
var plane := Plane()

func begin(cell: Vector3i, origin: Vector3, direction: Vector3, voxels_per_block: int) -> bool:
	anchor = cell
	density = float(voxels_per_block)
	var enter := -INF
	var leave := INF
	for candidate in 3:
		var low := float(cell[candidate])/density
		var high := float(cell[candidate]+1)/density
		if absf(direction[candidate]) < 0.000001:
			if origin[candidate] < low or origin[candidate] > high:
				return false
			continue
		var first := (low-origin[candidate])/direction[candidate]
		var last := (high-origin[candidate])/direction[candidate]
		var near := minf(first,last)
		leave = minf(leave,maxf(first,last))
		if near > enter:
			enter = near
			axis = candidate
			outward = -1 if direction[candidate] > 0 else 1
	if enter < 0 or leave < enter:
		return false
	var normal := Vector3.ZERO
	normal[axis] = outward
	var position := Vector3(cell)/density
	if outward > 0:
		position[axis] += 1.0/density
	plane = Plane(normal,position)
	return true

func footprint_bounds(origin: Vector3, direction: Vector3) -> Dictionary:
	var point: Variant = plane.intersects_ray(origin,direction)
	if point == null:
		return {"error":"Курсор параллелен плоскости. Измените ракурс перед выделением."}
	var end := Vector3i((point as Vector3)*density)
	for component in 3:
		end[component] = floori(point[component]*density)
	end[axis] = anchor[axis]
	var low := anchor.min(end)
	var high := anchor.max(end)
	return {"low":low,"high":high,"box":_box(low,high)}

func bounds_from_footprint(low: Vector3i, high: Vector3i, depth: int) -> Dictionary:
	var first := low
	low = first.min(high)
	high = first.max(high)
	if outward > 0:
		low[axis] -= maxi(1,depth)-1
	else:
		high[axis] += maxi(1,depth)-1
	return {"low":low,"high":high,"box":_box(low,high)}

func bounds(origin: Vector3, direction: Vector3, depth: int) -> Dictionary:
	var footprint := footprint_bounds(origin,direction)
	if footprint.has("error"):
		return footprint
	return bounds_from_footprint(footprint.low,footprint.high,depth)

func maximum_depth(grid_size: Vector3i) -> int:
	return anchor[axis]+1 if outward > 0 else grid_size[axis]-anchor[axis]

static func depth_from_screen(
	origin: Vector2,
	pointer: Vector2,
	inward_voxel_step: Vector2,
	maximum: int,
) -> int:
	var length_squared := inward_voxel_step.length_squared()
	if length_squared < 0.0001:
		return 1
	var distance := (pointer-origin).dot(inward_voxel_step)/length_squared
	return clampi(1+roundi(distance),1,maxi(1,maximum))

func _box(low: Vector3i, high: Vector3i) -> AABB:
	return AABB(Vector3(low)/density,Vector3(high-low+Vector3i.ONE)/density)
