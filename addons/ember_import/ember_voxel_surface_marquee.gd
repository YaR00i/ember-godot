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

func bounds(origin: Vector3, direction: Vector3, depth: int) -> Dictionary:
	var point: Variant = plane.intersects_ray(origin,direction)
	if point == null:
		return {"error":"Курсор параллелен плоскости. Измените ракурс перед выделением."}
	var end := Vector3i((point as Vector3)*density)
	for component in 3:
		end[component] = floori(point[component]*density)
	end[axis] = anchor[axis]
	var low := anchor.min(end)
	var high := anchor.max(end)
	if outward > 0:
		low[axis] -= maxi(1,depth)-1
	else:
		high[axis] += maxi(1,depth)-1
	return {"low":low,"high":high,"box":AABB(Vector3(low)/density,Vector3(high-low+Vector3i.ONE)/density)}
