@tool
extends RefCounted
## Pure voxel-footprint math shared by preview, saved collision and brushes.
const MAX_CELLS := 65536
const MAX_RECTS := 2048

static func valid(data: Dictionary) -> bool:
	if data.get("version", 0) != 1:
		return false
	if not data.get("count") is Vector2i or not data.get("cell") is Vector2 or not data.get("bits") is PackedByteArray or not data.get("allowed") is PackedByteArray:
		return false
	if data.has("height_cell") and (not (data.height_cell is float or data.height_cell is int) or not is_finite(float(data.height_cell)) or float(data.height_cell) <= 0):
		return false
	var count: Vector2i = data.get("count", Vector2i.ZERO)
	var cell: Vector2 = data.get("cell", Vector2.ZERO)
	var bits: PackedByteArray = data.get("bits", PackedByteArray())
	var allowed: PackedByteArray = data.get("allowed", PackedByteArray())
	if count.x < 1 or count.y < 1 or count.x * count.y > MAX_CELLS or not cell.is_finite() or cell.x <= 0 or cell.y <= 0 or bits.size() != count.x * count.y or allowed.size() != bits.size():
		return false
	for index in bits.size():
		if bits[index] > 1 or allowed[index] > 1 or bits[index] > allowed[index]:
			return false
	return true

static func make(count: Vector2i, cell: Vector2, bits: PackedByteArray) -> Dictionary:
	return {"version": 1, "count": count, "cell": cell, "bits": bits.duplicate(), "allowed": bits.duplicate()}

static func size(data: Dictionary) -> Vector2:
	return Vector2(data.count) * data.cell

static func at(point: Vector3, data: Dictionary) -> Vector2i:
	var p: Vector2 = (Vector2(point.x, point.z) + size(data) * 0.5) / data.cell
	return Vector2i(floori(p.x), floori(p.y))

static func inside(p: Vector2i, count: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < count.x and p.y < count.y

static func paint(data: Dictionary, a: Vector2i, b: Vector2i, diameter: int, restore: bool) -> bool:
	var changed := false
	var steps := maxi(absi(b.x-a.x), absi(b.y-a.y))
	var lo := -floori(float(diameter-1) / 2)
	for step in steps + 1:
		var center := Vector2i(Vector2(a).lerp(Vector2(b), float(step) / maxi(1, steps)).round())
		for y in range(lo, lo+diameter):
			for x in range(lo, lo+diameter):
				var p := center + Vector2i(x,y)
				if not inside(p, data.count):
					continue
				var index: int = p.y * data.count.x + p.x
				var value: int = data.allowed[index] if restore else 0
				if data.bits[index] != value:
					data.bits[index] = value
					changed = true
	return changed

static func close_gaps(source: PackedByteArray, count: Vector2i, maximum: int) -> PackedByteArray:
	var result := source.duplicate()
	# Both endpoints must be original support: filling never grows the outer
	# ends or recursively spreads from newly invented support.
	for axis in 2:
		var length := count.x if axis == 0 else count.y
		var rows := count.y if axis == 0 else count.x
		for row in rows:
			var previous := -1
			for column in length:
				var index := row * count.x + column if axis == 0 else column * count.x + row
				if source[index] == 0:
					continue
				if previous >= 0 and column-previous-1 <= maximum:
					for gap in range(previous+1, column):
						var target := row * count.x + gap if axis == 0 else gap * count.x + row
						result[target] = 1
				previous = column
	return result

static func rasterize(triangles: PackedVector3Array, count: Vector2i, cell: Vector2, tolerance: float) -> PackedByteArray:
	var result := PackedByteArray()
	result.resize(count.x * count.y)
	var extent := Vector2(count) * cell
	for index in range(0, triangles.size()-2, 3):
		var a := triangles[index]
		var b := triangles[index+1]
		var c := triangles[index+2]
		# Godot triangle winding is clockwise. Only near-horizontal top faces.
		var normal := (c-a).cross(b-a).normalized()
		if normal.y < 0.7 or minf(a.y, minf(b.y,c.y)) > 0.001 or maxf(a.y,maxf(b.y,c.y)) < -tolerance:
			continue
		var aa := Vector2(a.x,a.z)
		var bb := Vector2(b.x,b.z)
		var cc := Vector2(c.x,c.z)
		var low := Vector2i(((aa.min(bb).min(cc)+extent*0.5)/cell).floor()).max(Vector2i.ZERO)
		var high := Vector2i(((aa.max(bb).max(cc)+extent*0.5)/cell).ceil()).min(count-Vector2i.ONE)
		var denominator := (bb-aa).cross(cc-aa)
		if absf(denominator) < 0.000001:
			continue
		for z in range(low.y, high.y+1):
			for x in range(low.x, high.x+1):
				var p := (Vector2(x,z)+Vector2(0.5,0.5))*cell-extent*0.5
				var u := (p-aa).cross(cc-aa)/denominator
				var v := (bb-aa).cross(p-aa)/denominator
				if u >= -0.00001 and v >= -0.00001 and u+v <= 1.00001:
					var height := a.y*(1-u-v)+b.y*u+c.y*v
					if height <= 0.001 and height >= -tolerance-0.001:
						result[z*count.x+x] = 1
	return result

static func rectangles(data: Dictionary) -> Array[Rect2i]:
	var result: Array[Rect2i] = []
	var used := PackedByteArray()
	used.resize(data.bits.size())
	var count: Vector2i = data.count
	for z in count.y:
		for x in count.x:
			var index := z*count.x+x
			if used[index] != 0 or data.bits[index] == 0:
				continue
			var width := 1
			while x+width < count.x and data.bits[index+width] != 0 and used[index+width] == 0:
				width += 1
			var height := 1
			while z+height < count.y:
				var complete := true
				for xx in range(x,x+width):
					var next := (z+height)*count.x+xx
					if data.bits[next] == 0 or used[next] != 0:
						complete = false
						break
				if not complete:
					break
				height += 1
			for zz in range(z,z+height):
				for xx in range(x,x+width):
					used[zz*count.x+xx] = 1
			result.append(Rect2i(x,z,width,height))
			if result.size() > MAX_RECTS:
				return result
	return result

static func rect_pose(rect: Rect2i, data: Dictionary) -> Vector3:
	var p: Vector2 = (Vector2(rect.position)+Vector2(rect.size)*0.5)*data.cell-size(data)*0.5
	return Vector3(p.x,0,p.y)

static func visual_mesh(data: Dictionary) -> ArrayMesh:
	var vertices := PackedVector3Array()
	for rect in rectangles(data):
		var center := rect_pose(rect,data)
		var half: Vector2 = Vector2(rect.size)*data.cell*0.5
		var a := center+Vector3(-half.x,0,-half.y)
		var b := center+Vector3(half.x,0,-half.y)
		var c := center+Vector3(half.x,0,half.y)
		var d := center+Vector3(-half.x,0,half.y)
		vertices.append_array(PackedVector3Array([a,b,c,a,c,d]))
	var mesh := ArrayMesh.new()
	if not vertices.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

static func grid_lines(data: Dictionary) -> PackedVector3Array:
	var result := PackedVector3Array()
	var extent := size(data)
	for x in data.count.x+1:
		var p: float = -extent.x*0.5+x*data.cell.x
		result.append_array(PackedVector3Array([Vector3(p,0,-extent.y*0.5),Vector3(p,0,extent.y*0.5)]))
	for z in data.count.y+1:
		var p: float = -extent.y*0.5+z*data.cell.y
		result.append_array(PackedVector3Array([Vector3(-extent.x*0.5,0,p),Vector3(extent.x*0.5,0,p)]))
	return result
